# RIFT - codebase context

Hand this file to anyone (or any AI) who needs to understand what RIFT is, how
it is put together, how to build it, and what has been done to it. It is the
map; the code is the territory.

---

## 1. What RIFT is

A Windows desktop application for making audio-reactive video art. You give it
a piece of music and some footage; it runs the footage through a chain of GPU
effects whose parameters are driven by the music, and renders the result to a
video file. It also runs live, taking sound straight off the machine's audio
output so the visuals follow whatever a DAW is playing.

Two modes:

- **React** - a timeline. Lay out clips, animate parameters with keyframes,
  export to MP4/MOV.
- **Live** - no timeline. The picture reacts to sound in real time and a MIDI
  controller drives the parameters by hand.

---

## 2. History

RIFT started as a Python prototype (numpy + moderngl). That version worked but
could not hold frame rate at 4K, could not be shipped as one file, and could
not be given to anyone who did not already have a Python environment.

The whole thing was rewritten in C++ against Qt's RHI. The rewrite was done in
chunks, each one verified against the Python version's output before moving on
- the `rift_parity` test still exists and compares the C++ shader output with
recorded reference frames. **The Python prototype is gone; the C++ engine is
the product.** Do not reintroduce Python at runtime; the only Python left is in
throwaway build scripts.

Stack decision, fixed and not up for revisiting: **C++20, Qt 6 (QRhi over
Direct3D 11), QML/Qt Quick for the interface.**

---

## 3. Architecture

```
                 ┌──────────────────────────────────────────┐
   audio file ──▶│ AudioSystem                              │
   or live       │  decode / WASAPI loopback capture        │
   loopback      │  FFT (pffft) -> 10 named channels        │
                 └───────────────┬──────────────────────────┘
                                 │ rift_channel_frame (10 floats/frame)
                                 ▼
  media file ──▶ MediaDecoder ─▶ Timeline ─▶ ┌──────────────────────┐
                 (FFmpeg)        (clips,     │ Engine               │
                                  lanes)     │  per-clip chain      │
                                             │  composite lanes     │
                                             │  master colour grade │
                                             └──────┬───────────────┘
                                                    │ TexId
                                       ┌────────────┴────────────┐
                                       ▼                         ▼
                                 RiftViewport              Exporter
                                 (QQuickItem,              (readback ->
                                  live preview)             FFmpeg mux)
```

### Layers, bottom to top

