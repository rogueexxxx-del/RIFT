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
// Where to start the trace, 0..1. Found on the CPU once per frame.
#define scope_trigger   uC.z
// Newest row of the spectrogram ring, 0..255.
#define spectro_row     uC.w
#define u_palette_active uBg.a
#define u_color_bg      uBg.rgb
#define u_color_fg1     uFg1.rgb
#define u_color_fg2     uFg2.rgb

layout(binding = 2) uniform sampler2D u_tex;
layout(binding = 3) uniform sampler2D u_audio_texture;   // row0 FFT, row1 wave, row2 vecX, row3 vecY
layout(binding = 4) uniform sampler2D u_spectro_tex;     // 1024x256 FFT history
layout(binding = 5) uniform sampler2D u_lut_tex;         // 256x8 RGBA8 color styles
layout(binding = 6) uniform sampler2D u_feedback_tex;    // Previous frame texture for trails

layout(std140, binding = 1) uniform Params { vec4 _p[3]; };
#define mode _p[0].x
#define gain _p[0].y
#define thickness _p[0].z
#define tilt _p[0].w
#define fill _p[1].x
#define grid_amt _p[1].y
#define palette _p[1].z
#define glow _p[1].w
#define mapping _p[2].x
#define speed _p[2].y

// RIFT - oscilloscope.frag
//
// Modelled on MiniMeters: a flat instrument, not a CRT. The look there comes
// from restraint - one accent colour on a near-black field, a hairline grid
// behind the trace, a thin line with a soft fill beneath it. No glow, no
// scanlines, no phosphor bloom; those hide detail, and detail is the entire
// reason to put a meter on screen.
//
// Modes (MODE, snaps to whole numbers):
//   0  OSCILLOSCOPE - waveform, zero-crossing aligned so the trace holds still
//   1  SPECTRUM     - line + fill, log frequency, with a peak trace
//   2  SPECTROGRAM  - time on x, frequency on y, dark-to-hot ramp
//   3  VECTORSCOPE  - Lissajous mid/side string-art with feedback trails
//   4  BANDS        - level per band, flat columns

// u_audio_texture is 1024x4:
// Row 0 (y = 0.125): Spectrum
// Row 1 (y = 0.375): Mono Waveform
// Row 2 (y = 0.625): Vectorscope X (side = (L - R) * 0.7071)
// Row 3 (y = 0.875): Vectorscope Y (mid  = (L + R) * 0.7071)
float fftAt(float x) {
    return texture(u_audio_texture, vec2(clamp(x, 0.0, 1.0), 0.125)).r;
}
float waveAt(float x) {
    return texture(u_audio_texture, vec2(clamp(x, 0.0, 1.0), 0.375)).r * 2.0 - 1.0;
}
vec2 vecAt(float t) {
    float vx = texture(u_audio_texture, vec2(clamp(t, 0.0, 1.0), 0.625)).r * 2.0 - 1.0;
    float vy = texture(u_audio_texture, vec2(clamp(t, 0.0, 1.0), 0.875)).r * 2.0 - 1.0;
    return vec2(vx, vy);
}
float specBand(float a, float b) {
    float acc = 0.0;
    for (int i = 0; i < 8; i++) acc += fftAt(mix(a, b, (float(i) + 0.5) / 8.0));
    return acc * 0.125;
}

// uv is NOT isotropic: one unit of uv.x spans u_resolution.x pixels and one of
// uv.y spans u_resolution.y. Every distance here is measured in HEIGHT UNITS -
// uv with x stretched by the aspect - so 1.0 means the frame height on both
// axes. Measuring in raw uv and converting with the height alone made a steep
// segment thin out on a wide frame and fatten on a tall one: the same trace
// changed weight when the export aspect changed.
vec2 hu(vec2 p) { return p * vec2(u_resolution.x / max(u_resolution.y, 1.0), 1.0); }

