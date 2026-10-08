# RIFT Engine Bug Tracker (Release v0.1.9)

## Bug Summary

| ID | Severity | Flow | Title | Status |
|---|---|---|---|---|
| BUG-01 | S2 | F03 | Chopped clips sharing effect chain instead of independent per-clip chains | FIXED |
| BUG-02 | S3 | F04 | Effect node right-click options missing & unable to change existing effect | FIXED |
| BUG-03 | S3 | F03 | Razor tool cutting line and cursor invisible in timeline | FIXED |
| BUG-04 | S3 | F02 | Animated shaders and feedback loops keep running when video is paused | FIXED |
| BUG-05 | S3 | F03 | Timeline clip dragging has unwanted stickiness | FIXED |
| BUG-06 | S3 | F06 | Export dialog missing option to remove RIFT watermark | FIXED |
| BUG-07 | S4 | F07 | Top menu bar showed full wordmark text instead of the isolated monogram glyph | FIXED |
| BUG-08 | S4 | F07 | About dialog logo failing to load due to unreactive `assetsUrl` initialization | FIXED |
| BUG-09 | S4 | F07 | Timeline lane bed stuck highlighted with red border when not dragging | FIXED |
| BUG-10 | S4 | F07 | Chopped clips had artificial 3px red vertical stripes looking like cut divider errors | FIXED |
| BUG-11 | S4 | F07 | Timeline tool buttons and keyframe button styled as harsh light-grey blocks | FIXED |

---

### Bug Details & Verification

#### BUG-07: Top menu bar showed full text instead of isolated monogram glyph
- **Severity**: S4 (Cosmetic / Brand)
- **Steps**: Launch application, look at top header bar.
- **Expected**: Minimal, centered RIFT monogram glyph (`WHT MONOGRAM.png` / `BLK MONOGRAM.png`).
- **Actual**: Displayed the full wordmark text image.
- **Fix**: Added `Theme.monogram` property in `Theme.qml` pointing to `assets/logo/PNG/WHT MONOGRAM@0.5x.png` and updated `monogramLogo` in `Main.qml`.

#### BUG-08: About dialog logo failing to render
- **Severity**: S4 (Cosmetic)
- **Steps**: Open Help > About RIFT.
- **Expected**: Wordmark logo clearly visible at top of dialog.
- **Actual**: Blank gap above "Sound into picture".
- **Fix**: Made `Theme.logo` explicitly reactive to `Theme.assetsUrl` property changes and gave `Image` in `AboutDialog.qml` explicit `Layout.preferredWidth: 120` and `Layout.preferredHeight: 32`.

#### BUG-09: Timeline lane bed stuck with red border
- **Severity**: S4 (Visual glitch)
- **Steps**: Cut clip or click in timeline.
- **Expected**: Lane bed has subtle hairline border when idle.
- **Actual**: Entire lane V2 outlined in bright red across the full timeline width.
- **Fix**: Guarded lane border highlight in `TimelinePanel.qml` with `(panel.viewport.clipDragging && panel.dropLane === ...)` so it is strictly active only during live drag-and-drop. Disabled `DragHandler` when `panel.activeTool === "razor"`.

#### BUG-10: Chopped clips displaying vertical red stripes
- **Severity**: S4 (Visual glitch)
- **Steps**: Cut a clip multiple times with Razor tool.
- **Expected**: Clean contiguous clip segments with standard border.
- **Actual**: Each segment had a 3px solid red bar on its left edge, cluttering the view with red stripes.
- **Fix**: Removed the hardcoded 3px left edge bar from `TimelinePanel.qml` and added width check (`clip.width >= 32`) to prevent text overflow on micro-slices.

#### BUG-11: Clunky grey boxes on timeline toolbar
- **Severity**: S4 (Design inconsistency)
- **Steps**: View timeline toolbar.
- **Expected**: Sleek dark controls matching dark UI aesthetic.
- **Actual**: 9 stark grey rectangles (`#9A9A9A`) with black icons and an inconsistent keyframe button.
- **Fix**: Restyled `EditToolButton.qml` and the keyframe button in `TimelinePanel.qml` with dark backgrounds (`#181818`), subtle borders (`#242424`), light icons (`#CCCCCC`), and accent highlights when active.
