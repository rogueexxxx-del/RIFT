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
#define beam _p[0].x
#define edge_rim _p[0].y
#define scan_drift _p[0].z
#define charge _p[0].w
#define shot_noise _p[1].x
#define vignette _p[1].y


// Scanning electron microscope. An SEM has no colour: a beam rasters the
// sample and a detector counts electrons knocked loose. Steep faces throw
// more of them at the detector, so edges glow - that rim, not the greyscale,
// is what makes an image read as "SEM".
float hash21(vec2 p) {
    p = fract(p * vec2(443.897, 397.297));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float lum(vec2 uv) {
    return dot(texture(u_tex, uv).rgb, vec3(0.299, 0.587, 0.114));
}

void main() {
    vec2 px = 1.0 / max(u_resolution, vec2(1.0));

    // The beam is deflected by stray fields, and the drift is per-scanline:
    // a whole row shifts, which is why SEM stills tear horizontally.
    // 1080 scan rows, fixed. Tied to u_resolution.y a 4K export tore on twice
    // as many, half-height rows as the preview, which averages away to nothing.
    float row = floor(v_uv.y * 1080.0);
    float drift = (hash21(vec2(row, floor(time * 12.0))) - 0.5)
                * scan_drift * 0.012;
    vec2 uv = clamp(v_uv + vec2(drift, 0.0), 0.0, 1.0);

    float c = lum(uv);

    // Secondary-electron yield: emission rises with the angle between the
    // surface and the beam, approximated by the local gradient.
    float gx = lum(uv + vec2(px.x, 0.0)) - lum(uv - vec2(px.x, 0.0));
    float gy = lum(uv + vec2(0.0, px.y)) - lum(uv - vec2(0.0, px.y));
    float slope = length(vec2(gx, gy));

    float signal = c * 0.75 + slope * edge_rim * 2.2;
    signal = pow(clamp(signal * beam, 0.0, 1.0), 0.85);

    // Non-conductive samples build up charge and bloom white in patches.
    float charge_spot = hash21(floor(uv * 14.0) + floor(time * 0.7));
    signal += charge * smoothstep(0.82, 1.0, charge_spot) * slope * 6.0;

    // Detector shot noise: sparse, and worse where the signal is weak.
    float n = hash21(uv * u_resolution + time * 60.0);
    signal += (n - 0.5) * shot_noise * 0.28 * (1.2 - signal);

    signal = clamp(signal, 0.0, 1.0);

    // Phosphor is not neutral grey; SEM monitors run slightly cold.
    vec3 col = vec3(signal) * vec3(0.94, 0.97, 1.0);

    // Final aperture crops the beam into a circle.
    float r = length(v_uv - 0.5) * 2.0;
    col *= mix(1.0, smoothstep(1.35, 0.55, r), vignette);

    fragColor = vec4(col, 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float luma = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(luma * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((luma - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
