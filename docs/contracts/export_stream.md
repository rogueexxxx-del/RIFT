# Export Encoder Contract  (v2)

How the engine turns rendered frames into a video file. Entirely in-process:
libav for encoding/muxing, QPainter for overlays, **no Python and no child
process** - README P6 ("strip Python from runtime").

Implementation: `src/exporter.cpp`. Test: `tests/export_hybrid_test.cpp`.

> **v1 (superseded).** The first cut piped frames to a Python child
> (`tools/export/export_encoder.py`) over stdin. It worked, but it put a
> Python interpreter in the runtime, which P6 forbids. Both justifications for
> it turned out to be weak: QPainter is a Qt **C++** API the engine already
> links, and an encoder probe needs no subprocess - `avcodec_open2` failing
> *is* the driver check. The findings below were established with that
> prototype and carried over intact.

## Which ffmpeg

The engine links the **BtbN LGPL-shared** build (`RIFT_FFMPEG_DIR`). This is a
licensing constraint, not a preference: `imageio_ffmpeg`'s bundled binary is
built `--enable-gpl --enable-libx264` and cannot ship beside a proprietary
product.

Consequence: the linked build is `--disable-libx264 --disable-libx265`.
**libx264 is unavailable** - it was the prototype's entire software fallback
(`../RIFT/core/export_pipeline.py`). The ladder below replaces it with
LGPL-safe encoders.

## Encoder ladder

`RIFT_EXPORT_ARCHIVE` always uses `prores_ks` (native, LGPL, `yuv422p10le`,
`profile 3`). Every other tier takes the first encoder whose
`avcodec_open2()` **actually succeeds on this machine**:

```
h264_nvenc  →  h264_qsv  →  h264_amf  →  h264_mf  →  libopenh264
 (NVIDIA)      (Intel QSV)   (AMD)     (MediaFoundation)  (software floor)
```

Probing by opening the encoder - rather than by checking it exists - is the
whole point. A codec being present means nothing. On the reference machine:

```
[h264_nvenc] Driver does not support the required nvenc API version.
             Required: 13.1 Found: 13.0
[h264_nvenc] The minimum required Nvidia driver for nvenc is 610.00 or newer
```

`h264_nvenc` is listed and `avcodec_find_encoder_by_name` returns it happily;
only `avcodec_open2` reveals the truth. The prototype's grep-the-encoder-list
probe would commit an entire export to it and die on the first frame. The
ladder re-probes every run, so a driver update restores nvenc with no code
change. That machine currently lands on **h264_qsv**.

Per-tier rate control (`set_rate_control`), by encoder:

| encoder | high | youtube | preview |
|---|---|---|---|
| h264_nvenc | `preset=p4 rc=vbr cq=19` | `cq=23` | `cq=30` |
| h264_qsv | `global_quality=19` | `=23` | `=30` |
| h264_amf | `rc=cqp qp_i=qp_p=19` | `=23` | `=30` |
| h264_mf | `rate_control=quality quality=85` | `=70` | `=50` |
| libopenh264 | `bit_rate` @ 0.15 bpp | 0.10 bpp | 0.05 bpp |

`libopenh264` has no constant-quality mode, so it falls back to
`pick_bitrate()`: `width * height * fps * bpp`.

### Pixel format
Encoders disagree on input format (qsv prefers `nv12`, openh264 `yuv420p`).
`AVCodec::pix_fmts` was **removed in FFmpeg 8** - same removal that took
`sample_fmts` - so `pick_pix_fmt()` queries
`avcodec_get_supported_config(..., AV_CODEC_CONFIG_PIX_FORMAT, ...)`,
preferring `yuv420p`, then `nv12`, then whatever is first. A NULL result means
"all supported". The `SwsContext` and the reusable `AVFrame` are both built
from `venc->pix_fmt`, never a hardcoded constant.

## Overlays

Drawn with QPainter directly onto the RGBA frame in `paint_overlays()`, before
`sws_scale`. Because the caller's readback buffer is const, frames are copied
into a reused scratch buffer first - and only when there is something to draw
(`overlaysAlways()` is false when the watermark is off and no logo is set, so
text-free frames skip the copy entirely).

Order and style match the prototype's `write_frame()`:
1. **logo** - `logo_path`, bottom-right, 30 px margin, scaled to at most 12% of
   export width, aspect preserved.
2. **watermark** - `RIFT`, Geist 16, `rgba(245,245,245,120)`, at `(30, h-30)`.
   Skipped when `no_watermark` is set.
3. **lyrics** - the frame's text, Geist 36, centred, black `alpha 180` shadow
   at (2,2) under white `alpha 255`.

Fonts must be registered (`QFontDatabase::addApplicationFont` over `font_dir`)
in `open()`, before the first text draw, or "Geist" silently falls back to a
system face.

### Orientation - differs from the prototype
Frames are **top-down**. `QRhi::readBackTexture` returns rows in natural order.

The prototype read bottom-up moderngl FBOs, so it needed `-vf vflip` *and* a
mirrored QPainter transform (`export_pipeline.py:64-65,123-125`). **Neither is
reproduced here.** Reintroducing either silently exports upside-down.

The **source** side is where the flip lives: decoded rows arrive top-down, but
the fullscreen quad samples with `v=0` at the bottom, so `RhiContext::
uploadMedia` flips rows once on the way in. Do NOT "fix" this in
`fullscreen.vert` - a v-flip there re-flips on every pass, making orientation
depend on how many effects are in the chain.

Verified by encoding one render graph through two independent code paths and
comparing frame 0 (top-half vs bottom-half mean): 53.11/9.83 against
52.37/9.66 - same structure, differing only by codec loss.

## Spec fields

`rift_export_spec` (`include/rift/rift_types.h`). Fields after `audio_path`
were appended, so callers that zero-init keep the previous behaviour:

| field | meaning |
|---|---|
| `width`, `height` | must be even (masked `& ~1`) |
| `fps` | 0 → 30 |
| `quality` | HIGH / YOUTUBE / ARCHIVE / PREVIEW |
| `no_watermark` | bool; suppresses the RIFT mark |
| `out_path` | container inferred from extension |
| `audio_path` | transcoded to AAC and muxed; null = video-only |
| `logo_path` | PNG with alpha; null = none |
| `font_dir` | dir of `.ttf`/`.otf` for overlay text; null = system fonts |
| `total_frames` | 0 = derive from media/audio duration |

`Exporter::encoder()` reports which encoder was selected - worth logging,
since it is machine-dependent.

## Render queue

Jobs run **one at a time**: each builds its own `Engine` (own QRhi + render
thread), and two concurrent renders would only contend for the same GPU.

A job captures clips, chain, grade and audio paths **at enqueue time**, by
value. Editing the session afterwards does not change an already-queued render.

A failed job does not stop the queue - one bad output path must not throw away
an overnight batch. `stopQueue()` stops it moving on to the NEXT job;
`cancelExport()` abandons the one in progress (its job is marked `CANCELLED`,
not `DONE`, because a cancelled render still finalises its container and reports
success).

### Batch spec (`--queue PATH`)

One job per line; `#` comments and blank lines ignored:

```
OUT|QUALITY|WIDTHxHEIGHT|FPS
```

Everything after `OUT` is optional (defaults: quality 0, 1920x1080, 60). Every
job snapshots the session as it is when the file is read, so a batch file is a
list of **output variants of the current project**, not a list of projects.
