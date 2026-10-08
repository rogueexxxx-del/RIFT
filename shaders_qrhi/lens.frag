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
#define distortion   _p[0].x
#define aberration   _p[0].y
#define streak       _p[0].z
#define streak_angle _p[0].w
#define vignette     _p[1].x
#define falloff      _p[1].y

// RIFT - lens.frag
//
// The physical-camera pass: barrel/pincushion distortion, radial chromatic
// aberration, an anamorphic streak off the highlights, and a vignette.
//
// Aberration is RADIAL, scaled by distance from centre, not a flat per-channel
// offset. A constant offset shifts the whole picture and reads as a registration
// error; real glass separates colour only as it bends light, so the centre stays
// clean and the corners fringe. That difference is the entire effect.

const float kTau = 6.28318530718;

vec2 distort(vec2 uv, float k) {
    vec2 c = uv - 0.5;
    float r2 = dot(c, c);
    return 0.5 + c * (1.0 + k * r2);
}

void main() {
    float ar = u_resolution.x / max(u_resolution.y, 1.0);
    vec2 c = v_uv - 0.5;
    float r = length(c * vec2(ar, 1.0)) * 2.0;   // 0 centre, ~1 at the short edge

    // Barrel (negative) through pincushion (positive).
    vec2 uv = distort(v_uv, distortion);

    // Radial aberration: each channel gets its own distortion strength, so the
    // separation grows with radius on its own.
    float a = aberration * 0.06;
    vec2 uvR = distort(v_uv, distortion + a);
    vec2 uvB = distort(v_uv, distortion - a);

    vec3 col;
    col.r = texture(u_tex, clamp(uvR, 0.0, 1.0)).r;
    col.g = texture(u_tex, clamp(uv,  0.0, 1.0)).g;
    col.b = texture(u_tex, clamp(uvB, 0.0, 1.0)).b;

    // Anamorphic streak: a one-dimensional smear of the bright parts only,
    // along a fixed angle. Thresholded first - streaking everything just blurs
    // the frame, streaking the highlights is what reads as a lens.
    if (streak > 0.001) {
        float ang = streak_angle * kTau;
        vec2 dir = vec2(cos(ang), sin(ang)) / max(u_resolution, vec2(1.0));
        vec3 acc = vec3(0.0);
        float wsum = 0.0;
        for (int i = 1; i <= 12; i++) {
            float t = float(i);
            float w = 1.0 / t;                       // 1/x tail, not gaussian:
                                                     // the long thin reach is
                                                     // the anamorphic signature
            vec2 o = dir * t * streak * 24.0;
            vec3 s1 = texture(u_tex, clamp(uv + o, 0.0, 1.0)).rgb;
            vec3 s2 = texture(u_tex, clamp(uv - o, 0.0, 1.0)).rgb;
            acc  += (max(s1 - 0.6, 0.0) + max(s2 - 0.6, 0.0)) * w;
            wsum += 2.0 * w;
        }
        col += acc / max(wsum, 1e-4) * streak * 3.0;
    }

    // Vignette. falloff sets how abruptly it closes; without it the only
    // control is depth, and a deep soft vignette and a shallow hard one are
    // very different looks.
    float v = 1.0 - smoothstep(1.0 - max(falloff, 1e-3), 1.0 + 0.3, r);
    col *= mix(1.0, v, clamp(vignette, 0.0, 1.0));

    fragColor = vec4(col, 1.0);
}
