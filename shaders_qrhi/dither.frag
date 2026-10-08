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
#define levels _p[0].x
#define bayer_scale _p[0].y
#define color_mode _p[0].z
#define threshold_bias _p[0].w
#define contrast _p[1].x















// Color Palette Uniforms


void main() {
    // 8x8 Bayer matrix (normalized / 64.0)
    const float bayer8[64] = float[64](
         0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0,
        48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0,
        12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0,
        60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0,
         3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0,
        51.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0,
        15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0,
        63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0
    );

    // Time-animated bayer coordinates - pattern crawls and shifts
    float time_offset_x = sin(time * 2.3) * 2.0;
    float time_offset_y = cos(time * 1.7) * 2.0;
    // Cell size scales with the frame, quoted at 1080. gl_FragCoord is in
    // DEVICE pixels, so dividing by bayer_scale alone pinned the pattern to a
    // pixel count: a 4K export came out with a dither half the relative size
    // of the one judged in the viewport.
    float bscale = max(bayer_scale * u_resolution.y / 1080.0, 1e-3);
    int bx = int(mod(gl_FragCoord.x / bscale + time_offset_x, 8.0));
    int by = int(mod(gl_FragCoord.y / bscale + time_offset_y, 8.0));

    vec4 src = texture(u_tex, v_uv);

    // Amplitude-driven contrast
    float dyn_contrast = contrast + amplitude * 0.6;
    vec3 col = (src.rgb - 0.5) * dyn_contrast + 0.5;

    // Bass-wobbled threshold bias
    float dyn_bias = threshold_bias + bass * 0.15 * sin(time * 6.0);
    float threshold = bayer8[by * 8 + bx] + dyn_bias;

    // Mid-modulated dither levels - smoother dithering on mid content
    float lvl = max(2.0, levels + mid * 8.0);

    // --- Transient flash/inversion effect ---
    // On strong transients, briefly invert the source before dithering
    float flash = smoothstep(0.5, 0.9, transient);
    col = mix(col, 1.0 - col, flash * 0.7);
    // Add brightness flash
    col += flash * 0.15;

    if (color_mode < 0.5) {
        // Full color ordered dither: threshold offsets the quantizer.
        // (lvl - 1) divisor so output actually reaches pure white.
        col = floor(col * (lvl - 1.0) + threshold) / (lvl - 1.0);
    } else if (color_mode < 1.5) {
        // Monochrome ordered dither
        float lum = dot(col, vec3(0.299, 0.587, 0.114));
        float d = floor(lum * (lvl - 1.0) + threshold) / (lvl - 1.0);
        col = vec3(d);
    } else if (color_mode < 2.5) {
        // Two-tone: classic 1-bit Bayer - compare luma directly against
        // the Bayer threshold (this is the textbook ordered-dither test).
        float lum = dot(col, vec3(0.299, 0.587, 0.114));
        float d = step(threshold, lum);
        // Pulse the accent color with bass
        vec3 accent = mix(vec3(1.0, 0.75, 0.2), vec3(1.0, 0.4, 0.1), bass * 0.5);
        col = mix(vec3(0.04, 0.04, 0.08), accent, d);
    } else {
        // True 3-bit RGB: 1-bit Bayer test per channel = 8 colors
        col = step(vec3(threshold), col);
    }

    // --- Subtle rhythmic pulsation ---
    // Slight brightness pulse synced to a beat-like oscillation
    float pulse = 1.0 + sin(time * 8.0) * 0.02 * bass;
    col *= pulse;

    // --- Transient edge highlight ---
    // Brief white-hot edge on transient
    float edge_flash = smoothstep(0.8, 1.0, transient) * 0.1;
    col += edge_flash;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float l = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(l * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((l - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
