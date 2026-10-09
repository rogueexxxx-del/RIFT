pragma Singleton
import QtQuick

// Design tokens - RIFT Design Spec (docs: section 2). The ONLY place colours,
// sizes and font names live. Components read these, nothing else.
//
// Token -> property mapping. The old names are kept so the ~20 existing
// components pick up the spec without a rename pass:
//   bg-0 bg | bg-1 panel | bg-2 raised | bg-3 hover | sunken = bg-0
//   line-0 hairline | line-1 border | line-2 borderHover
//   text-0 text | text-1 textDim | text-2 textMuted | text-3 textDisabled
QtObject {
    id: theme

    // ── palette ──
    // Not readonly: Preferences writes to these to retheme the app live.
    property color accent:        "#A78BFA"
    // Hover on a primary button: accent at 85% over the panel.
    readonly property color accentPressed: Qt.tint(panel, Qt.rgba(accent.r, accent.g, accent.b, 0.85))
    // accent-dim: accent at 18% on bg-1. Selected row background.
    readonly property color accentSoft:    Qt.tint(panel, Qt.rgba(accent.r, accent.g, accent.b, 0.18))
    // Text on an accent fill: darkest bg, unless the accent itself is dark.
    readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.5
                                      ? (preset === "light" ? "#0A0A0A" : bg) : "#FFFFFF"

    property color bg:      "#070707"
    property color panel:   "#0C0C0C"
    property color raised:  "#121212"
    property color hover:   "#1A1A1A"
    property color sunken:  "#070707"

    property color text:         "#EDEDED"
    property color textDim:      "#A8A8A8"
    property color textMuted:    "#808080"   // WCAG AA compliant (5.2:1 contrast against panel)
    property color textDisabled: "#4D4D4D"

    property color hairline:    "#222222"
    property color border:      "#333333"
    property color borderHover: "#555555"

    readonly property color ok:     "#46C26B"
    readonly property color warn:   "#F5A524"
    readonly property color danger: "#E5484D"

    // Audio channel colours. Fixed: never follow theme or accent.
    readonly property var channelColors: ({
        "BAS": "#FF5A36", "KIK": "#FF3D40", "BASS": "#FF5A36", "KICK": "#FF3D40", "SUB": "#FF5A36",
        "MID": "#FFB020", "SNR": "#FFB020", "MELODY": "#FFB020", "MIDS": "#FFB020", "SNARE": "#FFB020",
        "HIG": "#3CC8FF", "CEN": "#3CC8FF", "HIGH": "#3CC8FF", "HIGHS": "#3CC8FF", "CENTROID": "#3CC8FF",
        "DRM": "#307D07", "TRN": "#5BE08A", "DRUMS": "#307D07", "TRANSIENT": "#5BE08A",
        "BPM": "#FF6FB5", "TIM": "#FF6FB5", "PITCH": "#FF6FB5"
    })
    function channelColor(name) {
        const c = channelColors[String(name).toUpperCase()]
        return c ? c : textDim
    }

    readonly property var effectColors: ({
        "ascii":           "#E5D633",
        "dither":          "#7B2EFF",
        "tunnel":          "#FA1E21",
        "risograph":       "#3CADFF",
        "bloom":           "#FF4D88",
        "blur":            "#6C757D",
        "chromatic":       "#00F5D4",
        "pixelate":        "#70E000",
        "halftone":        "#FFA229",
        "glitch":          "#9B5DE5",
        "scanlines":       "#38B000",
        "crt":             "#F15BB5",
        "vignette":        "#495057",
        "film_grain":      "#D4A373",
        "color_grade":     "#FF006E",
        "lut":             "#3A86FF",
        "edge_detect":     "#FF0054",
        "emboss":          "#9E0059",
        "invert":          "#4CC9F0",
        "posterize":       "#F72585",
        "solarize":        "#B5179E",
        "threshold":       "#7209B7",
        "voronoi_shatter": "#E76F51",
        "lens":            "#A855F7",
        "flow_warp":       "#2A9D8F",
        "vortex":          "#264653",
        "kaleido":         "#EC4899",
        "mirror_tile":     "#84CC16",
        "dot_field":       "#0D9488",
        "cyanotype":       "#1D4ED8",
        "terminal":        "#16A34A",
        "thermal":         "#EA580C",
        "datamosh":        "#10B981",
        "electron_scan":   "#06B6D4",
        "pixel_sort":      "#6366F1",
        "oscilloscope":    "#14B8A6",
        "feedback":        "#4338CA",
        "slit_scan":       "#0284C7",
        "post_fx":         "#475569"
    })
    function effectColor(name) {
        const c = effectColors[String(name).toLowerCase()]
        return c ? c : accent
    }

    // ── type ──
    // Ships with the bundled face (Geist). Geist has tabular figures, so
    // fontMono is only kept for hex fields and code/timecode callers.
    property string fontUI:   "Geist"
    property string fontMono: "Geist Mono"
    property url assetsUrl: ""
    function asset(subpath) {
        if (!assetsUrl || assetsUrl.toString() === "") return ""
        var base = assetsUrl.toString()
        if (!base.endsWith("/")) base += "/"
        return base + subpath
    }
    readonly property url logo: (assetsUrl && assetsUrl.toString() !== "")
        ? (preset === "light" ? asset("logo/SVG/RIFT BLK.svg") : asset("logo/SVG/RIFT WHT.svg"))
        : ""
    readonly property url monogram: (assetsUrl && assetsUrl.toString() !== "")
        ? (preset === "light" ? asset("logo/SVG/BLK MONOGRAM.svg") : asset("logo/SVG/WHT MONOGRAM.svg"))
        : ""

    // Sizes at the "Small" setting; applyScale multiplies.
    property int sizeBig:   18   // timecode, fps
    property int sizeTitle: 14   // dialog title
    property int size:      12   // body
    property int sizeSmall: 11   // label / value
    property int sizeTiny:  10   // micro label (UPPERCASE, +0.08em)
    readonly property int labelSize: size
    readonly property real microSpacing: sizeTiny * 0.08

    // ── themes ──
    // A preset only overrides surface/line/text tokens; accent stays the user's.
    readonly property var presets: ({
        "darker":   { bg: "#070707", panel: "#0C0C0C", raised: "#121212", hover: "#1A1A1A",
                      hairline: "#222222", border: "#333333", borderHover: "#555555",
                      text: "#EDEDED", textDim: "#A8A8A8", textMuted: "#808080", textDisabled: "#4D4D4D" },
        "dark":     { bg: "#0E0E0E", panel: "#141414", raised: "#1B1B1B", hover: "#242424",
                      hairline: "#242424", border: "#3E3E3E", borderHover: "#555555",
                      text: "#EDEDED", textDim: "#B0B0B0", textMuted: "#888888", textDisabled: "#555555" },
        "contrast": { bg: "#000000", panel: "#000000", raised: "#0A0A0A", hover: "#1A1A1A",
                      hairline: "#2A2A2A", border: "#FFFFFF", borderHover: "#FFFFFF",
                      text: "#FFFFFF", textDim: "#E0E0E0", textMuted: "#B8B8B8", textDisabled: "#666666" },
        "light":    { bg: "#E6E6E3", panel: "#F0F0EE", raised: "#FFFFFF", hover: "#DCDCD8",
                      hairline: "#D0D0CC", border: "#111111", borderHover: "#4A4A4A",
                      text: "#0A0A0A", textDim: "#444444", textMuted: "#666666", textDisabled: "#555555" }
    })

    property string preset: "darker"
    property real   textScale: 1.1

    function applyPreset(name) {
        const p = presets[name]
        if (!p) return
        preset = name
        bg = p.bg; sunken = p.bg; panel = p.panel; raised = p.raised; hover = p.hover
        hairline = p.hairline; border = p.border; borderHover = p.borderHover
        text = p.text; textDim = p.textDim; textMuted = p.textMuted; textDisabled = p.textDisabled
    }

    // Shader manifests and effect ids are written in caps ("MODE", "pixel_sort")
    // because they are data, not prose. Nothing in the UI should shout, so they
    // get sentence-cased on the way to the screen - except acronyms, which read
    // wrong any other way.
    readonly property var acronyms: ["MIDI", "OSC", "RIFT", "BPM", "FPS", "XY",
                                     "FFT", "RGB", "HSL", "CC", "LFO", "UI"]
    function nice(s) {
        if (!s) return ""
        const words = String(s).replace(/_/g, " ").split(" ")
        let out = []
        for (let i = 0; i < words.length; ++i) {
            const w = words[i]
            if (w === "") continue
            if (acronyms.indexOf(w.toUpperCase()) !== -1) out.push(w.toUpperCase())
            else if (out.length === 0) out.push(w[0].toUpperCase() + w.slice(1).toLowerCase())
            else out.push(w.toLowerCase())
        }
        return out.join(" ")
    }

    // Small 1.0, Default 1.1, Large 1.25, Largest 1.5.
    function applyScale(s) {
        textScale = s
        sizeBig   = Math.round(18 * s)
        sizeTitle = Math.round(14 * s)
        size      = Math.round(12 * s)
        sizeSmall = Math.round(11 * s)
        sizeTiny  = Math.round(10 * s)
        control   = s >= 1.5 ? 32 : s >= 1.25 ? 28 : s >= 1.1 ? 24 : 22
        rowHeight = control + 4
        toolbar   = Math.round(32 * s)
    }

    // ── shape / spacing (4px grid: 4 8 12 16 24 32) ──
    property int control:   24   // button / field / dropdown height
    property int rowHeight: 28   // list rows, chain rows, panel headers
    property int toolbar:   35   // top bar / toolbars (32 x scale)
    readonly property int header: 28
    readonly property int padding:  12
    readonly property int gap:      8
    readonly property int gapTight: 4
    readonly property int labelCol: 44
    readonly property int groupGap: 16
    readonly property int radius:   4    // subtle rounded corners matching Figma

    // ── motion ──
    property bool reduceMotion: false
    readonly property int fast: reduceMotion ? 0 : 80    // hover / press / toggle
    readonly property int fade: reduceMotion ? 0 : 100   // popovers / dialogs

    // ── grain (0 = off) ──
    property int grain: 4
}
