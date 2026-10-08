// Composite: lay one clip's rendered output (u_tex) over what is already on
// screen (u_under), with a blend mode, opacity, and a 2D transform.
//
// This is what makes stacked lanes useful - without it a higher lane simply
// replaced the one beneath. Transform runs on the TOP layer only, so a clip can
// be scaled and moved (picture-in-picture) while the layer below stays put.
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

layout(binding = 2) uniform sampler2D u_tex;      // this clip (top layer)
layout(binding = 3) uniform sampler2D u_under;    // accumulated layers below

layout(std140, binding = 1) uniform Params { vec4 _p[3]; };
// 0 normal, 1 add, 2 multiply, 3 screen, 4 difference, 5 overlay, 6 subtract
#define blend_mode _p[0].x
#define opacity    _p[0].y
#define pos_x      _p[0].z   // -1..1, fraction of the frame
#define pos_y      _p[0].w
#define scale      _p[1].x
// Rectangle of the FRAME this clip may paint, 0..1. Default 0,0,1,1.
#define crop_x     _p[1].y
#define crop_y     _p[1].z
#define crop_w     _p[1].w
#define crop_h     _p[2].x

void main() {
    vec4 under = texture(u_under, v_uv);

    // Outside its crop the clip does not exist, so the frame keeps whatever is
    // already there. Two clips cropped to opposite halves give split screen.
    if (v_uv.x < crop_x || v_uv.x > crop_x + crop_w ||
        v_uv.y < crop_y || v_uv.y > crop_y + crop_h) {
        fragColor = under;
        return;
    }

    // Inverse-transform the sample point: scaling the lookup DOWN scales the
    // image UP, and the offset is subtracted for the same reason.
    vec2 uv = v_uv - 0.5;
    uv /= max(scale, 0.001);
    uv -= vec2(pos_x, -pos_y);
    uv += 0.5;

    // Outside the transformed clip there is nothing to composite - show what is
    // underneath rather than clamping the edge pixel into a smear.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        fragColor = under;
        return;
    }

    vec4 top = texture(u_tex, uv);

    vec3 b;
    int mode = int(blend_mode + 0.5);
    if (mode == 1)      b = under.rgb + top.rgb;                       // add
    else if (mode == 2) b = under.rgb * top.rgb;                       // multiply
    else if (mode == 3) b = 1.0 - (1.0 - under.rgb) * (1.0 - top.rgb); // screen
    else if (mode == 4) b = abs(under.rgb - top.rgb);                  // difference
    else if (mode == 5)                                                // overlay
        b = mix(2.0 * under.rgb * top.rgb,
                1.0 - 2.0 * (1.0 - under.rgb) * (1.0 - top.rgb),
                step(0.5, under.rgb));
    else if (mode == 6) b = under.rgb - top.rgb;                       // subtract
    else                b = top.rgb;                                   // normal
    b = clamp(b, 0.0, 1.0);

    // Opacity also honours the layer's own alpha, so a source with
    // transparency composites correctly instead of punching a hole.
    float a = clamp(opacity, 0.0, 1.0) * top.a;
    fragColor = vec4(mix(under.rgb, b, a), max(under.a, a));
}
