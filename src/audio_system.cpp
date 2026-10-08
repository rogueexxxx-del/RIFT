// AudioSystem impl.
//
// The channel math (AnalysisSource + Smoother) is header-only and already
// numerically validated (parity check A). This file adds playback
// (miniaudio) + the per-frame tick that publishes to the ChannelRing, plus
// the live-input FFT path (pffft). Playback/FFT calls are marked <<MA>> /
// <<PFFFT>> for the build machine; the offline tick works without them.
#include "audio_system.hpp"
#include <cstdio>

#if RIFT_WITH_AUDIO
#include <miniaudio.h>          // declarations only; impl lives in miniaudio_impl.cpp
#include <pffft/pffft.h>        // vcpkg installs it under a pffft/ subdir
#include <algorithm>            // std::clamp / std::max
#include <atomic>
#include <cmath>
#include <cstring>
#include <vector>
#endif

namespace rift {

#if RIFT_WITH_AUDIO
// Live analysis constants. n_fft matches the offline analyzer (audio_engine.py
// uses 2048) so the band edges below land on comparable resolution.
static constexpr int kFftN  = 2048;
static constexpr int kRingN = 1 << 15;      // power of two, ~0.68 s at 48k
#endif

struct AudioSystem::Ma {
#if RIFT_WITH_AUDIO
    // ── playback: the mixer's output device ──
    // The mixer IS the sound source now; a raw playback device with our data
    // callback replaces the ma_engine + ma_sound pair that played one file.
    // The device is the master clock: the mixer's frame cursor is what the
    // listener hears, so visuals stay locked to it.
    ma_device        output{};
    bool             output_ok = false;
    AudioMixer*      mixer = nullptr;   // borrowed; lives as long as AudioSystem

    // ── live capture ──
    ma_device        input{};
    bool             input_ok = false;
    // Lock-free-ish ring: the audio callback only advances `wpos`, the render
    // thread only reads behind it. Locking inside an audio callback would risk
    // dropouts, and a torn read costs at most one slightly stale frame.
    float                 ring[kRingN] = {0};
    std::atomic<uint64_t> wpos{0};
    uint32_t              sr = 48000;

