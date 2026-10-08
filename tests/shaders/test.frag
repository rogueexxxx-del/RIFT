#version 440
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;
// std140 uniform block (QRhi requires a UBO, not loose uniforms)
layout(std140, binding = 0) uniform Buf {
    float time;
    float bass;
    vec2  res;
};
void main() {
    vec3 c = vec3(v_uv, 0.5 + 0.5 * sin(time));
    c *= 0.6 + bass;                 // audio-reactive brightness
    fragColor = vec4(c, 1.0);
}
