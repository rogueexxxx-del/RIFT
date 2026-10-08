// AudioMixer impl.
//
// Structural changes compile a fresh immutable Set (decoding only sources not
// already decoded) and publish it atomically; the audio callback only sums.
#include "audio_mixer.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>

#if RIFT_WITH_FFMPEG
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/channel_layout.h>
#include <libavutil/mathematics.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
}
#endif

namespace rift {

// A decoded source. Shared across every placement of the same path, so moving
// or trimming a clip never re-decodes.
struct AudioMixer::Decoded {
    std::string        path;
    std::vector<float> pcm;     // interleaved stereo, kMixRate
    int64_t            frames = 0;   // per-channel frame count
};

// A placement of a Decoded on the timeline. Immutable except for `gain`.
struct AudioMixer::Placed {
    std::shared_ptr<const Decoded> dec;
    int64_t start  = 0;    // timeline frame of the clip head
    int64_t in     = 0;    // first source frame used
    int64_t placed = 0;    // frames of source used
    int     lane   = 0;
    mutable std::atomic<float> gain{1.f};
};

// The published snapshot. Immutable; swapped whole.
struct AudioMixer::Set {
    std::vector<std::shared_ptr<const Placed>> clips;
    int64_t frames = 0;    // end of the last clip, in frames
    int     lanes  = 1;
};

AudioMixer::AudioMixer() = default;
AudioMixer::~AudioMixer() = default;

bool AudioMixer::empty() const {
    auto s = set_.load();
    return !s || s->clips.empty();
}

int AudioMixer::count() const {
    auto s = set_.load();
    return s ? int(s->clips.size()) : 0;
}

int AudioMixer::laneCount() const {
    auto s = set_.load();
    return s ? std::max(1, s->lanes) : 1;
}

double AudioMixer::duration() const {
    auto s = set_.load();
    return s ? double(s->frames) / double(kMixRate) : 0.0;
}

double AudioMixer::clipStart(int i) const {
    auto s = set_.load();
    if (!s || i < 0 || i >= int(s->clips.size())) return 0.0;
    return double(s->clips[i]->start) / double(kMixRate);
}

double AudioMixer::clipSpan(int i) const {
    auto s = set_.load();
    if (!s || i < 0 || i >= int(s->clips.size())) return 0.0;
    return double(s->clips[i]->placed) / double(kMixRate);
}

void AudioMixer::setGain(int index, float gain) {
    auto s = set_.load();
    if (!s || index < 0 || index >= int(s->clips.size())) return;
    s->clips[index]->gain.store(std::clamp(gain, 0.f, 4.f),
                                std::memory_order_relaxed);
}

void AudioMixer::setClips(const std::vector<AudioClipSpec>& clips) {
    auto old = set_.load();
    auto ns  = std::make_shared<Set>();

    // Auto-append resolves per audio lane: a clip with start < 0 lands after
    // whatever is already on its own lane.
    std::vector<int64_t> laneEnd;

    for (const AudioClipSpec& spec : clips) {
        // Reuse a decoded source if any previous placement used the same path.
        std::shared_ptr<const Decoded> dec;
        if (old) {
            for (const auto& op : old->clips) {
                if (op->dec && op->dec->path == spec.path) { dec = op->dec; break; }
            }
        }
        if (!dec) {
            auto d = std::make_shared<Decoded>();
            d->path = spec.path;
            if (!decode(spec.path, d->pcm)) continue;   // unreadable: skip
            d->frames = int64_t(d->pcm.size()) / kMixChannels;
            if (d->frames <= 0) continue;
            dec = d;
        }

        auto p = std::make_shared<Placed>();
        p->dec   = dec;
        p->lane  = std::max(0, spec.lane);
        p->in    = int64_t(std::max(0.0, spec.in) * kMixRate);
        if (p->in > dec->frames) p->in = dec->frames;
        if (spec.out > spec.in) {
            int64_t want = int64_t((spec.out - spec.in) * kMixRate);
            p->placed = std::min(want, dec->frames - p->in);
        } else {
            p->placed = dec->frames - p->in;
        }
        if (p->placed < 0) p->placed = 0;

        if (p->lane >= int(laneEnd.size())) laneEnd.resize(p->lane + 1, 0);
        int64_t st = spec.start < 0.0
                   ? laneEnd[p->lane]
                   : int64_t(std::max(0.0, spec.start) * kMixRate);
        p->start = st;
        laneEnd[p->lane] = st + p->placed;

        p->gain.store(float(std::clamp(spec.gain, 0.0, 2.0)),
                      std::memory_order_relaxed);

        ns->lanes  = std::max(ns->lanes, p->lane + 1);
        ns->frames = std::max(ns->frames, st + p->placed);
        ns->clips.push_back(std::move(p));
    }

    set_.store(ns, std::memory_order_release);
}

void AudioMixer::applyCommands_() {
    const int64_t s = seek_req_.exchange(-1, std::memory_order_acq_rel);
    if (s >= 0) cursor_.store(s, std::memory_order_release);
}

void AudioMixer::mix(float* out, uint32_t frames) {
    std::memset(out, 0, size_t(frames) * kMixChannels * sizeof(float));
    applyCommands_();
    if (!playing_.load(std::memory_order_acquire)) return;

    auto s = set_.load(std::memory_order_acquire);
    if (!s || s->clips.empty()) return;

    const int64_t total = s->frames;
    int64_t pos = cursor_.load(std::memory_order_relaxed);
    bool done = false;

    for (uint32_t i = 0; i < frames; ++i) {
        if (total > 0 && pos >= total) {
            if (loop_.load(std::memory_order_relaxed)) {
                pos = 0;
            } else {
                done = true;
                break;
            }
        }
        float l = 0.f, r = 0.f;
        for (const auto& c : s->clips) {
            const int64_t rel = pos - c->start;
            if (rel < 0 || rel >= c->placed) continue;
            const int64_t src = c->in + rel;
            if (src < 0 || src >= c->dec->frames) continue;
            const float g  = c->gain.load(std::memory_order_relaxed);
            const size_t si = size_t(src) * kMixChannels;
            l += c->dec->pcm[si]     * g;
            r += c->dec->pcm[si + 1] * g;
        }
        out[size_t(i) * kMixChannels]     = std::clamp(l, -1.f, 1.f);
        out[size_t(i) * kMixChannels + 1] = std::clamp(r, -1.f, 1.f);
        ++pos;
    }
    cursor_.store(done ? total : pos, std::memory_order_release);
}

void AudioMixer::renderMono(std::vector<float>& out) const {
    auto s = set_.load();
    out.clear();
    if (!s || s->frames <= 0) return;
    out.assign(size_t(s->frames), 0.f);
    for (const auto& c : s->clips) {
        const float g = c->gain.load(std::memory_order_relaxed);
        const int64_t n = c->placed;
        for (int64_t k = 0; k < n; ++k) {
            const int64_t tl = c->start + k;
            if (tl < 0 || tl >= s->frames) continue;
            const size_t si = size_t(c->in + k) * kMixChannels;
            out[size_t(tl)] += 0.5f * (c->dec->pcm[si] + c->dec->pcm[si + 1]) * g;
        }
    }
}

void AudioMixer::renderRange(float* out, int64_t startFrame,
                             int64_t frames) const {
    std::memset(out, 0, size_t(frames) * kMixChannels * sizeof(float));
    auto s = set_.load();
    if (!s) return;
    for (const auto& c : s->clips) {
        const float g = c->gain.load(std::memory_order_relaxed);
        for (int64_t k = 0; k < frames; ++k) {
            const int64_t rel = (startFrame + k) - c->start;
            if (rel < 0 || rel >= c->placed) continue;
            const size_t si = size_t(c->in + rel) * kMixChannels;
            out[size_t(k) * kMixChannels]     += c->dec->pcm[si]     * g;
            out[size_t(k) * kMixChannels + 1] += c->dec->pcm[si + 1] * g;
        }
    }
}

// ── decode ──────────────────────────────────────────────────────────────────

bool AudioMixer::decode(const std::string& path, std::vector<float>& out) {
    out.clear();
#if RIFT_WITH_FFMPEG
    if (path.empty()) return false;
    AVFormatContext* ic = nullptr;
    if (avformat_open_input(&ic, path.c_str(), nullptr, nullptr) < 0) return false;

    bool ok = false;
    AVCodecContext* dec = nullptr;
    SwrContext*     swr = nullptr;
    AVFrame*        fr  = av_frame_alloc();
    AVPacket*       pkt = av_packet_alloc();

    do {
        if (avformat_find_stream_info(ic, nullptr) < 0) break;
        const AVCodec* codec = nullptr;
        const int idx = av_find_best_stream(ic, AVMEDIA_TYPE_AUDIO, -1, -1,
                                            &codec, 0);
        if (idx < 0 || !codec) break;
        dec = avcodec_alloc_context3(codec);
        if (!dec) break;
        if (avcodec_parameters_to_context(dec, ic->streams[idx]->codecpar) < 0) break;
        if (avcodec_open2(dec, codec, nullptr) < 0) break;

        AVChannelLayout outLayout;
        av_channel_layout_default(&outLayout, kMixChannels);   // stereo
        const int swrRet = swr_alloc_set_opts2(
            &swr, &outLayout, AV_SAMPLE_FMT_FLT, kMixRate,
            &dec->ch_layout, dec->sample_fmt, dec->sample_rate, 0, nullptr);
        av_channel_layout_uninit(&outLayout);
        if (swrRet < 0 || swr_init(swr) < 0) break;

        while (av_read_frame(ic, pkt) >= 0) {
            if (pkt->stream_index == idx && avcodec_send_packet(dec, pkt) >= 0) {
                while (avcodec_receive_frame(dec, fr) >= 0) {
                    const int64_t delay = swr_get_delay(swr, dec->sample_rate);
                    const int outMax = int(av_rescale_rnd(
                        delay + fr->nb_samples, kMixRate, dec->sample_rate,
                        AV_ROUND_UP)) + 256;
                    const size_t base = out.size();
                    out.resize(base + size_t(outMax) * kMixChannels);
                    uint8_t* dst[1] = {
                        reinterpret_cast<uint8_t*>(out.data() + base) };
                    int got = swr_convert(swr, dst, outMax,
                                          (const uint8_t**)fr->data,
                                          fr->nb_samples);
                    if (got < 0) got = 0;
                    out.resize(base + size_t(got) * kMixChannels);
                }
            }
            av_packet_unref(pkt);
        }
        // Flush whatever the resampler is holding.
        for (;;) {
            const size_t base = out.size();
            out.resize(base + size_t(4096) * kMixChannels);
            uint8_t* dst[1] = { reinterpret_cast<uint8_t*>(out.data() + base) };
            const int got = swr_convert(swr, dst, 4096, nullptr, 0);
            if (got <= 0) { out.resize(base); break; }
            out.resize(base + size_t(got) * kMixChannels);
        }
        ok = !out.empty();
    } while (false);

    if (swr) swr_free(&swr);
    if (dec) avcodec_free_context(&dec);
    av_frame_free(&fr);
    av_packet_free(&pkt);
    avformat_close_input(&ic);
    return ok;
#else
    (void)path;
    return false;
#endif
}

} // namespace rift
