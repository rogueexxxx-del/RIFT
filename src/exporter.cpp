// Exporter impl - RGBA frames -> video via libav, entirely in-process.
//
// Flow: open() picks an encoder by probing (see pick_video_encoder), builds
// the muxer (+ audio encoder/decoder/resampler when audio_path is set), and
// writes the header. writeFrame() composites overlays then encodes. finish()
// flushes video, transcodes the whole audio track into the same container,
// then writes the trailer.
#include "exporter.hpp"
#include <cstdio>
#include <cstring>
#include <vector>

#if RIFT_WITH_FFMPEG
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/channel_layout.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
}
#include <QImage>
#include <QPainter>
#include <QFont>
#include <QFontDatabase>
#include <QColor>
#include <QRect>
#include <QDir>
#include <QString>
#endif

namespace rift {

#if RIFT_WITH_FFMPEG
struct Exporter::Impl {
    AVFormatContext* oc = nullptr;
    // video
    AVStream*        vst = nullptr;
    AVCodecContext*  venc = nullptr;
    SwsContext*      sws = nullptr;
    AVFrame*         vframe = nullptr;
    AVPacket*        pkt = nullptr;
    int              w = 0, h = 0;
    int64_t          vpts = 0;
    bool             header_written = false;
    // Where the file is ACTUALLY written. Not always the caller's path: an
    // ARCHIVE export is ProRes, which cannot live in MP4, so the extension is
    // corrected to .mov.
    std::string      out_path;
    // audio (optional)
    std::string      audio_path;
    AVStream*        ast = nullptr;
    AVCodecContext*  aenc = nullptr;
    int              aframe_size = 1024;
    int64_t          apts = 0;
    // overlay compositing
    bool             no_watermark = false;
    QImage           logo;
    std::vector<uint8_t> paint_buf;   // scratch for QPainter (frames are const)
    bool overlaysAlways() const { return !no_watermark || !logo.isNull(); }

    // Move any ready packets from `enc` to the muxer, tagged for `st`.
    bool drain(AVCodecContext* enc, AVStream* st) {
        for (;;) {
            int r = avcodec_receive_packet(enc, pkt);
            if (r == AVERROR(EAGAIN) || r == AVERROR_EOF) return true;
            if (r < 0) return false;
            av_packet_rescale_ts(pkt, enc->time_base, st->time_base);
            pkt->stream_index = st->index;
            int wr = av_interleaved_write_frame(oc, pkt);
            av_packet_unref(pkt);
            if (wr < 0) return false;
        }
    }

    bool transcodeAudio();     // decode source audio -> AAC -> mux

