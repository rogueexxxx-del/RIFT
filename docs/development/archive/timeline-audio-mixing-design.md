# Timeline audio tracks + real-time mixing - Phase 1 design

Status: proposed (awaiting review)
Date: 2026-10-04
Scope: Phase 1 of the timeline NLE redesign - the engine, data model, export
and bridge. The V/A split layout, linked-A/V editing gestures, the Project
panel and the razor/keyboard tools are Phases 2-4 and are out of scope here.

---

## 1. Context

Today RIFT has exactly one audio source per project. `AudioSystem::load()`
takes one `audio_path` (+ optional `.analysis` blob) and that single file
feeds three separate consumers:

- **Playback** - miniaudio plays the file (`ma_sound_init_from_file`).
- **Reactivity** - a fully-decoded mono copy (`pcm_`) drives the 10 channels,
  either through the offline `.analysis` blob (`AnalysisSource`) or the
  real-time FFT fallback (`analyzeFromPcm_` -> `analyzeLive_`).
- **Export** - `Exporter::transcodeAudio()` re-opens the same file with libav
  and encodes it to AAC.

The timeline holds video/image/text clips only (`ClipSpec`) on stacked lanes.
There is no way to place audio in time, and no way to mix more than one
source.

Phase 1 introduces audio **clips** on audio **tracks** and a **real-time
mixer** so several clips play together as one soundtrack. Reactivity and
export are driven by that mix. This is the foundation the later UI phases
build on.

### Decisions already made

- **Full mixing** - audio clips are real, placed, trimmed and mixed.
- **Fully linked A/V** - Phase 1 stores the link; Phase 2 makes the editing
  gestures act on it.
- **Approach B: real-time mixer** - the audio callback sums live decoders /
  clip buffers, so per-clip gain is live. (Rejected: bounce-to-one-stream.)
- **Project panel** to be built in a later phase; Phase 1 keeps the existing
  file-dialog/`loadAudio` entry point and adds just enough timeline UI to use
  and test audio clips.

---

## 2. Goals and non-goals

### Goals

1. A first-class `AudioClipSpec` with path, timeline position, trim, gain,
   track and link id.
2. Decode audio clips once and mix them in real time during playback (live
   gain), with the audio device as the master clock.
3. Derive the 10 reactive channels, the waveform and the beat markers from
   the **mix**, not from one file.
4. Export the mixed soundtrack, honoring the mark in/out range.
5. Project format **v5** with `audio_clips` + video `link`, and a migration
   from v4's single `audio_path`.
6. A minimal timeline UI (audio lanes with add/move/trim/delete) plus the
   `RiftViewport` bridge calls, so the phase is usable and testable.

### Non-goals (later phases)

- Top-half V-tracks / bottom-half A-tracks visual layout (Phase 2).
- Linked A/V selection, drag, trim, split gestures (Phase 2).
- Project/media bin panel and drag & drop from it or from Explorer (Phase 3).
- Razor tool mode (C), arrow-key frame stepping, +/- zoom keys (Phase 4).
- Streaming very long audio clips from disk (accepted limit, section 12).

---

## 3. Data model

### 3.1 `AudioClipSpec` (new, `src/timeline.hpp`)

```cpp
struct AudioClipSpec {
    std::string path;          // audio file (wav/mp3/m4a/ogg/...), libav/miniaudio decodable
    std::string name;          // display label (basename by default)
    double start = -1.0;       // timeline seconds; -1 = append after this track's last clip
    double in    = 0.0;        // trim start within the source
    double out   = 0.0;        // trim end within the source; <= in means "to end"
    int    lane  = 0;          // A-track index, 0 = A1. Separate namespace from video lanes.
    double gain  = 1.0;        // linear, 0..2 (UI may show dB)
    int    link  = -1;         // shared id with a video ClipSpec; -1 = independent
};
```

Audio lanes are a **separate namespace** from video lanes because only video
lanes composite. `laneCount()` keeps its video meaning; `audioLaneCount()`
is added.

### 3.2 Video `ClipSpec` gains `link`

`ClipSpec` (video) gains `int link = -1;`. It is stored and round-tripped in
Phase 1; only Phase 2 changes gestures to honor it. Importing a video file
creates a video clip and an audio clip with the same non-negative link id
when the file has an audio stream (Phase 2 wires the import; Phase 1's
`addAudioClip` can set a link explicitly).

### 3.3 Resolution / layout

