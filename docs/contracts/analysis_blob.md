# `.analysis` Blob Contract  (v1)

Precomputed audio analysis. Written ONCE per media file by the offline
analysis tool (`tools/analyze`, may wrap the existing Python
`audio_engine.py`). The runtime engine **memory-maps** this file and reads
per-frame channel values with zero heavy work in the hot path.

This is the boundary that keeps stem separation (HPSS/Demucs) out of the
runtime while preserving identical sync/accuracy.

## Why a binary blob
- mmap → no parse cost, page-cached by OS
- fixed-stride float arrays → O(1) frame lookup, cache-friendly
- matches the prototype's `audio_engine.py` per-frame arrays 1:1

## File layout (little-endian)

```
Header (64 bytes, 8-byte aligned)
  char     magic[8]      = "RIFTANLZ"
  uint32   version       = 1
  uint32   flags         = 0
  uint32   sample_rate               // analysis sr (prototype uses 22050)
  uint32   hop_length                // int(sr/fps); frame_for_time hop
  uint32   fps                       // analysis fps (60)
  uint32   frame_count   = N
  uint32   channel_count = C (=10)
  float    bpm                       // real bpm (NOT normalized)
  uint32   reserved[6]               // pads header to exactly 64 bytes

Channel table (C entries, 16 bytes each)
  char     name[12]                  // "bass","melody","highs","drums",
                                     // "transient","bpm","centroid","time",
                                     // "kick","snare"
  uint32   kind                      // 0=energy(smoothed) 1=trigger(sharp)

Data (C planes, each N float32, contiguous, plane-major)
  plane[c][f] = channel c value at frame f, already normalized [0,1]
                (post gating/compression, PRE per-frame smoothing -
                 runtime applies smoothing, same as prototype update())
```

Total size = 64 + C*16 + C*N*4 bytes.

## Channel semantics (match prototype `AudioEngine`)
| idx | name | kind | source |
|---|---|---|---|
| 0 | bass | energy | low band 20-250Hz (BASS) |
| 1 | melody | energy | 250-2000Hz (MIDS) |
| 2 | highs | energy | 2-20kHz (AIR) |
| 3 | drums | energy | percussive RMS (BEAT) |
| 4 | transient | trigger | onset strength (HIT) |
| 5 | bpm | const | bpm/200 normalized |
| 6 | centroid | energy | spectral centroid |
| 7 | time | ramp | playhead 0..1 (computed at runtime, plane may be zero) |
| 8 | kick | trigger | <150Hz percussive onset (KICK) |
| 9 | snare | trigger | 1.5-8kHz percussive onset (SNARE) |

## Runtime read (pseudocode)
```
frame = int(playhead_seconds * sample_rate / hop_length)   // no drift
frame = clamp(frame, 0, frame_count-1)
for c in 0..C:  raw[c] = plane[c][frame]
// then engine applies exponential smoothing (attack/release), identical
// to prototype update(); trigger channels use fast-attack constants.
```

## Versioning
`version` int. Loader migrates older → current, rejects newer with warning.
New channels appended (channel_count grows); readers ignore unknown names.