// Distance from p to segment ab, in height units.
float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 pa = hu(p) - hu(a), ba = hu(b) - hu(a);
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

// Line width, as a FRACTION of frame height rather than a count of device
// pixels. px_w is quoted at a 1080-tall frame.
//
// This used to divide by u_resolution.y, which held the trace at a constant
// size in device pixels. That is right for a widget on screen and wrong for a
// rendered frame: the viewport is ~670 px tall, so a 1.8 px trace there is
// 0.27% of the picture, while the same 1.8 px in a 2160-tall export is 0.08%.
// Exporting at 4K therefore turned a bold preview into a hairline that all but
// vanished once the file was played back scaled down - reported as "the
// oscilloscope exports black".
//
// Floored at one real pixel so the trace does not alias away entirely at a
// reduced preview scale, where the frame can be only a couple of hundred tall.
float stroke(float d, float px_w) {
    float px = max(px_w / 1080.0, 1.0 / max(u_resolution.y, 1.0));
    return 1.0 - smoothstep(px * 0.5, px * 0.5 + px * 0.6, d);
}

// Palette, taken from MiniMeters. The field is true black, not a dark grey,
// and everything drawn on it runs along ONE heat ramp: indigo where a signal is
// barely there, through magenta and red, to orange and white where it is loud.
// A single flat hue for everything -- the earlier teal -- throws away the
// loudness reading that the colour is carrying.
const vec3 kInk  = vec3(0.008, 0.008, 0.012);
const vec3 kGrid = vec3(0.140, 0.140, 0.160);
const vec3 kLine = vec3(0.839, 0.855, 0.945);   // pale outline over the fill
const vec3 kHot  = vec3(1.000, 0.180, 0.180);   // waveform red

// Hairline grid: quarters both ways, centre line heavier. Drawn under
// everything at low contrast so it reads as paper, not as data.
// Through stroke(), so the grid scales with the frame like everything else. A
// hairline quoted in device pixels survives the viewport and disappears at 4K.
// abs(uv.x - x) is scaled by the aspect to match: a vertical rule has to come
// out the same weight as a horizontal one.
float grid(vec2 uv) {
    float ax = u_resolution.x / max(u_resolution.y, 1.0);
    float g = 0.0;
    for (int i = 1; i < 4; i++) {
        float x = float(i) / 4.0;
        g = max(g, stroke(abs(uv.x - x) * ax, 1.2));
    }
    for (int i = 1; i < 4; i++) {
        float y = float(i) / 4.0;
        g = max(g, (i == 2 ? 1.0 : 0.6)
                 * stroke(abs(uv.y - y), (i == 2) ? 1.6 : 1.2));
    }
    return g;
}

// Five ramps through the same five stops, so PALETTE only changes the colours
// and never the shape of the reading. Most of each range sits below the middle,
// because that is where nearly every bin sits -- spacing the stops evenly puts
// the whole picture in one colour.
vec3 ramp(vec3 a, vec3 b, vec3 c, vec3 d, vec3 e, float x) {
    vec3 o = mix(kInk, a, smoothstep(0.00, 0.18, x));
    o = mix(o, b, smoothstep(0.18, 0.36, x));
    o = mix(o, c, smoothstep(0.36, 0.54, x));
    o = mix(o, d, smoothstep(0.54, 0.78, x));
    o = mix(o, e, smoothstep(0.78, 1.00, x));
    return o;
}