`AudioClipSpec` resolves like video clips do: `start = -1` appends after the
end of the previous clip **on the same audio lane**, resolved once the
source duration is known. `out <= in` means "use the whole source from `in`".

---

## 4. Project format v5

`docs/contracts/project_format.md` is frozen; this is a version bump.

- New top-level `"audio_clips": [ {path, name, start, in, out, lane, gain, link} ]`.
- Video clips gain `"link"` (omitted when `-1`).
- Presets omit `audio_clips` exactly as they omit `clips`.
- `audio_path` / `analysis_path`: still **read** (v4 and earlier). On load,
  a present `audio_path` becomes one `audio_clips` entry: lane 0, start 0,
  in 0, out 0, gain 1, link -1, name = basename. `analysis_path` is retained
  in memory only to preserve the single-clip reactivity optimization
  (section 6). Saving always writes v5 and no longer writes `audio_path`.
- Unknown/newer keys: ignored, as today.

A separate migration note will be appended to the contract doc.

---

## 5. Audio engine - the real-time mixer

### 5.1 New component: `AudioMixer` (`src/audio_mixer.{hpp,cpp}`)

Owns the mixed timeline audio. One decoded buffer per clip; the audio thread
sums them live.

```cpp
struct MixClip {
    AudioClipSpec        spec;       // structural; immutable while this set is live
    std::vector<float>   pcm;        // interleaved stereo, kMixRate, whole source
    int64_t              frames = 0; // per-channel frame count
    std::atomic<float>   gain{1.f};  // live, mutable in place
};

class AudioMixer {
public:
    // Render/UI thread. Decodes any new/changed source, reuses the rest by
    // path, then publishes a new immutable clip set to the audio thread.
    void setClips(const std::vector<AudioClipSpec>& clips);

    // Render/UI thread. Live fader. Applied by the callback next block.
    void setGain(int index, float gain);

    // ── audio thread (called from the device data callback) ──
    // Sums active clips into `out` (interleaved stereo, kMixRate), honoring
    // start/in/out/gaps/end and gain. Non-blocking: no decode, no locks.
    void mix(float* out, uint32_t frames);
    // Loads the pending seek/lifecycle commands. Called at the top of mix().
    void applyCommands();

    // ── offline (render thread / export) ──
    // Mono mix of the whole piece, for reactivity/waveform/beats. Also the
    // length source of truth for the mix.
    void renderMono(std::vector<float>& out) const;
    // Interleaved stereo for [startFrame, startFrame+frames), for export.
    void renderRange(float* out, int64_t startFrame, int64_t frames) const;
    double duration() const;            // end of the last audio clip, seconds
    int64_t cursor() const;             // playback frame, audio-thread-updated
    void seek(int64_t frame);           // posts a command
    void setLoop(bool on);
};
```

- **Decode format**: every clip is decoded once to `f32, stereo, kMixRate`
  (48 kHz) at `setClips` time, through libav (`avformat`/`avcodec` +
  `swresample`, the dependency the exporter already uses), written into the
  clip's RAM buffer at one rate and channel count. The callback then only
  does integer-add mixing. Decoding through libav rather than
  `ma_decoder` covers every container RIFT already accepts (wav/mp3/m4a/ogg
  and the audio streams of video files), and keeps one decoder stack in the
  project. Reuse is by source path, mirroring `Timeline::apply()`.
- **Active-clip test**: a clip is audible for output frame `n` when
  `n` falls in `[clipStartFrame, clipStartFrame + clipFrames)` and within
  its `[in, out)` source window. Source index = `(n - clipStart) + inFrame`.
- **Gain**: `std::atomic<float>` per clip; a fader move needs no rebuild.
- **Clamp**: the summed sample is clamped to `[-1, 1]` only at the device
  boundary; internal sums may exceed 1 (headroom), matching how an NLE sums
  and then limits.

### 5.2 Threading

- Structural change (`setClips`): decode on the calling thread into a fresh
  `std::vector<MixClip>`, wrap in `std::shared_ptr<const ClipSet>`, and
  publish with an atomic store. The audio callback `atomic_load`s the set and
  reads it; the previous set is freed when the last reference drops. No locks
  in the callback.
- Live gain: mutate the clip's atomic in place. If a `setClips` swapped the
  set between the UI's index and the call, `setGain` looks up the current set
  by index - gains are re-applied from the spec on rebuild.
