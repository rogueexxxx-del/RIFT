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
#define threshold _p[0].x
#define max_length _p[0].y
#define speed _p[0].z
#define color_bleed _p[0].w
#define sort_dir _p[1].x













// Custom params




   // 0 down, 1 up, 2 right, 3 left

// Color Palette Uniforms


// Simple random generator
float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = v_uv;

    // Rhythmic speed multiplier
    float t = time * speed;

    // Sort axis from direction param
    int dir = int(floor(sort_dir + 0.5));
    vec2 axis = (dir == 0) ? vec2(0.0, 1.0)
              : (dir == 1) ? vec2(0.0, -1.0)
              : (dir == 2) ? vec2(-1.0, 0.0)
              : vec2(1.0, 0.0);
    float cross_coord = (dir < 2) ? uv.x : uv.y;
    float cross_res = (dir < 2) ? u_resolution.x : u_resolution.y;

    float search_limit = max_length + transient * 0.15; // stretch further on beat

    // One sort lane per texture pixel row/column - true per-lane streaks
    float col_count = max(cross_res, 64.0);
    float segment_id = floor(cross_coord * col_count);
    float col_offset = rand(vec2(segment_id, 123.4)) * t * 0.2;

    float offset = 0.0;
    bool found = false;

    // Dynamic threshold modulated by audio
    float dyn_threshold = threshold + 0.1 * sin(t + col_offset);

    // Coarse-to-fine search: coarse pass finds the bright interval,
    // fine pass refines the boundary so streak edges are not quantized
    // into visible bands.
    float coarse_step = search_limit / 40.0;
    for (float i = 0.0; i < 40.0; i += 1.0) {
        float step_size = i * coarse_step;
        vec2 sample_uv = clamp(uv + axis * step_size, 0.0, 1.0);

        vec4 sample_col = texture(u_tex, sample_uv);
        float br = dot(sample_col.rgb, vec3(0.299, 0.587, 0.114));

        if (br > dyn_threshold) {
            // Refine: binary search between previous and current step
            float lo = max(step_size - coarse_step, 0.0);
            float hi = step_size;
            for (int j = 0; j < 5; j++) {
                float m = (lo + hi) * 0.5;
                vec2 mid_uv = clamp(uv + axis * m, 0.0, 1.0);
                float mbr = dot(texture(u_tex, mid_uv).rgb, vec3(0.299, 0.587, 0.114));
                if (mbr > dyn_threshold) { hi = m; } else { lo = m; }
            }
            offset = hi;
            found = true;
            break;
        }
    }

    // Streak falloff: fade displacement with distance so long streaks
    // taper out instead of hard-copying one bright row forever
    if (found) {
        float falloff = 1.0 - smoothstep(0.0, search_limit, offset) * 0.35;
        offset *= falloff;
    }

    // Sample texture with the displaced UV coordinate
    vec2 sort_uv = clamp(uv + axis * offset, 0.0, 1.0);

    // Chromatic aberration (color bleed) perpendicular to the sort axis
    vec3 out_col;
    if (color_bleed > 0.0) {
        float bleed = color_bleed + transient * 0.01;
        vec2 perp = vec2(-axis.y, axis.x) * bleed;
        out_col.r = texture(u_tex, clamp(sort_uv - perp, 0.0, 1.0)).r;
        out_col.g = texture(u_tex, sort_uv).g;
        out_col.b = texture(u_tex, clamp(sort_uv + perp, 0.0, 1.0)).b;
    } else {
        out_col = texture(u_tex, sort_uv).rgb;
    }
    
    fragColor = vec4(out_col, 1.0);
    
    // -- Global Color Palette Modulator --
    if (u_palette_active > 0.5) {
        float luma = dot(fragColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 grad = mix(u_color_bg, u_color_fg1, clamp(luma * 2.0, 0.0, 1.0));
        grad = mix(grad, u_color_fg2, clamp((luma - 0.5) * 2.0, 0.0, 1.0));
        fragColor.rgb = grad;
    }
}
