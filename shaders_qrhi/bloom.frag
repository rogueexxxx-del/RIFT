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

layout(std140, binding = 1) uniform Params { vec4 _p[2]; };
#define threshold _p[0].x
#define knee      _p[0].y
#define radius    _p[0].z
#define intensity _p[0].w
#define tint      _p[1].x
#define chroma    _p[1].y

// RIFT - bloom.frag
//
// Threshold, spread, add back. Not blur: blur replaces the picture, bloom keeps
// it and lays light over the top, which is why it needs its own node.
//
// ponytail: single-pass, 32-tap golden-angle spiral rather than the textbook
// two-pass downsample-and-blur chain. The chain already ping-pongs, so a second
// pass would be a second node the user has to wire; one wide-tap pass buys most
// of the look for one draw. If a really wide, soft bloom is ever needed
// (radius past ~0.15 of the frame) the spiral starts to show as discrete dots
// and it wants the proper mip chain.

const float kGolden = 2.39996323;

// Soft-knee threshold. A hard step makes bloom pop on and off as a highlight
// crosses the line, which flickers badly on moving footage.
vec3 prefilter(vec3 c) {
    float l = max(max(c.r, c.g), c.b);
    float k = max(knee, 1e-4);
    float soft = clamp((l - threshold + k) / (2.0 * k), 0.0, 1.0);
    float w = max(soft * soft * k * 2.0, max(l - threshold, 0.0)) / max(l, 1e-4);
    return c * w;
}

void main() {
    vec3 base = texture(u_tex, v_uv).rgb;

    // Sample in height units so the spread is a circle on any aspect.
    float ar = u_resolution.x / max(u_resolution.y, 1.0);
    vec2 agr = vec2(1.0 / max(ar, 1e-3), 1.0);

    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 32; i++) {
        float t = (float(i) + 0.5) / 32.0;
        float ang = float(i) * kGolden;
        // sqrt spacing spreads the taps evenly over the DISC; linear spacing
        // clusters them all at the centre and the outer bloom goes ragged.
        float rr = sqrt(t) * radius;
        vec2 o = vec2(cos(ang), sin(ang)) * rr * agr;
        float w = 1.0 - t;                       // falls off toward the rim
        acc  += prefilter(texture(u_tex, clamp(v_uv + o, 0.0, 1.0)).rgb) * w;
        wsum += w;
    }
    vec3 glow = acc / max(wsum, 1e-4);

    // Warm/cool tint across the glow only, leaving the base untouched: a tinted
    // bloom is how a look gets a colour without grading the whole picture.
    vec3 warm = vec3(1.0, 0.82, 0.62);
    vec3 cool = vec3(0.62, 0.80, 1.0);
    glow *= mix(vec3(1.0), mix(cool, warm, clamp(tint, 0.0, 1.0)),
                abs(tint * 2.0 - 1.0));

    // Channel-split radius, so the halo fringes outward like real glass.
    if (chroma > 0.001) {
        vec2 o = vec2(radius * chroma * 0.25) * agr;
        glow.r = mix(glow.r, prefilter(texture(u_tex, clamp(v_uv + o, 0.0, 1.0)).rgb).r, 0.5);
        glow.b = mix(glow.b, prefilter(texture(u_tex, clamp(v_uv - o, 0.0, 1.0)).rgb).b, 0.5);
    }

    fragColor = vec4(base + glow * intensity, 1.0);
}
