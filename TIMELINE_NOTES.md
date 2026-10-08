# RIFT Timeline Rework Notes

## Phase 0 Findings
- Data Model: `ClipSpec` & `AudioClipSpec` store `start`, `in`, `out` (sec), `lane`, `gain`, `link`.
- Render Order: `Timeline::activeAt()` composites bottom lane (V1) to top (Vn); gaps show empty black.
- Controls: "Snap 493" = beat snap toggle (493 beats), "Aud" = separate waveform, "Key" = 1 shared lane.
- "Fit" resets zoom=1/viewStart=0; "Clear" clears in/out marks; "4:21" = total track duration.
- Audio: Reactivity reads mixed mono stream; A1 clip & "Aud" bar are split; (none) = uninitialized label.
- Keyframes: `Param::keys` stores `time`, `value`, `interp` (Linear/Ease/Step). Base + audio mod on top.

## Phase 1 Plan
- Implement Premiere-style zoom/pan (Ctrl/Alt+Wheel, middle-drag, navigator bar, vertical track sizing).
- Ruler with adaptive non-overlapping timecode ticks and sub-ruler beat markers.
- Draggable project End marker with auto/manual toggle + work area in/out bar.
- Visually culled rendering + multi-resolution audio waveform peak caching.