vec3 heat(float x) {
    x = clamp(x, 0.0, 1.0);
    int pal = int(floor(palette + 0.5));
    if (pal == 1)        // ice: deep blue through cyan to white
        return ramp(vec3(0.03, 0.09, 0.32), vec3(0.05, 0.30, 0.62),
                    vec3(0.10, 0.62, 0.82), vec3(0.45, 0.88, 0.92),
                    vec3(0.92, 0.99, 1.00), x);
    if (pal == 2)        // acid: green through lime to a pale yellow
        return ramp(vec3(0.02, 0.16, 0.10), vec3(0.04, 0.42, 0.22),
                    vec3(0.22, 0.74, 0.26), vec3(0.66, 0.93, 0.24),
                    vec3(0.96, 1.00, 0.78), x);
    if (pal == 3)        // ember: brown through amber to white
        return ramp(vec3(0.16, 0.05, 0.02), vec3(0.45, 0.14, 0.03),
                    vec3(0.82, 0.36, 0.05), vec3(0.98, 0.68, 0.16),
                    vec3(1.00, 0.95, 0.82), x);
    if (pal == 4)        // mono: for anyone laying the scope over footage
        return ramp(vec3(0.14, 0.14, 0.16), vec3(0.32, 0.32, 0.35),
                    vec3(0.55, 0.55, 0.59), vec3(0.78, 0.78, 0.82),
                    vec3(1.00, 1.00, 1.00), x);
    // 0: magma, the MiniMeters look
    return ramp(vec3(0.10, 0.03, 0.30), vec3(0.35, 0.05, 0.55),
                vec3(0.72, 0.08, 0.62), vec3(0.98, 0.13, 0.36),
                vec3(1.00, 0.72, 0.30), x);
}

