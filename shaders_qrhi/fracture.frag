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
#define slices _p[0].x
#define offset_max _p[0].y
#define decay _p[0].z
#define color_bleed _p[0].w
#define invert_thresh _p[1].x
#define glitch_acc _p[1].y















// Color Palette Uniforms


float rand(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float rand2(vec2 n) { return fract(sin(dot(n, vec2(12.9898,4.1414))) * 43758.5453); }

void main() {
    vec2 uv = v_uv;

    // Transient-boosted glitch accumulator
    float ga = glitch_acc * (1.0 + transient * 2.0);

    // Time quantisation for glitch stepping
    float tq = floor(time * 4.0);

    // --- Horizontal slice offset (original axis) ---
    float by = floor(uv.y * slices);
    float offsetH = (rand(by + tq) - 0.5) * ga * 2.0;
    // Apply decay: slices further from center decay
    float decayH = exp(-abs(by - slices * 0.5) * decay * 0.1);
    offsetH *= decayH;
    offsetH = clamp(offsetH, -offset_max, offset_max);

    // --- Vertical fracture offset (perpendicular) ---
    float bx = floor(uv.x * slices * 0.5);
    float offsetV = (rand(bx + tq * 1.7 + 99.0) - 0.5) * ga * 1.2;
    float decayV = exp(-abs(bx - slices * 0.25) * decay * 0.15);
    offsetV *= decayV;
    offsetV = clamp(offsetV, -offset_max * 0.6, offset_max * 0.6);

    // Combined displacement
    vec2 totalOffset = vec2(offsetH, offsetV);

    // Amplitude-modulated color bleed
    float bleed = color_bleed * (1.0 + amplitude * 1.5);

    // RGB split sampling with both offsets
    float r = texture(u_tex, uv + totalOffset * vec2(bleed, 0.8)).r;
    float g = texture(u_tex, uv + totalOffset * vec2(0.5, 0.5)).g;
    float b = texture(u_tex, uv + totalOffset * vec2(-bleed * 0.7, -0.6)).b;

    // Inversion bands
    float inv = step(invert_thresh, rand2(vec2(by, floor(time * 6.0)))) * step(0.3, ga * 10.0);
    vec3 col = mix(vec3(r,g,b), 1.0 - vec3(r,g,b), inv);

    // --- Edge glow: detect glitch boundaries ---
    // Check adjacent horizontal slice
    float byNext = floor((uv.y + 1.0 / slices) * slices);
    float offsetAdj = (rand(byNext + tq) - 0.5) * ga * 2.0;
    offsetAdj *= exp(-abs(byNext - slices * 0.5) * decay * 0.1);
    float edgeH = abs(offsetH - offsetAdj);

    // Check adjacent vertical slice
    float bxNext = floor((uv.x + 2.0 / slices) * slices * 0.5);
    float offsetAdjV = (rand(bxNext + tq * 1.7 + 99.0) - 0.5) * ga * 1.2;
    offsetAdjV *= exp(-abs(bxNext - slices * 0.25) * decay * 0.15);
    float edgeV = abs(offsetV - offsetAdjV);

    // Edge proximity within slice (glow near boundaries)
    float fracY = fract(uv.y * slices);
    float fracX = fract(uv.x * slices * 0.5);
    float edgeProxH = 1.0 - smoothstep(0.0, 0.08, min(fracY, 1.0 - fracY));
    float edgeProxV = 1.0 - smoothstep(0.0, 0.08, min(fracX, 1.0 - fracX));

    // Glow intensity based on offset difference and edge proximity
    float glowH = edgeH * edgeProxH * 8.0;
    float glowV = edgeV * edgeProxV * 6.0;
    float glow = clamp(glowH + glowV, 0.0, 1.0);

    // Glow color: bright cyan-white
    vec3 glowCol = mix(vec3(0.4, 0.8, 1.0), vec3(1.0), glow * 0.5);
    col += glowCol * glow * (0.5 + transient * 1.5);

    // Bass-driven brightness pulse
    col *= 1.0 + bass * 0.25;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float luma = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(luma * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((luma - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
