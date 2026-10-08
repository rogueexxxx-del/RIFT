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
#define speed   _p[0].x
#define twist   _p[0].y
#define fov     _p[0].z
#define fog     _p[0].w
#define detail  _p[1].x
#define palette _p[1].y

// RIFT - tunnel.frag
//
// Raymarched corridor. The only generator here that builds depth rather than
// bending the source: the media is projected onto the tunnel wall as it flies
// past, so footage becomes the texture of a moving space.
//
// EXPENSIVE. 48 steps of an SDF for every pixel, plus a texture fetch on hit.
// Budget it like the oscilloscope - one of these in a chain, not three. If it
// needs profiling use PIX or RenderDoc; guessing at raymarch cost is how you
// end up optimising the wrong loop.

const float kTau = 6.28318530718;

// Distance to the inside of a pipe down +z, with a slow ripple so the wall is
// not a perfect cylinder (a perfect one has no parallax and reads as a flat
// spinning ring).
float mapDist(vec3 p) {
    float wob = sin(p.z * 0.6 + time * 0.7) * 0.12
              + sin(p.z * 1.7 - time * 0.4) * 0.06 * detail;
    return (1.0 + wob) - length(p.xy);
}

vec3 ramp(float x) {
    x = clamp(x, 0.0, 1.0);
    int pal = int(floor(palette + 0.5));
    if (pal == 1) return mix(vec3(0.02, 0.06, 0.20), vec3(0.60, 0.95, 1.00), x);
    if (pal == 2) return mix(vec3(0.02, 0.14, 0.06), vec3(0.80, 1.00, 0.40), x);
    if (pal == 3) return mix(vec3(0.14, 0.03, 0.02), vec3(1.00, 0.80, 0.35), x);
    return mix(vec3(0.08, 0.02, 0.20), vec3(1.00, 0.35, 0.55), x);   // 0 magma
}

void main() {
    float ar = u_resolution.x / max(u_resolution.y, 1.0);
    vec2 sc = (v_uv - 0.5) * vec2(ar, 1.0) * 2.0;

    vec3 ro = vec3(0.0, 0.0, time * speed);
    vec3 rd = normalize(vec3(sc * max(fov, 0.1), 1.0));

    // Twist the ray about z by depth, which spirals the whole corridor.
    float t = 0.0;
    float hit = -1.0;
    for (int i = 0; i < 48; i++) {
        vec3 p = ro + rd * t;
        float a = twist * p.z * 0.25;
        float cs = cos(a), sn = sin(a);
        p.xy = mat2(cs, -sn, sn, cs) * p.xy;
        float d = mapDist(p);
        if (d < 0.002) { hit = t; break; }
        // 0.8 not 1.0: the twist makes this a non-conservative distance field,
        // and a full step overshoots straight through the wall as banding.
        t += d * 0.8;
        if (t > 40.0) break;
    }

    vec3 col;
    if (hit < 0.0) {
        col = ramp(0.0);
    } else {
        vec3 p = ro + rd * hit;
        float a = twist * p.z * 0.25;
        float cs = cos(a), sn = sin(a);
        vec2 q = mat2(cs, -sn, sn, cs) * p.xy;

        // Wall coordinates: angle around, distance along. This is the unwrap
        // that lets the source be the tunnel's surface.
        float ang = atan(q.y, q.x) / kTau + 0.5;
        float depth = p.z * 0.15;
        vec2 uv = fract(vec2(ang, depth));

        col = texture(u_tex, uv).rgb;
        col *= ramp(1.0 - clamp(hit / 12.0, 0.0, 1.0)) * 1.6;
    }

    // Fog to black with distance, which is what gives the corridor its end.
    float f = 1.0 - exp(-max(hit, 0.0) * fog * 0.12);
    col = mix(col, vec3(0.0), clamp(hit < 0.0 ? 1.0 : f, 0.0, 1.0));

    fragColor = vec4(col, 1.0);
}
