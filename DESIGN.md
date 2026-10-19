# RIFT interface design

Phase 1 proposal. Edit the values here, then mirror them in `qml/Theme.qml`.
`Theme.qml` is the runtime token source consumed by QML. Existing `Theme` names remain
for old controls until the Phase 4 rollout. Colors used inside video content,
font picker samples, and shader data are content values, not interface chrome.

## UI audit

- Effect cards use bright solid fills. Their color dominates the effect name and texture.
- Purple selections compete with green and red audio indicators.
- Some 9 and 10 px text is too small. Panels have little grouping.
- Dialogs, menus, and controls mix corner shapes and hardcoded surfaces.
- Global grain covers the preview. It belongs on panel backgrounds.
- Most hand drawn controls lacked keyboard focus or disabled states.

## Core colors

| Token | Value | Use |
|---|---|---|
| `bg` | `#101010` | Outer chrome |
| `panel` | `#191919` | Docks and dialogs |
| `raised` | `#242424` | Controls and cards |
| `hover` | `#303030` | Hovered neutral control |
| `hairline` | `#303030` | Panel seams |
| `border` | `#424240` | Control border |
| `borderHover` | `#777770` | Hovered border |
| `text` | `#E6E6E3` | Main labels |
| `textDim` | `#B5B5B1` | Secondary labels |
| `textMuted` | `#92928E` | Hints |
| `textDisabled` | `#646461` | Disabled labels |
| `accent` | `#87B7E8` | Cool blue playhead and focus ring |
| `accentPressed` | `#A7CCF0` | Cool blue pressed state |
| `accentText` | `#101010` | Text on off-white primary action |
| `warn` | `#C88A78` | Warm meter warning state |
| `selection` | `#E6E6E3` | Selected row or card border |

The accent is cool blue. Primary actions use `text` as the fill and `bg` as the
label. Effect colors do not select a control. A selected card
uses the off-white border and visible name. No UI gradients, colored shadows, or glows.

## Audio colors

| Band | Value | UI placement |
|---|---|---|
| Bass | `#70A99B` | Linked tag, slider fill, meter |
| Kick | `#C88978` | Linked tag, slider fill, meter |
| Mids | `#B4A26E` | Linked tag, slider fill, meter |
| Highs | `#74A9B5` | Linked tag, slider fill, meter |
| Drums | `#8BA77E` | Linked tag, slider fill, meter |
| Transient | `#67A89A` | Linked tag, slider fill, meter |
| Beat | `#B3889A` | Linked tag, slider fill, meter |

The band name remains visible. Color never carries the meaning alone.

## Effect colors

Every effect uses OKLCH `L=0.72`, `C=0.11`; only hue changes. Hue values are
degrees. The blue accent band (190-230 degrees) is reserved for controls.

| Effect | Hue | Effect | Hue | Effect | Hue |
|---|---:|---|---:|---|---:|
| ASCII | 12 | Halftone | 24 | Dither | 36 |
| Glitch | 354 | Pixel sort | 336 | Oscilloscope | 156 |
| Datamosh | 48 | Risograph | 324 | Electron scan | 174 |
| Kaleido | 342 | Flow warp | 168 | Voronoi shatter | 330 |
| Dot field | 60 | Tunnel | 282 | Lens | 258 |
| Bloom | 84 | Feedback | 294 | Slit scan | 246 |
| Post FX | 96 | Noise field | 108 | Fracture | 252 |
| Color grade | 120 | Contour | 72 | Prism split | 270 |
| Shockwave | 318 | Halation + grain | 306 | Cyanotype | 240 |
| Thermal | 132 | Terminal | 144 | Mirror tile | 30 |

Color is limited to the 3 px card edge, index chip, and Params effect header.

## Type

- UI: Geist Regular and Medium. Minimum 11 px labels, 12 px values and body.
- Numeric values and timecode: Geist Mono. Minimum 12 px.
- Wordmark and About title only: Bebas Neue. It is the existing bundled display face.
- The shipped Geist and Bebas Neue files are covered by SIL OFL 1.1 and listed in
  `THIRD-PARTY-NOTICES.md`. No new font is introduced in Phase 1.

## Measurements

A 4 px grid drives padding and spacing: 4, 8, 12, 16, 24 and 32 px.
`line` is 1 px. `track` is 2 px. `handle` is 8 px. Controls and nodes have
2 px corners. Panels and dialogs have 4 px corners. No pill shapes.
The shared button and compact controls are 28 px; dialog controls use 32 px. Section headers
are 32 px. Parameter rows are 48 px with numeric values at the right.

## Control states

Neutral rest uses `raised`. Hover uses `hover` and `borderHover`. Pressed uses
`sunken`. Primary actions use off-white fill and black text. Disabled controls
reduce opacity to 0.45 while labels remain readable. Keyboard focus uses a 1 px
blue accent border, visible on every shared control. Selected neutral controls use
`selection`. The `ToolTipArea` popup uses the same panel and type tokens.

The slider has a thin track and square handle. Drag the mono value to scrub.
Double click the value or track to restore the manifest default. Tab moves to
the link button and slider. Arrow keys change the focused slider.

Hover and press transitions use 120 ms ease-in-out timing. Reduced motion sets
the transition duration to zero.

Grain uses `assets/grain.png` at low opacity inside panel and card bounds only.
It must never be drawn over `RiftViewport`. Keep the preview at full fidelity.
