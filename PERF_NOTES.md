# RIFT Performance Notes

## Phase 0 & 1 Measurements
- Light effect add (dither): 28 ms -> <1 ms UI time (pre-compiled).
- Heavy effect add (tunnel): 145 ms -> <1 ms UI time (pre-compiled).
- Effect picker switch: 42 ms -> <1 ms (cached JSON manifest & pipeline).
- Parameter change: <0.5 ms (direct dynamic UBO update).
- Export 1080p60 (4 fx): 17.1 fps (58 ms/frame).
- Export 4K (4 fx): 4.0 fps (246 ms/frame).

## Phase 1 Changes
- Pre-compiled all 24 effect pipelines on startup in RhiContext::warmPipelines.
- In-memory manifest caching in RiftViewport (eliminated disk JSON parsing).
- Direct O(1) pipeline lookup avoiding linear scan.

## Phase 2 Plan
- Multi-buffered async GPU readback ring (3 staging buffers).
- Asynchronous encoder worker thread with bounded frame queue.
- Hardware NVENC encoding option & precomputed audio analysis.
