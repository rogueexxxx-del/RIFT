# Changelog

## 0.1.3 - 10 August 2026

Nine new effects, the feedback loop that three of them needed, and a fix for the
Oscilloscope disappearing at high output resolutions.

### New

- **Feedback texture.** Shaders can now read the previous finished frame. This
  was declared in the code and never wired up - a shader asking for it was
  silently handed a 1x1 black pixel. Three of the new effects need it, and
  Datamosh is the next in line to use it.
- **Kaleido** - polar mirror, wedges folded around a movable centre. Segment
  count is patched to Snare, so it snaps on a hit.
- **Mirror tile** - the same on a rectangular grid, with four mirroring modes.
- **Flow warp** - domain-warped noise. The molten, liquid look; the field runs
  through itself twice so the currents fold instead of sliding as one sheet.
- **Voronoi shatter** - the frame breaks into cells that slide apart on a
  transient and snap back.
- **Dot field** - a grid of shaded dots lifted out of the picture by brightness.
- **Tunnel** - a raymarched corridor with the footage projected onto the wall.
- **Lens** - barrel distortion, radial colour fringing, anamorphic streak,
  vignette.
- **Bloom** - threshold, spread, add back, with a tint that colours only the
  glow.
- **Feedback** - last frame laid under this one. Trails and echo tunnels.
- **Slit scan** - time displacement, each column from a different moment.
- **Post FX** is now in the effect picker. It was in the app all along and
  unreachable from the interface.

### Fixed

- **The Oscilloscope faded out at 4K and changed weight with the aspect ratio.**
  Line and grid widths were held at a fixed number of *device pixels*, which is
  right for something drawn on screen and wrong for a rendered frame: the same
  trace that is bold in the viewport is a third as thick, proportionally, in a
  2160-tall export, and the hairline grid vanished entirely. Widths are now a
  fraction of the frame height, floored at one real pixel. Separately, distances
  were measured in raw uv and converted using the height alone, so a steep part
  of the trace thinned on a wide frame and thickened on a tall one.

### Removed

- **Noise field** and **Fracture** are no longer offered in the effect picker.
  Existing projects that use them still load and render.

## 0.1.2 - 1 August 2026

Second and third rounds of testing fixes. Everything on the list from the last
round is in, and the timeline was largely rebuilt.

### Fixed

- **A terminal window opened alongside the app.** The executable was being
  linked as a console program, so Windows gave it a console every launch.
- **The timeline stuttered.** With it on screen the worst frame was 251 ms;
  hidden, 33 ms. A per-frame check compared the track length with a tolerance
  of about a picosecond, so a duration wobbling in its last bits rebuilt the
  entire clip model on every single frame. Worst frame is now around 30 ms and
  React sits within a couple of frames per second of Live.
- **The three dots beside a parameter did nothing.** They drew, but their
  container had no height, and a zero-height item receives no clicks.
- **Exporting was far slower than it needed to be.** Every render pass opened
  its own GPU frame, and each one is a submit followed by a wait for the card to
  drain - so a chain of three effects paid three full stalls per frame on top of
  the audio uploads and the readback. The whole frame is now one submit, and a
  three-effect chain costs the same as one.
- Audio textures were uploaded in two separate GPU submissions per frame instead
  of one.

### New

- **Preset library.** Save the current look and pick it back out of a list.
  Presets live in your app data, so they are there in every project.
- **Duplicate clip**, effects and all.
- **Seek buttons** either side of play, five seconds at a time.
- **Mark in / mark out** for exporting a range.

### Changed

- **Sliders** have a real handle instead of a filled box, so the value is
  visible and the control looks draggable.
- **One transport, not two.** Live mode had its own play/pause under the
  controller as well as the one under the viewport.
- **Panels are ordered per mode** - Live puts the controller first, React puts
  colour and parameters first with the render queue last.
- **Export defaults to 30 fps**, which halves both render time and file size
  against 60.

### The timeline

- **Trimming did nothing until you let go of the mouse.** The edge handle only
  reported its drag on release, so pulling a clip edge felt like the grab had
  never registered. Both edges now follow the pointer live.
- **Clips lagged behind the cursor while dragging.** The drag distance was
  measured in the coordinate system of the item being dragged - which moves as
  it is dragged, so each measurement cancelled part of its own effect. Clips,
  clip edges and keyframes all sit under the pointer now.
- **Dropping onto a lane was guesswork.** A dragged clip floated between rows.
  It snaps to whole lanes, and the lane it will land on lights up.
- **Snapping.** Clips pull to the start of the piece, the playhead, and the
  head or tail of any other clip - ten pixels of pull, so it feels the same at
  every zoom.
