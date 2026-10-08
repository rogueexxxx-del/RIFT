// AnalysisSource - reads the precomputed .analysis blob (see
// docs/contracts/analysis_blob.md) and serves raw per-frame channel targets.
// mmap in the real engine; plain file read here (portable, header-only, so
// the parity gate runs in the quick build with no deps).
//
// The TIME channel (index 7) is NOT stored in the blob (plane is zero) - it is
// computed at runtime as frame/frame_count, matching the prototype
// update()'s targets[7] = float(i)/total_frames.
#pragma once
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>
#include "rift/rift_types.h"

namespace rift {

// Onset picking, shared by the analysis-blob path and the waveform fallback.
//
// Peak-picking, not thresholding: a fixed threshold either floods a loud
// track with markers or finds nothing in a quiet one. A sample qualifies when
// it is a local maximum, sits `delta` above the mean of a ~200 ms window
// around it, and is at least `min_gap` seconds after the last accepted one.
inline std::vector<double> pickPeaks(const float* v, size_t n,
                                     double sec_per_sample, float delta,
                                     double min_gap) {
    std::vector<double> out;
    if (!v || n < 3 || sec_per_sample <= 0.0) return out;
    const size_t win = std::max<size_t>(3, size_t(0.20 / sec_per_sample));
    double last = -1e9;
    for (size_t i = 1; i + 1 < n; ++i) {
        if (v[i] <= v[i - 1] || v[i] < v[i + 1]) continue;   // local max
        const size_t a = (i > win) ? i - win : 0;
        const size_t b = std::min(n, i + win + 1);
        double mean = 0.0;
        for (size_t k = a; k < b; ++k) mean += v[k];
        mean /= double(b - a);
        if (v[i] < mean + delta) continue;
        const double t = double(i) * sec_per_sample;
        if (t - last < min_gap) continue;
        out.push_back(t);
        last = t;
    }
    return out;
}


class AnalysisSource {
public:
    bool load(const std::string& path) {
        FILE* f = std::fopen(path.c_str(), "rb");
        if (!f) return false;
        std::fseek(f, 0, SEEK_END); long sz = std::ftell(f);
        std::fseek(f, 0, SEEK_SET);
        buf_.resize(sz);
        size_t rd = std::fread(buf_.data(), 1, sz, f); std::fclose(f);
        if (rd != (size_t)sz) return false;
        if (std::memcmp(buf_.data(), "RIFTANLZ", 8) != 0) return false;

        std::memcpy(&version_, buf_.data() + 8, 4);
        std::memcpy(&sr_,   buf_.data() + 16, 4);
        std::memcpy(&hop_,  buf_.data() + 20, 4);
        std::memcpy(&fps_,  buf_.data() + 24, 4);
        std::memcpy(&n_,    buf_.data() + 28, 4);
        std::memcpy(&chan_, buf_.data() + 32, 4);
        std::memcpy(&bpm_,  buf_.data() + 36, 4);

        // planes start after header(64) + channel table(chan_*16)
        plane0_ = 64 + chan_ * 16;
        return chan_ >= RIFT_CH_COUNT && n_ > 0;
    }

    uint32_t frames() const { return n_; }
    uint32_t sr()     const { return sr_; }
    uint32_t hop()    const { return hop_; }
    uint32_t fps()    const { return fps_; }

    // Analysis frame index for a playhead - same integer hop as written, so
    // no drift (matches AudioEngine.frame_for_time).
    uint32_t frameForTime(double seconds) const {
        if (hop_ == 0 || sr_ == 0) return 0;
        long i = (long)(seconds * sr_ / hop_);
        if (i < 0) i = 0;
        if ((uint32_t)i >= n_) i = n_ - 1;
        return (uint32_t)i;
    }

    // Fill `targets` with raw (pre-smoothing) channel values at `frame`.
    void targets(uint32_t frame, float targets_out[RIFT_CH_COUNT]) const {
        if (frame >= n_) frame = n_ ? n_ - 1 : 0;
        for (int c = 0; c < RIFT_CH_COUNT; ++c) {
            if (c == RIFT_CH_TIME) {
                targets_out[c] = n_ ? float(frame) / float(n_) : 0.f;
            } else {
                size_t off = plane0_ + (size_t)c * n_ * 4 + (size_t)frame * 4;
                float v; std::memcpy(&v, buf_.data() + off, 4);
                targets_out[c] = v;
            }
        }
    }

    float bpm() const { return bpm_; }

    // Onset times (seconds) picked from one channel plane - KICK by default,
    // which the offline pass fills with low-band spectral flux, so its peaks
    // are the beats rather than merely loud moments. See pickPeaks().
    std::vector<double> onsets(int channel = RIFT_CH_KICK,
                               float delta = 0.06f,
                               double min_gap = 0.12) const {
        if (!n_ || !sr_ || !hop_ || channel < 0 || channel >= int(chan_))
            return {};

        std::vector<float> v(n_);
        for (uint32_t i = 0; i < n_; ++i) {
            size_t off = plane0_ + (size_t)channel * n_ * 4 + (size_t)i * 4;
            std::memcpy(&v[i], buf_.data() + off, 4);
        }
        return pickPeaks(v.data(), v.size(),
                         double(hop_) / double(sr_), delta, min_gap);
    }

private:
    std::vector<uint8_t> buf_;
    uint32_t version_=0, sr_=0, hop_=0, fps_=0, n_=0, chan_=0;
    float    bpm_=0.f;
    size_t   plane0_=0;
};

} // namespace rift
