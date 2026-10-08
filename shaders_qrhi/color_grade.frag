// Master colour grade - the last pass before display/export.
//
// Order matters and follows what colourists expect: lift/gamma/gain first
// (shadows / midtones / highlights), then contrast about mid grey, then
// temperature+tint, then saturation last so it acts on the corrected image.
//
// Defaults are neutral (lift 0, gamma 1, gain 1, contrast 1, temp/tint 0,
// saturation 1), so an untouched grade is a pass-through.
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

layout(binding = 2) uniform sampler2D u_tex;

layout(std140, binding = 1) uniform Params { vec4 _p[3]; };
#define lift        _p[0].x   // shadows offset, -0.5..0.5
#define gamma_v     _p[0].y   // midtone curve, 0.1..3
#define gain_v      _p[0].z   // highlight scale, 0..3
#define contrast_v  _p[0].w   // 0..3, pivot 0.5
#define saturation  _p[1].x   // 0 grey .. 2 oversaturated
#define temperature _p[1].y   // -1 cool .. +1 warm
#define tint        _p[1].z   // -1 green .. +1 magenta
#define exposure    _p[1].w   // stops, -2..2

void main() {
    vec3 c = texture(u_tex, v_uv).rgb;
    float a = texture(u_tex, v_uv).a;

    c *= exp2(exposure);

    // Lift / gamma / gain. Lift raises shadows without crushing highlights;
    // gain scales the top end; gamma bends the middle.
    c = c + lift * (1.0 - c);
    c = max(c, 0.0);
    c = pow(c, vec3(1.0 / max(gamma_v, 0.001)));
    c *= gain_v;

    c = (c - 0.5) * contrast_v + 0.5;

    // Temperature warms by trading blue for red; tint trades green for
    // magenta. Small coefficients so the full range stays usable.
    c.r += temperature * 0.10;
    c.b -= temperature * 0.10;
    c.g -= tint * 0.10;
    c.r += tint * 0.05;
    c.b += tint * 0.05;

    // Rec. 709 luma, so desaturating preserves perceived brightness.
    float y = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c = mix(vec3(y), c, saturation);

    fragColor = vec4(clamp(c, 0.0, 1.0), a);
}
