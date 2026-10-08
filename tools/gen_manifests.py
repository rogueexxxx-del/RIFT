"""
Generate shader manifests (docs/contracts/shader_manifest.md) from the
prototype's hard-coded effect tables, so ranges/defaults/bindings match the
Python app EXACTLY. One-time Phase 1 bridge.

Reads ../RIFT effect defs by instantiating a headless _GLViewport-free copy
of _init_effects via the ShaderParams/Mod dataclasses, plus the post_fx set.

Usage: python gen_manifests.py OUTDIR
Emits OUTDIR/<id>/<id>.json + copies the .frag from ../RIFT/shaders.
"""
import sys, os, json, shutil, inspect

_PROTO = os.path.join(os.path.dirname(__file__), "..", "..", "RIFT")
sys.path.insert(0, os.path.abspath(_PROTO))
from core.params import ShaderParams, Mod  # noqa: E402

# canonical channel keys used by the engine
_CH = {"none", "drums", "bass", "melody", "highs", "transient",
       "kick", "snare", "bpm", "centroid", "time"}


def _effects_source():
    """Extract the effect list by executing _init_effects's body against a
    stub self. Avoids importing window.py (pulls in Qt/GL). We re-run the
    same ShaderParams/Mod construction by importing the source table."""
    import importlib.util
    win_path = os.path.join(_PROTO, "core", "window.py")
    src = open(win_path, encoding="utf-8").read()
    # pull the effects list literal region between 'self.effects = [' and the
    # matching close, then eval with ShaderParams/Mod in scope.
    start = src.index("self.effects = [")
    i = start + len("self.effects = ")
    depth, j = 0, i
    while j < len(src):
        if src[j] == "[":
            depth += 1
        elif src[j] == "]":
            depth -= 1
            if depth == 0:
                j += 1
                break
        j += 1
    literal = src[i:j]
    return eval(literal, {"ShaderParams": ShaderParams, "Mod": Mod})


def _post_fx_params():
    win_path = os.path.join(_PROTO, "core", "window.py")
    src = open(win_path, encoding="utf-8").read()
    start = src.index('ShaderParams("POST_FX"')
    i = src.index("{", start)
    depth, j = 0, i
    while j < len(src):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                j += 1
                break
        j += 1
    return eval(src[i:j], {"Mod": Mod})


def _binding(mod):
    if mod.source == "none" or mod.mod_amount == 0.0:
        return None
    return {
        "channel": mod.source, "depth": round(mod.mod_amount, 4),
        "curve": getattr(mod, "curve", "lin"),
        "attack": getattr(mod, "attack", 0.0),
        "release": getattr(mod, "release", 0.0),
        "in_lo": getattr(mod, "in_lo", 0.0),
        "in_hi": getattr(mod, "in_hi", 1.0),
        "invert": bool(getattr(mod, "invert", False)),
    }


def _uniforms(params: dict):
    out = []
    for name, mod in params.items():
        u = {
            "name": name, "label": mod.label, "type": "float",
            "min": mod.min_val, "max": mod.max_val, "step": mod.step,
            "default": mod.value, "discrete": mod.step >= 1.0,
        }
        b = _binding(mod)
        if b:
            u["binding"] = b
        out.append(u)
    return out


def main(outdir):
    os.makedirs(outdir, exist_ok=True)
    effects = _effects_source()
    manifests = []

    for idx, eff in enumerate(effects):
        cat = "generator"
        manifests.append((eff.shader_key, {
            "id": eff.shader_key, "name": eff.name, "version": 1,
            "frag": f"{eff.shader_key}.frag", "category": cat,
            "uniforms": _uniforms(eff.params),
            "samplers": [{"name": "u_tex", "unit": 0, "source": "upstream"}],
        }))

    # master post-fx as the 'output' node manifest
    manifests.append(("post_fx", {
        "id": "post_fx", "name": "Output", "version": 1,
        "frag": "post_fx.frag", "category": "output",
        "uniforms": _uniforms(_post_fx_params()),
        "samplers": [
            {"name": "u_tex", "unit": 0, "source": "upstream"},
            {"name": "u_feedback_tex", "unit": 1, "source": "feedback"},
        ],
    }))

    proto_sh = os.path.join(_PROTO, "shaders")
    for sid, man in manifests:
        d = os.path.join(outdir, sid)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, f"{sid}.json"), "w", encoding="utf-8") as f:
            json.dump(man, f, indent=2)
        frag = os.path.join(proto_sh, man["frag"])
        if os.path.exists(frag):
            shutil.copy(frag, os.path.join(d, man["frag"]))
    print(f"[gen_manifests] wrote {len(manifests)} manifests -> {outdir}")
    return manifests


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "shaders_manifest"
    main(out)
