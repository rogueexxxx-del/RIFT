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
#define ink_count _p[0].x
#define dot_size _p[0].y
#define misreg _p[0].z
#define ink_weight _p[0].w
#define roughness _p[1].x


// Risograph: a duplicator that prints one spot ink per pass. Every pass is a
// 1-bit halftone screen of a single colour, the drum re-registers the paper
// each time (so the layers never line up), and the inks sit on top of each
// other rather than blending, which is why riso greens look nothing like CMY.
float hash21(vec2 p) {
    p = fract(p * vec2(311.7, 127.1));
    p += dot(p, p + 42.3);
    return fract(p.x * p.y);
}

// One ink pass: rotate into the screen's angle, threshold against a dot
// lattice, and return coverage as 0 or 1 - a riso cannot print grey.
float screen_pass(vec2 uv, float amount, float angle, float cell) {
    float s = sin(angle), c = cos(angle);
    vec2 r = vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
    // Lattice measured against a 1080-tall reference frame. In device pixels
    // the dot count tracked the resolution, so a 4K export screened at twice
    // the density of the preview it was set up on.
    vec2 g = r * vec2(u_resolution.x / max(u_resolution.y, 1.0), 1.0) * 1080.0
           / max(cell, 1.0);
    // Distance to the nearest lattice point sets the dot's radius, so the
    // dots grow with ink amount instead of just getting denser.
    float d = length(fract(g) - 0.5) * 1.4142;
    float rough = (hash21(floor(g)) - 0.5) * roughness * 0.35;
    return step(d + rough, sqrt(clamp(amount, 0.0, 1.0)));
}

void main() {
    vec3 src = texture(u_tex, v_uv).rgb;
    int inks = int(floor(ink_count + 0.5));

    // Real riso spot inks, not process colours.
    vec3 ink_a = vec3(0.000, 0.478, 0.808);   // Federal Blue
    vec3 ink_b = vec3(0.965, 0.310, 0.435);   // Fluorescent Pink
    vec3 ink_c = vec3(1.000, 0.906, 0.243);   // Yellow
    vec3 ink_d = vec3(0.000, 0.663, 0.400);   // Green

    // Each pass gets its own registration error, because each is a separate
    // trip through the drum.
    float m = misreg * 0.010;
    vec2 off_a = vec2( m,      -m * 0.6);
    vec2 off_b = vec2(-m * 0.8, m * 0.9);
    vec2 off_c = vec2( m * 0.4, m);
    vec2 off_d = vec2(-m * 0.3, -m * 1.2);

    // Separate on how much each ink is *needed*, which for a spot colour is
    // how much of its complement the source is missing.
    float a_amt = (1.0 - src.r) * ink_weight;
    float b_amt = (1.0 - src.g) * ink_weight;
    float c_amt = (1.0 - src.b) * ink_weight;
    float d_amt = (1.0 - dot(src, vec3(0.333))) * ink_weight * 0.7;

    vec3 col = vec3(0.949, 0.937, 0.898);     // newsprint stock

    // Multiply, not mix: overlapping ink absorbs twice.
    col *= mix(vec3(1.0), ink_a, screen_pass(v_uv + off_a, a_amt, 0.262, dot_size));
    col *= mix(vec3(1.0), ink_b, screen_pass(v_uv + off_b, b_amt, 1.309, dot_size));
    if (inks >= 3)
        col *= mix(vec3(1.0), ink_c, screen_pass(v_uv + off_c, c_amt, 0.785, dot_size));
    if (inks >= 4)
        col *= mix(vec3(1.0), ink_d, screen_pass(v_uv + off_d, d_amt, 1.833, dot_size));

    // The drum smears ink downward and skips patches; this is the defect
    // people actually print riso for.
    // The drum drags ink in streaks down the sheet and misses patches. Keyed
    // on a coarse 2D cell, not on the row alone - a whole-width band reads as
    // a scanline, which is a different artefact from a different machine.
    // 180 bands, fixed. Off u_resolution.y the patch count tracked the frame,
    // so the skip defect was coarse in the viewport and fine grain at 4K.
    vec2 sc = floor(v_uv * vec2(9.0, 1080.0 / 6.0));
    float skip = hash21(sc);
    col = mix(col, vec3(0.949, 0.937, 0.898), roughness * 0.4 * step(0.93, skip));

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float luma = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(luma * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((luma - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
