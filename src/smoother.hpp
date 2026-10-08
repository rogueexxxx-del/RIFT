// Smoother - per-channel exponential smoothing, an EXACT port of the
// prototype AudioEngine.update() reactive-params math. This is the numeric
// contract validated by parity check A: raw blob targets -> smoothed params
// must match the Python golden channels.csv within atol 1e-4.
//
// Constants + rule (from audio_engine.py):
//   ATTACK=0.2  RELEASE=0.85           (energy channels)
//   TRANSIENT_ATTACK=0.05 TRANSIENT_RELEASE=0.82   (trigger channels 4,8,9)
//   per channel (except TIME):
//     alpha = (target > current) ? attack : release
//     param = current*alpha + target*(1-alpha)
//   TIME channel: passthrough (param = target)
#pragma once
#include "rift/rift_types.h"

namespace rift {

class Smoother {
public:
    static constexpr float ATTACK  = 0.2f;
    static constexpr float RELEASE = 0.85f;
    static constexpr float T_ATTACK  = 0.05f;
    static constexpr float T_RELEASE = 0.82f;

    void reset() { for (int c = 0; c < RIFT_CH_COUNT; ++c) p_[c] = 0.f; }

    // Advance one frame from raw targets. Returns pointer to smoothed params.
    const float* update(const float targets[RIFT_CH_COUNT]) {
        for (int c = 0; c < RIFT_CH_COUNT; ++c) {
            if (c == RIFT_CH_TIME) { p_[c] = targets[c]; continue; }
            const bool trig = (c == RIFT_CH_TRANSIENT ||
                               c == RIFT_CH_KICK || c == RIFT_CH_SNARE);
            const float cur = p_[c], tgt = targets[c];
            float a;
            if (trig) a = (tgt > cur) ? T_ATTACK : T_RELEASE;
            else      a = (tgt > cur) ? ATTACK   : RELEASE;
            p_[c] = cur * a + tgt * (1.f - a);
        }
        return p_;
    }

    const float* params() const { return p_; }

private:
    float p_[RIFT_CH_COUNT] = {0};
};

} // namespace rift
