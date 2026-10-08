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
layout(binding = 6) uniform sampler2D u_feedback_tex;   // previous final frame

layout(std140, binding = 1) uniform Params { vec4 _p[2]; };
#define block _p[0].x
#define smear _p[0].y
#define bloom_amt _p[0].z
#define iframe _p[0].w
#define chroma _p[1].x
#define rate _p[1].y
#define persist _p[1].z


// Datamosh: what a video codec does when you delete its keyframes. The
// P-frames that survive still carry motion vectors, so the decoder keeps
// pushing blocks of the *old* picture around according to the *new* motion -
// the image liquefies while its edges stay locked to a macroblock grid.
//
// PERSIST is the real thing. Above zero, each block is pulled from the PREVIOUS
// output rather than from the current frame, so old pixels are dragged around
// by new motion and survive across a cut - one shot genuinely bleeds into the
// next. IFRAME is then what lets the true picture back in.
//
// At persist = 0 this behaves as it did before the previous frame was
// available: the residual is faked from the current frame only, which still
// gives the grid, the drift and the bloom, but nothing smears through a cut.
// Projects saved before persist existed load with it at 0 and look unchanged.
//
// Keep persist below 1.0. It is a feedback loop, and at unity gain nothing ever
// decays out of it.
float hash21(vec2 p) {
    p = fract(p * vec2(163.31, 271.97));
    p += dot(p, p + 29.71);
    return fract(p.x * p.y);
}
vec2 hash22(vec2 p) {
    return vec2(hash21(p), hash21(p + 7.31)) * 2.0 - 1.0;
}

void main() {
    vec2 res = max(u_resolution, vec2(1.0));
    float bs = max(block, 2.0);
    vec2 cells = floor(res / bs);
    vec2 cell = floor(v_uv * cells);

    // Motion vectors update on the codec's frame clock, not per pixel - hold
    // them across a whole frame or the blocks buzz instead of drifting.
    float frame = floor(time * rate);

    // A block keeps reusing its vector until the next keyframe, so error
    // accumulates. That accumulation is the whole look.
    float age = fract(hash21(cell) + frame * 0.13);
    vec2 mv = hash22(cell + frame * 3.7) * smear * 0.09 * (0.3 + age);

    // Blocks that actually CHANGED get the bigger vectors, which is what a real
    // encoder does - it spends its motion budget where the picture moved. The
    // difference between this frame and the last is a genuine motion signal and
    // costs two fetches; the old version used the block's own brightness, which
    // put the most drift on whatever happened to be palest.
    vec2 cuv = (cell + 0.5) / cells;
    vec3 now  = texture(u_tex, cuv).rgb;
    vec3 was  = texture(u_feedback_tex, cuv).rgb;
    float moved = clamp(length(now - was) * 3.0, 0.0, 1.0);
    float energy = mix(dot(now, vec3(0.333)), moved, clamp(persist, 0.0, 1.0));
    mv *= 0.4 + energy * 1.6;

    vec2 uv = clamp(v_uv + mv, 0.0, 1.0);

    // Each channel is stored at a different resolution, so they tear apart.
    // Sampled from the PREVIOUS output when persist is up: that is the whole
    // difference between a real mosh and a picture of one. The decoder has no
    // new pixels between keyframes, only vectors, so it keeps shoving the frame
    // it already had.
    vec3 col;
    col.r = texture(u_tex, clamp(uv + mv * chroma * 0.6, 0.0, 1.0)).r;
    col.g = texture(u_tex, uv).g;
    col.b = texture(u_tex, clamp(uv - mv * chroma * 0.6, 0.0, 1.0)).b;

    if (persist > 0.001) {
        vec3 old;
        old.r = texture(u_feedback_tex, clamp(uv + mv * chroma * 0.6, 0.0, 1.0)).r;
        old.g = texture(u_feedback_tex, uv).g;
        old.b = texture(u_feedback_tex, clamp(uv - mv * chroma * 0.6, 0.0, 1.0)).b;
        col = mix(col, old, clamp(persist, 0.0, 0.98));
    }

    // Bloom: a block whose residual never arrives keeps its old DC value and
    // sits there as a flat smudge of colour.
    float stuck = hash21(cell + floor(frame * 0.5) * 11.0);
    if (stuck < bloom_amt * 0.35) {
        vec3 dc = texture(u_tex, (cell + 0.5) / cells).rgb;
        col = mix(col, dc, 0.85);
    }

    // A surviving keyframe snaps part of the picture back to correct.
    float key = step(1.0 - iframe, hash21(vec2(frame, 0.0)));
    if (key > 0.5) {
        float band = step(hash21(vec2(frame, 1.0)), fract(v_uv.y + hash21(vec2(frame, 2.0))));
        col = mix(col, texture(u_tex, v_uv).rgb, band);
    }

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float luma = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(luma * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((luma - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
