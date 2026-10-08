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
#define tiles_x _p[0].x
#define tiles_y _p[0].y
#define mode    _p[0].z
#define offset  _p[0].w
#define scroll  _p[1].x
#define seam    _p[1].y

// RIFT - mirror_tile.frag
//
// Rectilinear mirror tiling. Distinct from kaleido: that one folds around a
// centre in polar space, this one repeats on a grid in x/y. Straight edges and
// right angles rather than wedges - the symmetry look that reads as graphic
// design instead of psychedelia.
//
// MODE (snaps to whole numbers):
//   0  TILE     - plain repeat, no mirroring
//   1  MIRROR X - alternate columns flipped
//   2  MIRROR Y - alternate rows flipped
//   3  QUAD     - both, the four-way mirror
//
// Route TILES X to BEAT-ish channels (they are discrete, so counts snap) and
// SCROLL to MIDS.

// Reflect t into [0,1]. Used instead of fract() on mirrored axes: fract alone
// repeats, which leaves a hard cut where the right edge meets the left.
float mirror01(float t) { return abs(fract(t * 0.5) * 2.0 - 1.0); }

void main() {
    float nx = max(floor(tiles_x + 0.5), 1.0);
    float ny = max(floor(tiles_y + 0.5), 1.0);
    int m = int(floor(mode + 0.5));

    vec2 uv = v_uv;
    uv.x += scroll * time * 0.05 + offset;
    uv.y += scroll * time * 0.03;

    vec2 g = vec2(uv.x * nx, uv.y * ny);
    vec2 cell = floor(g);
    vec2 f = fract(g);

    // Flip alternate cells. Doing it per-cell rather than with mirror01 over
    // the whole axis keeps every tile a full copy of the source; mirroring the
    // axis would halve the picture into each tile instead.
    bool mx = (m == 1 || m == 3) && mod(cell.x, 2.0) >= 1.0;
    bool my = (m == 2 || m == 3) && mod(cell.y, 2.0) >= 1.0;
    if (mx) f.x = 1.0 - f.x;
    if (my) f.y = 1.0 - f.y;

    vec3 col = texture(u_tex, clamp(f, 0.0, 1.0)).rgb;

    // Seam: a dark rule on the tile border. Width is a fraction of the CELL,
    // and cells shrink as the count rises, so it stays proportional instead of
    // swallowing the picture at high tile counts.
    if (seam > 0.0) {
        vec2 d = min(f, 1.0 - f);
        float e = min(d.x, d.y);
        col *= smoothstep(0.0, seam * 0.05, e);
    }

    fragColor = vec4(col, 1.0);
}
