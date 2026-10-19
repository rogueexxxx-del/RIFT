#version 440
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform Engine {
    vec4 uTimeRes;
    vec4 uA;
    vec4 uB;
    vec4 uC;
    vec4 uBg;
    vec4 uFg1;
    vec4 uFg2;
};
#define time uTimeRes.x
#define resolution uTimeRes.zw
#define bass uA.x
#define melody uA.y
#define highs uA.z
#define drums uA.w
#define transient uB.x
#define bpm uB.y
#define centroid uB.z
#define kick uC.x
layout(binding = 2) uniform sampler2D u_tex;
layout(std140, binding = 1) uniform Params { vec4 _p[2]; };
#define threshold _p[0].x
#define radiusPx _p[0].y
#define halation _p[0].z
#define grain _p[0].w
#define quality _p[1].x

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main() {
    vec2 px = 1.0 / max(resolution, vec2(1.0));
    vec2 r = px * clamp(radiusPx, 0.5, 8.0);
    vec3 src = texture(u_tex, v_uv).rgb;
    vec3 glow = max(src - threshold, 0.0) * 0.4;
    glow += max(texture(u_tex, clamp(v_uv + vec2(r.x, 0.0), 0.0, 1.0)).rgb - threshold, 0.0) * 0.15;
    glow += max(texture(u_tex, clamp(v_uv - vec2(r.x, 0.0), 0.0, 1.0)).rgb - threshold, 0.0) * 0.15;
    glow += max(texture(u_tex, clamp(v_uv + vec2(0.0, r.y), 0.0, 1.0)).rgb - threshold, 0.0) * 0.15;
    glow += max(texture(u_tex, clamp(v_uv - vec2(0.0, r.y), 0.0, 1.0)).rgb - threshold, 0.0) * 0.15;
    if (quality > 0.5) {
        glow += max(texture(u_tex, clamp(v_uv + r, 0.0, 1.0)).rgb - threshold, 0.0) * 0.06;
        glow += max(texture(u_tex, clamp(v_uv - r, 0.0, 1.0)).rgb - threshold, 0.0) * 0.06;
        glow += max(texture(u_tex, clamp(v_uv + vec2(r.x, -r.y), 0.0, 1.0)).rgb - threshold, 0.0) * 0.06;
        glow += max(texture(u_tex, clamp(v_uv + vec2(-r.x, r.y), 0.0, 1.0)).rgb - threshold, 0.0) * 0.06;
    }
    float frame = floor(time * 24.0);
    vec2 pixel = floor(v_uv * resolution);
    float n = hash(pixel + vec2(frame * 17.0, frame * 31.0)) - 0.5;
    float grainAmount = grain * (0.55 + 0.45 * (1.0 - dot(src, vec3(0.299, 0.587, 0.114))));
    vec3 color = src + glow * halation + n * grainAmount;
    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
