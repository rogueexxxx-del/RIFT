// Patch bay: resolves a bound uniform from the current channel frame.
// Direct C++ port of params.py Mod.resolve() (v2) - input window remap,
// invert, curve, per-binding attack/release envelope, depth, clamp.
// Envelope state lives per-binding (mutable), advanced once per frame.
#pragma once
#include <cmath>
#include <algorithm>
#include <string>
#include <vector>
#include "rift/rift_types.h"

namespace rift {

// One automation point on a parameter's timeline.
struct Keyframe {
    double time  = 0.0;      // seconds on the timeline
    float  value = 0.f;
    enum Interp { Linear = 0, Ease = 1, Step = 2 };
    int    interp = Linear;  // how to reach the NEXT key
};

struct Param {
    float        value;      // static base, used when there are no keyframes
    float        min_v, max_v, step;
    bool         discrete;   // step>=1 snaps
    rift_binding bind;       // channel<0 => static
    float        env = 0.f;  // per-binding envelope state
    // Automation. Sorted by time. Empty => `value` is the base.
    std::vector<Keyframe> keys;
};

// Blend modes, shared by clip compositing and per-effect layering. Values are
// the `blend_mode` uniform composite.frag switches on - do not renumber.
enum BlendMode {
    Blend_Normal = 0, Blend_Add = 1, Blend_Multiply = 2, Blend_Screen = 3,
    Blend_Difference = 4, Blend_Overlay = 5, Blend_Subtract = 6,
    Blend_Count = 7
};

// One effect pass in a chain. `blend`/`mix` decide how the pass's OUTPUT is
// laid back over its own INPUT, so an effect can be dialled in - mix 1 with
// Normal is the plain "replace the frame" behaviour and costs no extra draw.
struct ChainPass {
    std::string        shader;
    std::vector<Param> params;
    int   blend = Blend_Normal;
    float mix   = 1.f;         // 0 = dry (input), 1 = fully the effect

    // True when the pass output can be used directly, with no blend draw.
    bool passthrough() const noexcept {
        return blend == Blend_Normal && mix >= 0.999f;
    }
};

// The parameter's base value at time `t`: keyframes if any, else the static
// value. This is what audio modulation is applied ON TOP of, so a parameter can
// be animated and audio-reactive at once rather than one overriding the other.
inline float keyedBase(const Param& p, double t) noexcept {
    if (p.keys.empty()) return p.value;
    if (t <= p.keys.front().time) return p.keys.front().value;
    if (t >= p.keys.back().time)  return p.keys.back().value;

    // Segment containing t. Key lists are short (tens), so a scan beats the
    // cache miss of anything cleverer.
    size_t i = 0;
    while (i + 1 < p.keys.size() && p.keys[i + 1].time <= t) ++i;
    const Keyframe& a = p.keys[i];
    const Keyframe& b = p.keys[i + 1];

    const double span = b.time - a.time;
    if (span <= 1e-9) return b.value;
    float u = float((t - a.time) / span);

    switch (a.interp) {                    // the OUTGOING key owns the curve
        case Keyframe::Step: return a.value;
        case Keyframe::Ease: u = u * u * (3.f - 2.f * u); break;   // smoothstep
        default: break;                                            // linear
    }
    return a.value + (b.value - a.value) * u;
}

inline float resolve(Param& p, const rift_channel_frame& f) noexcept {
    // Keyframes drive the base; audio modulation is added to it below.
    const float base = keyedBase(p, f.playhead);

    if (p.bind.channel < 0)
        return std::clamp(base, p.min_v, p.max_v);

    float s = f.ch[p.bind.channel];

    // input window [in_lo,in_hi] -> [0,1]
    float span = p.bind.in_hi - p.bind.in_lo;
    if (span > 1e-6f) s = (s - p.bind.in_lo) / span;
    s = std::clamp(s, 0.f, 1.f);

    if (p.bind.invert) s = 1.f - s;

    switch (p.bind.curve) {
        case RIFT_CURVE_EXP: s = s * s;              break;
        case RIFT_CURVE_LOG: s = std::sqrt(s);       break;
        default: break;
    }

    // per-binding envelope (attack on rise, release on fall)
    if (p.bind.attack > 0.f || p.bind.release > 0.f) {
        float a = (s > p.env) ? p.bind.attack : p.bind.release;
        a = std::clamp(a, 0.f, 0.99f);
        p.env = p.env * a + s * (1.f - a);
        s = p.env;
    }

    // Audio rides on top of the keyframed base, not the static value.
    float r = base + s * p.bind.depth;
    return std::clamp(r, p.min_v, p.max_v);
}

} // namespace rift