- **Edge handles are wider** (7px was narrower than a cursor's hot zone) and
  show grip marks and a resize cursor.
- **A new clip lands on the first empty lane** instead of being appended after
  whatever is already on V1.
- **Razor, copy, paste, fill and remove** as icon buttons on the toolbar.

### Live

- **Audio from any application.** Pick an output device and RIFT reacts to
  whatever it is playing - a DAW, a browser, a player. No virtual cable, no
  plugin. The device list refreshes when you open it, so a DAW started after
  RIFT still appears.
- **Two sound sources could play at once.** Live listens to the machine's
  output while React plays the project track, so you heard both - and RIFT
  could react to its own output. Switching modes now stops the other one.
- **Footage can be imported with the timeline hidden**, which was previously
  impossible in Live.
- **One source picker**, not two disagreeing ones.
- **A mapping list that works with any controller**, beside the drawn one.

### Composition

- **Split screen and picture in picture.** A clip carries a crop rectangle as
  well as a transform, and the clip inspector has one-click layouts: full,
  left, right, top, bottom, corner.
- **Aspect ratio is chosen when the project starts**, not at export - composing
  against the wrong frame and finding out at the end means redoing the work.
- **Preset library**, saved to your app data and available in every project.
- **Stills can be stretched.** A PNG reports one frame of duration, so it
  landed on the timeline a few pixels wide with an edge too small to grab.

### Interface

- **Every dock panel is a collapsible section** with the same header: click
  anywhere on the row, and a closed section still reports what it is doing.
- **Effect chain drawn as nodes** with ports and a signal path, rather than a
  list of boxes.
- **Consistent spacing.** Twenty-seven hand-picked gap values across thirteen
  files meant no two rows in the app lined up; they now share one token.
- Smaller slider handles, a larger and easier-to-hit disclosure control, and
  compact buttons in the keyframe and patch strips.

### Also fixed

- **Effects silently did nothing when a blend mode was set.** The compositor
  gained crop parameters and two callers were still passing the old count, so
  the crop arrived as zero and the shader discarded every pixel.
- **The three dots beside a parameter did nothing.** The property they wrote to
  was declared on the wrong object, so every click was a no-op.
- **SVG files loaded and rendered as a placeholder checkerboard.** Decoding is
  FFmpeg, which has no SVG decoder in an LGPL build. They are no longer offered,
  and loading one says why.

## 0.1.1 - 31 July 2026

Fixes from the first round of testing.

### Fixed

- **Exports stopped when the footage ran out.** A 4 second clip under a 2 minute
  track rendered a few seconds of picture and then two minutes of black. Footage
  shorter than the piece now loops. Keyframes and audio reactivity keep running
  forward on real time, so only the picture repeats.
- **Export length ignored the audio** unless a pre-analysis file was present, so
  a render could come out as long as the clip instead of as long as the track.
  It now uses the decoded length, and runs to whichever of audio or footage is
  longer.
- **An effect could not be changed.** The only way to swap one was to add a
  second effect and delete the first. Selected effects now carry a button that
  reopens the picker and replaces them.
- **Right-clicking a clip deleted it instantly.** It asks first.
- A clip could be dragged to a negative start time, where it stopped following
  the mouse with no explanation.

### Changed

- **Mark in / mark out.** Set a range on the timeline and the export renders
  only that. Everything outside the marks is dimmed so the range is visible
  without opening a dialog.
- **Effect settings are no longer a wall of controls.** Every parameter used to
  draw four rows; now it draws one, and the keyframe, audio and MIDI controls
  open for the parameter you are working on.
- **The timeline reads like a timeline** - filled lane beds so an empty lane is
  a visible target, a time grid aligned to the ruler, taller lanes, a usable
  keyframe lane, and a playhead with a head you can see. Clips are tinted with
  an accent edge instead of a solid block that drowned their name.
- **MIDI controls light up when they send**, so a controller confirms itself
  where you are looking instead of on the far side of the window.
- **The frame-rate readout** is a chip that matches the rest of the interface
  rather than loose red text.
- Plain hyphens instead of em dashes throughout.

## 0.1.0 - 31 July 2026

First build shared for testing.

### New

- **Five new effects** - Cyanotype, Electron scan, Risograph, Thermal camera,
  Terminal. Fifteen in total.
- **Oscilloscope rebuilt** as five instruments in one: waveform, spectrum,
  spectrogram, stereometer, bands. Flat instrument styling rather than a CRT,
  with five colour palettes.
- **New project dialog** on launch - name it, point it at audio and footage.
- **Fonts** - the interface font is now yours to choose from anything installed
  on the machine, and text layers get their own font picker with each family
  previewed in its own face.
- **Preferences** - theme, accent colour, text size, per-region colours.
- **Export** - 1080p / 2K / 4K, several aspect ratios, and a progress dialog you
  can keep working behind.
- **Keyboard shortcuts** drawn on a keyboard instead of listed as text.
- **Frame-time readout** - shows the *worst* frame over a rolling window, not
  just an average, because an average hides exactly the stutter people notice.

### Fixed

- **Audio reactivity did not work without a pre-analysis step.** Loading an
  ordinary audio file left all ten channels reading zero - every meter flat and
  every audio-driven control dead. Channels are now derived from the live signal
  when no analysis file is present. *This was the largest problem in the app.*
- **The viewport looked soft and blocky.** It rendered at logical pixel size and
  was then stretched to the real framebuffer, which lost resolution on any
  display running above 100% scaling. It now renders at full device resolution.
- **Exported text used the wrong font.** The exporter registers fonts separately
  from the interface, so a text layer that looked right on screen came out in a
  system fallback face.
- **Oscilloscope drew nothing.** Its audio textures were matched by binding
  number, which collided with another shader, so it silently sampled a blank
  1×1 texture.
- **Effect picker opened behind the viewport.** It now opens above everything,
  and has a search box.
- Spectrum and level meters were drawn upside down.
- Band meters read zero without a pre-analysis file.
- Menus and dialogs showed a pale border from the default widget style.
- Interface text was in capitals throughout.

### Changed

- The project name is shown in the window title bar rather than inside the app.
- Effect settings are sentence case, not shouted.
- Side panels collapse, resize and can swap sides; the arrangement persists.

### Known limitations

- Not code-signed - Windows SmartScreen warns on first run.
- Windows only; the renderer is Direct3D 11 with no software fallback.
- The Oscilloscope is the most expensive effect, Stereometer especially.
- Datamosh approximates the look; it cannot smear one shot into the next.
- Panels swap sides rather than floating freely.
