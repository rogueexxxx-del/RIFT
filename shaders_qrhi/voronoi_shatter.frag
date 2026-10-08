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
#define cells     _p[0].x
#define split     _p[0].y
#define bevel     _p[0].z
#define edge_glow _p[0].w
#define jitter    _p[1].x
#define chroma    _p[1].y

// RIFT - voronoi_shatter.frag
//
// Cellular break-up. A Voronoi diagram over the frame; every cell samples the
// picture from its own displaced position, so on a hit the image cracks into
// plates that slide apart and snap back.
//
// Route SPLIT to TRANSIENT and JITTER to KICK. SPLIT is the one that reads as
// an impact, because the cells all move at once and the seams open together.

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

void main() {
    float ar = u_resolution.x / max(u_resolution.y, 1.0);
    float n = max(floor(cells + 0.5), 2.0);

    // Cell lattice in height units, so cells stay square rather than stretching
    // with the frame.
    vec2 g = vec2(v_uv.x * ar, v_uv.y) * n;
    vec2 gi = floor(g), gf = fract(g);

    // F1 and F2: the nearest seed and the runner-up. The gap between them is
    // the distance to the cell EDGE, which is what the bevel and the glow need
    // - distance to the seed alone gives blobs, not plates.
    float f1 = 8.0, f2 = 8.0;
    vec2 id1 = vec2(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 o  = vec2(float(x), float(y));
            vec2 h  = hash2(gi + o);
            // Seeds drift so the pattern is never a static grid; jitter also
            // pushes them, which is what makes a hit re-shuffle the plates.
            vec2 sp = o + 0.5 + 0.5 * sin(time * 0.4 + 6.2831 * h) * (0.4 + jitter);
            float d = length(sp - gf);
            if (d < f1) { f2 = f1; f1 = d; id1 = gi + o; }
            else if (d < f2) { f2 = d; }
        }
    }

    // Per-cell displacement direction, constant for the life of the cell.
    vec2 dir = normalize(hash2(id1 + 17.0) - 0.5 + vec2(1e-5));
    vec2 off = dir * split * 0.06;

    vec2 uv = clamp(v_uv + off, 0.0, 1.0);
    float ca = chroma * 0.012;
    vec3 col;
    col.r = texture(u_tex, clamp(uv + dir * ca, 0.0, 1.0)).r;
    col.g = texture(u_tex, uv).g;
    col.b = texture(u_tex, clamp(uv - dir * ca, 0.0, 1.0)).b;

    float edge = f2 - f1;                       // 0 on the seam, grows inward
    // Bevel: darken toward the seam so plates read as separate pieces with
    // thickness rather than as a flat mosaic.
    float b = smoothstep(0.0, max(bevel, 1e-4), edge);
    col *= mix(1.0, b, clamp(bevel > 0.0 ? 1.0 : 0.0, 0.0, 1.0));

    // Glow along the crack itself, tinted by the cell's own colour so it reads
    // as light leaking between plates.
    float line = 1.0 - smoothstep(0.0, 0.06, edge);
    col += col * line * edge_glow * 2.0;

    fragColor = vec4(col, 1.0);
}
