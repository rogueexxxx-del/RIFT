# RIFT Engine Test Plan (Release v0.1.9)

## Overview
Comprehensive test suite covering RIFT core user flows, edge cases, stability, and UI verification.

---

### Flow 1: Project Management (F01)
- **F01-H1 (Happy path - New Project)**: Launch app without arguments. New project initializes with empty timeline, default aspect ratio 16:9, clean master effect chain.
- **F01-H2 (Happy path - Save Project)**: Save project via Ctrl+S / File > Save. Output `.rt` contains clips, audio tracks, keyframes, master chain, and per-clip chains.
- **F01-H3 (Happy path - Open Project)**: Open existing project. All clips, positions, per-clip chains, and master chains restore accurately.
- **F01-E1 (Edge case - Blank Project Export)**: Attempt export with zero clips. Exporter reports graceful error or handles empty timeline without crash.
- **F01-N1 (Negative case - Corrupt file load)**: Open malformed `.rt` file. Error logged gracefully, engine stays responsive.

---

### Flow 2: Media & Playback Transport (F02)
- **F02-H1 (Happy path - Video Playback)**: Import MP4/MOV footage. Spacebar toggles Play/Pause smoothly.
- **F02-H2 (Happy path - Transport Bar)**: Seek +/-5s, Stop (returns to 0.0s), timecode updates accurately.
- **F02-H3 (Happy path - Effect Freeze on Pause)**: Pause video during animated effect (feedback loop, oscilloscope). Frame rendering and audio analysis freeze completely.
- **F02-E1 (Edge case - Rapid Play/Pause toggling)**: Hammer Spacebar 10 times in 1 second. No audio underrun, no deadlocks, state stays consistent.
- **F02-E2 (Edge case - Seek out of bounds)**: Seek past duration or before 0. Clamped smoothly.

---

### Flow 3: Timeline & Editing Tools (F03)
- **F03-H1 (Happy path - Clip Placement & Selection)**: Drag clip across lanes V1-V3. Snapping aligns to grid when Snap is enabled; smooth dragging when Snap is off.
- **F03-H2 (Happy path - Razor Tool)**: Press 'C' or click Razor Tool button. Red cutting line tracks mouse with crosshair cursor. Clicking cuts clip into two independent slices. Press Esc to return to Selection.
- **F03-H3 (Happy path - Per-Clip Chain Independence)**: Split a video clip. Select Clip 1 and add Fracture effect. Select Clip 2 and add ASCII effect. Both clips render their distinct effects independently without polluting each other or the Master FX chain.
- **F03-E1 (Edge case - Multiple Rapid Cuts)**: Slice a clip into 8+ small segments. No visual glitches, no stuck drop lane highlights, no crashes.
- **F03-E2 (Edge case - Razor click on empty lane)**: Click empty timeline area with Razor tool. No cut happens, deselects any active clip cleanly.

---

### Flow 4: Node Rail & Effect Chain (F04)
- **F04-H1 (Happy path - Master Chain)**: Add effects (Bloom, Halftone, Glitch) to Master chain. Effects composite in order.
- **F04-H2 (Happy path - Node Right-Click Context Menu)**: Right-click any effect node in NodeRail. Context menu appears with "Change Effect...", "Duplicate Effect", "Reset Parameters", "Delete Effect".
- **F04-H3 (Happy path - Replace Effect)**: Select "Change Effect...". Pick new effect. Parameters update, node replaces seamlessly.
- **F04-H4 (Happy path - Master vs Clip Banner)**: Selecting clip shows "CLIP X FX" banner with "Master FX" return button. Clicking returns to Master chain.

---

### Flow 5: Audio Reactivity & Oscilloscope (F05)
- **F05-H1 (Happy path - Audio Import & Mixing)**: Import audio file. Waveform draws in audio lane, mixer audio plays through output device.
- **F05-H2 (Happy path - Reactive Modulation)**: Map Bass/Kick/Centroid to effect parameter. Slider modulates in sync with audio beats.
- **F05-H3 (Happy path - Oscilloscope & Minimeters)**: Switch effect to oscilloscope. Live waveform and FFT spectrum render cleanly.
- **F05-E1 (Edge case - Video with no audio track)**: Load video without placing audio clip. Transport clock runs on steady_clock fallback smoothly without stalling.

---

### Flow 6: Export & Rendering (F06)
- **F06-H1 (Happy path - Video Export with Watermark)**: Open Export dialog. Default includes watermark. Video renders to MP4 with RIFT watermark.
- **F06-H2 (Happy path - Video Export without Watermark)**: Toggle watermark button to disabled. Video renders completely clean without any watermark overlay.
- **F06-E1 (Edge case - Cancel Export)**: Click cancel midway through export. Background thread cleanly terminates, temporary files cleaned up.

---

### Flow 7: Visual & UI Polish (F07)
- **F07-H1 (Top Menu Bar Logo)**: Monogram glyph logo (`Theme.monogram`) displayed centered in the top bar, sharp and without full wordmark text.
- **F07-H2 (About Dialog Logo)**: About dialog displays full official RIFT wordmark logo with crisp proportions.
- **F07-H3 (Toolbar Buttons)**: Timeline tool buttons and keyframe buttons use refined dark theme styling (`#181818` / `#262626` / `Theme.accentSoft`) without clunky grey blocks.
- **F07-H4 (Clip Aesthetics)**: Timeline clips have clean rounded cards without artificial 3px vertical red stripes. Drop lanes only highlight during active drag.
