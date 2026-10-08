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
#define nf_scale _p[0].x
#define nf_amount _p[0].y
#define nf_speed _p[0].z
#define nf_warp _p[0].w
#define nf_chroma _p[1].x




// RIFT - noise_field.frag
// Frequency-driven noise displacement (TouchDesigner "Noise TOP → Displace"
// pattern): an fbm field warps the media's UVs. Route nf_amount to BASS,
// nf_warp to MIDS, nf_detail to AIR for full-band reactivity.








    // noise frequency
   // displacement strength
    // field animation speed
     // domain-warp depth (noise warping noise)
   // RGB split along the displacement vector


vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}

// Gradient noise (smoother than value noise for displacement fields)
float gnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = dot(hash2(i), f);
    float b = dot(hash2(i + vec2(1, 0)), f - vec2(1, 0));
    float c = dot(hash2(i + vec2(0, 1)), f - vec2(0, 1));
    float d = dot(hash2(i + vec2(1, 1)), f - vec2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        v += amp * gnoise(p);
        p = p * 2.03 + vec2(17.3, 9.1);
        amp *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = v_uv;
    float t = time * nf_speed;

    vec2 p = uv * nf_scale;

    // Domain warp: q warps the lookup of the final field (IQ's technique)
    vec2 q = vec2(fbm(p + vec2(t * 0.7, 0.0)),
                  fbm(p + vec2(5.2, t * 0.6)));
    vec2 field = vec2(fbm(p + nf_warp * 4.0 * q + vec2(1.7, 9.2)),
                      fbm(p + nf_warp * 4.0 * q + vec2(8.3, 2.8)));

    vec2 disp = field * nf_amount;
    vec2 duv = uv + disp;

    // Chromatic split follows the local displacement direction
    vec3 col;
    if (nf_chroma > 0.0001) {
        vec2 cd = normalize(disp + 1e-6) * nf_chroma;
        col.r = texture(u_tex, clamp(duv + cd, 0.0, 1.0)).r;
        col.g = texture(u_tex, clamp(duv, 0.0, 1.0)).g;
        col.b = texture(u_tex, clamp(duv - cd, 0.0, 1.0)).b;
    } else {
        col = texture(u_tex, clamp(duv, 0.0, 1.0)).rgb;
    }

    fragColor = vec4(col, 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float l = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(l * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((l - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