| Layer | Files | What it owns |
|---|---|---|
| GPU | `src/rhi_context.{hpp,cpp}` | Owns the `QRhi`. Pipelines, textures, uniform buffers, offscreen frames, audio texture uploads. Everything GPU goes through here. |
| Effects | `src/render_graph.{hpp,cpp}` | The shared effect chain: a list of shader ids, each with its own uniforms, run one into the next through ping-pong targets. |
| Layers | `src/layer_stack.{hpp,cpp}` | Per-clip chains, lane compositing (blend / opacity / transform / crop), and the master colour grade. |
| Timeline | `src/timeline.{hpp,cpp}` | Clips: where they sit, what they trim to, which lane, their own effect stack. `activeAt(t)` returns what is on screen. |
| Media | `src/media_decoder.{hpp,cpp}` | FFmpeg decode of video/image/vector into GPU textures. |
| Text | `src/text_source.{hpp,cpp}` | Rasterises text layers (own font registry, separate from Qt's). |
| Audio | `src/audio_system.{hpp,cpp}` | Decode, playback, live capture, FFT, band splitting into 10 channels. |
| Params | `src/parameter_graph.hpp`, `src/smoother.hpp` | A uniform's value = base + keyframes + audio patch + MIDI, smoothed. |
| Engine | `src/engine.{hpp,cpp}` | The conductor. Owns the render thread, the playhead, and the export loop. |
| Export | `src/exporter.{hpp,cpp}`, `src/frame_queue.hpp` | GPU readback -> encoder, on its own thread. |
| UI glue | `src/ui/rift_viewport.{hpp,cpp}` | The single `QQuickItem` the whole QML interface talks to. Big on purpose - it is the entire C++/QML boundary. |
| Input | `src/ui/control_input.{hpp,cpp}` | MIDI CC in, OSC over UDP. |
| Shell | `src/ui/main_qml.cpp`, `qml/` | The application itself. |

### Things worth knowing before you touch anything

- **Uniform order is positional, not by name.** A shader's `*.layout.json`
  manifest lists its parameters; index `n` in the manifest is index `n` in the
  `Params` uniform block. Reorder one without the other and every slider drives
  the wrong thing. The `rift_manifest` test exists to catch exactly that.
- **Samplers are matched by NAME, not binding number.** `buildSrb` looks up
  `u_audio_texture` / `u_spectro_tex` / `u_feedback_tex` by name. Binding numbers
  collide between shaders (the compositor's `u_under` sits on binding 3, same as
  the spectrogram), and matching by number silently bound the wrong texture.
  A name this list does not know falls through to the 1x1 dummy WITHOUT
  complaining - that is how `u_feedback_tex` sat declared-but-dead in
  `post_fx.layout.json` for a whole release.
- **`u_feedback_tex` is the previous FINAL frame**, one shared history for the
  whole chain, not one per node. `RhiContext::capturePrev()` copies the finished
  scene at the end of every frame - preview, offscreen and export alike - and
  `Engine` calls it after the grade. It is a GPU copy rather than a ping-pong of
  the final target on purpose: the id handed to Qt Quick has to stay stable.
  On frame 0 and immediately after a resize it is the dummy, so a feedback
  shader starts from black instead of from garbage.
- **A feedback loop with gain >= 1 saturates to white in seconds.** Whatever a
  feedback shader multiplies the history by, before compositing, must come to
  less than 1.0 across every path. `feedback.frag` shipped briefly with
  `decay * (inject + 0.35)`, which is 1.35 at full injection, and no value of
  decay could save it.
- **A preset is not a project, and the difference is one flag.** `asProject`
  runs through `projectJson_` / `applyProjectJson_` / `saveProject`. False means
  the look only - chain, params, grade, controls - and it also stops
  `project_path_` being re-pointed at the file. All three used to be conflated:
  saving a preset made the session BE the preset, so the next save overwrote it,
  and applying one loaded the audio it was saved against. The read side enforces
  it against what the file actually contains, not what it should contain, so
  presets written before 0.1.3 (which do carry `audio_path`, and at least one of
  which carries `clips`) still apply as a look and nothing more. Do not
  "simplify" this back into a single load path.
- **`u_feedback_tex` is what makes datamosh real.** Its `persist` param pulls
  blocks from the previous output instead of the current frame. Zero restores
  the pre-0.1.3 look, which is what old projects get, since `drawPass`
  zero-fills params a saved file does not carry.
- **A QRhi offscreen frame is a submit plus a wait for the GPU to drain.**
  Opening one per effect pass costs a full stall each. `beginFrame`/`endFrame`
  are nestable through a depth counter so a whole frame - every chain pass, the
  composite, the grade, the readback - is one submit.
- **The texture id handed to Qt Quick must be stable.** If the id changes every
  frame, the `QSGTexture` wrapper is destroyed and rebuilt every frame, which
  crashed. The final pass always renders into a fixed target for this reason.
- **The viewport renders at device pixels, not logical pixels.** Multiply by
  `effectiveDevicePixelRatio()`. Skipping this rendered at the wrong size and
  stretched, which looked like a mosaic on any display above 100% scaling.
- **The compositor takes nine parameters, not five.** `blend, opacity, posX,
  posY, scale, cropX, cropY, cropW, cropH`. `drawPass` zero-fills the rest of
  the uniform block, so passing the old count of five makes the crop rectangle
  arrive as `(0,0,0,0)` - the shader then discards every pixel and returns its
  input, which looks exactly like the effect silently not working. Use
  `LayerStack::kCompositeParams` and pass `0,0,1,1` for "no crop". Three call
  sites: `engine.cpp` (a clip in a lane), `layer_stack.cpp` (a pass folded over
  its input), `render_graph.cpp` (the same, for the shared chain).
- **An empty track still needs a source.** `Engine::emptySource_()` is the
  placeholder picture the chain runs over when no clip covers the playhead, and
  every path uses it - preview, the standalone render loop and export. Export
  used to pass texture 0, which `drawPass` binds to the 1x1 black dummy, so
  every shader that samples `u_tex` (tunnel, lens, kaleido...) exported pure
  black while the viewport looked fine.
- **Clip decoders loop; clips do not.** `Timeline::ensureOpen_` opens every
  decoder with `setLoop(true)`; how long a clip occupies is still its span.
  With loop off the worker thread ended at EOF, so when `renderLayers_` wrapped
  the lookup for footage shorter than the track there was nothing left to
  decode and the last frame was held forever.
- **Anything holding an index into a vector must be fixed up when that vector
  changes.** `control_map_` (MIDI/OSC bindings) names a chain node by index and
  `edited_clip_` names a clip by index. `removeNode` / `moveNode` and
  `removeClip` / `splitClip` fix them up. Miss one and a knob drives the wrong
  effect, or `syncChainToClip_` writes the rail into an unrelated clip.
- **The shared chain is parked while a clip's stack is edited.** `selectClip(i)`
  swaps `Priv::chain` for the clip's passes and parks the shared chain in
  `Priv::shared_chain`; `selectClip(-1)` puts it back, and `projectJson_` writes
  the parked copy while a clip is selected. Before this, selecting a clip
  destroyed the shared chain.
- **Every chain mutation must call `syncChainToClip_()`.** A selected clip
  renders through its own `ClipSpec::chain`; the rail is a working copy.
  `setEffect` forgot, so swapping a clip's effect did nothing.
- **"Is there a key here" is one function.** `keyAtPlayhead_()` accepts a key at
  the raw playhead OR at the snapped time. `addKey` places keys on the snapped
  beat, but dragged and beat-keyed ones can sit anywhere; checking only one time
  made Set, Delete and the keyed indicator disagree. Effect params and the grade
  both use it.
- **The UI reads AudioSystem data as copies, gated by a generation counter.**
  `waveform()` / `beats()` return by value under a mutex, and
  `audioDataGeneration()` bumps once per completed load. The waveform is always
  2048 buckets, so its size could not detect a new track, and the old accessors
  returned references the UI thread read while the render thread refilled them.
- **Trimming a clip's head moves its `start`.** `setClipTrim` shifts the start by
  however far `in` moved, so the edge under the pointer is the one that moves.

### QML traps this codebase has already hit

- **Measure drags in scene coordinates.** `centroid.position` is relative to
  the item the handler is on. If that item MOVES as a result of the drag - a
  clip following the pointer, a trim handle anchored to the edge it resizes -
  each measurement cancels part of its own effect and the item crawls along
  behind the cursor. Always `centroid.scenePosition - centroid.scenePressPosition`.
- **Do not name a component after a Qt Quick Controls type.** A file called
  `ToolButton.qml` lost to `QtQuick.Controls.ToolButton` in any file importing
  Controls, and the failure was `Cannot assign to non-existent property "tip"`
  on a line that looked correct. It is `EditToolButton.qml` for that reason.
- **Declare a property on the object you assign to.** `openRow` was declared on
  a `ColumnLayout` inside the panel while delegates wrote `panel.openRow`.
  Different object; QML cannot create the property, so every click was a silent
  no-op and the disclosure control did nothing.
- **A `Column` does not size children from their implicit height.** A wrapper
  `Item` needs `height:`, not `implicitHeight:`. At zero height it still DRAWS
  (nothing clips it) but receives no pointer events.
- **A `ColumnLayout` centres its children on the axis when nothing in it can
  grow.** With a list hidden, a lone header drifted to the middle of the dock.
  `Layout.alignment: Qt.AlignTop`, or a trailing `Item { Layout.fillHeight }`.
- **A `Rectangle` does not clip.** A collapsed panel whose declared height was
  smaller than its content drew that content over whatever came next.
- **Bindings to `Q_INVOKABLE` calls evaluate once.** `liveDevices()` is a
  function, not a property, so a device list bound at window construction was
  empty before the engine existed and stale forever after. Re-query on open.
- **Never derive one layout position from two properties you assign in
  sequence.** Bindings re-evaluate on the FIRST assignment, so between
  `effectsSide = settingsSide` and `settingsSide = e` both docks read "right",
  both resolved to `Layout.column: 2`, and two items in one `GridLayout` cell
  makes the layout place the second somewhere else entirely - which is why a
  dock would not stay on the side it was moved to. One `docksSwapped` bool now
  feeds two readonly derived sides, so they cannot disagree even for an instant.
- **A `Timer` referenced from `Component.onCompleted` must actually exist.**
  `presetKick.start()` against a missing id throws a ReferenceError that aborts
  the REST of `onCompleted` silently - no dialog, no console line, the app just
  sits there having skipped every later step. If a CLI flag does nothing at all,
  suspect an exception earlier in that block before suspecting the flag.
- **Pin `Layout.row` as well as `Layout.column` in a `GridLayout`.** With a
  column alone the layout auto-places: a column behind its cursor wraps onto the
  next row. After a dock swap that put a dock in a different cell, over the
  viewport, where it swallowed clicks meant for its own controls.
- **Repeater delegates are children of the Repeater's PARENT.** A
  `parent.parent.parent` chain from a delegate lands one level higher than it
  reads. ClipInspector's colour buttons did exactly that, got `undefined`, and
  `qBound` turned the NaNs into maximums - the caption jumped off-frame. Give
  the target an `id` (`textBox`) instead of counting parents.
- **Nested TapHandlers both fire.** A row-wide TapHandler with a smaller one
  inside it runs both on a tap in the small one. PresetBar's delete x also
  applied the preset; the row handler now ignores taps over the x.
- **A binding to a Q_INVOKABLE must READ the thing that changes.** ClipInspector's
  `st` called `clipText(idx)` and re-evaluated only when `idx` did, so each text
  slider sent a stale style back and undid the others. It now reads
  `viewport.clips` (republished on every edit) inside the binding.
- **`lastControl` is `"<key> <value>"`,** e.g. `"cc:74 0.53"`. Compare with a
  prefix plus the space (`indexOf(key + " ") === 0`), or the controller view's
  activity flash never lights and `cc:1` lights for `cc:10`.
- **New QML files must be added to `QML_FILES` in `CMakeLists.txt`**, or the
  type is missing at runtime with the build reporting nothing.

---

## 4. Audio reactivity

Ten channels, derived from the signal every frame:

`level, bass, low_mid, mid, high_mid, treble, transient, flux, centroid, beat`

Any shader uniform can be *patched* to a channel with a depth, so the audio
adds to the value the slider is set to. Two gates decide whether the channels
carry anything - both have burned us:

1. `ready_` must be true, or `tick()` returns early and publishes ten zeros.
   It is `have_analysis || !pcm_.empty()`, not just the pre-analysis blob.
2. The parameter has to actually be patched, with a non-zero depth.

**Live capture is WASAPI loopback**, not a microphone. The device list puts
*playback* devices first, marked "(playing)"; opening one with
`ma_device_type_loopback` hands back the mix that device is producing. That is
what makes RIFT follow Ableton, FL, a browser, anything - with no virtual audio
cable and no plugin.

---

## 5. Effects

Twenty-nine fragment shaders in `shaders_qrhi/`, each with a `.layout.json`
(param order + sampler bindings, read by the engine) and, if it is user-facing,
a `.manifest.json` (labels, ranges, defaults, default audio patch, read by the
UI). `rift_manifest` checks the two agree slot for slot.

Twenty-four are offered in the picker, listed in `effectIds` in `qml/Main.qml`:

ascii, halftone, dither, glitch, pixel_sort, blur, oscilloscope, datamosh,
cyanotype, risograph, thermal, terminal, electron_scan, kaleido, mirror_tile,
flow_warp, voronoi_shatter, dot_field, tunnel, lens, bloom, feedback, slit_scan,
post_fx.

Three are internal passes the engine calls directly and the picker never shows:
blit, color_grade, composite.

`noise_field` and `fracture` still exist on disk and still render for any
project that references them, but were dropped from `effectIds` in 0.1.3.

`feedback`, `slit_scan` and `post_fx` sample `u_feedback_tex` - see the feedback
notes above before touching any of them.

`slit_scan` accumulates from that single previous frame rather than holding a
ring of past frames, so its history is however long content takes to cross the
frame (about 1.7 s at the default) and it cannot be scrubbed. A real Time
Machine-style version wants N frames in a 2D array texture, at N x frame-size of
VRAM.

`oscilloscope` is five instruments in one shader, selected by a `mode`
parameter: waveform, spectrum, spectrogram, stereometer, bands. It is the most
expensive effect in the app by a wide margin, and the reason is not fully
explained - measured cost is flat across all five modes, which points at
register pressure in the uber-shader rather than at any one mode's maths. If
you profile it, use PIX or RenderDoc; guessing has been wrong three times.
`tunnel` is second, at ~48 raymarch steps per pixel, and that one IS explained.

**Line widths belong to the frame, not to the screen.** Anything drawn as a
stroke - a scope trace, a grid, an outline - has to be a fraction of frame
height, not a count of device pixels. The viewport is ~670 px tall and a 4K
export is 2160: a width fixed in device pixels is over three times thinner,
proportionally, in the export than in the preview, which is how the oscilloscope
came to "export black" at 4K while looking right on screen. Related: uv is
anisotropic, so a distance in uv has to be converted with the aspect before it
is compared against a width, or the same stroke changes weight with the export
aspect ratio. `oscilloscope.frag`'s `stroke()` and `hu()` are the reference.

The same rule holds for every SIZE an effect exposes, not only strokes. Blur
(Gaussian mode), Dither, Halftone, Post FX (halftone and dither), Terminal
scanlines, Cyanotype paper grain, the Risograph screen and Electron scan rows
all counted device pixels, so a 4K export drew them at a third of the size they
were set to on screen. They are now quoted against a 1080-tall reference
(`* u_resolution.y / 1080.0`, or a fixed count of 1080-based lines), which is
bit-identical at 1920x1080. **ASCII's scanline is the one exception left:**
`rift_parity` pins ASCII at 640x360 (`testdata/gold/golden.json`), so changing
it means regenerating the golden frames first.

Per-effect notes that are not obvious from the manifests:

- `glitch` multiplies every control through `is_active`, which is driven by
  audio. It has a 0.2 drive floor so it still does something with no track
  loaded; without it every slider read as broken.
- `fracture`'s master amount is `glitch_acc` (manifest label AMOUNT). It was
  missing from the manifest, `drawPass` zero-filled it, and the effect was a
  pass-through.
- `halftone`'s anti-alias width is one pixel PLUS `ht_soft`. As a `max()` the
  pixel floor swallowed the bottom half of the slider.
- ASCII's typed-glyph atlas was removed. Nothing ever uploaded `u_ascii_atlas`,
  and its count uniform was never in the manifest, so the branch could not run.
  Bringing it back needs a real atlas upload in `RhiContext`, not a uniform.

Shaders are compiled by Qt's `qsb.exe` at build time into `shaders/*.qsb`.

---

## 6. The interface

QML, in `qml/`. One `RiftViewport` C++ item; everything else is QML talking to
it through `Q_PROPERTY` / `Q_INVOKABLE`.

```
Main.qml
├─ AppMenu / StyledMenu          menu bar
├─ Dock (left)   NodeRail        the effect chain, drawn as nodes
│                ChannelMeters   the ten audio channels
├─ RiftViewport                  the picture
│  TransportBar                  play, seek, mark in/out, presets
├─ Dock (right)  ClipInspector   selected clip: blend, layout, transform
│                ControlPanel    MIDI / OSC          (Live first)
│                AudioInputPanel where the sound comes from
│                ColorPanel      master grade
│                ParamPanel      the selected effect's parameters
│                QueuePanel      batch renders       (React last)
├─ TimelinePanel                 React only
└─ ControllerView + MappingList  Live only, full width
```

Panel order differs by mode on purpose: Live puts the controller and the audio
source first, because those are what you set before a set starts; React puts
colour and parameters first and the render queue last.

Shared components worth reusing rather than reinventing: `SectionHeader` (the
disclosure header every dock panel uses), `FlatButton` (`small: true` for the
compact rows), `EditToolButton` (canvas-drawn editing icons), `ParamSlider`,
`ClipTrimHandle`, `AppDialog`, `StyledMenu`, `ToolTipArea`, and `Theme` - the
single source of colours, fonts and spacing.

The colour grade reuses the parameter controls rather than having its own.
`PatchRow` takes a `grade: true` flag and routes to the grade calls, and each
`ColorPanel` row is slider + disclosure + Key row + `PatchRow`, like a
`ParamPanel` row. The C++ side mirrors the chain-side API one for one:
`setGradeBinding`, `addGradeKey`, `removeGradeKeyAt`, `clearGradeKeys`,
`cycleGradeKeyInterp`, `keyGradeOnMarkers`, plus `gradeKeyedNow` /
`gradeKeyInterpNow`, which stay out of the `grade` model for the same reason
`keyedNow` stays out of `params`. The engine always supported this -
`LayerStack::applyGrade` resolves the grade through `resolve()` and the project
format round-trips its keys and bindings - there was just no way to reach it.

Every panel in a dock follows the same shape, and a new one should too:

```qml
Rectangle {
    property bool expanded: true
    implicitHeight: hdr.height + (expanded ? col.implicitHeight + Theme.padding * 2 : 0)
    clip: true                       // a Rectangle does not clip by default

    SectionHeader {                  // OUTSIDE the column, or it is inset by
        id: hdr                      // the padding and misaligns with the rest
        anchors { left: parent.left; right: parent.right; top: parent.top }
        title: "…"
        hint: "…"                    // what it is doing while closed
        expanded: parent.expanded
        onToggled: parent.expanded = !parent.expanded
    }
    ColumnLayout {
        id: col
        visible: parent.expanded
        anchors { left: parent.left; right: parent.right; top: hdr.bottom }
        anchors.margins: Theme.padding
        spacing: Theme.gap
    }
}
```

**Spacing comes from `Theme`, never from a number.** `padding` (16) around a
panel's content, `groupGap` (18) between unrelated groups, `gap` (10) between
controls, `gapTight` (6) between controls that belong to one another, and
`labelCol` (44) for the label column in the keyframe and patch strips. Before
this existed there were twenty-seven hand-picked 4s, 6s and 8s across thirteen
files, and no two rows in the app lined up with each other.

---

## 7. Feature list

**Composition**
- Multi-lane timeline: drag, trim from either edge, split at the playhead,
  copy/paste, duplicate, delete, stretch a clip over the whole track
- Clips snap to the start of the piece, the playhead, and any other clip's head
  or tail - ten pixels of pull, so it behaves the same at every zoom
- A dragged clip snaps to whole lanes and the target lane lights up
- A new clip lands on the first empty lane, so sources stack rather than queue
- Per-clip effect stacks as well as one shared chain
- Blend modes, opacity, position, scale, and a crop rectangle - so two clips
  can share the frame as split screen or picture-in-picture, with one-click
  layouts (full, left, right, top, bottom, corner)
- Text layers with any installed font
- Mark in / mark out for exporting a range
- Timeline zoom, and a time grid aligned to the ruler

**Reactivity**
- Ten audio channels, any uniform patchable to any channel with its own depth
- Keyframes per parameter, linear / ease / step
- The master colour grade takes keyframes and audio patches like any parameter
- MIDI CC and OSC in, learn-by-moving mapping, device-agnostic mapping list
- Live capture from any application's audio output. Only one sound source runs
  at a time: entering Live pauses the project track, and returning to React
  stops listening - otherwise both play at once and RIFT reacts to itself
  through the loopback

**Output**
- MP4 / MOV, 1080p / 2K / 4K, several aspect ratios
- Aspect ratio chosen when the project is created, not at export
- Render queue for batching
- Footage shorter than the audio loops rather than going black

**Comfort**
- Preset library, saved to app data and available in every project
- Themes, accent colour, text size, interface font
- Undo/redo, project save/load
- Worst-frame time readout (an average hides the stutter people actually see)

---

## 8. Build

### What you need

| | |
|---|---|
| Compiler | MSVC (Visual Studio 2022+), C++20 |
| Build | CMake + Ninja |
| Deps | vcpkg in manifest mode (`vcpkg.json`) - Qt 6 is built from source, which takes hours the first time |
| FFmpeg | BtbN's LGPL-shared build, pointed at by `-DFFMPEG_DIR` |
| Installer | Inno Setup (`iscc.exe` on PATH), optional |

### Development build

Configure with the vcpkg toolchain and build the `rift_shell` target. CMake
**silently ignores** a toolchain file if the build directory already has a
cache, so a fresh build directory has to be told, and a stale one has to be
deleted rather than reconfigured.

### Release build and installer

```
powershell -ExecutionPolicy Bypass -File packaging\build_release.ps1 -Zip -Installer
```

This is a separate `build-release` directory on purpose - reconfiguring the
development build as Release would rebuild Qt from scratch again. The script:

1. kills any running `rift*` process (they hold the DLLs the link is about to
   overwrite, which MSVC reports as a baffling LNK1168)
2. configures and builds Release
3. stages `dist/`: the exe, Qt DLLs, the QML plugin tree, the libav DLLs, the
   MSVC runtime (located through `vswhere`), shaders, fonts, and a `qt.conf`
4. smoke-tests the staged build **with a cleared environment**, so a missing
   DLL fails here rather than on someone else's machine
5. runs `packaging/check_deps.ps1`, which walks the whole import graph of every
   binary in `dist/` and reports anything resolved from outside it
6. zips, and optionally builds the installer

Two traps that cost several failed builds:

- `windeployqt` is **not** in the vcpkg Qt package. Everything it would do is
  done by hand in the script.
- Copying only the DLLs the exe links against is not enough. QML plugins are
  loaded at runtime and pull in Qt libraries nothing links to directly.

### Tests

`ctest` in the build directory. The ones that matter:

- `manifest` - every shader's manifest order matches its uniform block
- `parity` - shader output still matches the recorded reference frames
- `render`, `graph_render`, `export`, `export_hybrid` - end-to-end renders

The GPU tests construct a `QGuiApplication`, which aborts with 0xc0000409 ("no
Qt platform plugin") unless it can find `plugins/platforms`. `CMakeLists.txt`
sets `QT_PLUGIN_PATH` on each of them from `Qt6::QWindowsIntegrationPlugin`, so
`ctest -C Release` runs with no environment set and Debug gets the debug
plugins. If that abort comes back, check the rule is still there.

**A Visual Studio update rebuilds Qt.** VS ships its own CMake modules; when they
are newer than `generate.stamp`, the next build re-runs configure, configure
re-runs `vcpkg install`, and a new MSVC version invalidates the prebuilt Qt -
about two and a half hours from source (vcpkg lives at `D:\vcpkg`). Nothing in
the source causes it. After it finishes, rebuilds are back to a minute or two.

---

## 9. Layout on disk

```
RIFT_engine/
├─ src/                 engine, decode, audio, export
│  └─ ui/               the QQuickItem bridge and input
├─ qml/                 the whole interface
├─ shaders_qrhi/        .frag + .layout.json manifests
├─ shaders/             compiled .qsb (build output)
├─ fonts/               vendored interface font
├─ assets/              icon, .rc
├─ tests/               ctest binaries + reference frames
├─ packaging/           build_release.ps1, check_deps.ps1, rift.iss
└─ tools/               bench.ps1 and other measuring scripts

RIFT-release/           what actually ships: README, GUIDE, CHANGELOG,
                        screenshots. Binaries go to GitHub Releases, not into
                        the repo - the exe is over GitHub's 100 MB file limit.
                        THE ONLY GIT REPO of the three. RIFT_engine, the actual
                        source, is not under version control at all.
```

### Driving it without the mouse

`rift_shell.exe` takes enough flags to exercise most paths headlessly, which is
how the effects and the save formats get tested - there is no UI automation.
The ones that do something and then quit: `--export PATH`, `--queue PATH`,
`--save PATH` (project) and `--savepreset NAME` (look only, into the preset
library). Setup flags: `--media`, `--clip`, `--text`, `--audio`, `--analysis`,
`--chain a,b,c`, `--param I=V`, `--grade I=V`, `--key`, `--blend`,
`--nodeblend`, `--open`, `--map`, `--osc`, `--play`, `--live`.

Two things about running it from a script: it is a WINDOWS-subsystem binary, so
`console.log` from QML only reaches a redirected stderr with
`QT_FORCE_STDERR_LOGGING=1` set; and the built exe in `build-release/Release`
cannot start on its own (no Qt platform plugin - `windeployqt` is not in the
vcpkg package). Copy it over `dist/rift_shell.exe` and run it from there.

**File size is a usable regression signal for exports**, since nothing here
decodes frames back. A black 5 s 1080p60 export is about 30 KB, and a held still
compresses to almost nothing, so "is this effect exporting" is "is the file much
bigger than 30 KB", and a loop test is "N times the frames should be roughly N
times the bytes". That is how the 0.1.4 export and looping fixes were proven.

---

## 10. Known limits

- Windows only. The renderer is Direct3D 11 with no software fallback.
- Not code-signed, so SmartScreen warns on first run.
- **No SVG.** Decoding is FFmpeg, and an LGPL build has no SVG decoder, so a
  vector file loaded successfully and then rendered the placeholder
  checkerboard. It is refused at import with an explanation. Supporting it
  means linking Qt Svg and rasterising through `QSvgRenderer`, the way
  `text_source.cpp` already rasterises text.
- **A still image has no duration of its own.** FFmpeg reports one frame, which
  put a PNG on the timeline a few pixels wide with an edge too small to grab.
  `Timeline::spanOf_` treats anything under 0.2 s as a still and gives it the
  same nominal 5 s a text clip gets.
- **A live set cannot be rendered.** Export runs the same chain, but against
  the project's audio file - the loopback capture is not recorded anywhere. Two
  things would be needed: writing the captured stream to disk, and rendering
  against it instead of the project track.
- Oscilloscope is expensive, Stereometer mode especially, and the reason is
  not yet understood.
- Datamosh approximates the look; it cannot smear one shot into the next,
  because it has no access to the previous shot's motion vectors. It could now
  read `u_feedback_tex` for the previous frame, which is not motion vectors but
  is enough for a real smear - nobody has done it yet.
- `--queue` segfaults on teardown (exit 139) once the batch drains. It happens
  after the trailer is written, so the files are complete and valid; a single
  `--export` run exits 0. Not diagnosed.
- Docks swap sides rather than floating freely.
- The render queue always renders at 60 fps; the export dialog is the only
  place to pick a frame rate.
- Saving a preset under a name that already exists overwrites it without asking.
- The Oscilloscope ignores its input and replaces the frame. To lay it over
  footage, use the node's blend and mix.
- `src/api.cpp` is a 68-export C ABI with no consumer. It was the seam between
  the Python front end and the C++ engine during the rewrite. Harmless, and a
  candidate for deletion.

---

## 11. Conventions

- Comments explain **why**, not what. If a line looks wrong and is not, the
  comment says what goes wrong without it. Several comments in this codebase
  are bug post-mortems - do not delete them, they are the only record.
- Sentence case in the interface, not shouting.
- Plain hyphens, not em dashes, everywhere including documentation.
- The `Theme` singleton is the only place colours, fonts and spacing live.
- New effect = fragment shader + `.layout.json` + `.manifest.json` + one line in
  `effectIds`. Nothing else. CMake `file(GLOB)`s the shader directory, so a new
  shader needs a CMake **reconfigure**, not just a build, before it appears.

---

## 12. The 0.1.4 audit (15 September 2026)

Every effect, parameter and editing path was audited and 29 fixes shipped as
0.1.4 (installer + portable zip on GitHub Releases, CHANGELOG in RIFT-release).
The traps behind them are written up in sections 3, 5, 6 and 8; this is the
index.

- **Export.** The empty-track source is shared by every render path, so
  Tunnel, Lens, Kaleido and the rest no longer export black with no footage.
  Clip decoders loop, so short footage repeats instead of freezing. Eight
  shaders converted from device pixels to a 1080 reference.
- **Effects.** Glitch drive floor. Fracture AMOUNT exposed. Halftone Soft made
  additive. Dead declarations removed: ASCII's glyph atlas, Pixel sort's unused
  audio sampler.
- **Editing.** Shared-chain parking. Index fix-ups for `control_map_` and
  `edited_clip_`. `setEffect` syncs to the clip. Head trim moves `start`.
  `keyAtPlayhead_()`. "Key on beats" runs to the end of the music, not the
  footage. Audio data by copy + generation counter. Text layers auto-append.
  Queued renders keep the mark in/out they were queued with.
- **Interface.** Colour grade keyframes and patching. Dock `GridLayout` row pin.
  ClipInspector's stale style and wrong parent chain. Controller view activity
  flash. Deleting a preset no longer applies it.
- **Build.** `ctest` is self-sufficient.

How it was checked: all 8 ctests; a mechanical sweep of every shader comparing
manifest against `.layout.json` against the shader's `#define`s (count, order,
slot, whether each param and sampler is actually used, defaults in range, audio
channel keys valid); and headless exports measured by file size (section 9).

Left alone on purpose: ASCII's scanline (parity-pinned), the queue's fixed
60 fps, silent preset overwrite, and the Oscilloscope's unused `u_tex`.

---

## 13. The 0.1.5 release (October 2026)

- **Minimeters-Style Visualizer Suite**:
  - Unified 8192-sample rolling audio tap in `AudioSystem` for Oscilloscope, Spectrum Analyzer, Spectrogram, and Lissajous Vectorscope.
  - Sub-sample zero-crossing hysteresis trigger for Oscilloscope; logarithmic 20Hz-20kHz curve with dB-domain decay for Spectrum; 2D scrolling waterfall ring texture for Spectrogram; 45° mid/side stereo projection for Vectorscope.
- **Export & Rendering Parity**:
  - Ring-buffered per-pass uniform buffers (`parUbos[32]`) in `RhiContext` eliminating multi-pass parameter overwrite bugs.
  - Mirrored visualizer LUT textures to `export_engine` and initialized built-in default 8-row color table.
  - Ensured `applyPendingLoads_()` is executed synchronously at the start of `runExport_()`.
  - Loud error reporting on shader pipeline failures in `RenderGraph` (no silent fallbacks to checkerboard).
- **Brutalist UI & Design Spec**:
  - Rebuilt `Theme.qml` with tokens, Darker default theme, and fixed audio channel color mappings.
  - 0px corner radius enforced across all controls, dialogs, clips, and nodes.
  - 2px track sliders with 8px square thumbs and inline audio-mapping chips.
  - Standardized uppercase micro-labels and 28px panel/section headers.

---

## 14. The Figma UI Redesign & Timeline Overhaul (October 2026)

- **Figma Design System & Palette**:
  - Minimal brutalist UI with pitch dark `#000000`/`#0C0C0C` backgrounds and `#2B2B2B` control wells.
  - Non-duplicate distinct colors assigned to each of the 24 GPU shader effects in `Theme.qml` (`ascii`: `#E5D634`, `dither`: `#7B2FFF`, `tunnel`: `#FA1E22`, `risograph`: `#3CAEFF`, `glitch`: `#772985`, `blur`: `#857476`, etc.).
  - Top Bar: Centered RIFT Monogram logo (`assets/logo/PNG/WHT MONOGRAM@0.5x.png`), left-aligned menus, and glowing `#E5D634` `REACT` / `#D9D9D9` `LIVE` mode toggle buttons.
- **Left Dock (Chain & Presets)**:
  - Tabbed switching between `Effect Chain` and `Presets` in `NodeRail.qml`.
  - Effect Chain: Solid rectangular colored cards with preview thumbnail overlays (`assets/effect_previews/`), bold centered black text, and white bracket connectors.
  - Presets View: Categorized collapsible groups (`v FAV`, `> NEW STUFF`, `v Top Secrettttttttt`) with square preview thumbnail cards (`PresetGroup.qml`) and `+` save preset dialog.
- **Right Dock (Parameters & Levels)**:
  - Header title `◀ parameters` with header `+` button removed.
  - Parameter Sliders (`ParamSlider.qml`): Solid `#2B2B2B` rectangular tracks, channel-tinted/white progress fills, parameter name + channel tag, and `LINK` popup menu to route modulation to any audio channel (`Drums`, `Kick`, `Sub/Bass`, `Mids`, `Highs`, `Transient`, `None`).
  - Levels Panel (`ChannelMeters.qml`): 5-column vertical channel mixer meters with `#2B2B2B` background wells and vibrant channel token level fills.
- **Timeline Panel (`TimelinePanel.qml`)**:
  - Tool strip: Selection (`↔`), Text (`T`), Razor/Split (`✄`), and `+ Clip` buttons.
  - Styled track headers: Steel `V1` (`#3F5260`), olive `A1` (`#3A5236`), with `#2B2B2B` track beds.
  - Bottom horizontal navigator scrollbar (`#2B2B2B` track, `#D9D9D9` thumb) for scrubbing and zoom control.
- **Dialogs & Popups**:
  - `AppDialog.qml`, `ExportDialog.qml`, `ExportProgressDialog.qml`, and `NewProjectDialog.qml` restyled to match the dark 0px radius aesthetic with `#2B2B2B` wells.

---

## 15. The 0.1.6 Release (October 2026)

- **Timeline Toolbar Unification**:
  - Replaced text buttons (`+ Clip`, `+ Audio`) with standardized `EditToolButton` components with vector art.
  - Added "Stretch until end" (`stretch_end` / `| <-> |`) action tool button.
  - Standardized all 9 toolbar buttons to 28×24 rounded rectangles (radius 4px) with high-contrast `#9A9A9A` fill, `#D0D0D0` hover, and solid `#000000` vector iconography (`select`, `text`, `razor`, `stretch_end`, `copy`, `paste`, `add_clip`, `add_audio`, `remove`).
- **Audio Meter Proportions**:
  - Meter wells shortened and bottom channel tag labels (`BAS`, `MID`, `HIG`, `DRM`) spaced with an 8px vertical margin, eliminating overlap.
- **Parameters Panel Polish**:
  - Removed hairline horizontal separator lines between uniform controls for a clean, unified inspector.
  - Added automatic title capitalization on uniform labels (`Columns`, `Charset`, `Bright`, `Color`, `Dot size`).
  - Increased spacing on parameter slider headers between value readout, audio patch channel, and `LINK` button.
  - Widened right dock default from 300px to 330px (`minWidth: 280px`) for improved desktop breathing room.
- **Packaging & Distribution**:
  - Bumped project version to `0.1.6` across CMake, Inno Setup script (`packaging/rift.iss`), and documentation.
  - Inno Setup compiler generation for `dist-installer/RIFT-0.1.6-setup.exe`.

