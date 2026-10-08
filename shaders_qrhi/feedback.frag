#version 440
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform Engine {
    vec4 uTimeRes;   // x=time, zw=resolution
    vec4 uA;         // bass, melody, highs, drums
    vec4 uB;         // transient, bpm, centroid, playhead
    vec4 uC;         // kick, snare, _, _
    vec4 uBg;        // color_bg.rgb, palette_active
    vec4 uFg1;       // color_fg1.rgb
    vec4 uFg2;       // color_fg2.rgb
};
#define time            uTimeRes.x
#define u_resolution    uTimeRes.zw
#define bass            uA.x
#define melody          uA.y
#define mid             uA.y
#define highs           uA.z
#define high            uA.z
#define drums           uA.w
#define amplitude       uA.w
#define transient       uB.x
#define bpm             uB.y
#define centroid        uB.z
#define kick            uC.x
#define snare           uC.y
#define u_palette_active uBg.a
#define u_color_bg      uBg.rgb
#define u_color_fg1     uFg1.rgb
#define u_color_fg2     uFg2.rgb

layout(binding = 2) uniform sampler2D u_tex;
layout(binding = 6) uniform sampler2D u_feedback_tex;   // last finished frame

layout(std140, binding = 1) uniform Params { vec4 _p[2]; };
#define decay     _p[0].x
#define zoom      _p[0].y
#define rotate    _p[0].z
#define warp      _p[0].w
#define hue_shift _p[1].x
#define threshold _p[1].y

// RIFT - feedback.frag
//
// The feedback loop: last frame, transformed slightly, laid under this one.
// Iterated every frame it builds trails, echo tunnels and dye smear - the look
// a Resolume/TouchDesigner feedback TOP produces.
//
// u_feedback_tex is the previous FINAL frame (see RhiContext::capturePrev), so
// this node's own output is part of what it reads next time. That is the loop.
// On frame 0 and immediately after a resize the sampler is a 1x1 black dummy,
// so the effect starts from nothing rather than from garbage.
//
// DECAY under 1.0 is what keeps it stable. At 1.0 nothing is ever lost and the
// buffer saturates to white within a couple of seconds; the transform alone
// does not attenuate.

const float kTau = 6.28318530718;

vec3 hueRotate(vec3 c, float a) {
    // Luma-preserving rotation about the grey axis. Cheaper than a full
    // RGB->HSV->RGB trip and it does not blow out saturated inputs.
    const vec3 k = vec3(0.57735);
    float ca = cos(a);
    return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

void main() {
    float ar = u_resolution.x / max(u_resolution.y, 1.0);

    // Transform the SAMPLE coordinate, not the output: to make the trail move
    // outward the lookup has to move inward.
    vec2 c = (v_uv - 0.5) * vec2(ar, 1.0);
    float a = rotate * 0.02 * kTau;
    float cs = cos(a), sn = sin(a);
    c = mat2(cs, -sn, sn, cs) * c;
    c /= max(zoom, 1e-3);

    // A little curl so the trail bends instead of running dead straight.
    if (warp != 0.0) {
        float r = length(c);
        float w = warp * 0.05 * sin(r * 8.0 - time * 1.3);
        c += vec2(-c.y, c.x) * w;
    }

    vec2 fuv = clamp(c / vec2(ar, 1.0) + 0.5, 0.0, 1.0);
    vec3 prev = texture(u_feedback_tex, fuv).rgb;
    prev = hueRotate(prev, hue_shift * kTau) * clamp(decay, 0.0, 1.0);

    vec3 src = texture(u_tex, v_uv).rgb;

    // Only bright enough parts of the source are injected into the loop. Feed
    // everything in and the trail is just a smeared copy of the frame; feeding
    // the highlights is what leaves readable streaks behind moving subjects.
    float l = max(max(src.r, src.g), src.b);
    float inject = smoothstep(threshold, min(threshold + 0.25, 1.0), l);

    // Lighten, not mix: the trail must never darken the live picture, and max()
    // keeps the source fully intact wherever it is brighter than the history.
    //
    // The history is scaled by AT MOST 1.0 before the compare, so total loop
    // gain is decay and nothing else. Adding the injection on top of a standing
    // 0.35 term instead - which is what this did first - gives a gain of
    // decay * 1.35, and any gain above 1 saturates the whole frame to white
    // within a couple of seconds however low decay is set.
    fragColor = vec4(max(src, prev * mix(0.35, 1.0, inject)), 1.0);
}
