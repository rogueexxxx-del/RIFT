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
#define block_count _p[0].x
#define offset_max _p[0].y
#define trigger_thresh _p[0].z
#define color_bleed _p[0].w
#define time_speed _p[1].x
















// Color Palette Uniforms


float rand(float n) { return fract(sin(n * 91.233) * 43758.5453); }
float rand2(vec2 n) { return fract(sin(dot(n, vec2(12.9898, 78.233))) * 43758.5453); }
float rand3(vec2 n) { return fract(sin(dot(n, vec2(41.256, 93.117))) * 27634.1832); }

// Hue rotation: rotate RGB by angle in radians (reuses codebase's standard hue shift helper)
vec3 hueRotate(vec3 col, float hue) {
    vec3 k = vec3(0.57735);
    float cosAngle = cos(hue);
    return col * cosAngle + cross(k, col) * sin(hue) + k * dot(k, col) * (1.0 - cosAngle);
}

// Noise for static overlay
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec2 uv = v_uv;

    // BPM-modulated flicker rate
    float flicker_speed = time_speed * (1.0 + bpm);
    float t = floor(time * flicker_speed);

    // Bass-driven block size variation: fewer, larger blocks when bass hits
    float effective_blocks = block_count * (1.0 - bass * 0.4);
    float by = floor(uv.y * effective_blocks);

    // Amplitude modulates overall glitch intensity
    float intensity = 0.3 + amplitude * 0.7;

    // Video luminance drives glitch scale
    float luma = dot(texture(u_tex, uv).rgb, vec3(0.299, 0.587, 0.114));

    // Block activation - transient + amplitude driven
    float activation_seed = rand(by + t);
    // Audio drives the amount, but with a floor: EVERY control in this shader
    // multiplies through is_active, so on a project with no audio loaded the
    // whole effect collapsed to a pass-through and block_count, offset_max and
    // trigger_thresh read as broken sliders.
    float drive = max(max(transient, amplitude * 0.5), 0.2);
    float is_active = step(trigger_thresh, activation_seed) * drive * intensity;

    // --- Screen Tear Lines ---
    // Occasional full-width horizontal displacement bands
    float tear_seed = rand(floor(time * 15.0));
    float tear_y = rand(floor(time * 7.3 + 3.0));
    float tear_band = smoothstep(0.0, 0.02, abs(uv.y - tear_y)) ;
    float tear_active = step(0.85, tear_seed) * transient;
    float tear_offset = (rand(floor(time * 23.7)) - 0.5) * 0.15 * tear_active;
    uv.x += tear_offset * (1.0 - tear_band);

    // --- Block Displacement ---
    float off = (rand(by + t + 0.5) - 0.5) * offset_max * is_active * (0.5 + luma * 1.5) * intensity;

    // Additional sub-block jitter for aggression
    float micro_jitter = (rand2(vec2(by, t + 7.7)) - 0.5) * 0.02 * is_active * amplitude;

    // Chromatic aberration with color bleed
    float bleed = color_bleed * (1.0 + transient * 0.5);
    float r = texture(u_tex, vec2(uv.x + off * bleed + micro_jitter, uv.y)).r;
    float g = texture(u_tex, vec2(uv.x + off + micro_jitter * 0.5, uv.y)).g;
    float b = texture(u_tex, vec2(uv.x - off * bleed * 0.5 - micro_jitter, uv.y)).b;

    vec3 glitch_col = vec3(r, g, b);

    // --- Hue Rotation per Active Block ---
    float hue_angle = rand(by + t + 2.3) * 6.28318 * is_active;
    glitch_col = hueRotate(glitch_col, hue_angle * 0.7);

    // --- Color Inversion on random blocks ---
    float inv = step(0.88, rand2(vec2(by, t))) * is_active;
    vec3 inv_col = abs(glitch_col - vec3(luma));
    glitch_col = mix(glitch_col, inv_col, inv);

    // --- Static / Noise Overlay on Inactive Blocks ---
    float is_inactive = 1.0 - step(0.01, is_active);
    float static_noise = noise(uv * 800.0 + vec2(time * 100.0));
    float static_intensity = high * 0.15 * is_inactive;
    glitch_col += vec3(static_noise) * static_intensity;

    // --- Scanline Artifacts ---
    float scanline = sin(uv.y * 800.0 + time * 50.0) * 0.03 * is_active;
    glitch_col += vec3(scanline);

    // --- Digital Dropout: random black bars ---
    float dropout = step(0.96, rand2(vec2(by * 3.0, t))) * is_active;
    glitch_col *= (1.0 - dropout * 0.8);

    // --- RGB Channel Shift on tear lines ---
    glitch_col.r += tear_active * 0.1 * (1.0 - tear_band);
    glitch_col.b -= tear_active * 0.08 * (1.0 - tear_band);

    fragColor = vec4(clamp(glitch_col, 0.0, 1.0), 1.0);

    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float l = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(l * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((l - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
