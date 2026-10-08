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

layout(std140, binding = 1) uniform Params { vec4 _p[1]; };
#define blur_mode _p[0].x
#define blur_radius _p[0].y
#define blur_angle _p[0].z
#define blur_boost _p[0].w




// RIFT - blur.frag
// Reactive blur (TouchDesigner "modulate Blur size on snares/drops"):
//   mode 0 = gaussian   (13-tap, two-axis approximation in one pass)
//   mode 1 = directional (motion smear along blur_angle)
//   mode 2 = radial zoom (samples toward/away from center - drop hit look)
// Route blur_radius to HIT for snare-triggered smears.









   // 0..1, scaled internally
    // radians, for directional mode
    // brightness compensation / bloom feel


void main() {
    float radius = clamp(blur_radius, 0.0, 1.0);
    int mode = int(floor(blur_mode + 0.5));
    vec3 acc = vec3(0.0);
    float wsum = 0.0;

    if (radius < 0.002) {
        acc = texture(u_tex, v_uv).rgb;
        wsum = 1.0;
    }
    else if (mode == 1) {
        // Directional smear
        vec2 dir = vec2(cos(blur_angle), sin(blur_angle)) * radius * 0.15;
        for (int i = -8; i <= 8; i++) {
            float t = float(i) / 8.0;
            float w = exp(-t * t * 2.0);
            acc += texture(u_tex, clamp(v_uv + dir * t, 0.0, 1.0)).rgb * w;
            wsum += w;
        }
    }
    else if (mode == 2) {
        // Radial zoom blur from center
        vec2 toC = v_uv - 0.5;
        for (int i = 0; i < 16; i++) {
            float t = float(i) / 15.0;
            float s = 1.0 - radius * 0.35 * t;
            float w = 1.0 - t * 0.5;
            acc += texture(u_tex, clamp(toC * s + 0.5, 0.0, 1.0)).rgb * w;
            wsum += w;
        }
    }
    else {
        // Gaussian disc: 13 taps on a poisson-ish ring layout.
        //
        // Tap spacing is a fraction of frame HEIGHT, quoted at 1080, not a
        // fixed count of device pixels. Dividing 40 px by u_resolution held the
        // disc at 40 px whatever the frame was: the viewport is ~670 tall and a
        // 4K export is 2160, so the same slider blurred over three times less
        // of the picture in the export than in the preview it was judged in.
        // Modes 1 and 2 were already frame-relative; this one was not.
        // x is scaled by the inverse aspect so the disc stays round.
        float r_h = radius * 40.0 / 1080.0;
        vec2 px = vec2(r_h * u_resolution.y / max(u_resolution.x, 1.0), r_h);
        const vec2 taps[13] = vec2[13](
            vec2(0.0, 0.0),
            vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
            vec2(0.707, 0.707), vec2(-0.707, 0.707), vec2(0.707, -0.707), vec2(-0.707, -0.707),
            vec2(2.0, 0.0), vec2(-2.0, 0.0), vec2(0.0, 2.0), vec2(0.0, -2.0)
        );
        const float wts[13] = float[13](
            0.20, 0.11, 0.11, 0.11, 0.11, 0.08, 0.08, 0.08, 0.08, 0.06, 0.06, 0.06, 0.06
        );
        for (int i = 0; i < 13; i++) {
            acc += texture(u_tex, clamp(v_uv + taps[i] * px, 0.0, 1.0)).rgb * wts[i];
            wsum += wts[i];
        }
    }

    vec3 col = (acc / max(wsum, 1e-5)) * (1.0 + (blur_boost - 1.0) * radius);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float l = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(l * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((l - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
