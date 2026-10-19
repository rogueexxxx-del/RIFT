# RIFT Export & Performance Notes

## Found
- Export creates new `Engine` instance without GUI LUT tables or feedback history.
- `parUbo` dynamic uniform buffer overwritten across multi-pass frames in single submit.
- Missing shader pipelines silently fell back to checkerboard lines (`emptySource_`).
- `Placed::gain` atomic const qualifier prevented MSVC compilation.

## Changed
- Ring-buffered per-pass `parUbos` (32 slots) in `RhiContext` to prevent UBO overwrites.
- Default visualizer LUT baked into `RhiContext` on creation; mirrored to export engine.
- `applyPendingLoads_()` called at top of `runExport_()` before measuring duration.
- Loud error reporting on null shader pipelines in `RenderGraph`.
- `Placed::gain` marked mutable; visualizer suite unified with 4-channel audio texture.

## Left
- Build and run repro suite (`tools/repro_export.ps1`) across all effects.
- Verify 1080p, 4K, and 3+ effect chains.
- Wait for user before Part 2 (Performance).
