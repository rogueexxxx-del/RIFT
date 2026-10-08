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
#define cols _p[0].x
#define phosphor _p[0].y
#define bleed _p[0].z
#define scanline _p[0].w
#define curve _p[1].x
#define flicker _p[1].y


// CRT text terminal. Not an ASCII filter: the point here is the *display*,
// not the character set. A shadow-masked tube quantises the image into
// character cells, lights one phosphor colour, blooms sideways along each
// scanline, and bends the picture over a curved glass face.
float hash21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Rough glyph coverage: a 5x7 dot cell lit in proportion to brightness. Real
// glyphs would need an atlas; this reproduces the texture at a glance.
float glyph(vec2 cell_uv, float level) {
    vec2 g = floor(cell_uv * vec2(5.0, 7.0));
    float seed = hash21(g + floor(level * 8.0) * 17.0);
    return step(1.0 - clamp(level, 0.0, 1.0) * 1.15, seed);
}

void main() {
    // Screen curvature, applied before sampling so the whole image bends.
    vec2 c = v_uv * 2.0 - 1.0;
    c += c.yx * c.yx * c * curve * 0.18;
    vec2 uv = c * 0.5 + 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // Character grid. Rows follow columns at a 2:1 aspect, the way a real
    // text mode does.
    float nx = max(cols, 8.0);
    float ny = max(floor(nx * (u_resolution.y / max(u_resolution.x, 1.0)) * 0.5), 4.0);
    vec2 grid = vec2(nx, ny);
    vec2 cell = floor(uv * grid);
    vec2 cell_uv = fract(uv * grid);

    // One sample per cell: the terminal only knows one character per cell.
    vec3 src = texture(u_tex, (cell + 0.5) / grid).rgb;
    float level = dot(src, vec3(0.299, 0.587, 0.114));

    float lit = glyph(cell_uv, level);

    vec3 tint = phosphor < 0.5 ? vec3(0.25, 1.00, 0.35)    // P1 green
              : phosphor < 1.5 ? vec3(1.00, 0.72, 0.20)    // amber
              : phosphor < 2.5 ? vec3(0.85, 0.92, 1.00)    // white
                               : vec3(0.35, 0.75, 1.00);   // IBM blue

    vec3 col = tint * lit * level;

    // Limited video bandwidth smears each lit dot to the right.
    if (bleed > 0.0) {
        float side = glyph(fract(cell_uv - vec2(0.35, 0.0)), level)
                   + glyph(fract(cell_uv - vec2(0.7, 0.0)), level) * 0.5;
        col += tint * side * level * bleed * 0.18;
    }

    // Interlace gaps between scanlines.
    // 540 scanlines, fixed, rather than one per two DEVICE pixels. Against
    // u_resolution.y the line count tracked the frame: the viewport showed
    // chunky CRT lines and a 4K export put them at twice the density, which
    // scaled back down reads as flat grey or moire.
    float sl = 0.5 + 0.5 * cos(uv.y * 1080.0 * 3.14159);
    col *= mix(1.0, sl, scanline);

    // Mains-frequency ripple in the supply.
    col *= 1.0 + sin(time * 47.0) * flicker * 0.12;

    // Even an unlit tube is not black: the phosphor coating is grey and the
    // glass reflects the room.
    col += tint * 0.018;
    float r = length(v_uv - 0.5) * 2.0;
    col *= smoothstep(1.6, 0.7, r);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float luma = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(luma * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((luma - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
