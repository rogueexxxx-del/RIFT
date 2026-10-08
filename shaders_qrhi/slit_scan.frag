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
layout(binding = 6) uniform sampler2D u_feedback_tex;   // last finished frame

layout(std140, binding = 1) uniform Params { vec4 _p[2]; };
#define axis    _p[0].x
#define span    _p[0].y
#define curve   _p[0].z
#define offset  _p[0].w
#define mix_amt _p[1].x
#define sharpen _p[1].y

// RIFT - slit_scan.frag
//
// Time displacement: each column (or row) shows the picture from a different
// moment, so a moving subject is stretched across the frame in time rather
// than in space.
//
// ponytail: built on the one-frame feedback texture, marching the history one
// step per frame, NOT on a Texture3D ring of N frames the way TouchDesigner's
// Time Machine TOP does it. That means the depth of history is however many
// frames it takes content to cross the frame, and it cannot be scrubbed or
// seeked - it accumulates. Upgrade path if that becomes a limit: a ring of N
// past frames in RhiContext and a 2D-array sampler here, at N x frame-size of
// VRAM.
//
// The consequence to know about: after a seek the history is whatever was on
// screen before, so the first second of an export shows the ramp filling. Give
// it a lead-in rather than cutting on frame 0.

const float kEdge = 0.02;    // width of the live band, in uv

void main() {
    bool horiz = int(floor(axis + 0.5)) == 0;
    float t = horiz ? v_uv.x : v_uv.y;
    t = fract(t + offset);

    // curve reshapes where time is compressed. At 1.0 the ramp is linear and
    // the streak is even; away from that it bunches the history toward one end,
    // which is what makes a smear read as motion rather than as a wipe.
    float shaped = pow(clamp(t, 0.0, 1.0), max(curve, 0.05));

    // One step per frame, so the depth of history in FRAMES is 1/step_uv - at
    // 60 fps, span 1.0 here is 100 frames, about 1.7 seconds of past.
    //
    // The scale was 0.05 first, which crossed the frame in 20 frames: a third
    // of a second of history, which is not enough time displacement to read as
    // anything except a horizontal smear.
    float step_uv = max(span, 1e-4) * 0.01;

    vec2 back = v_uv;
    if (horiz) back.x -= step_uv; else back.y -= step_uv;
    back = clamp(back, 0.0, 1.0);

    vec3 hist = texture(u_feedback_tex, back).rgb;
    vec3 src  = texture(u_tex, v_uv).rgb;

    // The leading edge takes the live frame; everything past it is history
    // shifted along. Iterated, that walks each moment across the frame.
    float live = 1.0 - smoothstep(0.0, kEdge + shaped * 0.001, t);

    // sharpen counteracts the blur that repeated bilinear resampling adds -
    // every frame the history is sampled off-grid, and a few hundred of those
    // turn a crisp edge to mush.
    if (sharpen > 0.0) {
        vec2 px = 1.0 / max(u_resolution, vec2(1.0));
        vec3 blur = (texture(u_feedback_tex, clamp(back + vec2(px.x, 0.0), 0.0, 1.0)).rgb
                   + texture(u_feedback_tex, clamp(back - vec2(px.x, 0.0), 0.0, 1.0)).rgb
                   + texture(u_feedback_tex, clamp(back + vec2(0.0, px.y), 0.0, 1.0)).rgb
                   + texture(u_feedback_tex, clamp(back - vec2(0.0, px.y), 0.0, 1.0)).rgb) * 0.25;
        hist += (hist - blur) * sharpen;
    }

    vec3 col = mix(hist, src, clamp(live, 0.0, 1.0));
    // mix_amt dials the whole displacement back toward the untouched source,
    // so the effect can sit under a cut instead of replacing the shot.
    fragColor = vec4(mix(src, col, clamp(mix_amt, 0.0, 1.0)), 1.0);
}
