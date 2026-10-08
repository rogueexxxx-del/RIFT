"""Helper: pull a shader's default uniform Mod table from the prototype
_init_effects, without importing Qt/window.py."""
import os, sys
_PROTO = os.path.join(os.path.dirname(__file__), "..", "..", "RIFT")
sys.path.insert(0, os.path.abspath(_PROTO))
from core.params import ShaderParams, Mod  # noqa: E402


def _effects():
    src = open(os.path.join(_PROTO, "core", "window.py"), encoding="utf-8").read()
    i = src.index("self.effects = ") + len("self.effects = ")
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
    return eval(src[i:j], {"ShaderParams": ShaderParams, "Mod": Mod})


def effect_defaults(shader_key):
    for e in _effects():
        if e.shader_key == shader_key:
            return e.params
    raise KeyError(shader_key)
