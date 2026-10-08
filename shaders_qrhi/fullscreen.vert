#version 440
layout(location = 0) out vec2 v_uv;
void main() {
    vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
    // v flipped against clip-space y so ONE pass is orientation-neutral.
    // With v_uv = p every pass flipped the image, which made the final
    // orientation depend on how many passes ran - a 2-effect chain looked
    // right and a 3-effect chain came out upside down.
    v_uv = vec2(p.x, 1.0 - p.y);
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