void main() {
    // Screen space is y-down; every readout here means "up is more".
    vec2 uv = vec2(v_uv.x, 1.0 - v_uv.y);

    float g = max(gain, 0.01);
    float lw = 0.6 + thickness * 3.4;            // line width in pixels
    int m = int(floor(mode + 0.5));

    vec3 col = kInk;
    if (m != 2) col = mix(col, kGrid, grid(uv) * grid_amt);

    if (m == 0) {
        // ════ OSCILLOSCOPE ════
        // The signal is already aligned on CPU with sub-sample precision across [0, 1].
        float px = 1.0 / max(u_resolution.x, 256.0);
        float d = 1e9;
        float here = 0.5;

        // Sampling consecutive pixel columns keeps steep edges connected with sharp corners
        for (int i = -2; i <= 2; i++) {
            float x0 = uv.x + float(i) * px;
            float x1 = x0 + px;
            vec2 a = vec2(x0, 0.5 + waveAt(x0) * 0.44 * g);
            vec2 b = vec2(x1, 0.5 + waveAt(x1) * 0.44 * g);
            d = min(d, segDist(uv, a, b));
            if (i == 0) here = a.y;
        }

        // Fill between the trace and the center
        float band = step(min(here, 0.5), uv.y) * step(uv.y, max(here, 0.5));
        float swing = clamp(abs(here - 0.5) * 2.0, 0.0, 1.0);

        // Color LUT mapping:
        // mapping <= 0.5: horizontal position (left to right, uv.x)
        // mapping > 0.5:  amplitude (center to peak, swing)
        float map_val = (mapping > 0.5) ? swing : clamp(uv.x, 0.0, 1.0);

        // Visualizer 0 (Oscilloscope): row 0 line, row 1 glow
        vec4 lut_col = texture(u_lut_tex, vec2(map_val, 0.0625));
        vec4 glow_col = texture(u_lut_tex, vec2(map_val, 0.1875));
        vec3 line_col = lut_col.a > 0.01 ? lut_col.rgb : mix(kHot, vec3(1.0), swing * 0.4);
        vec3 glow_c   = glow_col.a > 0.01 ? glow_col.rgb : line_col;

        // Soft fill beneath the trace
        if (fill > 0.001) {
            col = mix(col, line_col * 0.4, band * fill * 0.5);
        }

        // Optional glow: wide low-alpha pass plus thin bright pass
        if (glow > 0.5) {
            float glow_alpha = stroke(d, lw * 3.5) * 0.4;
            col = mix(col, glow_c, glow_alpha);
        }

        // Real pixel thickness sharp line
        float line_alpha = stroke(d, lw);
        col = mix(col, line_col, line_alpha);
    }
    else if (m == 1) {
        // ════ SPECTRUM ANALYZER ════
        // Smooth, fluid curve across log-mapped 20 Hz - 20 kHz points.
        // Y mapped from -90..0 dB range into 0..1.
        float px = 1.0 / max(u_resolution.x, 256.0);
        float mag = clamp(fftAt(uv.x) * g, 0.0, 1.0);

        // Determine gradient mapping value:
        // mapping <= 0.5: frequency (left to right, uv.x)
        // mapping > 0.5:  level (bottom to top of curve, uv.y / max(mag, 1e-3))
        float level_norm = clamp(uv.y / max(mag, 1e-3), 0.0, 1.0);
        float map_val = (mapping > 0.5) ? level_norm : clamp(uv.x, 0.0, 1.0);

        // Visualizer 1 (Spectrum Analyzer): row 2 line/fill, row 3 glow
        vec4 lut_col = texture(u_lut_tex, vec2(map_val, 0.3125));
        vec4 glow_col = texture(u_lut_tex, vec2(map_val, 0.4375));
        vec3 line_col = lut_col.a > 0.01 ? lut_col.rgb : heat(0.15 + map_val * 0.85);
        vec3 glow_c   = glow_col.a > 0.01 ? glow_col.rgb : line_col;

        // Filled curve below magnitude
        if (uv.y < mag && fill > 0.001) {
            float fill_alpha = fill * (0.35 + 0.65 * level_norm);
            col = mix(col, line_col, fill_alpha);
        }

        // Outline curve across full width
        float d = 1e9;
        for (int i = -1; i <= 1; i++) {
            float x0 = uv.x + float(i) * px;
            float x1 = x0 + px;
            float m0 = clamp(fftAt(x0) * g, 0.0, 1.0);
            float m1 = clamp(fftAt(x1) * g, 0.0, 1.0);
            d = min(d, segDist(uv, vec2(x0, m0), vec2(x1, m1)));
        }

        // Optional glow pass
        if (glow > 0.5) {
            float glow_alpha = stroke(d, lw * 3.5) * 0.4;
            col = mix(col, glow_c, glow_alpha);
        }

        // Sharp outline stroke
        float line_alpha = stroke(d, lw);
        col = mix(col, line_col, line_alpha);
    }
    else if (m == 2) {
        // ════ SPECTROGRAM ════
        // Scrolling 2D heatmap: new columns appear at the right edge and scroll left.
        // X = time (newest at right), Y = log frequency (low at bottom).
        // Uses the raw dB array from the Spectrum Analyzer (un-smoothed).
        float spd = max(speed, 5.0);
        float age = (1.0 - uv.x) * (spd / 60.0);
        float row = fract((spectro_row - age * 255.0) / 256.0);
        float mag = clamp(texture(u_spectro_tex, vec2(uv.y, row)).r * g, 0.0, 1.0);

        // Visualizer 2 (Spectrogram): row 4 in u_lut_tex (y = 4.5 / 8.0 = 0.5625)
        // Default gradient: -90 dB black/purple through magenta and orange to 0 dB white.
        vec4 lut_col = texture(u_lut_tex, vec2(mag, 0.5625));
        col = lut_col.a > 0.01 ? lut_col.rgb : heat(pow(mag, 0.75));

        // Fade out columns older than the 256-column history buffer
        if (age > 1.0) {
            col = mix(col, kInk, clamp((age - 1.0) * 10.0, 0.0, 1.0));
        }
    }
    else if (m == 3) {
        // ════ 4. LISSAJOUS VECTORSCOPE ════
        // True stereo mid/side (X = side, Y = mid) string-art cloud with fading feedback trails.
        // Pure mono (L == R) produces a laser-straight VERTICAL line (X == 0).
        // Wide stereo opens into a luminous webbed string-art cloud.
        float aspect = u_resolution.x / max(u_resolution.y, 1.0);
        vec2 c = (uv - 0.5) * vec2(aspect, 1.0);

        // 1. Trails via feedback texture:
        // Multiplying by decay factor plus floor subtraction (-0.005) ensures
        // true black silence with zero 8-bit quantization ghosting.
        vec3 trail = texture(u_feedback_tex, v_uv).rgb;
        float decay = clamp(fill, 0.70, 0.98);
        trail *= smoothstep(0.44, 0.41, length(c)); // Confine feedback to inside frame
        trail = max(trail * decay - 0.005, vec3(0.0));

        // 2. String-art connected segments with additive blending:
        vec3 accum_col = vec3(0.0);
        float reach = 0.42;

        // Check for silence: if peak amplitude is near zero, skip geometry and let trails fade out
        vec2 test0 = vecAt(0.1), test1 = vecAt(0.5), test2 = vecAt(0.9);
        bool silent = max(length(test0), max(length(test1), length(test2))) < 1e-4;

        if (!silent && length(c) < reach + 0.02) {
            float lw = max((1.0 + thickness * 2.0) / 1080.0, 1.0 / max(u_resolution.y, 1.0));
            const int N = 80;
            vec2 p0 = clamp(vecAt(0.0) * 0.38 * g, vec2(-0.39), vec2(0.39));
            for (int i = 0; i < N; ++i) {
                float t1 = float(i + 1) / float(N);
                vec2 p1 = clamp(vecAt(t1) * 0.38 * g, vec2(-0.39), vec2(0.39));

                vec2 pa = c - p0, ba = p1 - p0;
                float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-7), 0.0, 1.0);
                float d = length(pa - ba * h);

                float core = 1.0 - smoothstep(lw * 0.4, lw * 1.3, d);

                // Color mapping: 0 = distance from center, 1 = sample age, 2 = angle
                float lut_coord = 0.0;
                if (mapping < 0.5) {
                    lut_coord = clamp(length(p1) / 0.38, 0.0, 1.0);
                } else if (mapping < 1.5) {
                    lut_coord = float(i) / float(N);
                } else {
                    lut_coord = fract(atan(p1.y, p1.x) / 6.2831853 + 0.5);
                }

                // Sample Visualizer 3 color styles from u_lut_tex:
                // Row 6 (y = 6.5 / 8.0 = 0.8125): Line LUT
                // Row 7 (y = 7.5 / 8.0 = 0.9375): Glow LUT
                vec4 lut_col = texture(u_lut_tex, vec2(lut_coord, 0.8125));
                vec4 glow_col = texture(u_lut_tex, vec2(lut_coord, 0.9375));
                vec3 line_rgb = lut_col.a > 0.01 ? lut_col.rgb : heat(0.35 + lut_coord * 0.65);
                vec3 glow_rgb = glow_col.a > 0.01 ? glow_col.rgb : line_rgb;

                accum_col += line_rgb * core * 0.42;
                if (glow > 0.5) {
                    float halo = exp(-d * d / (lw * lw * 12.0)) * 0.12;
                    accum_col += glow_rgb * halo;
                }
                p0 = p1;
            }
        }

        // Composite trails and new geometry
        col = trail + accum_col;

        // 3. Circular Frame, Concentric Guide & Axes (Minimeters instrument look)
        float r = length(c);
        float inside_circle = step(r, 0.40);
        // Outer circular bezel
        col = mix(col, kGrid * 1.5, stroke(abs(r - 0.40), 1.4) * grid_amt);
        // Concentric inner guide circle at half radius
        col = mix(col, kGrid * 0.6, stroke(abs(r - 0.20), 0.9) * grid_amt * inside_circle * 0.5);

        // Mid/Side (cross) and Left/Right (diagonals) axes
        float d_cross = min(abs(c.x), abs(c.y));
        float d_diag = min(abs(c.x - c.y) * 0.7071, abs(c.x + c.y) * 0.7071);
        col = mix(col, kGrid * 0.8, stroke(d_cross, 1.0) * grid_amt * inside_circle * 0.5);
        col = mix(col, kGrid * 0.5, stroke(d_diag, 0.9) * grid_amt * inside_circle * 0.35);

        // 4. Phase Correlation Bar at bottom (-1 = out of phase, 0 = stereo, +1 = mono)
        if (uv.y < 0.05 && abs(uv.x - 0.5) < 0.28) {
            float sxy = 0.0, sxx = 0.0, syy = 0.0;
            for (int k = 0; k < 64; ++k) {
                float tk = float(k) / 63.0;
                vec2 ms = vecAt(tk);
                float l = (ms.y + ms.x) * 0.7071;
                float r_sig = (ms.y - ms.x) * 0.7071;
                sxy += l * r_sig; sxx += l * l; syy += r_sig * r_sig;
            }
            float denom = max(sqrt(sxx * syy), 1e-6);
            float corr = clamp(sxy / denom, -1.0, 1.0);

            float bar_x = (uv.x - 0.5) / 0.25;
            float lo = min(0.0, corr);
            float hi = max(0.0, corr);
            float in_corr = step(lo, bar_x) * step(bar_x, hi) * step(0.015, uv.y) * step(uv.y, 0.04);

            vec3 corr_col = corr < 0.0 ? vec3(0.95, 0.2, 0.2) : vec3(0.2, 0.85, 0.4);
            col = mix(col, corr_col, in_corr * 0.85);
            col = mix(col, kGrid * 1.5, stroke(abs(uv.x - 0.5), 1.0) * step(0.01, uv.y) * step(uv.y, 0.045));
            col = mix(col, kGrid, stroke(abs(abs(uv.x - 0.5) - 0.25), 1.0) * step(0.01, uv.y) * step(uv.y, 0.045));
        }
    }
    else {
        // ════ BANDS ════
        // Flat columns in one accent, level marked by a brighter cap. The old
        // per-band rainbow made seven meters look like seven unrelated things.
        float n = 7.0;
        float idx = floor(uv.x * n);

        float v =
            idx < 0.5 ? bass : idx < 1.5 ? mid : idx < 2.5 ? high :
            idx < 3.5 ? amplitude : idx < 4.5 ? transient :
            idx < 5.5 ? kick : snare;

        // The 10 reactive channels come from the offline .analysis blob, which
        // "load a wav and press play" does not have - every meter would read
        // zero. Fall back to the live FFT, and let real channels win.
        float f =
            idx < 0.5 ? specBand(0.00, 0.27) :   // low
            idx < 1.5 ? specBand(0.27, 0.64) :   // mid
            idx < 2.5 ? specBand(0.64, 0.95) :   // high
            idx < 3.5 ? specBand(0.00, 1.00) :   // level
            idx < 4.5 ? specBand(0.55, 0.80) :   // attack
            idx < 5.5 ? specBand(0.00, 0.12) :   // low hit
                        specBand(0.30, 0.60);    // mid hit
        v = clamp(max(v, f) * g, 0.0, 1.0);

        float bx = fract(uv.x * n);
        float in_bar = step(0.14, bx) * step(bx, 0.86);
        float pad = 0.06;
        float level = pad + v * (1.0 - 2.0 * pad);

        // Column track, so an empty meter still shows where it is.
        float span = in_bar * step(pad, uv.y) * step(uv.y, 1.0 - pad);
        col = mix(col, kGrid * 0.6, span * 0.5);
        // Same ramp as everything else: the top of a full meter runs hot.
        float t = (uv.y - pad) / max(level - pad, 1e-3);
        col = mix(col, heat(0.20 + t * 0.80),
                  in_bar * step(pad, uv.y) * step(uv.y, level));
        col = mix(col, kLine,
                  in_bar * stroke(abs(uv.y - level), 2.0) * step(0.01, v));
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
