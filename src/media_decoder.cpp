// MediaDecoder impl - libav async software decode -> RGBA -> FrameQueue.
// SW decode + sws_scale to RGBA is the correct, portable baseline; D3D11VA
// zero-copy HW decode is a later optimization (the queue/handoff already
// supports an is_gpu payload). Threading, seek/loop, and the frame-selection
// contract are backend-agnostic (see media_decoder.hpp).
#include "media_decoder.hpp"
#include "rhi_context.hpp"
#include <filesystem>
#include <cstdio>

#if RIFT_WITH_FFMPEG
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}
#endif

namespace fs = std::filesystem;
namespace rift {

#if RIFT_WITH_FFMPEG
struct MediaDecoder::Ff {
    AVFormatContext* fmt = nullptr;
    AVCodecContext*  dec = nullptr;
    SwsContext*      sws = nullptr;
    AVFrame*         frame = nullptr;
    AVPacket*        pkt = nullptr;
    int              vstream = -1;
    AVRational       tb{1, 1};        // stream time base
    int64_t          total_frames = 0;
    int64_t          counter = 0;     // running decoded-frame index

    void close() {
        if (sws)   { sws_freeContext(sws); sws = nullptr; }
        if (frame) { av_frame_free(&frame); }
        if (pkt)   { av_packet_free(&pkt); }
        if (dec)   { avcodec_free_context(&dec); }
        if (fmt)   { avformat_close_input(&fmt); }
        vstream = -1;
    }
};
#else
struct MediaDecoder::Ff { int64_t total_frames = 0; double time_base = 0.0; };
#endif

MediaDecoder::MediaDecoder(RhiContext* rhi) : rhi_(rhi), ff_(std::make_unique<Ff>()) {}
MediaDecoder::~MediaDecoder() { stop(); }

static bool is_image(const std::string& p) {
    auto e = fs::path(p).extension().string();
    for (auto& c : e) c = (char)tolower(c);
    return e==".png"||e==".jpg"||e==".jpeg"||e==".webp"||e==".bmp"||
           e==".tif"||e==".tiff"||e==".svg";
}

void MediaDecoder::open(const std::string& path) {
    stop();
    queue_.start();              // clear the stop latch left by stop()
    last_up_ = -1;
    running_ = true;
    ready_ = false;
    thread_ = std::thread([this, path]{ worker_(path); });
}

#if RIFT_WITH_FFMPEG
// Open `path`, find the video stream, set up decoder + RGBA converter.
// Returns false (and cleans up) on failure. Fills w_/h_/fps_/duration_.
static bool ff_open(MediaDecoder::Ff& F, const std::string& path,
                    int& w, int& h, double& fps, double& duration) {
    if (avformat_open_input(&F.fmt, path.c_str(), nullptr, nullptr) < 0) return false;
    if (avformat_find_stream_info(F.fmt, nullptr) < 0) return false;

    const AVCodec* codec = nullptr;
    F.vstream = av_find_best_stream(F.fmt, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
    if (F.vstream < 0 || !codec) return false;
    AVStream* st = F.fmt->streams[F.vstream];

    F.dec = avcodec_alloc_context3(codec);
    if (!F.dec) return false;
    if (avcodec_parameters_to_context(F.dec, st->codecpar) < 0) return false;
    F.dec->thread_count = 0;                     // auto multi-threaded decode
    if (avcodec_open2(F.dec, codec, nullptr) < 0) return false;

    w = F.dec->width; h = F.dec->height;
    F.tb = st->time_base;

    AVRational fr = st->avg_frame_rate.num ? st->avg_frame_rate : st->r_frame_rate;
    fps = (fr.num && fr.den) ? av_q2d(fr) : 30.0;
    if (F.fmt->duration > 0) duration = double(F.fmt->duration) / AV_TIME_BASE;
    else if (st->duration > 0) duration = st->duration * av_q2d(st->time_base);
    else duration = 0.0;
    F.total_frames = st->nb_frames > 0 ? st->nb_frames
                   : (duration > 0 ? int64_t(duration * fps) : 0);

    F.sws = sws_getContext(w, h, F.dec->pix_fmt, w, h, AV_PIX_FMT_RGBA,
                           SWS_BILINEAR, nullptr, nullptr, nullptr);
    if (!F.sws) return false;
    F.frame = av_frame_alloc();
    F.pkt   = av_packet_alloc();
    return F.frame && F.pkt;
}

// Convert the current decoded F.frame to a DecodedFrame (RGBA). pts in seconds.
static DecodedFrame ff_to_rgba(MediaDecoder::Ff& F, int w, int h) {
    DecodedFrame df;
    df.w = w; df.h = h; df.is_gpu = false;
    df.rgba.resize(size_t(w) * h * 4);
    uint8_t* dst[4] = { df.rgba.data(), nullptr, nullptr, nullptr };
    int dstStride[4] = { w * 4, 0, 0, 0 };
    sws_scale(F.sws, F.frame->data, F.frame->linesize, 0, h, dst, dstStride);
    int64_t pts = F.frame->best_effort_timestamp;
    if (pts == AV_NOPTS_VALUE) pts = F.frame->pts;
    df.pts = (pts == AV_NOPTS_VALUE) ? (F.counter / 30.0) : pts * av_q2d(F.tb);
    df.frame_index = F.counter++;
    return df;
}
#endif

void MediaDecoder::worker_(std::string path) {
#if RIFT_WITH_FFMPEG
    const bool image = is_image(path);

    if (!ff_open(*ff_, path, w_, h_, fps_, duration_)) {
        std::printf("[MediaDecoder] open FAILED: %s\n", path.c_str());
        ff_->close();
        ready_ = true;                 // ready-but-empty; engine renders on black
        return;
    }
    is_video_ = !image && ff_->total_frames != 1;
    ready_ = true;

    Ff& F = *ff_;

    // Single-frame (image): decode one frame, stage it, done.
    if (!is_video_.load()) {
        while (running_.load(std::memory_order_relaxed) &&
               av_read_frame(F.fmt, F.pkt) >= 0) {
            if (F.pkt->stream_index == F.vstream) {
                if (avcodec_send_packet(F.dec, F.pkt) >= 0 &&
                    avcodec_receive_frame(F.dec, F.frame) >= 0) {
                    DecodedFrame df = ff_to_rgba(F, w_, h_);
                    queue_.push(std::move(df));
                    av_packet_unref(F.pkt);
                    break;
                }
            }
            av_packet_unref(F.pkt);
        }
        return;
    }

    // Video decode loop.
    while (running_.load(std::memory_order_relaxed)) {
        double sk = seek_req_.exchange(-1.0);
        if (sk >= 0.0) {
            int64_t ts = int64_t(sk / av_q2d(F.tb));
            av_seek_frame(F.fmt, F.vstream, ts, AVSEEK_FLAG_BACKWARD);
            avcodec_flush_buffers(F.dec);
            queue_.flush();
        }

        int rr = av_read_frame(F.fmt, F.pkt);
        if (getenv("RIFT_DBG") && rr < 0) std::fprintf(stderr, "[dec] read rc=%d (EOF)\n", rr);
        if (rr < 0) {                          // EOF
            if (loop_.load()) {
                av_seek_frame(F.fmt, F.vstream, 0, AVSEEK_FLAG_BACKWARD);
                avcodec_flush_buffers(F.dec);
                F.counter = 0;
                queue_.flush();
                continue;
            }
            break;                             // hold last frame
        }
        if (F.pkt->stream_index != F.vstream) { av_packet_unref(F.pkt); continue; }

        int sp = avcodec_send_packet(F.dec, F.pkt);
        if (sp >= 0) {
            int rf;
            while ((rf = avcodec_receive_frame(F.dec, F.frame)) >= 0) {
                DecodedFrame df = ff_to_rgba(F, w_, h_);
                if (getenv("RIFT_DBG")) std::fprintf(stderr, "[dec] push idx=%lld pts=%.3f\n",
                    (long long)df.frame_index, df.pts);
                if (!queue_.push(std::move(df))) { av_packet_unref(F.pkt); return; }
            }
            if (getenv("RIFT_DBG") && rf != AVERROR(EAGAIN))
                std::fprintf(stderr, "[dec] receive_frame rc=%d\n", rf);
        } else if (getenv("RIFT_DBG")) {
            std::fprintf(stderr, "[dec] send_packet rc=%d\n", sp);
        }
        av_packet_unref(F.pkt);
    }
#else
    (void)path;
    ready_ = true;
#endif
}

uint32_t MediaDecoder::frameForPlayhead(double playhead) {
    DecodedFrame f;
    // 2 s is generous for one frame; past that the decoder is wedged or the
    // source has ended, and the export should finish rather than hang.
    const bool got = blocking_.load()
                   ? queue_.pop_for_blocking(playhead, f, 2000)
                   : queue_.pop_for(playhead, f);
    if (!got) return static_tex_;              // underrun -> last good (0 first)

    if (f.frame_index == last_up_ && static_tex_) return static_tex_;  // unchanged

    if (f.is_gpu) {
        static_tex_ = f.gpu_tex;               // HW path (future zero-copy)
    } else if (!f.rgba.empty() && rhi_) {
        static_tex_ = rhi_->uploadMedia(static_tex_, f.rgba.data(), f.w, f.h);
    }
    last_up_ = f.frame_index;
    return static_tex_;
}

void MediaDecoder::seek(double s) { seek_req_.store(s); }

void MediaDecoder::stop() {
    running_ = false;
    queue_.stop();
    if (thread_.joinable()) thread_.join();
#if RIFT_WITH_FFMPEG
    if (ff_) ff_->close();
#endif
}

} // namespace rift
