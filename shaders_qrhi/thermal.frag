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
#define palette _p[0].x
#define t_low _p[0].y
#define t_high _p[0].z
#define bloom _p[0].w
#define sensor _p[1].x
#define posterize _p[1].y


// Thermal camera. A microbolometer measures emitted infrared, then maps the
// span between the coldest and hottest pixel in the scene onto a false-colour
// ramp. The level/span controls matter more than the ramp: an uncalibrated
// thermal image is flat, which is why COLD/HOT are the real knobs here.
float hash21(vec2 p) {
    p = fract(p * vec2(217.31, 731.19));
    p += dot(p, p + 37.7);
    return fract(p.x * p.y);
}

vec3 ramp_iron(float t) {
    vec3 c = mix(vec3(0.0, 0.0, 0.06), vec3(0.36, 0.0, 0.53), smoothstep(0.0, 0.30, t));
    c = mix(c, vec3(0.85, 0.15, 0.35), smoothstep(0.30, 0.55, t));
    c = mix(c, vec3(1.0, 0.62, 0.06),  smoothstep(0.55, 0.80, t));
    c = mix(c, vec3(1.0, 1.0, 0.88),   smoothstep(0.80, 1.0,  t));
    return c;
}
vec3 ramp_rainbow(float t) {
    vec3 c = mix(vec3(0.0, 0.0, 0.25), vec3(0.0, 0.45, 0.95), smoothstep(0.0, 0.25, t));
    c = mix(c, vec3(0.0, 0.85, 0.35), smoothstep(0.25, 0.45, t));
    c = mix(c, vec3(0.95, 0.95, 0.0), smoothstep(0.45, 0.65, t));
    c = mix(c, vec3(1.0, 0.35, 0.0),  smoothstep(0.65, 0.85, t));
    c = mix(c, vec3(1.0, 1.0, 1.0),   smoothstep(0.85, 1.0,  t));
    return c;
}
vec3 ramp_white(float t) { return vec3(t); }
vec3 ramp_arctic(float t) {
    vec3 c = mix(vec3(0.02, 0.03, 0.10), vec3(0.10, 0.35, 0.62), smoothstep(0.0, 0.4, t));
    c = mix(c, vec3(0.55, 0.85, 0.95), smoothstep(0.4, 0.72, t));
    c = mix(c, vec3(1.0, 0.95, 0.80),  smoothstep(0.72, 1.0, t));
    return c;
}

void main() {
    vec2 px = 1.0 / max(u_resolution, vec2(1.0));

    // Thermal optics are soft: germanium lenses and a coarse sensor mean no
    // sharp edges ever reach the display. A small box blur stands in.
    float t = 0.0;
    for (int y = -1; y <= 1; y++)
        for (int x = -1; x <= 1; x++)
            t += dot(texture(u_tex, v_uv + vec2(x, y) * px * 1.5).rgb,
                     vec3(0.299, 0.587, 0.114));
    t /= 9.0;

    // Level/span. Guarded so dragging HOT below COLD inverts cleanly instead
    // of dividing by zero.
    float lo = min(t_low, t_high), hi = max(t_low, t_high);
    t = clamp((t - lo) / max(hi - lo, 0.001), 0.0, 1.0);

    // Hot regions bleed into their surroundings on a real sensor.
    if (bloom > 0.0) {
        float around = 0.0;
        for (int i = 0; i < 6; i++) {
            float a = float(i) * 1.0472;
            around += dot(texture(u_tex, v_uv + vec2(cos(a), sin(a)) * px * 6.0).rgb,
                          vec3(0.299, 0.587, 0.114));
        }
        t += max(around / 6.0 - hi, 0.0) * bloom * 1.5;
        t = clamp(t, 0.0, 1.0);
    }

    // Fixed-pattern noise sits still while the scene moves - that is what
    // distinguishes a sensor artefact from film grain.
    t += (hash21(floor(v_uv * u_resolution / 2.0)) - 0.5) * sensor * 0.12;
    t += (hash21(v_uv * u_resolution + time * 31.0) - 0.5) * sensor * 0.05;
    t = clamp(t, 0.0, 1.0);

    // Isotherm banding, as used to read exact temperatures off a scene.
    float steps = floor(posterize + 0.5);
    if (steps >= 2.0) t = floor(t * steps) / (steps - 1.0);

    int p = int(floor(palette + 0.5));
    vec3 col = p == 0 ? ramp_iron(t)
             : p == 1 ? ramp_rainbow(t)
             : p == 2 ? ramp_white(t)
                      : ramp_arctic(t);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float luma = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(luma * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((luma - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
