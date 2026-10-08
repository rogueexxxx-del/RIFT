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
layout(binding = 6) uniform sampler2D u_feedback_tex;

layout(std140, binding = 1) uniform Params { vec4 _p[5]; };
#define u_vignette _p[0].x
#define u_grain_scale _p[0].y
#define u_grain_amount _p[0].z
#define u_grain_speed _p[0].w
#define u_scanline_count _p[1].x
#define u_scanline_opacity _p[1].y
#define u_dither_levels _p[1].z
#define u_dither_scale _p[1].w
#define u_dither_mono _p[2].x
#define u_dither_bias _p[2].y
#define u_halftone_dot _p[2].z
#define u_track_feedback _p[2].w
#define u_track_zoom _p[3].x
#define u_track_rotate _p[3].y
#define u_track_warp _p[3].z
#define u_glass_crystal _p[3].w
#define u_glass_aberration _p[4].x
#define u_glass_distortion _p[4].y
#define u_glass_pixelate _p[4].z
#define u_glass_refract _p[4].w



          // input frame from previous pass
 // accumulated feedback frame

// Texture FX







// Dither FX






// Track FX





// Glass FX


// 2D Hash for Voronoi
vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

// Simple Voronoi cell offset
vec2 voronoi(vec2 x) {
    vec2 n = floor(x);
    vec2 f = fract(x);
    vec2 mr = vec2(0.0);
    float md = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash2(n + g);
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < md) {
                md = d;
                mr = r;
            }
        }
    }
    return mr;
}

