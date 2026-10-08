// Passthrough blit: sample the final scene texture to the swapchain backbuffer.
// Used only by RhiContext::present (on-screen preview), not a user effect.
#version 440
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;
layout(binding = 2) uniform sampler2D u_tex;
void main() {
    fragColor = texture(u_tex, v_uv);
}
