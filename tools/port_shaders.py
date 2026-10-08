"""
Port prototype GLSL 410 shaders (loose uniforms) -> QRhi GLSL 440
(uniform blocks). Mechanical + repeatable so re-running stays in sync with
../RIFT/shaders.

Output per shader (in shaders_qrhi/):
  <id>.frag         QRhi-compatible fragment
  <id>.vert         shared fullscreen vertex (copied)
  <id>.layout.json  ordered custom-param names -> the engine packs the
                    Params UBO in this exact order (std140 vec4-packed)

Uniform scheme:
  binding 0  Engine UBO  (fixed layout: time, resolution, 10 channels, palette)
  binding 1  Params UBO  (per-shader custom params, vec4-packed float array)
  binding 2  u_tex            (upstream / media)
  binding 3  u_audio_texture  (fft/wave)
  binding 4  u_spectro_tex    (spectrogram ring)
  binding 5  u_ascii_atlas    (ascii typed glyphs)
  binding 6  u_feedback_tex   (post_fx feedback)
"""
import os, re, sys, json

PROTO = os.path.join(os.path.dirname(__file__), "..", "..", "RIFT", "shaders")
OUT   = os.path.join(os.path.dirname(__file__), "..", "shaders_qrhi")

# uniforms handled by the fixed Engine UBO (name -> GLSL expression)
ENGINE = {
    "time": "uTimeRes.x",
    "u_resolution": "uTimeRes.zw",
    "bass": "uA.x", "melody": "uA.y", "mid": "uA.y",
    "highs": "uA.z", "high": "uA.z",
    "drums": "uA.w", "amplitude": "uA.w",
    "transient": "uB.x", "bpm": "uB.y", "centroid": "uB.z",
    "kick": "uC.x", "snare": "uC.y",
    "u_palette_active": "uBg.a",
    "u_color_bg": "uBg.rgb", "u_color_fg1": "uFg1.rgb", "u_color_fg2": "uFg2.rgb",
}
SAMPLER_BINDING = {
    "u_tex": 2, "u_audio_texture": 3, "u_spectro_tex": 4,
    "u_ascii_atlas": 5, "u_feedback_tex": 6,
}

ENGINE_PREAMBLE = """#version 440
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
"""

VERT = """#version 440
layout(location = 0) out vec2 v_uv;
void main() {
    vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
    v_uv = p;
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
"""

_uniform_re = re.compile(r'^\s*uniform\s+(\w+)\s+(\w+)\s*;', re.M)


def port(path):
    src = open(path, encoding="utf-8").read()
    sid = os.path.splitext(os.path.basename(path))[0]

    samplers = []          # (name, binding)
    params = []            # custom scalar/vec param names (order preserved)
    param_types = {}
    for m in _uniform_re.finditer(src):
        gtype, name = m.group(1), m.group(2)
        if name in ENGINE:
            continue
        if gtype.startswith("sampler"):
            if name in SAMPLER_BINDING:
                samplers.append((name, SAMPLER_BINDING[name]))
            continue
        # custom param (float/int/vec) -> Params UBO
        params.append(name)
        param_types[name] = gtype

    # strip prototype header: #version, in/out, all uniform lines
    body = _uniform_re.sub("", src)
    body = re.sub(r'^\s*#version.*$', "", body, flags=re.M)
    body = re.sub(r'^\s*in\s+vec2\s+v_uv\s*;', "", body, flags=re.M)
    body = re.sub(r'^\s*out\s+vec4\s+fragColor\s*;', "", body, flags=re.M)

    # build params block (vec4-packed). float params map to a slot; the engine
    # packs values in this order. Non-float params (int/vec) are rare in the
    # custom set - treat ints as floats (GLSL will accept via the define).
    lines = [ENGINE_PREAMBLE]
    for name, binding in samplers:
        lines.append(f"layout(binding = {binding}) uniform sampler2D {name};")
    if params:
        nvec = (len(params) + 3) // 4
        lines.append(f"\nlayout(std140, binding = 1) uniform Params {{ vec4 _p[{nvec}]; }};")
        for i, name in enumerate(params):
            comp = "xyzw"[i % 4]
            lines.append(f"#define {name} _p[{i // 4}].{comp}")
    lines.append("\n")
    lines.append(body)

    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, f"{sid}.frag"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    with open(os.path.join(OUT, f"{sid}.layout.json"), "w", encoding="utf-8") as f:
        json.dump({"id": sid, "params": params, "samplers": samplers}, f, indent=2)
    return sid, len(params), [s for s, _ in samplers]


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "fullscreen.vert"), "w", encoding="utf-8") as f:
        f.write(VERT)
    frags = sorted(f for f in os.listdir(PROTO) if f.endswith(".frag"))
    for fn in frags:
        sid, nparams, samp = port(os.path.join(PROTO, fn))
        print(f"  {sid:14s} params={nparams:2d} samplers={samp}")
    print(f"[port_shaders] {len(frags)} shaders -> {OUT}")


if __name__ == "__main__":
    main()
