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
#define segments  _p[0].x
#define twist     _p[0].y
#define zoom      _p[0].z
#define cx        _p[0].w
#define cy        _p[1].x
#define edge_fade _p[1].y
#define feather   _p[1].z

// RIFT - kaleido.frag
//
// Polar mirror. The frame is folded into N wedges around a movable centre, so
// one slice of the source is repeated and mirrored around the circle. Route
// SEGMENTS to SNARE (it is discrete, so it snaps between counts on a hit) and
// TWIST to MIDS.
//
// Mirrored, not merely repeated: reflecting alternate wedges makes the seams
// continuous. Plain modulo leaves a hard radial cut every wedge, which reads as
// a rendering fault rather than a kaleidoscope.

const float kTau = 6.28318530718;

// Fold t into [0,1] by reflection. The sampler is ClampToEdge, so anything
// outside would otherwise smear the border pixel across the whole wedge -
// mirroring keeps sampling real picture however far the twist pushes.
float mirror01(float t) {
    t = abs(fract(t * 0.5) * 2.0 - 1.0);
    return t;
}

void main() {
    // Work in height units so a wedge stays a wedge on any aspect. In raw uv a
    // 60-degree slice comes out elliptical on a 16:9 frame.
    float ar = u_resolution.x / max(u_resolution.y, 1.0);
    vec2 c = vec2(clamp(cx, 0.0, 1.0), clamp(cy, 0.0, 1.0));
    vec2 p = (v_uv - c) * vec2(ar, 1.0);

    float r = length(p);
    float a = atan(p.y, p.x);

    // Fold. seg is held at 2 or more: one segment is a no-op and zero divides.
    float seg = max(floor(segments + 0.5), 2.0);
    float wedge = kTau / seg;
    a += twist * r + time * 0.05 * twist;

    float k = a / wedge;
    float f = fract(k);
    // Reflect every other wedge so neighbours meet along a shared edge.
    if (mod(floor(k), 2.0) >= 1.0) f = 1.0 - f;

    // feather softens the fold line itself: without it the mirrored seam is a
    // pixel-hard crease that aliases badly once the wedge count is high.
    float seam = min(f, 1.0 - f);
    f = mix(f, smoothstep(0.0, max(feather, 1e-4), seam) * f
             + (1.0 - smoothstep(0.0, max(feather, 1e-4), seam)) * 0.5,
            step(1e-5, feather));

    a = f * wedge;

    // Back to uv, undoing the aspect stretch.
    float z = max(zoom, 1e-3);
    vec2 q = vec2(cos(a), sin(a)) * r / z;
    vec2 uv = c + q / vec2(ar, 1.0);
    uv = vec2(mirror01(uv.x), mirror01(uv.y));

    vec3 col = texture(u_tex, uv).rgb;

    // Circular falloff to black at the rim, so the fold does not just stop at
    // the frame corners where the wedges run out of radius.
    float fade = 1.0 - smoothstep(0.5, 0.5 + max(1.0 - edge_fade, 1e-3) * 0.7, r);
    col *= mix(1.0, fade, clamp(edge_fade, 0.0, 1.0));

    fragColor = vec4(col, 1.0);
}
