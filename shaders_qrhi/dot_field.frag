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
#define grid       _p[0].x
#define dot_size   _p[0].y
#define depth      _p[0].z
#define tilt       _p[0].w
#define shade      _p[1].x
#define color_mode _p[1].y

// RIFT - dot_field.frag
//
// The TouchDesigner instancing look - a point cloud lifted out of the picture
// by brightness - done in a fragment shader. RIFT draws one fullscreen triangle
// per pass and has no vertex path, so there are no instances to place; instead
// each cell is shaded as though a dot were sitting at its displaced position.
//
// Not halftone. Halftone varies dot SIZE on a flat plane to reproduce tone;
// this displaces dots in DEPTH and shades them, so the frame reads as geometry
// standing off a surface rather than as print.

void main() {
    float ar = u_resolution.x / max(u_resolution.y, 1.0);
    float n = max(floor(grid + 0.5), 2.0);

    // Square cells regardless of aspect.
    vec2 g = vec2(v_uv.x * ar, v_uv.y) * n;
    vec2 gi = floor(g), gf = fract(g) - 0.5;

    // Cell centre back in uv, so the dot samples ONE colour for the whole cell.
    // Sampling per-pixel instead would just reproduce the source and the dots
    // would never read as discrete objects.
    vec2 cuv = (gi + 0.5) / n;
    cuv.x /= ar;
    vec3 src = texture(u_tex, clamp(cuv, 0.0, 1.0)).rgb;
    float luma = dot(src, vec3(0.2126, 0.7152, 0.0722));

    // Lift by brightness, projected as a simple vertical parallax. tilt is the
    // viewing angle: 0 looks straight on and the displacement is invisible.
    //
    // The shift is in CELL units and must stay under about one cell. Scaling it
    // by the grid count - the honest uv-to-cell conversion - put every dot 15
    // cells from its own square at the default settings, so the mask was zero
    // everywhere and the whole effect rendered black.
    float z = luma * depth;
    vec2 shift = vec2(0.0, -z * tilt);
    vec2 d = gf - shift;

    // Dot radius grows a little with brightness so bright cells read as nearer.
    float rad = clamp(dot_size, 0.05, 1.5) * 0.5 * (0.65 + luma * 0.7);
    float aa = 1.5 / max(u_resolution.y / n, 1.0);   // one pixel, in cell units
    float mask = 1.0 - smoothstep(rad - aa, rad + aa, length(d));

    // Shade the sphere: brighter on the upper-left, dark at the rim. This is
    // what turns a flat disc into something with volume.
    vec2 ln = normalize(vec2(-0.5, -0.7));
    float lam = clamp(dot(normalize(d + vec2(1e-5)), ln), 0.0, 1.0);
    float sph = mix(1.0, 0.35 + 0.9 * lam, clamp(shade, 0.0, 1.0));

    vec3 dotCol = int(floor(color_mode + 0.5)) == 0
                ? vec3(luma)          // 0 MONO - the depth reading, uncoloured
                : src;                // 1 SOURCE
    dotCol *= sph;

    // Height fog: cells that sit further back sink toward black, which is the
    // depth cue that survives being viewed small. Skipped entirely at depth 0,
    // or a flat grid would come out uniformly dimmed for no reason.
    dotCol *= mix(1.0, 0.35 + z * 1.6, step(1e-4, depth));

    fragColor = vec4(dotCol * mask, 1.0);
}
