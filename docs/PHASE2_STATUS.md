# Phase 2 - Async Media Decode - Status

Goal: replace the prototype's imageio/pyav decode (ran on the UI thread in
`media_loader.py`) with libav hardware decode on a worker thread, feeding the
render thread a bounded frame queue. Kills main-thread decode stalls
(priority 3: low-latency video).

## Design (fixed here, backend-agnostic)
- **FrameQueue** ([frame_queue.hpp](../src/frame_queue.hpp)) - bounded SPSC
  handoff decode→render. Backpressure on push (decoder can't balloon RAM);
  `pop_for(playhead)` drops stale frames, never blocks render (returns last-good
  on underrun); `flush()` on seek/loop.
- **MediaDecoder** ([media_decoder.hpp](../src/media_decoder.hpp) /
  [.cpp](../src/media_decoder.cpp)) - worker thread demux+decode; HW path
  (D3D11VA/NVDEC) keeps frames as GPU textures (zero-copy); SW fallback →
  sws_scale RGBA → uploaded via RhiContext. Images (incl. SVG) = 1-frame source.
- **Engine wiring** - render loop pulls `frameForPlayhead(cf.playhead)` each
  frame; `loadMedia/seek/setLoop` route to the decoder.

## Verified here (no build)
- **Frame-selection contract**: `frame_index_for(playhead,fps,total)` matches
  the prototype `media_loader.get_frame` (`int(elapsed*fps)%total`) - MATCH on
  all sampled playheads incl. loop wrap. Guarantees the C++ decoder shows the
  same frame the Python app would at any timestamp → export/preview parity.

## Needs build machine (FFmpeg + D3D11VA)
Every `<<FFMPEG>>` marker in `media_decoder.cpp` is a concrete libav call:
open_input, hw_device_ctx (D3D11VA), send_packet/receive_frame, EOF→loop seek,
sws_scale SW fallback. Complete + verify with:
`vcpkg install ffmpeg[avcodec,avformat,swscale,nvcodec]`, build
`-DRIFT_WITH_FFMPEG=ON`.

## Decode gate (build machine)
1. Decode a known clip; assert `frameForPlayhead(t)` returns the frame whose
   pts matches `frame_index_for(t,fps,total)` within ±1 frame.
2. Soak: 4K60 clip, confirm render thread never blocks (frame_ms stable, queue
   depth 1-8, no main-thread decode).
3. Seek storm: rapid seeks flush+refill without leak (hwframe refs released).

## Risks
| Risk | Mitigation |
|---|---|
| HW decode format varies by GPU/driver | get_format negotiates hw pixfmt; SW fallback path always present |
| D3D11 texture sharing between decode + RHI | both on D3D11; share via keyed mutex / shared handle (single device preferred) |
| Seek accuracy on B-frame codecs | seek to keyframe + decode-to-target; pts-driven pop tolerates ±1 |
| libav memory refs | RAII wrappers; frame/packet unref every iteration |

## Next
P3: runtime audio in C++ (pffft bands + envelope + patch-bay), offline stem
tool (already prototyped: `tools/analyze/analyze.py`). Feeds ChannelRing.
