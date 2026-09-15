# RIFT - user guide

Everything the app does, in the order you'd meet it.

---

## Contents

1. [First launch](#1-first-launch)
2. [The layout](#2-the-layout)
3. [Bringing in media](#3-bringing-in-media)
4. [Effects](#4-effects)
5. [Making it react to the music](#5-making-it-react-to-the-music)
6. [Keyframes](#6-keyframes)
7. [The timeline](#7-the-timeline)
8. [Text layers](#8-text-layers)
9. [Colour grading](#9-colour-grading)
10. [Live mode and MIDI](#10-live-mode-and-midi)
11. [Exporting](#11-exporting)
12. [Projects and presets](#12-projects-and-presets)
13. [Making it yours](#13-making-it-yours)
14. [Keyboard shortcuts](#14-keyboard-shortcuts)
15. [Effect reference](#15-effect-reference)
16. [When something goes wrong](#16-when-something-goes-wrong)

---

## 1. First launch

RIFT opens on a **New project** dialog. Name the project, and optionally point it
at an audio file and a video or image. Both are optional - **Start empty** drops
you straight into the app.

The audio is what everything reacts to. You can add it later from
**File ▸ Import audio…**, but adding it first means the timeline shows the
waveform and the beat markers immediately.

> **A note on audio:** you don't need to pre-analyse anything. Load a normal
> `.wav` or `.mp3` and the ten reactive channels start working straight away.

---

## 2. The layout

| Region | What lives there |
|---|---|
| **Top menu** | File, Edit, View, Help |
| **Mode switch** | React / Live, centred above the viewport |
| **Effects** (left) | The effect chain, source at top, output at bottom |
| **Channels** (bottom left) | The ten audio channels, as live meters |
| **Viewport** (centre) | What you're making |
| **Settings** (right) | Controls for the selected effect |
| **Timeline** (bottom) | Clips, audio waveform, beat markers, keyframes |

**Both side panels collapse.** Click the `‹` in a panel's title bar to fold it
away and give the picture more room; click the strip to bring it back. The `⇥`
button moves a whole panel to the other side of the window. Drag a panel's inner
edge to resize it. The arrangement is remembered between sessions.

The top-right corner shows the frame rate and the **worst** frame time over the
last few seconds. If that number goes amber or red, something in your chain is
too expensive - see [When something goes wrong](#16-when-something-goes-wrong).

---

## 3. Bringing in media

**File ▸ Import video or image…**, or the **+ Clip** button under the timeline.

Anything FFmpeg can open works: mp4, mov, mkv, avi, webm, gif, png, jpg, webp,
bmp, tif, svg and more. You are not limited to the formats listed in the file
dialog - pick *All files* if what you want isn't shown.

**Clips live on lanes.** Lane V1 is the bottom, V2 sits above it, and so on.
Where clips overlap in time, the **higher lane wins** unless you blend them.

- **Drag the middle** of a clip to move it in time
- **Drag an edge** to trim it
- **Drag up or down** to change lane
- **Right-click** to remove it

Click a clip to select it. The **Clip** panel on the right then controls that
clip specifically: blend mode, opacity, position, scale.

**Blend modes** decide how a clip combines with what's beneath: normal, add,
multiply, screen. *Add* is the one that makes light stack up and is usually what
you want for anything glowing.

---

## 4. Effects

The **Effects** panel on the left is a signal chain read top to bottom:
**Source → your effects → Output**.

- **`+`** adds an effect. The picker has a search box - type three letters
  rather than scanning fifteen entries.
- **Drag an effect up or down** to reorder it. Order matters: blur *then*
  ascii looks nothing like ascii *then* blur.
- **Drag it sideways out of the rail** to remove it.
- Click an effect to edit its settings on the right.

**Shared chain vs per-clip chain.** By default the chain applies to everything -
the header reads *Chain · all clips*. Click a clip on the timeline and the header
becomes *Chain · this clip*; now you're editing that clip's own stack. This is
how you give two clips completely different looks.

**Node blending.** Each effect has a small blend control (NORM / ADD / MULT /
SCRN / DIFF / OVER / SUB) and a **Mix** slider. Mix at 100 is the effect at full
strength; pull it back to blend the effect with the image going into it. This is
the single most useful control for making an effect look deliberate rather than
switched-on.

---

## 5. Making it react to the music

This is the point of the app.

Every slider can be driven by the audio. Under each one is a **Patch** row:

1. Click **Static** - it opens the channel list
2. Pick a channel (Bass, Mids, Highs, Drums, Transient, Kick, Snare, BPM,
   Centroid, Time)
3. Set **Depth** - how far the audio pushes the value

The slider then shows `~` to mark it as audio-driven. **Unpatch** returns it to
manual.

**The ten channels**, shown as meters at the bottom left:

| Channel | What it follows |
|---|---|
| BAS | Bass, roughly 20-250 Hz |
| MID | Mids, 250-2000 Hz |
| HIG | Highs, 2 kHz and up |
| DRM | Overall percussive movement |
| TRN | Transients - sharp attacks |
| BPM | Tempo |
| CEN | Spectral centroid - how bright the sound is |
| TIM | Time, a steady ramp |
| KIK | Kick drum |
| SNR | Snare |

**Depth is the knob that matters.** Small depths read as the image breathing with
the track; large depths read as strobing. Start small.

---

## 6. Keyframes

Audio reactivity handles *feel*. Keyframes handle *structure* - a value that has
to be exactly this at exactly that moment.

Under each slider, the **Key** row:

- **`+`** drops a key at the playhead with the current value
- **Linear / Ease / Step** sets how it travels to the next key
- **Delete** removes the key at the playhead, **Clear** removes all of them
- **Beats** keys the parameter on *every detected beat* in one action

Keyed parameters show `*`. **Keyframes and audio reactivity stack** - the keys
set the base value and the audio modulates on top, so you can automate a sweep
and still have it pulse.

The **KEY** lane on the timeline shows every key for the selected effect. Drag one
sideways to retime it; right-click to delete.

---

## 7. The timeline

- **Click or drag the ruler** to scrub
- **Ctrl + mouse wheel** zooms around the cursor; plain **wheel** pans
- **`−` / `+` / `Fit`** at the right for zoom
- **AUD lane** draws the audio waveform
- **KEY lane** shows keyframes for the selected effect

**Beat markers.** **View ▸ Detect beats** finds the beats and draws them on the
ruler. With **Snap to beats** on, dragging a clip locks it to them - the fastest
way to get cuts landing on the music.

---

## 8. Text layers

**+ Text** under the timeline, or **File ▸ Add text layer**.

A text layer is a clip like any other: it sits on a lane, takes effects, blends,
and can be audio-reactive. The **Clip** panel gives you:

- The text itself
- **Font** - any font installed on your machine, previewed in its own face
- Size, position, tracking, bold
- Colour presets

Because it's a normal clip, running an effect over it is how you get reactive
type - put `glitch` or `datamosh` on a text layer and patch the amount to Snare.

---

## 9. Colour grading

**View ▸ Colour grade** opens a master grade applied after everything else:
exposure, lift, gamma, gain, contrast, saturation, temperature, tint.

The header turns accent-coloured and reads *graded* whenever the grade is doing
anything - a control off its default, patched to audio, or carrying keyframes -
so you always know it's active. **Reset** returns to neutral and clears patches
and keys too. A neutral grade costs nothing - the pass is skipped entirely.

Grade controls are real parameters, so they take keyframes and audio patching
like everything else. Click the **dots** beside a slider to open the same Key and
Patch rows an effect parameter has: key the grade at the playhead, key it on
every beat, or patch Exposure to the kick so the whole frame flashes on a hit.

---

## 10. Live mode and MIDI

Switch to **Live** at the top (or press **2**).

Live mode is for performing rather than building: no timeline, controls sized for
using while looking at something else, and audio taken from an input device
instead of a file.

**Connecting a controller:**

1. **Scan** finds connected MIDI devices
2. Pick yours - an **Arturia MiniLab mk II** is drawn with its real knob and pad
   layout
3. Press **Map**, then move a control and click the parameter you want it on

Mappings are saved with the project. **OSC** works the same way - set a port,
press **Listen**, and send OSC messages to that address.

---

## 11. Exporting

**File ▸ Export video…** (or **Ctrl+E**).

- **Resolution** - 1080p, 2K, 4K
- **Aspect ratio** - 16:9, 4:3, 1:1 and others
- **Quality** - High, YouTube, Archive (ProRes), Preview

A progress dialog shows percentage and a Cancel button. **The app stays usable
while it renders** - the export runs on its own engine, so you can keep working.

**Render queue** (**File ▸ Render queue**) batches jobs: set up several exports
and run them in sequence, which is how you export the same piece at several
resolutions without babysitting it.

> ProRes always writes `.mov` regardless of the extension you type - that's the
> only container that carries it.

---

## 12. Projects and presets

Projects save as **`.rt`**.

- **File ▸ Save / Save as…** - everything: clips, chains, keyframes, grade,
  mappings, mode
- **File ▸ Save preset…** - the *look* only

A preset carries the effect chain, its parameters, the colour grade and your
controller mappings. It deliberately does **not** carry clips, the audio track,
markers or which mode you were in - those belong to the piece, not to the look.
Applying one drops your look onto whatever is already loaded and changes nothing
else.

**Editing a preset does not change the preset.** Applying one is a starting
point: tweak whatever you like afterwards and Save still writes to your project.
The saved preset only changes when you explicitly save over it by name.

Both use the same `.rt` file format, so there is no second format to learn -
they differ in what is written into them.

**Undo/redo** covers timeline and parameter edits. The Edit menu names what it
will undo.

---

## 13. Making it yours

**Edit ▸ Preferences**:

- **Theme** - Dark, Darker, High contrast, Light
- **Accent** - the highlight colour used throughout
- **Text size** - Small through Largest
- **Interface font** - any font on your machine, each previewed in its own face
- **Custom surfaces** - per-region colours, for people who want them

The font changes immediately. **Restart app** re-measures every panel against it,
which matters for fonts with unusual metrics. Save your project first.

---

## 14. Keyboard shortcuts

**Help ▸ Keyboard shortcuts** draws them on a keyboard rather than listing them -
the point is showing where your hands go.

| Key | Does |
|---|---|
| `Space` | Play / pause |
| `1` / `2` | React mode / Live mode |
| `Ctrl+N` | New project |
| `Ctrl+O` | Open |
| `Ctrl+S` | Save |
| `Ctrl+E` | Export |
| `Ctrl+Z` | Undo |
| `Ctrl+Y` / `Ctrl+Shift+Z` | Redo |
| `Ctrl` + wheel | Zoom the timeline |
| Wheel | Scroll the timeline |

---

## 15. Effect reference

Fifteen effects. Every one has a **Mix** control, and every slider can be
keyframed and audio-patched.

### Pattern and dither

| Effect | What it does |
|---|---|
| **Ascii** | Redraws the image as text characters. Columns, charset, brightness, colour, dot size. |
| **Halftone** | Print-style dot screen. Scale, angle, contrast, softness. |
| **Dither** | Reduces to few colours with ordered dithering - the early-computer look. |
| **Risograph** | Duplicator printing: two to four spot inks, each its own halftone pass, deliberately misregistered. Raise **Misreg** and patch it to Transient. |
| **Terminal** | A CRT text terminal - character cells, phosphor colour, scanlines, screen curvature. |

### Glitch and damage

| Effect | What it does |
|---|---|
| **Glitch** | Block displacement and colour bleed, triggered by transients. |
| **Pixel sort** | Sorts pixels along a direction by brightness. Slower than most; expect it. |
| **Datamosh** | What a codec does with its keyframes deleted - macroblocks smearing, colour tearing, I-frame snaps. **Persist** is the one that matters: above zero, blocks are dragged from the previous frame, so one shot bleeds into the next. **I-frame** lets the real picture back in - patch it to Kick. |

### Photographic and scientific

| Effect | What it does |
|---|---|
| **Cyanotype** | Sun-print process. A blue negative on rag paper, with wash blotches and edge burn. |
| **Thermal cam** | False-colour infrared. Four palettes; **Cold** and **Hot** set the range and matter more than the palette. |
| **Electron scan** | Scanning electron microscope - greyscale, glowing edges, beam drift, charge bloom. |
| **Blur** | Gaussian blur with several modes. |
| **Lens** | The camera itself - barrel distortion, radial colour fringing, an anamorphic streak off the highlights, vignette. **Fringe** grows with distance from centre, so the middle stays clean. |
| **Bloom** | Threshold, spread, add back. Unlike Blur it keeps the picture and lays light over it. **Tint** colours only the glow. |

### Symmetry

| Effect | What it does |
|---|---|
| **Kaleido** | Folds the frame into wedges around a movable centre, mirroring alternate ones so the seams meet. **Segments** is patched to Snare by default, so the count snaps on a hit. |
| **Mirror tile** | The same idea on a rectangular grid. **Mode** picks plain repeat, mirror X, mirror Y or the four-way quad. |

### Motion and time

| Effect | What it does |
|---|---|
| **Flow warp** | Domain-warped noise - the molten, liquid look. The field is fed through itself twice, which makes currents that fold rather than one sheet sliding. Warp/Speed/Chroma are patched to Bass/Mids/Highs. |
| **Feedback** | Last frame, transformed slightly, laid under this one. Trails, echo tunnels, dye smear. Keep **Decay** below 1.0 - at 1.0 nothing is ever lost and the frame saturates to white. |
| **Slit scan** | Time displacement: each column shows a different moment. Builds its history as it plays, so give it a couple of seconds of run-up. |

### Geometry

| Effect | What it does |
|---|---|
| **Voronoi shatter** | Breaks the frame into cells that slide apart and snap back. **Split** is patched to Transient, which is what makes it read as an impact. |
| **Dot field** | A grid of shaded dots lifted out of the picture by brightness. Not Halftone - these have depth and shading rather than varying size on a flat plane. |
| **Tunnel** | A raymarched corridor with the footage projected onto the wall. The second most expensive effect after the Oscilloscope. |

### Finishing

| Effect | What it does |
|---|---|
| **Post FX** | The catch-all output pass - vignette, grain, scanlines, dither, halftone dot, glass refraction, and a feedback tracker. Twenty parameters; most projects use three of them. |

### Audio visualisation

| Effect | What it does |
|---|---|
| **Oscilloscope** | Five instruments in one, chosen with **Mode**. |

**Oscilloscope modes:**

| Mode | Shows |
|---|---|
| 0 - Wave | The waveform, locked to a zero crossing so it holds still |
| 1 - Spectrum | Frequency bars with a peak-trace outline |
| 2 - Spectrogram | Frequency over time, scrolling |
| 3 - Stereometer | Mid/side cloud with a correlation meter |
| 4 - Bands | Level per frequency band |

**Palette** switches all five between Magma, Ice, Acid, Ember and Mono. **Gain**,
**Line**, **Tilt**, **Fill** and **Grid** shape the drawing. Tilt lifts the high
end so a full-range mix reads flat instead of falling away.

---

## 16. When something goes wrong

**Nothing reacts to the audio.** Check the Channels meters at the bottom left. If
they're flat: is audio loaded, and is it playing? The channels only move while
the playhead does.

**A scope shows a flat line.** Same cause - no audio, or paused. A steady tone
also *looks* still in Wave mode, because the trace is deliberately locked to the
waveform so it doesn't slide around.

**The picture stutters.** Watch the *worst* figure top-right. Amber means frames
are missing 60 fps, red means 30. Usual causes: too many effects stacked, or the
Oscilloscope, which is the most expensive effect in the app - particularly
Stereometer. Fewer effects, or a smaller window.

**Windows says "Windows protected your PC".** The app isn't code-signed. Click
*More info → Run anyway*. Some antivirus will also flag a new unsigned program.

**It won't start at all.** You need Windows 10/11 64-bit and a GPU supporting
Direct3D 11 (anything from roughly 2012). There's no software fallback.

**An export came out wrong.** ProRes ("Archive") always writes `.mov`. For
everything else, check the resolution and aspect ratio in the export dialog -
they default to the project, not to the source.

---

*Built by Revanth Rangisetti. Designed by a human, written with AI.*
