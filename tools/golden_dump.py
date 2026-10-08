"""
Golden reference generator for the Phase 1 parity gate.

Produces, from the Python prototype, the two references the C++ render core
must reproduce:
  1) channels.csv  - per-frame SMOOTHED 10-channel values (AudioEngine.update)
  2) frame_NNNN.raw - RGBA8 pixels of the rendered scene for sampled frames

The C++ engine, fed the SAME .analysis blob + same shader, must match:
  - channels within atol 1e-4 (identical smoothing math)
  - frames within a small per-pixel tolerance (GL vs RHI rounding)

Usage:
  python golden_dump.py --image IMG --audio WAV --shader ascii \
      --frames 0,60,120,300 --out GOLDDIR
"""
import sys, os, csv, argparse
import numpy as np

_PROTO = os.path.join(os.path.dirname(__file__), "..", "..", "RIFT")
sys.path.insert(0, os.path.abspath(_PROTO))


def build_channel_reference(audio_path, n_frames, out_csv):
    from audio_engine import AudioEngine
    e = AudioEngine(fps=60)
    e.load(audio_path)
    # emulate runtime: index by frame, apply update() smoothing, record params
    rows = []
    for f in range(n_frames):
        e.update(f % max(1, e.total_frames), force_timeline=True)
        rows.append([f] + [float(x) for x in e.params])
    hdr = ["frame", "bass", "melody", "highs", "drums", "transient",
           "bpm", "centroid", "time", "kick", "snare"]
    with open(out_csv, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(hdr)
        w.writerows(rows)
    return e


def render_reference_frames(image_path, audio_engine, shader_key,
                            frame_ids, outdir, w=640, h=360):
    import moderngl
    from core.renderer import Renderer
    from core.params import ShaderParams, Mod
    from PIL import Image

    ctx = moderngl.create_standalone_context(require=410)
    r = Renderer(ctx)

    img = Image.open(image_path).convert("RGBA").resize((w, h))
    img = img.transpose(Image.FLIP_TOP_BOTTOM)
    data = np.array(img, dtype=np.uint8)
    tex = ctx.texture((w, h), 4, data.tobytes())
    tex.filter = (moderngl.LINEAR, moderngl.LINEAR)
    r.set_texture(tex)
    r.set_shader(shader_key)

    # default uniforms for this shader from the prototype table
    import importlib.util
    # minimal: pull defaults via a fresh effects list
    from tools_effects import effect_defaults  # tiny helper below
    uni_defaults = effect_defaults(shader_key)

    pal = {"u_palette_active": 0.0, "u_color_bg": (0, 0, 0),
           "u_color_fg1": (1, 0, 0), "u_color_fg2": (0, 1, 1)}
    fbo, _ = r.create_export_fbo(w, h)

    ae = audio_engine
    saved = []
    maxf = max(frame_ids) + 1
    fset = set(frame_ids)
    for f in range(maxf):
        ae.update(f % max(1, ae.total_frames), force_timeline=True)
        audio = ae.params
        # resolve audio-reactive uniforms same as window.py
        audio_dict = {k: float(audio[i]) for i, k in enumerate(
            ["bass", "melody", "highs", "drums", "transient",
             "bpm", "centroid", "time", "kick", "snare"])}
        audio_dict["none"] = 0.0
        uni = {k: mod.resolve(audio_dict) for k, mod in uni_defaults.items()}
        r.update_audio_texture(*ae.get_fft_and_waveform(f))
        r.begin_pipeline(w, h)
        r.render_cell(f / 60.0, audio_params=audio, custom_uniforms=uni,
                      post_shader_name=None, post_custom_uniforms=None,
                      palette_colors=pal, viewport=(0, 0, w, h))
        out = r.apply_chain([], f / 60.0, audio_params=audio, palette_colors=pal)
        # read scene texture (skip post_fx/feedback for deterministic parity)
        if f in fset:
            raw = out.read()
            p = os.path.join(outdir, f"frame_{f:04d}.raw")
            with open(p, "wb") as fh:
                fh.write(raw)
            saved.append((f, len(raw)))
    return saved, (w, h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--audio", required=True)
    ap.add_argument("--shader", default="ascii")
    ap.add_argument("--frames", default="0,60,120,300")
    ap.add_argument("--nframes", type=int, default=360)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    frame_ids = [int(x) for x in a.frames.split(",")]

    ae = build_channel_reference(a.audio, a.nframes,
                                 os.path.join(a.out, "channels.csv"))
    saved, dims = render_reference_frames(a.image, ae, a.shader,
                                          frame_ids, a.out)
    meta = {"shader": a.shader, "w": dims[0], "h": dims[1],
            "frames": [f for f, _ in saved]}
    import json
    with open(os.path.join(a.out, "golden.json"), "w") as fh:
        json.dump(meta, fh, indent=2)
    print(f"[golden] channels.csv + {len(saved)} frames ({dims[0]}x{dims[1]}) "
          f"-> {a.out}")


if __name__ == "__main__":
    main()