    PFFFT_Setup* fft = nullptr;
    std::vector<float> win, in, out, work;
    std::vector<float> prev_mag;            // previous frame, for spectral flux
    // Live signals have no "whole track" to normalise against, so each channel
    // tracks a decaying peak and is scaled by it (a simple AGC).
    float peak[RIFT_CH_COUNT] = {0};
#endif
};

AudioSystem::AudioSystem(ChannelRing* ring)
    : ring_(ring), mixer_(std::make_unique<AudioMixer>()) {}

AudioSystem::~AudioSystem() {
    stopLive();
#if RIFT_WITH_AUDIO
    if (vis_fft_) { pffft_destroy_setup((PFFFT_Setup*)vis_fft_); vis_fft_ = nullptr; }
    if (spec_in_)   { pffft_aligned_free(spec_in_); spec_in_ = nullptr; }
    if (spec_out_)  { pffft_aligned_free(spec_out_); spec_out_ = nullptr; }
    if (spec_work_) { pffft_aligned_free(spec_work_); spec_work_ = nullptr; }
    if (spec_fft_)  { pffft_destroy_setup((PFFFT_Setup*)spec_fft_); spec_fft_ = nullptr; }
    // Stop the device BEFORE the mixer dies: the callback borrows it.
    if (ma_ && ma_->output_ok) {
        ma_device_uninit(&ma_->output);
        ma_->output_ok = false;
        ma_->mixer = nullptr;
    }
#endif
}

// Audio thread. Sums the placed audio clips into the device buffer; nothing
// else runs here - no decode, no locks, no allocation.
#if RIFT_WITH_AUDIO
static void mixCb(ma_device* dev, void* out, const void*, ma_uint32 frames) {
    auto* M = static_cast<AudioSystem::Ma*>(dev->pUserData);
    if (M && M->mixer) M->mixer->mix(static_cast<float*>(out), frames);
    else std::memset(out, 0, size_t(frames) * kMixChannels * sizeof(float));
}
#endif

// One file is now one audio clip on A1 - the wrapper keeps every existing
// caller (the audio panel, --audio, project load) working unchanged.
bool AudioSystem::load(const std::string& audio_path,
                       const std::string& analysis_path) {
    std::vector<AudioClipSpec> clips;
    if (!audio_path.empty()) {
        AudioClipSpec a;
        a.path  = audio_path;
        a.start = 0.0;
        a.lane  = 0;
        clips.push_back(a);
    }
    setAudioClips(clips, analysis_path);
    // A fresh load starts from the top. This reset belongs HERE and not in
    // setAudioClips: editing a clip mid-playback goes through the same call,
    // and that must not move the transport.
    playhead_.store(0.0);
    if (mixer_) mixer_->seek(0);
    return ready_.load();
}

bool AudioSystem::setAudioClips(const std::vector<AudioClipSpec>& clips,
                                const std::string& analysis_path) {
    audio_clips_   = clips;
    analysis_path_ = analysis_path;
    smoother_.reset();

    // Single-clip blob optimization: exactly one untrimmed clip at the start
    // with a matching .analysis blob keeps the numerically validated offline
    // channel path, so an existing single-file project reacts exactly as it
    // did before mixing existed. Any other shape analyzes the mix live.
    const bool single = clips.size() == 1
                     && clips[0].start <= 0.0 && clips[0].in <= 0.0;
    blob_active_ = single && !analysis_path.empty() && src_.load(analysis_path);

    if (mixer_) {
        mixer_->setClips(clips);
        mixer_->setLoop(loop_.load());
    }

#if RIFT_WITH_AUDIO
    if (!ma_) ma_ = std::make_unique<Ma>();
    // Open the playback device once the mix has something to play; it then
    // runs for the life of the system and `playing_` gates the sound.
    if (!ma_->output_ok && mixer_ && !mixer_->empty()) {
        ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
        cfg.playback.format   = ma_format_f32;
        cfg.playback.channels = kMixChannels;
        cfg.sampleRate        = kMixRate;
        cfg.dataCallback      = mixCb;
        cfg.pUserData         = ma_.get();
        if (ma_device_init(nullptr, &cfg, &ma_->output) == MA_SUCCESS) {
            ma_->mixer = mixer_.get();   // BEFORE start: the callback runs now
            if (ma_device_start(&ma_->output) == MA_SUCCESS) {
                ma_->output_ok = true;
            } else {
                ma_device_uninit(&ma_->output);
                std::fprintf(stderr, "[AudioSystem] playback device would not "
                                     "start; channels still work\n");
            }
        } else {
            std::fprintf(stderr, "[AudioSystem] no playback device; channels "
                                 "still work, no monitor audio\n");
        }
    }
#else
    if (!ma_) ma_ = std::make_unique<Ma>();
#endif

    rebuildMixData_();
    return ready_.load();
}

// Beat markers. The blob's KICK plane is low-band spectral flux, so its peaks
// are actual hits; peak-picking that is far better than anything derivable from
// an amplitude envelope. Without a blob, fall back to flux over the waveform
// envelope - coarser (one bucket is tens of ms), but a usable grid to snap to.
std::vector<float> AudioSystem::waveform() const {
    std::lock_guard<std::mutex> lk(data_mu_);
    return wave_;
}

std::vector<double> AudioSystem::beats() const {
    std::lock_guard<std::mutex> lk(data_mu_);
    return beats_;
}

void AudioSystem::buildBeats_(double duration_hint) {
    std::lock_guard<std::mutex> lk(data_mu_);
    beats_.clear();
    if (src_.frames() > 0) {
        beats_ = src_.onsets();
        if (!beats_.empty()) return;
    }
    if (wave_.size() < 4 || duration_hint <= 0.0) return;

    // Rising edges only: a beat is where energy JUMPS, not where it is high.
    std::vector<float> flux(wave_.size(), 0.f);
    for (size_t i = 1; i < wave_.size(); ++i)
        flux[i] = std::max(0.f, wave_[i] - wave_[i - 1]);

    // Lower delta than the blob path: envelope flux is much flatter than
    // per-band spectral flux.
    beats_ = pickPeaks(flux.data(), flux.size(),
                       duration_hint / double(wave_.size()), 0.02f, 0.12);
}

// Rebuild everything derived from the audio after a structural change.
//
// pcm_ becomes the MONO MIX of the audio tracks (same shape the old decoded
// file had: mono f32 at one rate), so the scope, the FFT analyzer and the
// envelope code below all keep working untouched - they now simply see the
// mix instead of one file. The waveform and beats are rebuilt from it.
void AudioSystem::rebuildMixData_() {
    pcm_.clear();
    pcm_rate_ = 0;

    if (mixer_ && !mixer_->empty()) {
        mixer_->renderMono(pcm_);
        pcm_rate_ = kMixRate;
    }
    wave_dur_ = pcm_rate_ ? double(pcm_.size()) / double(pcm_rate_) : 0.0;

    // Peak-per-bucket envelope over the mix, same bucket count as always so
    // the timeline's drawing code needs no changes. Built into a LOCAL and
    // published at the end so data_mu_ is never held across the loop.
    constexpr int kBuckets = 2048;
    std::vector<float> w(kBuckets, 0.f);
    if (!pcm_.empty()) {
        const size_t per = std::max<size_t>(1, pcm_.size() / kBuckets);
        for (size_t i = 0; i < pcm_.size(); ++i) {
            const size_t b = std::min<size_t>(kBuckets - 1, i / per);
            w[b] = std::max(w[b], std::fabs(pcm_[i]));          // peak, not mean
        }
    }
    { std::lock_guard<std::mutex> lk(data_mu_); wave_ = std::move(w); }

    buildBeats_(blob_active_ ? duration() : wave_dur_);
    // Publish AFTER the pair is built, so a poller that notices the new
    // generation always sees a complete waveform+beats pair.
    data_gen_.fetch_add(1, std::memory_order_release);
    // "Ready" means there is something to drive the 10 channels from: the
    // blob, or any decoded mix. Gating on the blob alone left every meter and
    // every audio binding dead for a plain wav.
    ready_.store(blob_active_ || !pcm_.empty());
}

// Fill a waveform window and its spectrum for whatever is currently audible.
//
// Two sources, same output: decoded PCM when a file is loaded, the live
// capture ring otherwise. The caller does not care which - a scope should
// draw in both modes - so the branch lives here rather than in every effect.
void AudioSystem::visualiser(double playhead, float* wave, int nwave,
                             float* spec, int nspec) {
    if (wave && nwave > 0) std::fill(wave, wave + nwave, 0.f);
    if (spec && nspec > 0) std::fill(spec, spec + nspec, 0.f);
#if RIFT_WITH_AUDIO
    // Analysis window. Fixed rather than derived from nwave so the frequency
    // resolution does not change when the effect asks for a different width.
    constexpr int kN = 2048;
    if (vis_in_.empty()) {
        vis_in_.resize(kN); vis_out_.resize(kN); vis_work_.resize(kN);
        vis_win_.resize(kN);
        for (int i = 0; i < kN; ++i)                       // Hann
            vis_win_[i] = 0.5f * (1.f - std::cos(2.f * 3.14159265f * i / (kN - 1)));
        vis_fft_ = pffft_new_setup(kN, PFFFT_REAL);
    }
    if (!vis_fft_) return;

    // ── gather kN samples centred on what is being heard ──
    bool got = false;
    if (!pcm_.empty() && pcm_rate_) {
        const int64_t centre = int64_t(playhead * double(pcm_rate_));
        const int64_t start  = centre - kN / 2;
        for (int i = 0; i < kN; ++i) {
            const int64_t j = start + i;
            vis_in_[i] = (j >= 0 && j < int64_t(pcm_.size())) ? pcm_[size_t(j)] : 0.f;
        }
        got = true;
    } else if (ma_ && live_.load()) {
        const uint64_t w = ma_->wpos.load(std::memory_order_acquire);
        if (w >= uint64_t(kN)) {
            const uint64_t s0 = w - kN;
            for (int i = 0; i < kN; ++i)
                vis_in_[i] = ma_->ring[(s0 + i) & (kRingN - 1)];
            got = true;
        }
    }
    if (!got) return;

    // ── waveform: decimate to nwave by peak, so a spike never vanishes ──
    if (wave && nwave > 0) {
        const int per = std::max(1, kN / nwave);
        for (int o = 0; o < nwave; ++o) {
            float peak = 0.f;
            for (int i = 0; i < per; ++i) {
                const int j = o * per + i;
                if (j >= kN) break;
                if (std::fabs(vis_in_[j]) > std::fabs(peak)) peak = vis_in_[j];
            }
            wave[o] = std::clamp(peak, -1.f, 1.f);
        }
    }

    // ── spectrum ──
    if (spec && nspec > 0) {
        // Windowing happens after the waveform copy: the scope wants the raw
        // signal, the FFT wants it tapered.
        for (int i = 0; i < kN; ++i) vis_in_[i] *= vis_win_[i];
        pffft_transform_ordered((PFFFT_Setup*)vis_fft_, vis_in_.data(),
                                vis_out_.data(), vis_work_.data(),
                                PFFFT_FORWARD);
        const int bins = kN / 2;
        for (int o = 0; o < nspec; ++o) {
            // Log frequency axis: linear bins give 90% of the width to content
            // above 5 kHz, where music has almost nothing to show.
            const float t0 = float(o)       / float(nspec);
            const float t1 = float(o + 1)   / float(nspec);
            const int b0 = std::clamp(int(std::pow(float(bins), t0)), 1, bins - 1);
            const int b1 = std::clamp(int(std::pow(float(bins), t1)), b0 + 1, bins);
            float acc = 0.f;
            for (int b = b0; b < b1; ++b) {
                const float re = vis_out_[2*b], im = vis_out_[2*b + 1];
                acc = std::max(acc, std::sqrt(re*re + im*im));
            }
            // dB, mapped -60..0 dB into 0..1 - the range a meter actually uses.
            const float db = 20.f * std::log10(std::max(acc / (kN * 0.25f), 1e-6f));
            spec[o] = std::clamp((db + 60.f) / 60.f, 0.f, 1.f);
        }
    }
#else
    (void)playhead; (void)wave; (void)nwave; (void)spec; (void)nspec;
#endif
}

void AudioSystem::updateVisualizerTap(double playhead) {
#if RIFT_WITH_AUDIO
    constexpr int kN = VisualizerTap::kCapacity;
    tap_.sampleRate = pcm_rate_ ? pcm_rate_ : 48000;

    if (mixer_ && !mixer_->empty()) {
        const int64_t end = int64_t(playhead * double(kMixRate));
        const int64_t start = end - kN;
        std::vector<float> interleaved(kN * 2, 0.f);
        mixer_->renderRange(interleaved.data(), start, kN);
        for (int i = 0; i < kN; ++i) {
            tap_.L[i] = interleaved[i * 2];
            tap_.R[i] = interleaved[i * 2 + 1];
            tap_.mono[i] = (tap_.L[i] + tap_.R[i]) * 0.5f;
        }
    } else if (!pcm_.empty() && pcm_rate_) {
        const int64_t end = int64_t(playhead * double(pcm_rate_));
        const int64_t start = end - kN;
        for (int i = 0; i < kN; ++i) {
            const int64_t j = start + i;
            float s = (j >= 0 && j < int64_t(pcm_.size())) ? pcm_[size_t(j)] : 0.f;
            tap_.L[i] = s;
            tap_.R[i] = s;
            tap_.mono[i] = s;
        }
    } else if (ma_ && live_.load()) {
        const uint64_t w = ma_->wpos.load(std::memory_order_acquire);
        if (w >= uint64_t(kN)) {
            const uint64_t s0 = w - kN;
            for (int i = 0; i < kN; ++i) {
                float s = ma_->ring[(s0 + i) & (kRingN - 1)];
                tap_.L[i] = s;
                tap_.R[i] = s;
                tap_.mono[i] = s;
            }
        } else {
            std::fill(tap_.L, tap_.L + kN, 0.f);
            std::fill(tap_.R, tap_.R + kN, 0.f);
            std::fill(tap_.mono, tap_.mono + kN, 0.f);
        }
    } else {
        std::fill(tap_.L, tap_.L + kN, 0.f);
        std::fill(tap_.R, tap_.R + kN, 0.f);
        std::fill(tap_.mono, tap_.mono + kN, 0.f);
    }
#else
    (void)playhead;
#endif
}

void AudioSystem::getOscilloscope(double playhead, float* outW, int nW, float windowMs) {
    if (!outW || nW <= 0) return;
    std::fill(outW, outW + nW, 0.f);
#if RIFT_WITH_AUDIO
    updateVisualizerTap(playhead);

    constexpr int kScopeBuf = 4096;
    const float* src = tap_.mono + (VisualizerTap::kCapacity - kScopeBuf);

    int W = nW;
    if (windowMs > 0.f && tap_.sampleRate > 0) {
        W = std::clamp(int(windowMs * 0.001f * float(tap_.sampleRate) + 0.5f), 64, kScopeBuf / 2);
    }
    W = std::min(W, kScopeBuf / 2);

    float peak = 0.f;
    for (int i = 0; i < kScopeBuf; ++i)
        peak = std::max(peak, std::abs(src[i]));
    if (peak < 1e-4f) return; // silence: flatline

    const float fc = 400.f;
    const float sr = tap_.sampleRate ? float(tap_.sampleRate) : 48000.f;
    const float alpha = 1.0f - std::exp(-2.0f * 3.14159265f * fc / sr);
    std::vector<float> trig(kScopeBuf);
    float lp = 0.f;
    for (int i = 0; i < kScopeBuf; ++i) {
        lp += alpha * (src[i] - lp);
        trig[i] = lp;
    }

    const float threshold = 0.02f;
    int best_i = -1;
    bool armed = false;
    for (int i = 0; i + W < kScopeBuf; ++i) {
        if (trig[i] < -threshold) armed = true;
        if (armed && trig[i] <= 0.f && trig[i + 1] > 0.f) {
            best_i = i;
            armed = false;
        }
    }

    if (best_i < 0) {
        best_i = std::clamp(last_scope_trigger_i_, 0, kScopeBuf - W - 1);
    } else {
        last_scope_trigger_i_ = best_i;
    }

    const float denom = trig[best_i + 1] - trig[best_i];
    const float offset = denom > 1e-6f ? std::clamp(-trig[best_i] / denom, 0.f, 1.f) : 0.f;

    for (int k = 0; k < nW; ++k) {
        const float pos = (nW == W) ? float(k) : (float(k) * float(W) / float(nW));
        const float sampleIdx = float(best_i) + offset + pos;
        const int i0 = std::clamp(int(std::floor(sampleIdx)), 0, kScopeBuf - 1);
        const int i1 = std::clamp(i0 + 1, 0, kScopeBuf - 1);
        const float frac = sampleIdx - float(i0);
        outW[k] = std::clamp(src[i0] + frac * (src[i1] - src[i0]), -1.f, 1.f);
    }
#else
    (void)playhead; (void)windowMs;
#endif
}

void AudioSystem::getSpectrum(double playhead, float* outSpec, int nSpec, float dt, float slopeDbPerOct) {
    if (!outSpec || nSpec <= 0) return;
    std::fill(outSpec, outSpec + nSpec, 0.f);
#if RIFT_WITH_AUDIO
    constexpr int kN = 4096;
    if (!spec_fft_) {
        spec_fft_ = pffft_new_setup(kN, PFFFT_REAL);
        spec_in_   = (float*)pffft_aligned_malloc(kN * sizeof(float));
        spec_out_  = (float*)pffft_aligned_malloc(kN * sizeof(float));
        spec_work_ = (float*)pffft_aligned_malloc(kN * sizeof(float));
        spec_win_.resize(kN);
        for (int i = 0; i < kN; ++i) {
            // Hann window: 0.5 * (1 - cos(2*pi*i / (N-1)))
            spec_win_[i] = 0.5f * (1.f - std::cos(2.f * 3.141592653589793f * float(i) / float(kN - 1)));
        }
    }
    if (!spec_fft_ || !spec_in_ || !spec_out_ || !spec_work_) return;

    // Latest 4096 mono samples from the shared 8192 tap buffer
    const int offset = VisualizerTap::kCapacity - kN;
    const float* src = tap_.mono + offset;

    // Check silence
    float peak = 0.f;
    for (int i = 0; i < kN; ++i) {
        peak = std::max(peak, std::abs(src[i]));
    }

    // Hann window sum: for Hann window of length N, sum(w) = N / 2 = 2048.0
    constexpr float sum_w = float(kN) * 0.5f;

    // FFT complex output has N/2 + 1 bins: 0 to 2048
    constexpr int kBins = kN / 2; // 2048
    float bin_db[kBins + 1];

    if (peak < 1e-4f) {
        std::fill(bin_db, bin_db + kBins + 1, -90.f);
    } else {
        // Window the mono samples
        for (int i = 0; i < kN; ++i) {
            spec_in_[i] = src[i] * spec_win_[i];
        }

        pffft_transform_ordered((PFFFT_Setup*)spec_fft_, spec_in_, spec_out_, spec_work_, PFFFT_FORWARD);

        // In pffft ordered real format:
        // out[0] = DC real, out[1] = Nyquist real
        // out[2*k] = real, out[2*k + 1] = imag for k = 1 .. kBins - 1
        bin_db[0] = 20.f * std::log10(std::abs(spec_out_[0]) / sum_w + 1e-10f);
        bin_db[kBins] = 20.f * std::log10(std::abs(spec_out_[1]) / sum_w + 1e-10f);
        for (int k = 1; k < kBins; ++k) {
            const float re = spec_out_[2 * k];
            const float im = spec_out_[2 * k + 1];
            const float mag = std::sqrt(re * re + im * im) / sum_w;
            bin_db[k] = 20.f * std::log10(mag + 1e-10f);
        }
        for (int k = 0; k <= kBins; ++k) {
            bin_db[k] = std::clamp(bin_db[k], -90.f, 0.f);
        }
    }

    // Logarithmic frequency mapping: 20 Hz to 20 kHz
    const float sr = float(tap_.sampleRate > 0 ? tap_.sampleRate : 48000);
    const float binWidth = sr / float(kN); // ~11.72 Hz at 48kHz
    const float f_min = 20.f;
    const float f_max = std::min(20000.f, sr * 0.499f);
    const float logRatio = std::log(f_max / f_min);

    if (raw_spec_.size() != size_t(nSpec)) raw_spec_.resize(nSpec, 0.f);
    if (vis_smooth_db_.size() != size_t(nSpec)) vis_smooth_db_.assign(nSpec, -90.f);

    const float safeDt = std::clamp(dt, 0.001f, 0.1f);
    // Linear fall in dB: e.g. 60 dB per second
    const float fall_dB = 60.f * safeDt;

    for (int o = 0; o < nSpec; ++o) {
        const float t = float(o) / float(std::max(1, nSpec - 1));
        const float f_c = f_min * std::exp(t * logRatio);

        const float t_lo = float(std::max(0.f, float(o) - 0.5f)) / float(std::max(1, nSpec - 1));
        const float t_hi = float(std::min(float(nSpec - 1), float(o) + 0.5f)) / float(std::max(1, nSpec - 1));
        const float f_lo = f_min * std::exp(t_lo * logRatio);
        const float f_hi = f_min * std::exp(t_hi * logRatio);

        const float b_c = f_c / binWidth;
        const float b_lo = f_lo / binWidth;
        const float b_hi = f_hi / binWidth;

        float val_db = -90.f;
        if ((b_hi - b_lo) <= 1.0f) {
            // Low frequencies: interpolate between sparse bins
            const int k0 = std::clamp(int(std::floor(b_c)), 0, kBins - 1);
            const int k1 = k0 + 1;
            const float frac = b_c - float(k0);
            val_db = bin_db[k0] * (1.f - frac) + bin_db[k1] * frac;
        } else {
            // High frequencies: max of bins in group
            const int k_start = std::clamp(int(std::floor(b_lo)), 0, kBins);
            const int k_end = std::clamp(int(std::ceil(b_hi)), k_start, kBins);
            val_db = -90.f;
            for (int k = k_start; k <= k_end; ++k) {
                val_db = std::max(val_db, bin_db[k]);
            }
        }

        // Slope compensation: +3 dB/octave above 20 Hz
        if (slopeDbPerOct != 0.f && f_c > f_min) {
            const float octaves = std::log2(f_c / f_min);
            val_db += octaves * slopeDbPerOct;
            val_db = std::clamp(val_db, -90.f, 0.f);
        }

        // Cache raw normalized dB (0..1) for Spectrogram
        raw_spec_[o] = std::clamp((val_db + 90.f) / 90.f, 0.f, 1.f);

        // Smoothing in the dB domain:
        // Attack is instant; fall is linear (vis - fall_dB)
        if (val_db > vis_smooth_db_[o]) {
            vis_smooth_db_[o] = val_db;
        } else {
            vis_smooth_db_[o] = std::max(val_db, vis_smooth_db_[o] - fall_dB);
        }

        // Map -90..0 dB into 0..1 for shader display
        outSpec[o] = std::clamp((vis_smooth_db_[o] + 90.f) / 90.f, 0.f, 1.f);
    }
#else
    (void)playhead; (void)dt; (void)slopeDbPerOct;
#endif
}

void AudioSystem::getVectorscope(double playhead, float* outX, float* outY, int nPairs) {
    if (!outX || !outY || nPairs <= 0) return;
    std::fill(outX, outX + nPairs, 0.f);
    std::fill(outY, outY + nPairs, 0.f);
#if RIFT_WITH_AUDIO
    constexpr int kCap = VisualizerTap::kCapacity;
    const int count = std::min(nPairs, kCap);
    const int offset = kCap - count;
    const float* pL = tap_.L + offset;
    const float* pR = tap_.R + offset;

    // Check silence threshold to cleanly flatline / zero out
    float peak = 0.f;
    for (int i = 0; i < count; ++i) {
        peak = std::max(peak, std::max(std::abs(pL[i]), std::abs(pR[i])));
    }
    if (peak < 1e-4f) return;

    // Rotate 45 degrees:
    // X = (L - R) * 0.7071 (side, horizontal)
    // Y = (L + R) * 0.7071 (mid, vertical)
    // Pure mono (L == R) yields X == 0 (straight vertical line).
    constexpr float kInvSqrt2 = 0.70710678f;
    for (int i = 0; i < count; ++i) {
        outX[i] = std::clamp((pL[i] - pR[i]) * kInvSqrt2, -1.f, 1.f);
        outY[i] = std::clamp((pL[i] + pR[i]) * kInvSqrt2, -1.f, 1.f);
    }
#else
    (void)playhead; (void)nPairs;
#endif
}

bool AudioSystem::hasPlayback() const {
#if RIFT_WITH_AUDIO
    return ma_ && ma_->output_ok;
#else
    return false;
#endif
}

void AudioSystem::play() {
    playing_.store(true);
    // The device keeps running (it just outputs silence when stopped); the
    // mixer's `playing` flag is what actually gates the sound and the clock.
    if (mixer_) mixer_->start();
}
void AudioSystem::pause() {
    playing_.store(false);
    if (mixer_) mixer_->stop();
}
void AudioSystem::seek(double s) {
    playhead_.store(s);
    smoother_.reset();             // avoid a smear across a jump
    if (mixer_) mixer_->seek(int64_t(s * double(kMixRate)));
}

// When the playback device is open it is the master clock: channel lookup is
// driven by this value, so it must track what the listener actually hears or
// the visuals drift out of sync with the audio. The mixer's frame cursor is
// that clock.
double AudioSystem::playhead() const {
#if RIFT_WITH_AUDIO
    if (hasPlayback() && mixer_) return mixer_->cursorSeconds();
#endif
    return playhead_.load();
}

void AudioSystem::tick(double playhead) {
    playhead_.store(playhead);
    if (!ready_.load() && !live_.load()) return;

    rift_channel_frame cf{};
    cf.playhead = playhead;

    if (live_.load()) {
        float targets[RIFT_CH_COUNT] = {0};
#if RIFT_WITH_AUDIO
        if (ma_ && ma_->input_ok && ma_->fft) analyzeLive_(targets);
#endif
        // Same Smoother as the offline path, so attack/release behaviour is
        // identical - only the source of `targets` differs.
        const float* p = smoother_.update(targets);
        for (int c = 0; c < RIFT_CH_COUNT; ++c) cf.ch[c] = p[c];
    } else if (!blob_active_) {
        // The mix (or a blob-less file, which is a one-clip mix): analyse the
        // mono mix here instead of publishing ten zeros. The blob is an
        // optimisation, not a requirement - a user who just opened a wav, or
        // who has several audio clips placed, still expects the meters to move.
        float targets[RIFT_CH_COUNT] = {0};
        analyzeFromPcm_(playhead, targets);
        const float* p = smoother_.update(targets);
        for (int c = 0; c < RIFT_CH_COUNT; ++c) cf.ch[c] = p[c];
    } else {
        // Offline: playhead -> analysis frame -> raw targets -> smooth.
        uint32_t frame = src_.frameForTime(playhead);
        float targets[RIFT_CH_COUNT];
        src_.targets(frame, targets);
        const float* p = smoother_.update(targets);
        for (int c = 0; c < RIFT_CH_COUNT; ++c) cf.ch[c] = p[c];
    }

    ring_->push(cf);               // lock-free -> render thread
}

#if RIFT_WITH_AUDIO
// Audio thread. Mixes to mono and appends to the ring; nothing else.
static void captureCb(ma_device* dev, void*, const void* input, ma_uint32 frames) {
    auto* M = static_cast<AudioSystem::Ma*>(dev->pUserData);
    if (!M || !input) return;
    const float* src = static_cast<const float*>(input);
    const ma_uint32 ch = dev->capture.channels;
    uint64_t w = M->wpos.load(std::memory_order_relaxed);
    for (ma_uint32 i = 0; i < frames; ++i) {
        float s = 0.f;
        for (ma_uint32 c = 0; c < ch; ++c) s += src[i * ch + c];
        M->ring[(w + i) & (kRingN - 1)] = s / float(ch ? ch : 1);
    }
    M->wpos.store(w + frames, std::memory_order_release);
}
#endif

std::vector<AudioSystem::LiveDevice> AudioSystem::liveDevices() {
    std::vector<LiveDevice> out;
#if RIFT_WITH_AUDIO
    ma_context ctx;
    if (ma_context_init(nullptr, 0, nullptr, &ctx) != MA_SUCCESS) return out;

    ma_device_info* play = nullptr; ma_uint32 nplay = 0;
    ma_device_info* cap  = nullptr; ma_uint32 ncap  = 0;
    if (ma_context_get_devices(&ctx, &play, &nplay, &cap, &ncap) == MA_SUCCESS) {
        // Outputs first: capturing what is PLAYING is the common case here,
        // since the point is to react to another program's sound.
        for (ma_uint32 i = 0; i < nplay; ++i)
            out.push_back({ std::string(play[i].name) + " (playing)", true });
        for (ma_uint32 i = 0; i < ncap; ++i)
            out.push_back({ std::string(cap[i].name), false });
    }
    ma_context_uninit(&ctx);
#endif
    return out;
}

void AudioSystem::setLiveDevice(int index) {
    if (index == live_dev_) return;
    const bool wasLive = live_.load();
    if (wasLive) stopLive();
    live_dev_ = index;
    if (wasLive) startLive();
}

void AudioSystem::startLive() {
#if RIFT_WITH_AUDIO
    if (!ma_) ma_ = std::make_unique<Ma>();
    if (ma_->input_ok) { live_.store(true); return; }

    // Resolve the chosen device. A loopback device is a PLAYBACK device that
    // WASAPI hands us the outgoing mix from, so it is opened with the loopback
    // device type but identified by its playback id.
    bool wantLoopback = false;
    ma_device_id devId{};
    bool haveId = false;
    {
        ma_context ctx;
        if (ma_context_init(nullptr, 0, nullptr, &ctx) == MA_SUCCESS) {
            ma_device_info* play = nullptr; ma_uint32 nplay = 0;
            ma_device_info* cap  = nullptr; ma_uint32 ncap  = 0;
            if (ma_context_get_devices(&ctx, &play, &nplay, &cap, &ncap) == MA_SUCCESS
                && live_dev_ >= 0) {
                const ma_uint32 idx = ma_uint32(live_dev_);
                if (idx < nplay) {
                    devId = play[idx].id; haveId = true; wantLoopback = true;
                } else if (idx - nplay < ncap) {
                    devId = cap[idx - nplay].id; haveId = true;
                }
            }
            ma_context_uninit(&ctx);
        }
    }

    ma_device_config cfg = ma_device_config_init(
        wantLoopback ? ma_device_type_loopback : ma_device_type_capture);
    cfg.capture.format   = ma_format_f32;
    cfg.capture.channels = 0;              // native
    cfg.sampleRate       = 0;              // native
    cfg.dataCallback     = captureCb;
    cfg.pUserData        = ma_.get();
    if (haveId) cfg.capture.pDeviceID = &devId;

    if (ma_device_init(nullptr, &cfg, &ma_->input) != MA_SUCCESS) {
        std::fprintf(stderr,
                     "[AudioSystem] could not open %s device; live input off\n",
                     wantLoopback ? "loopback" : "capture");
        return;
    }
    if (ma_device_start(&ma_->input) != MA_SUCCESS) {
        std::fprintf(stderr, "[AudioSystem] capture device would not start\n");
        ma_device_uninit(&ma_->input);
        return;
    }
    ma_->input_ok = true;
    ma_->sr = ma_->input.sampleRate ? ma_->input.sampleRate : 48000;

    if (!ma_->fft) {
        ma_->fft = pffft_new_setup(kFftN, PFFFT_REAL);
        ma_->win.resize(kFftN);
        for (int i = 0; i < kFftN; ++i)     // Hann, same window family as librosa's default
            ma_->win[i] = 0.5f * (1.f - std::cos(2.f * 3.14159265358979f * i / (kFftN - 1)));
        ma_->in.assign(kFftN, 0.f);
        ma_->out.assign(kFftN, 0.f);
        ma_->work.assign(kFftN, 0.f);
        ma_->prev_mag.assign(kFftN / 2, 0.f);
    }
    std::memset(ma_->peak, 0, sizeof(ma_->peak));

    live_.store(true);
    smoother_.reset();
#else
    std::fprintf(stderr, "[AudioSystem] built without RIFT_WITH_AUDIO\n");
#endif
}

void AudioSystem::stopLive() {
    if (!live_.load()) return;
    live_.store(false);
#if RIFT_WITH_AUDIO
    if (ma_ && ma_->input_ok) {
        ma_device_uninit(&ma_->input);
        ma_->input_ok = false;
    }
    if (ma_ && ma_->fft) {
        pffft_destroy_setup(ma_->fft);
        ma_->fft = nullptr;
    }
#endif
    live_level_.store(0.f);
}

// Feed the decoded file into the same ring the microphone writes to, then run
// the live analyser over it. Reusing that path rather than writing a second
// band-splitter is the point: the two would drift apart, and "reactive" would
// mean something different for a file than for a mic.
bool AudioSystem::analyzeFromPcm_(double playhead, float* targets) {
#if RIFT_WITH_AUDIO
    if (pcm_.empty() || !pcm_rate_) return false;
    if (!ma_) ma_ = std::make_unique<Ma>();
    Ma& M = *ma_;

    if (!M.fft) {
        M.fft = pffft_new_setup(kFftN, PFFFT_REAL);
        if (!M.fft) return false;
        M.win.resize(kFftN);
        for (int i = 0; i < kFftN; ++i)     // Hann, as in the live path
            M.win[i] = 0.5f * (1.f - std::cos(2.f * 3.14159265358979f * i / (kFftN - 1)));
        M.in.assign(kFftN, 0.f);
        M.out.assign(kFftN, 0.f);
        M.work.assign(kFftN, 0.f);
        M.prev_mag.assign(kFftN / 2, 0.f);
        std::memset(M.peak, 0, sizeof(M.peak));
    }
    M.sr = pcm_rate_;

    // The window ENDS at the playhead, matching live capture, where the newest
    // sample is the one just heard. Centring it here would make the channels
    // lead the audio by half a window.
    const int64_t end = int64_t(playhead * double(pcm_rate_));
    const uint64_t w = M.wpos.load(std::memory_order_relaxed);
    for (int i = 0; i < kFftN; ++i) {
        const int64_t j = end - kFftN + i;
        M.ring[(w + i) & (kRingN - 1)] =
            (j >= 0 && j < int64_t(pcm_.size())) ? pcm_[size_t(j)] : 0.f;
    }
    M.wpos.store(w + kFftN, std::memory_order_release);

    analyzeLive_(targets);
    return true;
#else
    (void)playhead; (void)targets;
    return false;
#endif
}

#if RIFT_WITH_AUDIO
// Render thread. Reads the newest kFftN samples, windows + transforms them,
// and fills `targets` with the same 10 channels the offline blob provides.
//
// Band edges match audio_engine.py exactly (bass 20-250, mids 250-2000,
// highs 2000-20000, kick <150, snare 1500-8000) and band energy is the mean of
// magnitude^2 over the bins, as there. What CANNOT match is normalisation:
// offline percentile-normalises against the whole track, which needs the
// future. Live uses a decaying per-channel peak instead, so absolute values
// differ from an offline render of the same audio even though the bands do not.
void AudioSystem::analyzeLive_(float* targets) {
    Ma& M = *ma_;
    const uint64_t w = M.wpos.load(std::memory_order_acquire);
    if (w < uint64_t(kFftN)) return;

    float peakAbs = 0.f;
    const uint64_t start = w - kFftN;
    for (int i = 0; i < kFftN; ++i) {
        const float s = M.ring[(start + i) & (kRingN - 1)];
        peakAbs = std::max(peakAbs, std::fabs(s));
        M.in[i] = s * M.win[i];
    }
    live_level_.store(peakAbs);

    pffft_transform_ordered(M.fft, M.in.data(), M.out.data(), M.work.data(),
                            PFFFT_FORWARD);

    const int bins = kFftN / 2;
    const float binHz = float(M.sr) / float(kFftN);

    auto bandMeanSq = [&](float lo, float hi) {
        const int b0 = std::max(1, int(lo / binHz));
        const int b1 = std::min(bins - 1, int(hi / binHz));
        if (b1 <= b0) return 0.f;
        float acc = 0.f;
        for (int b = b0; b <= b1; ++b) {
            const float re = M.out[2*b], im = M.out[2*b + 1];
            acc += re*re + im*im;
        }
        return acc / float(b1 - b0 + 1);
    };

    // Spectral flux (positive change only) over a bin range = percussive proxy.
    auto fluxIn = [&](float lo, float hi) {
        const int b0 = std::max(1, int(lo / binHz));
        const int b1 = std::min(bins - 1, int(hi / binHz));
        float acc = 0.f;
        for (int b = b0; b <= b1; ++b) {
            const float re = M.out[2*b], im = M.out[2*b + 1];
            const float mag = std::sqrt(re*re + im*im);
            acc += std::max(0.f, mag - M.prev_mag[b]);
        }
        return acc;
    };

    float raw[RIFT_CH_COUNT] = {0};
    raw[RIFT_CH_BASS]      = bandMeanSq(20.f, 250.f);
    raw[RIFT_CH_MELODY]    = bandMeanSq(250.f, 2000.f);
    raw[RIFT_CH_HIGHS]     = bandMeanSq(2000.f, 20000.f);
    raw[RIFT_CH_DRUMS]     = fluxIn(20.f, 20000.f);
    raw[RIFT_CH_TRANSIENT] = raw[RIFT_CH_DRUMS];
    raw[RIFT_CH_KICK]      = fluxIn(20.f, 150.f);
    raw[RIFT_CH_SNARE]     = fluxIn(1500.f, 8000.f);

    // Spectral centroid, normalised to Nyquist -> already 0..1.
    {
        float num = 0.f, den = 0.f;
        for (int b = 1; b < bins; ++b) {
            const float re = M.out[2*b], im = M.out[2*b + 1];
            const float mag = std::sqrt(re*re + im*im);
            num += mag * (b * binHz);
            den += mag;
        }
        targets[RIFT_CH_CENTROID] =
            den > 1e-9f ? std::clamp(num / den / (float(M.sr) * 0.5f), 0.f, 1.f) : 0.f;
    }

    // Store magnitudes for the next frame's flux.
    for (int b = 0; b < bins; ++b) {
        const float re = M.out[2*b], im = M.out[2*b + 1];
        M.prev_mag[b] = std::sqrt(re*re + im*im);
    }

    // Per-channel AGC: track a decaying peak and scale against it, then apply
    // the same 0.6 compression curve the offline path uses.
    for (int c = 0; c < RIFT_CH_COUNT; ++c) {
        if (c == RIFT_CH_CENTROID || c == RIFT_CH_TIME || c == RIFT_CH_BPM) continue;
        M.peak[c] = std::max(raw[c], M.peak[c] * 0.999f);
        const float n = M.peak[c] > 1e-9f
                      ? std::clamp(raw[c] / M.peak[c], 0.f, 1.f) : 0.f;
        targets[c] = std::pow(n, 0.6f);
    }
    // No tempo estimate from a short live window, and no track to ramp through.
    targets[RIFT_CH_BPM]  = 0.f;
    targets[RIFT_CH_TIME] = 0.f;
}
#endif

// Offline bounce of the mix for the exporter: a plain RIFF WAV, f32 stereo at
// kMixRate, written by hand because it is trivial and avoids any encoder
// dependency. libav (the exporter) reads it back like any wav, which keeps
// the whole transcode/mux path untouched.
bool AudioSystem::renderMixToWav(const std::string& path,
                                 double start, double dur) const {
    if (!mixer_ || mixer_->empty() || dur <= 0.0) return false;
    const int64_t total = int64_t(mixer_->duration() * double(kMixRate));
    const int64_t startFrame = int64_t(std::max(0.0, start) * double(kMixRate));
    if (startFrame >= total) return false;
    const int64_t frames = std::min(int64_t(dur * double(kMixRate)),
                                    total - startFrame);
    if (frames <= 0) return false;

    std::vector<float> buf(size_t(frames) * kMixChannels);
    mixer_->renderRange(buf.data(), startFrame, frames);

    std::FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) return false;
    const uint32_t dataBytes = uint32_t(buf.size() * sizeof(float));
    const uint32_t byteRate  = uint32_t(kMixRate * kMixChannels * sizeof(float));
    const uint16_t blockAlign = uint16_t(kMixChannels * sizeof(float));
    auto w32 = [&](uint32_t v) { std::fwrite(&v, 4, 1, f); };
    auto w16 = [&](uint16_t v) { std::fwrite(&v, 2, 1, f); };
    std::fwrite("RIFF", 1, 4, f); w32(36 + dataBytes); std::fwrite("WAVE", 1, 4, f);
    std::fwrite("fmt ", 1, 4, f); w32(16); w16(3); w16(uint16_t(kMixChannels));
    w32(uint32_t(kMixRate)); w32(byteRate); w16(blockAlign); w16(32);
    std::fwrite("data", 1, 4, f); w32(dataBytes);
    const size_t wrote = std::fwrite(buf.data(), 1, dataBytes, f);
    std::fclose(f);
    return wrote == dataBytes;
}

} // namespace rift