- Seek/loop/play: atomic request fields consumed by `applyCommands()`.
- The cursor is an `std::atomic<int64_t>` advanced by `mix()`.

### 5.3 Playback output

Replace `ma_sound` playback with a miniaudio **playback** `ma_device` whose
`dataCallback` calls `AudioMixer::mix()`:

- Config: `ma_format_f32`, 2 channels, `kMixRate`, `ma_device_type_playback`.
- The device is the **master clock**: `AudioSystem::playhead()` returns
  `mixer.cursor() / kMixRate` when the device is running. This keeps visuals
  locked to what is heard, as `hasPlayback()` intended.
- Loop: the mixer wraps its cursor at `duration()`.
- `ma_engine` / `ma_sound` are removed from `Ma` (they were only used for
  this playback path). The live-capture `ma_device` is unchanged.
- If the device fails to open, fall back to the engine's wall-clock transport
  (`Engine::computePlayhead_()`), exactly as today's no-playback case.

### 5.4 Wire-up in `AudioSystem`

`AudioSystem` owns the `AudioMixer`. `load()` is superseded by a new
`setAudioClips(const std::vector<AudioClipSpec>&)`; `load(audio, analysis)`
is kept as a thin wrapper that builds a single A1 clip (+ optional blob).
After a structural change, `AudioSystem` rebuilds its derived data
(waveform/beats, section 6) and bumps `dataGeneration()`.

---

## 6. Reactivity, waveform and beats from the mix

- **Channels**: `tick()` analyzes the **mono mix** (`renderMono`) with the
  existing `analyzeFromPcm_` / `analyzeLive_` FFT path. No new DSP; the
  channels keep their current meaning.
- **Back-compat optimization**: when there is exactly one audio clip with
  `start == 0`, `in == 0` and a loaded `.analysis` blob, use the blob
  (`AnalysisSource`) exactly as today, so an existing single-file project
  reacts identically. Any other case uses the mix analyzer.
- **Waveform**: rebuilt from the mono mix on structural change, into `wave_`
  (peak-per-bucket), reusing the current bucket logic.
- **Beats**: `buildBeats_` runs over the mix waveform as it already does for
  a blob-less file.
- **Gain changes**: playback is live, but the mono mix / waveform / beats are
  rebuilt on structural change only. A pure fader move is heard immediately
  but does not immediately change the reactive channels; the next structural
  edit (or an explicit refresh) reconciles them. This is called out as a
  deliberate limit, not a bug.

---

## 7. Export from the mix

`Exporter::transcodeAudio()` stays a "decode a file -> AAC -> mux" routine,
but its input becomes a **mix bounce**:

1. At export start, the engine renders the mixer over the export range
   (mark in/out honored) to a temp PCM WAV under the cache dir
   (`cache/mix-<hash>.wav`), via `AudioMixer::renderRange`.
2. That path is handed to the exporter as `audio_path`.
3. Existing transcode/mux is unchanged.

Because the mix is a pure function of the clip set, playback and export
match. The `ExportJob` snapshot gains the audio clips so a queued job renders
the audio it was queued with, like it already snapshots video clips.

The mix `duration()` (end of the last audio clip) replaces `audioDuration()`
everywhere it feeds the piece length, so export length behavior is unchanged
from today.

(An in-memory AAC encode, skipping the temp WAV, is a later optimization;
the temp file keeps the exporter untouched and is fast.)

---

## 8. Bridge and minimal UI

### 8.1 `RiftViewport`

- `Q_PROPERTY(QVariantList audioClips READ audioClips NOTIFY audioClipsChanged)`
  entries `{index, name, path, start, in, out, span, lane, gain, linked, active}`.
- `Q_PROPERTY(int audioLaneCount ...)`.
- `Q_INVOKABLE addAudioClip(const QUrl&, int lane = -1, int link = -1)`.
- `Q_INVOKABLE removeAudioClip(int)`, `setAudioClipStart(int, qreal)`,
  `setAudioClipTrim(int, qreal in, qreal out)`, `setAudioClipGain(int, qreal)`,
  `setAudioClipLane(int, int)`, `splitAudioClip(int, qreal)`.
- `loadAudio` becomes "replace the A1 clip with this file" so existing
  callers keep working.
- `pushAudioClips_()` mirrors the model to `Engine::setAudioClips()`.
- Undo/preset/project JSON include `audio_clips` (snapshot serializer is
  shared, so undo comes free once `projectJson_` includes them).

