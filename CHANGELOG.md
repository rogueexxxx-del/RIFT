# Changelog

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
