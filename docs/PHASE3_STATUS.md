# Phase 3 - Runtime Audio - Status

Goal: runtime audio→uniform pipeline in C++ (no Python in the hot path),
numerically identical to the prototype. Heavy stem separation stays offline
(`tools/analyze/analyze.py`, already built).

## Design
- **AnalysisSource** ([analysis_source.hpp](../src/analysis_source.hpp)) - reads
  the `.analysis` blob, serves raw per-frame targets. TIME channel computed
  (frame/frame_count), matching the prototype.
- **Smoother** ([smoother.hpp](../src/smoother.hpp)) - exact port of
  `AudioEngine.update()` reactive-params math (ATTACK 0.2 / RELEASE 0.85;
  triggers 4,8,9 use 0.05 / 0.82; TIME passthrough).
- **AudioSystem** ([audio_system.hpp](../src/audio_system.hpp) /
  [.cpp](../src/audio_system.cpp)) - miniaudio playback + per-render `tick()`
  that maps playhead → frame → targets → Smoother → **ChannelRing** (lock-free
  to render). Live path: pffft band split (skeleton, `<<PFFFT>>` markers).
- **Engine wiring** - render loop calls `audio_->tick(playhead)` each frame,
  then reads the ring. loadAudio/play/pause/seek/loop routed.

## Verified (Python-equivalent, atol 1e-4)
The C++ `AnalysisSource.targets` + `Smoother.update` reproduce the prototype
`update()` **within 2.0e-07** worst-case over 360 frames (float precision,
centroid channel). The audio→uniform math is numerically identical.

## Parity check A is now a REAL gate (runs in quick build)
`tests/parity_test.cpp` check A: load `.analysis` (AnalysisSource) → run
Smoother frame-by-frame → diff vs golden `channels.csv`. No deps; runs under
`-DRIFT_WITH_RHI=OFF`.

To activate on the build machine:
```
python tools/golden_dump.py --image ..\RIFT\texture.png --audio ..\RIFT\track.mp3 ^
    --shader ascii --frames 0,60,120,300 --out testdata\gold
python tools\analyze\analyze.py ..\RIFT\track.mp3 testdata\gold.analysis
cmake --build build
ctest --test-dir build -C Debug --output-on-failure
```
Gate passes when check A reports 0 mismatches (worst |diff| ~1e-7).

## Needs build machine (audio libs)
`<<MA>>` (miniaudio playback/capture) + `<<PFFFT>>` (live FFT bands) in
`audio_system.cpp`. Build with `-DRIFT_WITH_AUDIO=ON` after
`vcpkg install pffft miniaudio`. The OFFLINE channel path (the validated one)
needs NONE of these - it compiles and passes parity in the quick build.

## Risks
| Risk | Mitigation |
|---|---|
| Live FFT ≠ offline analysis quality | live is best-effort real-time; file mode uses the offline blob (full HPSS/Demucs) |
| Smoother tick vs render fps | tick is per-render-frame like the prototype; at 60fps identical; parity gate covers the locked case |
| Playhead source of truth | AudioSystem owns playhead (miniaudio clock); engine reads it |

## Next
P4: QML shell + node graph wrapping the engine (migrate PySide6 UI).
P5: export via libav/NVENC. P6: deploy.
