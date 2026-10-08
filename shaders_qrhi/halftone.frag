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
#define ht_scale _p[0].x
#define ht_angle _p[0].y
#define ht_mode _p[0].z
#define ht_contrast _p[0].w
#define ht_soft _p[1].x




// RIFT - halftone.frag
// Classic print halftone (en.wikipedia.org/wiki/Halftone): continuous tone
// reproduced as dots of varying SIZE on a rotated screen grid. Dot area is
// proportional to tone, so radius ∝ sqrt(luminance). Three screen modes:
//   0 = mono ink   (single 45° screen, image-colored dots on black)
//   1 = paper mode (dark ink dots on light paper, true print look)
//   2 = tri-color  (R/G/B separations at classic offset angles 15°/45°/75°)








     // dot cell size in pixels
     // screen rotation (radians)
      // 0 mono / 1 paper / 2 tri-color

      // edge softness


// Sample one rotated halftone screen; returns coverage 0..1 for a channel
float screenDot(vec2 px, float angle, float value, float cell, float soft) {
    float c = cos(angle), s = sin(angle);
    vec2 rot = vec2(px.x * c - px.y * s, px.x * s + px.y * c);
    vec2 grid = rot / cell;
    vec2 f = fract(grid) - 0.5;
    float dist = length(f);
    // Area-linear: radius grows with sqrt of tone. 0.7071 covers the cell
    // fully at value=1 (dots merge, as in real print shadows).
    float radius = sqrt(clamp(value, 0.0, 1.0)) * 0.7071;
    // One pixel of anti-alias, PLUS whatever softness was asked for. As
    // max(soft, 1.0/cell) the floor swallowed the slider: at the default cell
    // of 9 px the floor is 0.111 and the control only reaches 0.2, so the
    // bottom half of its range changed nothing at all.
    float aa = 1.0 / cell + soft;
    return 1.0 - smoothstep(radius - aa, radius + aa, dist);
}

vec2 cellCenterUV(vec2 px, float angle, float cell) {
    float c = cos(angle), s = sin(angle);
    vec2 rot = vec2(px.x * c - px.y * s, px.x * s + px.y * c);
    vec2 center_rot = (floor(rot / cell) + 0.5) * cell;
    // rotate back
    vec2 back = vec2(center_rot.x * c + center_rot.y * s,
                     -center_rot.x * s + center_rot.y * c);
    return back / u_resolution;
}

void main() {
    // Cell size scales with the frame, quoted at 1080. Held at a fixed pixel
    // count, a 4K export doubled the dot count and halved their relative size
    // against the preview the screen was set up in.
    float cell = max(ht_scale * u_resolution.y / 1080.0, 2.0);
    vec2 px = v_uv * u_resolution;

    int mode = int(floor(ht_mode + 0.5));
    vec3 result;

    if (mode == 2) {
        // Tri-color separation, classic offset-press angles per channel
        float a_r = ht_angle + 0.2618;  // 15°
        float a_g = ht_angle + 0.7854;  // 45°
        float a_b = ht_angle + 1.3090;  // 75°
        vec3 src_r = texture(u_tex, clamp(cellCenterUV(px, a_r, cell), 0.0, 1.0)).rgb;
        vec3 src_g = texture(u_tex, clamp(cellCenterUV(px, a_g, cell), 0.0, 1.0)).rgb;
        vec3 src_b = texture(u_tex, clamp(cellCenterUV(px, a_b, cell), 0.0, 1.0)).rgb;
        float vr = clamp((src_r.r - 0.5) * ht_contrast + 0.5, 0.0, 1.0);
        float vg = clamp((src_g.g - 0.5) * ht_contrast + 0.5, 0.0, 1.0);
        float vb = clamp((src_b.b - 0.5) * ht_contrast + 0.5, 0.0, 1.0);
        result = vec3(screenDot(px, a_r, vr, cell, ht_soft),
                      screenDot(px, a_g, vg, cell, ht_soft),
                      screenDot(px, a_b, vb, cell, ht_soft));
    } else {
        // Single screen from luminance, sampled at the DOT CENTER so each
        // dot has exactly one size (true halftone, not per-pixel threshold)
        vec2 center_uv = clamp(cellCenterUV(px, ht_angle, cell), 0.0, 1.0);
        vec3 src = texture(u_tex, center_uv).rgb;
        float lum = dot(src, vec3(0.299, 0.587, 0.114));
        lum = clamp((lum - 0.5) * ht_contrast + 0.5, 0.0, 1.0);

        if (mode == 1) {
            // Paper mode: dark ink dots sized by DARKNESS on light paper
            float cover = screenDot(px, ht_angle, 1.0 - lum, cell, ht_soft);
            vec3 paper = vec3(0.92, 0.90, 0.86);
            vec3 ink = vec3(0.05, 0.05, 0.06);
            result = mix(paper, ink, cover);
        } else {
            // Mono: image-colored dots sized by brightness on black
            float cover = screenDot(px, ht_angle, lum, cell, ht_soft);
            result = src * cover;
        }
    }

    fragColor = vec4(clamp(result, 0.0, 1.0), 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float l = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(l * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((l - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
