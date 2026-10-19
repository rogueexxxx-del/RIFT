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
#define centerX _p[0].x
#define centerY _p[0].y
#define strength _p[0].z
#define frequency _p[0].w
#define width _p[1].x
#define mixAmount _p[1].y
void main() {
    float ar = resolution.x / max(resolution.y, 1.0);
    vec2 p = (v_uv - vec2(centerX, centerY)) * vec2(ar, 1.0);
    float radius = length(p);
    float phase = fract(time * clamp(bpm, 60.0, 180.0) / 60.0);
    float audioBeat = smoothstep(0.08, 0.55, max(kick, transient));
    float pulse = max(0.25 + 0.2 * sin(phase * 6.2831853), audioBeat);
    float ringRadius = phase * 0.9;
    float ring = exp(-pow((radius - ringRadius) / max(width, 0.005), 2.0));
    vec2 dir = normalize(p + vec2(1e-5));
    vec2 offset = dir * sin((radius - ringRadius) * frequency) * strength * ring * pulse;
    vec3 warped = texture(u_tex, clamp(v_uv + offset, 0.0, 1.0)).rgb;
    vec3 src = texture(u_tex, v_uv).rgb;
    fragColor = vec4(mix(src, warped, clamp(mixAmount, 0.0, 1.0)), 1.0);
}
