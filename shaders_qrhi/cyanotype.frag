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
#define exposure _p[0].x
#define contrast _p[0].y
#define grain _p[0].z
#define wash _p[0].w
#define edge_burn _p[1].x


// Cyanotype: the sun-print process. A UV-sensitive iron salt turns Prussian
// blue where light hits it, so the print is a single-ink negative - there is
// no hue information left, only how much blue survived the wash.
float hash21(vec2 p) {
    p = fract(p * vec2(233.34, 851.73));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

// Fibrous paper: two octaves of value noise, stretched sideways so it reads
// as pulp rather than TV static.
float paper(vec2 uv) {
    // Fibre size against a 1080-tall reference, not device pixels: paper grain
    // fixed in pixels comes out half as coarse, proportionally, in a 4K export
    // as in the preview - fine pulp turns into smooth nothing.
    vec2 s = uv * vec2(u_resolution.x / max(u_resolution.y, 1.0), 1.0) * 1080.0 / 3.0;
    float n = hash21(floor(s));
    n += 0.5 * hash21(floor(s * vec2(0.31, 2.7)));
    return n / 1.5;
}

void main() {
    vec3 src = texture(u_tex, v_uv).rgb;

    // Iron salts respond to UV, which is nowhere near the eye's green-weighted
    // luminance - blue and violet expose far more than red does.
    float uv_lum = dot(src, vec3(0.15, 0.35, 0.50));
    float e = pow(clamp(uv_lum * exposure, 0.0, 1.0), contrast);

    // Where the paper was exposed the salt is *removed* by the wash, so the
    // print is a negative: bright subject -> pale paper.
    float density = 1.0 - e;

    vec3 ink   = vec3(0.043, 0.208, 0.373);   // Prussian blue
    vec3 sheet = vec3(0.878, 0.882, 0.824);   // unbleached rag paper
    vec3 col = mix(sheet, ink, density);

    // Deep shadows go almost black-blue rather than staying flat.
    col = mix(col, ink * 0.45, smoothstep(0.75, 1.0, density));

    // The wash never rinses evenly; low-frequency blotches survive.
    float blotch = paper(v_uv * 0.12 + vec2(time * 0.005, 0.0));
    col = mix(col, sheet, wash * 0.35 * blotch * (1.0 - density));

    col += (paper(v_uv) - 0.5) * grain * 0.18;

    // Contact-printed edges over-expose where the frame did not hold flat.
    vec2 d = abs(v_uv - 0.5) * 2.0;
    float edge = max(d.x, d.y);
    col = mix(col, ink * 0.6,
              edge_burn * smoothstep(0.75, 1.15, edge + hash21(v_uv * 40.0) * 0.08));

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float luma = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(luma * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((luma - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
