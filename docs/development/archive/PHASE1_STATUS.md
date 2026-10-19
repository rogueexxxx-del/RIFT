# Phase 1 - Render Core + Parity Gate - Status

Goal: C++ render core reusing `../RIFT/shaders/*.frag`, validated by numeric
diff against Python golden frames/channels.

## Delivered (verified here, no C++ toolchain on this box)

| Item | State | Verified |
|---|---|---|
| Shader manifests (12) from prototype tables | done | ranges/defaults/bindings match `_init_effects` exactly (halftone ht_scale 3-40 def 9 → drums depth 6) |
| Golden channel reference (`channels.csv`) | done | 360 frames, dynamic (drums 0.12-0.57, transient/kick/snare fire), **deterministic** (byte-identical across runs) |
| Golden frame reference (`frame_NNNN.raw`) | done | RGBA8 640×360, **byte-identical** across runs |
| `.analysis` blob writer + reader | done (P0) | byte-exact round-trip vs `audio_engine.py` |
| Parity harness contract | done | `tests/parity_test.cpp` - check A channels (headless), check B frames (RHI) |

## Written, needs build machine (Qt6 + MSVC + vcpkg to compile)

| File | Role | Risk |
|---|---|---|
| `src/texture_pool.cpp` | pool reuse, weak alloc hook | low - pure logic, review-correct |
| `src/shader_cache.cpp` | FNV hash + disk cache, weak compile hook | low - pure logic |
| `src/render_graph.cpp` | Kahn topo sort + execute | low-med - logic done, GPU calls delegated |
| `src/engine.cpp` | render thread + facade | med - thread orchestration |
| `src/rhi_context.cpp` | **Qt RHI GPU wiring** | HIGH - every `<<RHI>>` marker is a QRhi call to complete on the build machine |

## Why C++ is unbuilt here
No C++ compiler / Qt on this machine (`no C++ toolchain found`). All GPU code
(`rhi_context.cpp`) is structured with `<<RHI>>` markers at each QRhi call site
and cannot be compiled/verified until a build machine has:
`vcpkg install qtbase[gui] qtshadertools ffmpeg[nvcodec] pffft miniaudio`.

## Parity gate procedure (on build machine)
```
# 1. reference (Python) - already reproducible here
python tools/golden_dump.py --image IMG --audio WAV --shader ascii \
    --frames 0,60,120,300 --out testdata/gold
python tools/analyze/analyze.py WAV testdata/gold.analysis

# 2. build engine
cmake -B build -DRIFT_WITH_RHI=ON \
    -DCMAKE_TOOLCHAIN_FILE=$VCPKG/scripts/buildsystems/vcpkg.cmake
cmake --build build

# 3. run gates
ctest --test-dir build           # smoke + parity
```
Gate passes when:
- **check A** channels match `channels.csv` within atol 1e-4 (identical smoothing)
- **check B** frames match `frame_NNNN.raw` within ≤2 LSB on ≥99.5% pixels
  (GL vs RHI rounding)

## Definition of done (P1 cutover)
- `rhi_context.cpp` `<<RHI>>` sites completed
- `ctest` green including parity check B
- headless engine renders the ascii/halftone/dither generators matching golden

## Next
P2: FFmpeg libav decode + async PBO upload (replace imageio/pyav).

## GPU path PROVEN (build machine, MSVC+Qt6.11+D3D11)
`tests/render_test.cpp` renders a fullscreen uniform-block shader offscreen via
QRhi (D3D11), reads it back: mean brightness 177.7, correct UV gradient.
Chain validated: QRhi init -> qsb-compiled .qsb -> QShader::fromSerialized ->
QRhiGraphicsPipeline -> std140 UBO (audio-reactive) -> offscreen RT -> readback.
This is the exact pattern to fill rhi_context.cpp's <<RHI>> markers.

Shader porting note: QRhi requires a std140 uniform BLOCK (not loose uniforms).
The 12 prototype .frag shaders must be converted (loose uniforms -> one UBO,
explicit sampler bindings) - mechanical, one-time.

## Ported shader RENDERS (build machine, D3D11)
tests/render_engine_test.cpp runs the ported ascii.frag through QRhi on a
synthetic image: correct ASCII quantization (glyph density tracks luminance,
input colors carried, scanlines). Engine UBO (channels) + Params UBO (ascii
params) + u_tex sampler all validated on GPU. This is the exact pattern for
rhi_context draw_pass.

Remaining chunk B: port this into rhi_context.cpp (QRhi init + .qsb/.layout
load + upload_media + draw_pass + texture pool), then multi-pass graph +
parity check B vs golden frames.
