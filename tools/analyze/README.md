# Offline Analyzer (`.analysis` writer)

Produces the `.analysis` blob (see `docs/contracts/analysis_blob.md`) that the
runtime engine memory-maps. This is where the heavy, latency-tolerant work
lives - HPSS / optional Demucs stem separation, band energy, onset triggers.
It runs ONCE per media file, out of the runtime process.

## Phase strategy
- **P0/P1**: reuse the existing Python `../RIFT/audio_engine.py` unchanged.
  A thin wrapper runs its `_analyze()` and serializes the per-channel arrays
  to the binary blob format. Zero risk to sync/accuracy - same code.
- **P3+**: optionally reimplement the *fast band path* in C++ (pffft) for the
  live-input case; keep Demucs via ONNX Runtime (C++) or the Python CLI for
  offline high-quality stems.

## Wrapper contract (Python, P1)
```
python analyze.py INPUT_AUDIO OUTPUT.analysis [--demucs]
```
- loads audio at 22050 (matches prototype ANALYSIS_SR)
- runs AudioEngine._analyze(); reads _bass/_melody/_highs/_drums/_transient/
  _kick/_snare/_centroid arrays + bpm
- writes header + channel table + float planes per the blob spec
- time plane written as zeros (runtime fills playhead ramp)

## Validation (golden)
The P1 render-core parity test consumes a blob produced here and compares
engine channel output against Python `AudioEngine.update()` values
frame-by-frame (np.allclose, atol 1e-4). Gate cutover on this.
