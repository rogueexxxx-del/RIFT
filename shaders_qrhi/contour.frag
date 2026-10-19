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
#define levels _p[0].x
#define thickness _p[0].y
#define contrast _p[0].z
#define mixAmount _p[0].w
void main() {
    vec3 src = texture(u_tex, v_uv).rgb;
    float lum = dot(src, vec3(0.299, 0.587, 0.114));
    float shaped = clamp((lum - 0.5) * contrast + 0.5, 0.0, 1.0);
    float phase = abs(fract(shaped * levels) - 0.5);
    float aa = max(fwidth(shaped * levels), 1e-4);
    float line = 1.0 - smoothstep(thickness, thickness + aa, phase);
    vec3 ink = mix(src * 0.15, vec3(1.0), shaped);
    fragColor = vec4(mix(src, mix(src, ink, line), clamp(mixAmount, 0.0, 1.0)), 1.0);
}