    void close() {
        if (sws)    { sws_freeContext(sws); sws = nullptr; }
        if (vframe) av_frame_free(&vframe);
        if (pkt)    av_packet_free(&pkt);
        if (venc)   avcodec_free_context(&venc);
        if (aenc)   avcodec_free_context(&aenc);
        if (oc) {
            if (!(oc->oformat->flags & AVFMT_NOFILE) && oc->pb) avio_closep(&oc->pb);
            avformat_free_context(oc); oc = nullptr;
        }
    }
    ~Impl() { close(); }
};
#else
struct Exporter::Impl {};
#endif

Exporter::Exporter() : d_(std::make_unique<Impl>()) {}
Exporter::~Exporter() = default;

#if RIFT_WITH_FFMPEG
static int64_t pick_bitrate(const rift_export_spec& s) {
    double bpp;
    switch (s.quality) {
        case RIFT_EXPORT_ARCHIVE: bpp = 0.20; break;
        case RIFT_EXPORT_HIGH:    bpp = 0.16; break;
        case RIFT_EXPORT_PREVIEW: bpp = 0.05; break;
        default:                  bpp = 0.10; break;   // YOUTUBE
    }
    return int64_t(double(s.width) * s.height * (s.fps > 0 ? s.fps : 30) * bpp);
}

// Tier index into the per-encoder quality tables below.
static int tier_of(rift_export_quality q) {
    switch (q) {
        case RIFT_EXPORT_YOUTUBE: return 1;
        case RIFT_EXPORT_PREVIEW: return 2;
        default:                  return 0;   // HIGH (ARCHIVE never gets here)
    }
}

// Rate-control options per encoder, indexed by tier. Constant-quality where
// the encoder supports it; libopenh264 has none, so it falls back to bitrate.
static void set_rate_control(AVDictionary** opts, const char* name, int tier,
                             AVCodecContext* ctx, const rift_export_spec& spec) {
    static const char* kCq[]  = { "19", "23", "30" };
    static const char* kMfQ[] = { "85", "70", "50" };

    // EVERY encoder gets a resolution-scaled target and ceiling, not just the
    // software fallback. AVCodecContext defaults bit_rate to 200 kbps, and the
    // hardware encoders clamp their VBR/quality modes to it - which is how a
    // 4K "high quality" export came out at 15 Mbps. The constant-quality
    // setting still decides the picture; this only gives it room to spend.
    const int64_t target = pick_bitrate(spec);
    ctx->bit_rate       = target;
    ctx->rc_max_rate    = target * 3 / 2;
    ctx->rc_buffer_size = int(target * 2);

    if (!std::strcmp(name, "h264_nvenc")) {
        av_dict_set(opts, "preset", "p6", 0);     // slower, better per bit
        av_dict_set(opts, "rc", "vbr", 0);
        av_dict_set(opts, "cq", kCq[tier], 0);
    } else if (!std::strcmp(name, "h264_qsv")) {
        av_dict_set(opts, "global_quality", kCq[tier], 0);
        av_dict_set(opts, "preset", "slower", 0);
    } else if (!std::strcmp(name, "h264_amf")) {
        av_dict_set(opts, "rc", "cqp", 0);
        av_dict_set(opts, "qp_i", kCq[tier], 0);
        av_dict_set(opts, "qp_p", kCq[tier], 0);
        av_dict_set(opts, "quality", "quality", 0);
    } else if (!std::strcmp(name, "h264_mf")) {
        av_dict_set(opts, "rate_control", "quality", 0);
        av_dict_set(opts, "quality", kMfQ[tier], 0);
    }
    // else: software encoder, the target above is all it needs.
}

// Encoders accept different input formats (qsv wants nv12, openh264 yuv420p).
// AVCodec::pix_fmts is gone in FFmpeg 8 - query the codec instead.
static AVPixelFormat pick_pix_fmt(const AVCodec* c, AVPixelFormat preferred) {
    const void* cfgs = nullptr;
    int n = 0;
    if (avcodec_get_supported_config(nullptr, c, AV_CODEC_CONFIG_PIX_FORMAT,
                                     0, &cfgs, &n) < 0 || !cfgs || n <= 0)
        return preferred;                        // NULL = "all supported"
    const AVPixelFormat* pf = static_cast<const AVPixelFormat*>(cfgs);
    for (int i = 0; i < n; ++i) if (pf[i] == preferred) return preferred;
    for (int i = 0; i < n; ++i) if (pf[i] == AV_PIX_FMT_NV12) return AV_PIX_FMT_NV12;
    return pf[0];
}

// Try each candidate for real. A codec being *present* means nothing: nvenc is
// always listed, yet avcodec_open2 rejects it when the driver predates the
// nvenc API the build wants ("Driver does not support the required nvenc API
// version"). Opening it is the only honest probe, and it costs one alloc.
static const char* pick_video_encoder(Exporter::Impl& D,
                                      const rift_export_spec& spec,
                                      AVFormatContext* oc, int fps) {
    static const char* kChain[] = {
        "h264_nvenc",    // NVIDIA
        "h264_qsv",      // Intel Quick Sync
        "h264_amf",      // AMD
        "h264_mf",       // Windows MediaFoundation
        "libopenh264",   // LGPL software floor
    };
    const bool archive = (spec.quality == RIFT_EXPORT_ARCHIVE);
    const int  tier    = tier_of(spec.quality);

    const int count = archive ? 1 : int(sizeof(kChain) / sizeof(*kChain));
    for (int i = 0; i < count; ++i) {
        const char* name = archive ? "prores_ks" : kChain[i];
        const AVCodec* c = avcodec_find_encoder_by_name(name);
        if (!c) continue;

        AVCodecContext* ctx = avcodec_alloc_context3(c);
        if (!ctx) continue;
        ctx->width = D.w; ctx->height = D.h;
        ctx->time_base = AVRational{1, fps};
        ctx->framerate = AVRational{fps, 1};
        ctx->gop_size = fps * 2;
        ctx->max_b_frames = archive ? 0 : 2;
        ctx->pix_fmt = archive ? AV_PIX_FMT_YUV422P10LE
                               : pick_pix_fmt(c, AV_PIX_FMT_YUV420P);
        if (oc->oformat->flags & AVFMT_GLOBALHEADER)
            ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

        AVDictionary* opts = nullptr;
        if (archive) av_dict_set(&opts, "profile", "3", 0);
        else         set_rate_control(&opts, name, tier, ctx, spec);

        const int r = avcodec_open2(ctx, c, &opts);
        av_dict_free(&opts);
        if (r >= 0) { D.venc = ctx; return name; }

        avcodec_free_context(&ctx);          // unusable here; try the next one
    }
    return nullptr;
}

// Add + open the AAC encoder stream (must run before write_header). Returns
// false but leaves the video export usable (caller treats audio as optional).
static bool setup_audio_enc(Exporter::Impl& D, int sample_rate) {
    const AVCodec* ac = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!ac) return false;
    D.ast = avformat_new_stream(D.oc, nullptr);
    if (!D.ast) return false;
    D.aenc = avcodec_alloc_context3(ac);
    D.aenc->sample_rate = sample_rate;
    av_channel_layout_default(&D.aenc->ch_layout, 2);     // stereo out
    D.aenc->sample_fmt = AV_SAMPLE_FMT_FLTP;              // AAC native encoder fmt
    D.aenc->bit_rate = 192000;
    D.aenc->time_base = AVRational{1, sample_rate};
    if (D.oc->oformat->flags & AVFMT_GLOBALHEADER)
        D.aenc->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    if (avcodec_open2(D.aenc, ac, nullptr) < 0) return false;
    if (avcodec_parameters_from_context(D.ast->codecpar, D.aenc) < 0) return false;
    D.ast->time_base = AVRational{1, sample_rate};
    D.aframe_size = D.aenc->frame_size > 0 ? D.aenc->frame_size : 1024;
    return true;
}

