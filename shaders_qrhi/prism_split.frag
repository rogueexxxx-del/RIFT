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
layout(std140, binding = 1) uniform Params { vec4 _p[1]; };
#define direction _p[0].x
#define spreadPx _p[0].y
#define mixAmount _p[0].z
void main() {
    float a = radians(direction);
    vec2 offset = vec2(cos(a), sin(a)) * spreadPx / max(resolution, vec2(1.0));
    float r = texture(u_tex, clamp(v_uv + offset, 0.0, 1.0)).r;
    float g = texture(u_tex, v_uv).g;
    float b = texture(u_tex, clamp(v_uv - offset, 0.0, 1.0)).b;
    vec3 split = vec3(r, g, b);
    vec3 source = texture(u_tex, v_uv).rgb;
    fragColor = vec4(mix(source, split, clamp(mixAmount, 0.0, 1.0)), 1.0);
}