### 8.2 Timeline UI (minimal)

- Audio lanes rendered below the video lanes, labeled `A1..An`, using the
  existing lane pattern (bed, drop highlight, lane count = highest in use + 1).
- Audio clip delegate: body block with name, drag to move (time + lane), trim
  handles, right-click remove - the video clip delegate reworked for the
  audio band. No cross-link selection yet.
- `+ Audio` toolbar button (file dialog) and a gain control for the selected
  clip.
- The existing single waveform strip is replaced by the per-clip drawing;
  beat markers and the keyframe lane stay where they are.

---

## 9. File-by-file change map (Phase 1)

| File | Change |
|---|---|
| `src/timeline.hpp` | add `AudioClipSpec`; add `link` to `ClipSpec` |
| `src/audio_mixer.hpp/.cpp` | **new** - mixer + clip set |
| `src/audio_system.hpp/.cpp` | own mixer; `setAudioClips`; playback device; mix-based `tick`/waveform/beats; keep `load` wrapper |
| `src/engine.hpp/.cpp` | `setAudioClips`, `audioLaneCount`, `audioClips`; feed export mix; expose to viewport |
| `src/exporter.hpp/.cpp` | accept the mix WAV path (mostly unchanged) |
| `src/ui/rift_viewport.hpp/.cpp` | audio-clip properties + invokables; serialization; push to engine |
| `qml/TimelinePanel.qml` | audio lanes + clip delegate + `+ Audio` |
| `CMakeLists.txt` | add `audio_mixer.cpp`, and `QML_FILES` already lists TimelinePanel |
| `docs/contracts/project_format.md` | version 5 + migration note |
| `tests/` | `audio_mix` unit test; export audio; format round-trip |

---

## 10. Testing

- **Mixer unit test** (`tests/test_audio_mix.cpp`, no files needed - synthetic
  PCM): clip offset, gain, in/out trim, gaps, overlap summing, seek,
  loop-wrap, `renderRange` boundary at the export range.
- **Reactivity parity**: channels from a 2-clip mix equal the channels from
  the equivalent single pre-summed signal via `analyzeFromPcm_`.
- **Export**: existing file-size regression still holds; output carries an
  audio stream whose duration matches the video; a silent range vs a tone
  range differ in size/energy.
- **Format**: v5 round-trip preserves clips/gain/lane/link; a v4 file with
  `audio_path` loads as one A1 clip.
- **Headless**: extend `rift_shell` flags - `--audioclip PATH@LANE[@START]`,
  `--audio-grade`, `--audiogain INDEX=VALUE` - so the mix is drivable and
  checkable without UI automation.

---

## 11. Rollout

Phase 1 is shippable on its own: existing projects still load (migrated to a
single A1 clip), single-file behavior is preserved by the blob optimization,
and multi-clip mixing/export works end to end. Phases 2-4 then restructure
the UI on top of a stable model.

---

## 12. Risks and limits

- **Memory**: clips are held decoded in RAM (stereo f32 48 kHz ~ 384 KB/s,
  ~115 MB for 5 min per clip). Accepted for Phase 1; streaming from disk via
  ring buffers is a later optimization.
- **Audio-thread safety**: solved by immutable `shared_ptr<const ClipSet>`
  swaps + per-clip atomic gain; no locks in the callback.
- **Master clock change**: removing `ma_sound` shifts the clock to the
  playback device callback. The wall-clock fallback must remain correct when
  no device opens, or playback/export drift returns.
- **Reactivity character**: for multi-clip projects the channels come from the
  live FFT analyzer (AGC-normalized), not the offline percentile-normalized
  blob. Single-clip projects keep the blob. Called out in section 6.
- **Gain vs reactivity lag**: a fader move is audible immediately but does not
  retune the channels until the next structural rebuild (section 6).
- **Codec coverage**: audio clips decode through libav, so any container the
  rest of the app accepts works. The playback `ma_device` only carries f32
  stereo at `kMixRate`; no per-clip codec handling is needed at playback.
- **Windows-only, D3D11**: unchanged from the rest of the app.

---

## 13. Open items to confirm during review

1. Gain range: linear `0..2` internally, shown as dB in the UI - OK?
2. `+ Audio` import parses a plain audio file; phase 2 handles a video file's
   audio stream. Confirm that split.
3. Mark in/out is the export audio range (already how video export works) -
   confirm no separate audio range is wanted.
