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
#define columns _p[0].x
#define char_set _p[0].y
#define brightness _p[0].z
#define color_mode _p[0].w
#define dot_size _p[1].x















// User-typed glyph atlas: horizontal strip of N cells, density-sorted.
// When u_ascii_count > 0 it overrides the built-in charsets.



// Color Palette Uniforms


// Pseudo-random for cell shimmer
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// ── Real ASCII glyphs ──
// 10-step luminance ramp " .:-=+*#%@" as 5x5 bitmaps packed into 25-bit ints.
// Bit index = row*5 + col, row 0 = top, col 0 = left (bit 0 = top-left).
int glyphBitmap(int idx) {
    if (idx == 0) return 0;          // ' '
    if (idx == 1) return 0x20000;    // '.'
    if (idx == 2) return 0x20080;    // ':'
    if (idx == 3) return 0x03800;    // '-'
    if (idx == 4) return 0x701C0;    // '='
    if (idx == 5) return 0x23880;    // '+'
    if (idx == 6) return 0x1577DD5;  // '*'
    if (idx == 7) return 0xAFABEA;   // '#'
    if (idx == 8) return 0x19D1173;  // '%'
    return 0x1FFFFFF;                // '@'
}

// Sample glyph bitmap at local cell position. local in [-0.5, 0.5], +y = up.
float glyphPixel(int idx, vec2 local) {
    vec2 g = (local + 0.5) * 5.0;
    ivec2 cell = ivec2(floor(g));
    if (cell.x < 0 || cell.x > 4 || cell.y < 0 || cell.y > 4) return 0.0;
    int row_from_top = 4 - cell.y;   // GL local.y grows upward
    int bit = row_from_top * 5 + cell.x;
    return float((glyphBitmap(idx) >> bit) & 1);
}

void main() {
    // Proper aspect ratio from u_resolution
    float aspect = u_resolution.x / max(u_resolution.y, 1.0);

    // Amplitude-modulated column count - breathing zoom effect
    float breath = 1.0 + amplitude * 0.12 * sin(time * 3.0);
    float eff_columns = columns * breath;
    float rows = eff_columns / aspect;

    vec2 grid = vec2(eff_columns, rows);
    vec2 cell = floor(v_uv * grid);
    vec2 cell_uv = (cell + 0.5) / grid;
    vec4 src = texture(u_tex, cell_uv);

    float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114)) * brightness;

    // --- Time-based shimmer/flicker per cell ---
    float cell_hash = hash(cell + floor(time * 8.0) * 0.01);
    float shimmer = 0.9 + 0.2 * sin(time * 12.0 + cell_hash * 40.0);
    lum *= shimmer;
    lum = clamp(lum, 0.0, 1.0);

    vec2 local = fract(v_uv * grid) - 0.5;
    vec3 fg = color_mode > 0.5 ? src.rgb : vec3(1.0);

    // Bass-pulsed dot size - breathing shapes
    float eff_dot_size = dot_size * (1.0 + bass * 0.25 * sin(time * 5.0));

    // --- Charset selection with transient flicker ---
    int charset_idx = int(floor(char_set + 0.5));
    // On transient hit, momentarily switch to a random different charset
    float transient_flicker = step(0.6, transient);
    int flicker_set = int(mod(float(charset_idx) + floor(hash(vec2(time * 100.0, 0.0)) * 3.0) + 1.0, 4.0));
    int active_charset = int(mix(float(charset_idx), float(flicker_set), transient_flicker));

    float shape = 0.0;

    // The user-typed glyph atlas that used to head this chain is gone: nothing
    // ever uploaded u_ascii_atlas, and buildSrb only resolves u_tex, the
    // second input and the three named audio/feedback samplers - every other
    // binding silently falls through to the 1x1 dummy. u_ascii_count was never
    // in the manifest either, so drawPass zero-filled it and the branch could
    // not be entered. Bring it back with a real atlas upload, not a uniform.
    if (active_charset == 0) {
        // CHARSET 0 - True ASCII ramp " .:-=+*#%@" via 5x5 procedural glyphs
        int glyph_idx = int(clamp(floor(lum * 10.0), 0.0, 9.0));
        // dot_size scales the glyph inside its cell
        vec2 glyph_local = local / max(eff_dot_size, 0.05);
        shape = glyphPixel(glyph_idx, glyph_local);
    }
    else if (active_charset == 1) {
        // CHARSET 1 - Block fill
        float half_size = lum * 0.48 * eff_dot_size;
        shape = step(max(abs(local.x), abs(local.y)), half_size);
    }
    else if (active_charset == 2) {
        // CHARSET 2 - Line density
        float line_count_local = floor(lum * 6.0 * eff_dot_size) + 1.0;
        float line_pattern = step(0.5, fract(local.y * line_count_local + 0.5));
        shape = line_pattern * step(abs(local.x), 0.45);
    }
    else {
        // CHARSET 3 - Crosses
        float arm = lum * 0.45 * eff_dot_size;
        float h_bar = step(abs(local.y), 0.08) * step(abs(local.x), arm);
        float v_bar = step(abs(local.x), 0.08) * step(abs(local.y), arm);
        shape = clamp(h_bar + v_bar, 0.0, 1.0);
    }

    vec3 char_col = fg * shape;

    // --- Subtle glow around bright characters ---
    float glow_radius = lum * 0.5 * eff_dot_size + 0.05;
    float dist = length(local);
    float glow = exp(-dist * dist / (glow_radius * glow_radius * 0.15)) * lum * 0.25;
    // Glow only adds to existing shape, creating a soft halo
    vec3 glow_col = fg * glow * (1.0 - shape); // glow only where shape isn't

    vec3 result = char_col + glow_col;

    // --- CRT Scanline Overlay ---
    float scanline = sin(v_uv.y * u_resolution.y * 1.5) * 0.5 + 0.5;
    scanline = mix(0.85, 1.0, scanline); // subtle darkening on scan lines
    result *= scanline;

    // Slight vignette for CRT feel
    float vig = 1.0 - dot(v_uv - 0.5, v_uv - 0.5) * 1.2;
    result *= clamp(vig, 0.0, 1.0);

    fragColor = vec4(result, 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float l = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(l * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((l - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
