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
#define scale    _p[0].x
#define warp     _p[0].y
#define speed    _p[0].z
#define octaves  _p[0].w
#define chroma   _p[1].x
#define contrast _p[1].y

// RIFT - flow_warp.frag
//
// Domain-warped fbm: the "molten / liquid" look. An fbm field is fed back into
// its own coordinates twice, which turns smooth noise into currents that fold
// over each other instead of drifting as one sheet.
//
// This is NOT noise_field's single displacement. Warping the domain twice is
// what produces the flow; one pass only ever slides the picture around.
//
// Route WARP to BASS, SPEED to MIDS, CHROMA to HIGHS - that is the band split
// every audio-reactive patch ends up at, and it is the reason the three do
// visually separable things here.

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);            // smoothstep, not linear: linear
                                            // interpolation shows the lattice
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fixed loop bound with an early break: a variable count is legal GLSL but
// cross-compiles badly to HLSL/MSL, and qsb targets both.
float fbm(vec2 p, float oct) {
    float sum = 0.0, amp = 0.5, norm = 0.0;
    for (int i = 0; i < 5; i++) {
        if (float(i) >= oct) break;
        sum  += vnoise(p) * amp;
        norm += amp;
        p    *= 2.02;                        // not exactly 2: an integer ratio
        amp  *= 0.5;                         // lines the octaves up into stripes
    }
    return sum / max(norm, 1e-4);
}

void main() {
    float ar = u_resolution.x / max(u_resolution.y, 1.0);
    vec2 p = (v_uv - 0.5) * vec2(ar, 1.0) * max(scale, 0.01);
    float t = time * speed;
    float oct = clamp(octaves, 1.0, 5.0);

    // Two levels of domain warp. q offsets the field; r offsets q. The second
    // level is what makes the currents curl back on themselves.
    vec2 q = vec2(fbm(p + vec2(0.0, 0.0) + t * 0.15, oct),
                  fbm(p + vec2(5.2, 1.3) - t * 0.11, oct));
    vec2 r = vec2(fbm(p + 3.0 * q + vec2(1.7, 9.2) + t * 0.09, oct),
                  fbm(p + 3.0 * q + vec2(8.3, 2.8) - t * 0.07, oct));

    vec2 off = (r - 0.5) * warp * 0.35;

    // Per-channel offset spread along the flow direction, so the smear picks up
    // colour fringing the way a real refractive surface does.
    vec2 dir = normalize(off + vec2(1e-5));
    float ca = chroma * 0.01;
    vec2 uv = clamp(v_uv + off, 0.0, 1.0);
    vec3 col;
    col.r = texture(u_tex, clamp(uv + dir * ca, 0.0, 1.0)).r;
    col.g = texture(u_tex, uv).g;
    col.b = texture(u_tex, clamp(uv - dir * ca, 0.0, 1.0)).b;

    // Lift the field itself into the picture so the flow is visible on flat or
    // dark footage instead of only showing where the source has detail.
    float sheen = r.x * r.y;
    col = mix(col, col * (0.6 + sheen * 1.6), clamp(contrast, 0.0, 1.0));

    fragColor = vec4(col, 1.0);
}
