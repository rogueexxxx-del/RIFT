# Shader Manifest Contract  (v1)

Replaces the prototype's hard-coded `ShaderParams`/`Mod` definitions in
`core/window.py` `_init_effects()`. Each effect is described by a JSON
manifest + its GLSL source. The engine reads manifests to build the effect
registry, uniform layouts, ranges, and default bindings - no code change to
add an effect.

## Directory
```
shaders/
  ascii/
    ascii.frag          GLSL 410 (reused from ../RIFT/shaders)
    ascii.json          manifest (this contract)
  halftone/ ...
  _common/
    fullscreen.vert     shared vertex
```

## Manifest schema
```json
{
  "id": "halftone",
  "name": "Halftone",
  "version": 1,
  "frag": "halftone.frag",
  "category": "generator",          // generator | fx | output
  "uniforms": [
    {
      "name": "ht_scale",
      "label": "Dot Size",
      "type": "float",
      "min": 3.0, "max": 40.0, "step": 0.5, "default": 9.0,
      "discrete": false,             // step>=1 snaps (prototype behavior)
      "binding": {                   // default patch-bay binding (optional)
        "channel": "drums",          // internal channel key
        "depth": 6.0,
        "curve": "lin",              // lin | exp | log
        "attack": 0.0, "release": 0.0,
        "in_lo": 0.0, "in_hi": 1.0,
        "invert": false
      }
    }
  ],
  "samplers": [                      // texture inputs the pass expects
    {"name": "u_tex",           "unit": 0, "source": "upstream"},
    {"name": "u_audio_texture", "unit": 2, "source": "audio_fft_wave"},
    {"name": "u_spectro_tex",   "unit": 6, "source": "spectrogram_ring"}
  ]
}
```

## Standard engine-provided uniforms (auto-bound, not in manifest)
`time`, `u_resolution`, and the 10 channel scalars
(`bass mid melody highs drums transient bpm centroid kick snare` - note the
prototype sends both `melody` and legacy `mid`; engine sends canonical names).

## Sampler `source` values
| source | bound texture |
|---|---|
| upstream | previous graph node output (or media for the generator) |
| audio_fft_wave | 512x2 R32F: row0 FFT, row1 waveform |
| spectrogram_ring | 512x256 R32F scrolling FFT history |
| media | current decoded media frame |
| ascii_atlas | user-typed glyph atlas (ascii effect) |

## Compilation
GLSL → `qsb` at build time → SPIR-V + backend variants, hashed and cached
on disk (`ShaderCache`). Manifest `version` + frag file hash form the cache
key; stale entries recompile.

## Migration note
A generator script converts the prototype `_init_effects()` Mod tables into
these JSON manifests (one-time, Phase 1) so ranges/defaults/bindings match
exactly.