// Pseudo-random noise generator
float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    // ==========================================
    // 1. GLASS FX - Coordinate warping & distortion
    // ==========================================
    vec2 uv = v_uv;

    // Lens distortion (pincushion/barrel)
    if (abs(u_glass_distortion) > 0.001) {
        vec2 tc = uv - 0.5;
        float r2 = dot(tc, tc);
        tc *= (1.0 + u_glass_distortion * r2);
        uv = tc + 0.5;
    }

    // Pixelate
    if (u_glass_pixelate > 1.0) {
        uv = floor(uv * u_glass_pixelate) / u_glass_pixelate;
    }

    // Crystal Voronoi refraction
    if (u_glass_crystal > 0.0) {
        vec2 cell_offset = voronoi(uv * u_glass_crystal);
        uv += cell_offset * u_glass_refract;
    }

    // Chromatic Aberration (Radial split)
    vec4 col = vec4(0.0);
    if (u_glass_aberration > 0.0) {
        vec2 to_center = uv - 0.5;
        col.r = texture(u_tex, uv + to_center * u_glass_aberration).r;
        col.g = texture(u_tex, uv).g;
        col.b = texture(u_tex, uv - to_center * u_glass_aberration).b;
        col.a = texture(u_tex, uv).a;
    } else {
        col = texture(u_tex, uv);
    }

    // ==========================================
    // 2. TRACK FX - Feedback Blend
    // ==========================================
    if (u_track_feedback > 0.0) {
        // Sample feedback texture with custom zoom/rotate offsets
        vec2 fb_uv = v_uv - 0.5;
        
        // Apply feedback rotation
        float theta = u_track_rotate * 0.05;
        float cos_theta = cos(theta);
        float sin_theta = sin(theta);
        vec2 rotated_fb_uv = vec2(
            fb_uv.x * cos_theta - fb_uv.y * sin_theta,
            fb_uv.x * sin_theta + fb_uv.y * cos_theta
        );
        
        // Apply zoom & warp
        rotated_fb_uv *= u_track_zoom;
        
        if (u_track_warp > 0.0) {
            rotated_fb_uv.x += sin(rotated_fb_uv.y * 10.0 + time) * u_track_warp;
            rotated_fb_uv.y += cos(rotated_fb_uv.x * 10.0 + time) * u_track_warp;
        }
        
        vec4 fb_col = texture(u_feedback_tex, rotated_fb_uv + 0.5);
        col = mix(col, fb_col, u_track_feedback);
    }

    // ==========================================
    // 3. DITHER FX - Color Reduction & Halftoning
    // ==========================================
    // Halftone dots - classic print screening:
    // dot AREA proportional to brightness => radius ∝ sqrt(brightness).
    // 45° grid rotation like offset printing, anti-aliased edges.
    if (u_halftone_dot > 0.0) {
        // Grid measured against a 1080-tall reference frame, not device pixels:
        // a dot size fixed in pixels doubles the dot COUNT and halves their
        // relative size in a 4K export against the preview it was dialled in
        // on. Identical at 1920x1080, proportional everywhere else.
        vec2 rres = vec2(u_resolution.x / max(u_resolution.y, 1.0), 1.0) * 1080.0;
        vec2 px = uv * rres;
        // Rotate grid 45 degrees (standard mono screening angle)
        const float c45 = 0.70710678;
        vec2 rot = vec2(px.x * c45 - px.y * c45, px.x * c45 + px.y * c45);
        vec2 grid = rot / u_halftone_dot;
        vec2 f_grid = fract(grid) - 0.5;
        float dot_dist = length(f_grid);

        // Sample brightness at the CELL CENTER so each dot has one size
        vec2 cell_center_rot = (floor(grid) + 0.5) * u_halftone_dot;
        vec2 cell_px = vec2(cell_center_rot.x * c45 + cell_center_rot.y * c45,
                            -cell_center_rot.x * c45 + cell_center_rot.y * c45);
        vec3 cell_col = texture(u_tex, cell_px / rres).rgb;
        float brightness = dot(cell_col, vec3(0.299, 0.587, 0.114));

        float radius = sqrt(brightness) * 0.5; // area-linear response
        float aa = 1.0 / u_halftone_dot;       // ~1px anti-alias band
        float is_dot = 1.0 - smoothstep(radius - aa, radius + aa, dot_dist);
        col.rgb *= is_dot;
    }

    // Bayer Dithering
    if (u_dither_levels > 0.0) {
        const float bayer8[64] = float[64](
             0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0,
            48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0,
            12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0,
            60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0,
             3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0,
            51.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0,
            15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0,
            63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0
        );

        // Scaled against a 1080-tall reference: gl_FragCoord is in device
        // pixels, so a raw scale pinned the pattern to a pixel count and a 4K
        // export dithered at half the relative size of the preview.
        float d_scale = max(max(1.0, u_dither_scale) * u_resolution.y / 1080.0, 1e-3);
        int bx = int(mod(gl_FragCoord.x / d_scale, 8.0));
        int by = int(mod(gl_FragCoord.y / d_scale, 8.0));
        float threshold = bayer8[by * 8 + bx] + u_dither_bias;
        
        if (u_dither_mono > 0.5) {
            float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
            float d = floor(lum * u_dither_levels + threshold) / u_dither_levels;
            col.rgb = vec3(d);
        } else {
            col.r = floor(col.r * u_dither_levels + threshold) / u_dither_levels;
            col.g = floor(col.g * u_dither_levels + threshold) / u_dither_levels;
            col.b = floor(col.b * u_dither_levels + threshold) / u_dither_levels;
        }
    }

    // ==========================================
    // 4. TEXTURE FX - Overlays & Grain
    // ==========================================
    // Scanlines
    if (u_scanline_count > 0.0) {
        float sl = sin(v_uv.y * u_scanline_count * 6.28318);
        float line_mult = mix(1.0, (sl * 0.5 + 0.5), u_scanline_opacity);
        col.rgb *= line_mult;
    }

    // Film Grain
    if (u_grain_amount > 0.0) {
        float noise = rand(uv * u_grain_scale + fract(time * u_grain_speed));
        col.rgb = mix(col.rgb, col.rgb + (noise - 0.5) * 0.5, u_grain_amount);
    }

    // Vignette
    if (u_vignette > 0.0) {
        vec2 d = abs(v_uv - 0.5) * u_vignette;
        float vig = clamp(1.0 - dot(d, d), 0.0, 1.0);
        col.rgb *= vig;
    }

    fragColor = vec4(clamp(col.rgb, 0.0, 1.0), col.a);
}