bool Exporter::open(const rift_export_spec& spec) {
    Impl& D = *d_;
    D.w = spec.width & ~1;
    D.h = spec.height & ~1;
    int fps = spec.fps > 0 ? spec.fps : 30;
    D.audio_path = spec.audio_path ? spec.audio_path : "";

    // ProRes has no MP4 tag, so an ARCHIVE export written to a .mp4 path failed
    // at write_header with a zero-byte file. The codec decides the container:
    // force QuickTime and correct the extension rather than refusing.
    D.out_path = spec.out_path ? spec.out_path : "";
    const char* fmt = nullptr;
    if (spec.quality == RIFT_EXPORT_ARCHIVE) {
        fmt = "mov";
        const size_t dot = D.out_path.find_last_of('.');
        const bool is_mov = dot != std::string::npos
                         && D.out_path.compare(dot, std::string::npos, ".mov") == 0;
        if (!is_mov) {
            D.out_path = (dot == std::string::npos ? D.out_path
                                                   : D.out_path.substr(0, dot)) + ".mov";
            std::fprintf(stderr, "[export] ARCHIVE is ProRes: writing %s\n",
                         D.out_path.c_str());
            std::fflush(stderr);
        }
    }

    if (avformat_alloc_output_context2(&D.oc, nullptr, fmt, D.out_path.c_str()) < 0
        || !D.oc) {
        err_ = "alloc output context failed"; return false;
    }

    const char* picked = pick_video_encoder(D, spec, D.oc, fps);
    if (!picked) { err_ = "no usable video encoder on this machine"; return false; }
    encoder_ = picked;
    // Which encoder ran is machine-dependent (the ladder falls through on
    // driver mismatches), and it decides the quality you actually get, so say so.
    std::fprintf(stderr, "[export] %s %dx%d @%dfps target %lld kbps\n",
                 picked, D.w, D.h, fps,
                 (long long)(D.venc->bit_rate / 1000));
    std::fflush(stderr);

    D.vst = avformat_new_stream(D.oc, nullptr);
    avcodec_parameters_from_context(D.vst->codecpar, D.venc);
    D.vst->time_base = D.venc->time_base;

    // Overlay assets. Fonts must be registered before the first QPainter text
    // draw or "Geist" silently falls back to a system face.
    D.no_watermark = spec.no_watermark != 0;
    if (spec.font_dir && *spec.font_dir) {
        const QDir fd(QString::fromUtf8(spec.font_dir));
        const auto files = fd.entryList({ QStringLiteral("*.ttf"),
                                          QStringLiteral("*.otf") }, QDir::Files,
                                        QDir::Name);
        for (const QString& f : files)
            QFontDatabase::addApplicationFont(fd.filePath(f));
    }
    if (spec.logo_path && *spec.logo_path) {
        QImage l(QString::fromUtf8(spec.logo_path));
        if (!l.isNull()) D.logo = l.convertToFormat(QImage::Format_RGBA8888);
    }

    // Optional audio: peek the source sample rate, then set up the AAC stream.
    if (!D.audio_path.empty()) {
        AVFormatContext* probe = nullptr;
        int sr = 48000;
        if (avformat_open_input(&probe, D.audio_path.c_str(), nullptr, nullptr) >= 0) {
            if (avformat_find_stream_info(probe, nullptr) >= 0) {
                int as = av_find_best_stream(probe, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
                if (as >= 0 && probe->streams[as]->codecpar->sample_rate > 0)
                    sr = probe->streams[as]->codecpar->sample_rate;
            }
            avformat_close_input(&probe);
            if (!setup_audio_enc(D, sr)) { D.ast = nullptr; }   // audio optional
        }
    }

    if (!(D.oc->oformat->flags & AVFMT_NOFILE)) {
        if (avio_open(&D.oc->pb, D.out_path.c_str(), AVIO_FLAG_WRITE) < 0) {
            err_ = "avio_open failed (bad path?)"; return false; }
    }
    if (avformat_write_header(D.oc, nullptr) < 0) { err_ = "write_header failed"; return false; }
    D.header_written = true;

    D.vframe = av_frame_alloc();
    D.vframe->format = D.venc->pix_fmt; D.vframe->width = D.w; D.vframe->height = D.h;
    if (av_frame_get_buffer(D.vframe, 0) < 0) { err_ = "frame buffer alloc failed"; return false; }
    D.pkt = av_packet_alloc();
    D.sws = sws_getContext(D.w, D.h, AV_PIX_FMT_RGBA, D.w, D.h, D.venc->pix_fmt,
                           SWS_BILINEAR, nullptr, nullptr, nullptr);
    if (!D.sws) { err_ = "sws context failed"; return false; }
    return true;
}

// Watermark / logo / lyrics, drawn straight onto the RGBA frame. No vertical
// flip: QRhi readback is top-down (the Python prototype's moderngl FBO was
// bottom-up, hence its vflip - do not reintroduce it here).
static void paint_overlays(Exporter::Impl& D, uint8_t* rgba, const char* text) {
    QImage img(rgba, D.w, D.h, QImage::Format_RGBA8888);
    QPainter p(&img);
    p.setRenderHint(QPainter::Antialiasing);

    if (!D.logo.isNull()) {
        int lw = D.logo.width(), lh = D.logo.height();
        const int max_w = int(D.w * 0.12);            // 12% of width, keep aspect
        if (lw > max_w) { lh = int(lh * (double(max_w) / lw)); lw = max_w; }
        p.drawImage(QRect(D.w - lw - 30, D.h - lh - 30, lw, lh), D.logo);
    }
    if (!D.no_watermark) {
        p.setFont(QFont(QStringLiteral("Geist"), 16));
        p.setPen(QColor(245, 245, 245, 120));
        p.drawText(30, D.h - 30, QStringLiteral("RIFT"));
    }
    if (text && *text) {
        const QString s = QString::fromUtf8(text);
        p.setFont(QFont(QStringLiteral("Geist"), 36));
        p.setPen(QColor(0, 0, 0, 180));                // drop shadow
        p.drawText(QRect(2, 2, D.w, D.h), Qt::AlignCenter, s);
        p.setPen(QColor(255, 255, 255, 255));
        p.drawText(QRect(0, 0, D.w, D.h), Qt::AlignCenter, s);
    }
}

bool Exporter::writeFrame(const uint8_t* rgba, const char* overlay_text) {
    Impl& D = *d_;
    if (av_frame_make_writable(D.vframe) < 0) { err_ = "frame not writable"; return false; }

    const uint8_t* src_data = rgba;
    if (D.overlaysAlways() || (overlay_text && *overlay_text)) {
        // QPainter needs a mutable buffer; the caller's readback is const.
        const size_t n = size_t(D.w) * D.h * 4;
        if (D.paint_buf.size() != n) D.paint_buf.resize(n);
        std::memcpy(D.paint_buf.data(), rgba, n);
        paint_overlays(D, D.paint_buf.data(), overlay_text);
        src_data = D.paint_buf.data();
    }

    const uint8_t* src[4] = { src_data, nullptr, nullptr, nullptr };
    int srcStride[4] = { D.w * 4, 0, 0, 0 };
    sws_scale(D.sws, src, srcStride, 0, D.h, D.vframe->data, D.vframe->linesize);
    D.vframe->pts = D.vpts++;
    if (avcodec_send_frame(D.venc, D.vframe) < 0) { err_ = "video send_frame failed"; return false; }
    if (!D.drain(D.venc, D.vst)) { err_ = "video packet write failed"; return false; }
    return true;
}

// Decode the whole source audio -> resample to AAC format -> encode -> mux.
bool Exporter::Impl::transcodeAudio() {
    AVFormatContext* aic = nullptr;
    if (avformat_open_input(&aic, audio_path.c_str(), nullptr, nullptr) < 0) return false;
    bool ok = false;
    AVCodecContext* adec = nullptr;
    SwrContext* swr = nullptr;
    AVAudioFifo* fifo = nullptr;
    AVFrame* dfr = av_frame_alloc();
    AVFrame* efr = av_frame_alloc();
    AVPacket* ap = av_packet_alloc();

    do {
        if (avformat_find_stream_info(aic, nullptr) < 0) break;
        const AVCodec* dc = nullptr;
        int as = av_find_best_stream(aic, AVMEDIA_TYPE_AUDIO, -1, -1, &dc, 0);
        if (as < 0 || !dc) break;
        adec = avcodec_alloc_context3(dc);
        if (avcodec_parameters_to_context(adec, aic->streams[as]->codecpar) < 0) break;
        if (avcodec_open2(adec, dc, nullptr) < 0) break;

        if (swr_alloc_set_opts2(&swr, &aenc->ch_layout, aenc->sample_fmt, aenc->sample_rate,
                                &adec->ch_layout, adec->sample_fmt, adec->sample_rate,
                                0, nullptr) < 0 || swr_init(swr) < 0) break;

        fifo = av_audio_fifo_alloc(aenc->sample_fmt, aenc->ch_layout.nb_channels, 1);
        if (!fifo) break;

        // encode whatever full frames the FIFO can supply
        auto pump = [&](bool flush)->bool {
            while (av_audio_fifo_size(fifo) >= aframe_size ||
                   (flush && av_audio_fifo_size(fifo) > 0)) {
                int n = av_audio_fifo_size(fifo);
                if (!flush) n = aframe_size; else n = n < aframe_size ? n : aframe_size;
                av_frame_unref(efr);
                efr->nb_samples = n;
                av_channel_layout_copy(&efr->ch_layout, &aenc->ch_layout);
                efr->format = aenc->sample_fmt;
                efr->sample_rate = aenc->sample_rate;
                if (av_frame_get_buffer(efr, 0) < 0) return false;
                av_audio_fifo_read(fifo, (void**)efr->data, n);
                efr->pts = apts; apts += n;
                if (avcodec_send_frame(aenc, efr) < 0) return false;
                if (!drain(aenc, ast)) return false;
            }
            return true;
        };

        // read/decode/resample loop
        while (av_read_frame(aic, ap) >= 0) {
            if (ap->stream_index == as && avcodec_send_packet(adec, ap) >= 0) {
                while (avcodec_receive_frame(adec, dfr) >= 0) {
                    int out_max = (int)av_rescale_rnd(
                        swr_get_delay(swr, adec->sample_rate) + dfr->nb_samples,
                        aenc->sample_rate, adec->sample_rate, AV_ROUND_UP);
                    uint8_t** cvt = nullptr;
                    if (av_samples_alloc_array_and_samples(&cvt, nullptr,
                            aenc->ch_layout.nb_channels, out_max, aenc->sample_fmt, 0) < 0) break;
                    int got = swr_convert(swr, cvt, out_max,
                            (const uint8_t**)dfr->data, dfr->nb_samples);
                    if (got > 0) av_audio_fifo_write(fifo, (void**)cvt, got);
                    if (cvt) { av_freep(&cvt[0]); av_freep(&cvt); }
                    if (!pump(false)) break;
                }
            }
            av_packet_unref(ap);
        }
        // flush resampler tail
        for (;;) {
            uint8_t** cvt = nullptr;
            if (av_samples_alloc_array_and_samples(&cvt, nullptr,
                    aenc->ch_layout.nb_channels, aframe_size, aenc->sample_fmt, 0) < 0) break;
            int got = swr_convert(swr, cvt, aframe_size, nullptr, 0);
            if (got > 0) av_audio_fifo_write(fifo, (void**)cvt, got);
            if (cvt) { av_freep(&cvt[0]); av_freep(&cvt); }
            if (got <= 0) break;
        }
        pump(true);
        avcodec_send_frame(aenc, nullptr);       // flush AAC encoder
        drain(aenc, ast);
        ok = true;
    } while (false);

    if (fifo) av_audio_fifo_free(fifo);
    if (swr)  swr_free(&swr);
    if (adec) avcodec_free_context(&adec);
    av_frame_free(&dfr); av_frame_free(&efr); av_packet_free(&ap);
    avformat_close_input(&aic);
    return ok;
}

bool Exporter::finish() {
    Impl& D = *d_;
    if (!D.oc || !D.header_written) return false;
    avcodec_send_frame(D.venc, nullptr);        // flush video
    D.drain(D.venc, D.vst);
    if (D.ast && !D.audio_path.empty()) {
        if (!D.transcodeAudio())
            std::fprintf(stderr, "[Exporter] audio mux failed; video-only output\n");
    }
    int r = av_write_trailer(D.oc);
    D.close();
    if (r < 0) { err_ = "write_trailer failed"; return false; }
    return true;
}
#else
bool Exporter::open(const rift_export_spec&) { err_ = "built without FFMPEG"; return false; }
bool Exporter::writeFrame(const uint8_t*, const char*) { return false; }
bool Exporter::finish() { return false; }
#endif

} // namespace rift
