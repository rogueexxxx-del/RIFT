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
    readonly property color accentForeground: foregroundFor(Qt.rgba(accent.r, accent.g, accent.b, accent.a))
    // Keep the legacy token linked when the accent changes.
    readonly property alias onAccent: theme.accentForeground
    readonly property color accentText: readableText(Qt.rgba(accent.r, accent.g, accent.b, accent.a),
        Qt.rgba(panel.r, panel.g, panel.b, panel.a))
    readonly property color focusRing: contrastRatio(Qt.rgba(accent.r, accent.g, accent.b, accent.a),
        Qt.rgba(panel.r, panel.g, panel.b, panel.a)) >= 3 ? accent : text
    readonly property color flyout: Qt.rgba(raised.r, raised.g, raised.b, preset === "contrast" ? 1 : 0.98)
    readonly property color popupBorder: Qt.tint(panel, Qt.rgba(text.r, text.g, text.b, 0.20))
    readonly property color inputBorder: preset === "contrast" ? text : (preset === "light" ? "#767676" : "#8D8D8D")
    readonly property bool glowAllowed: preset !== "contrast" && !reduceMotion

    function luminance(color) {
        const value = typeof color === "string" ? Qt.tint(color, "transparent") : color
        function linear(value) { return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(value.r) + 0.7152 * linear(value.g) + 0.0722 * linear(value.b)
    }
    function contrastRatio(first, second) {
        const a = luminance(first), b = luminance(second)
        return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
    }
    function foregroundFor(background) {
        return contrastRatio(Qt.rgba(0, 0, 0, 1), background) >= contrastRatio(Qt.rgba(1, 1, 1, 1), background)
            ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1)
    }
    function readableText(color, background) {
        return contrastRatio(color, background) >= 4.5 ? color : foregroundFor(background)
    }

    property color bg:      "#202020"
    property color panel:   "#272727"
    property color raised:  "#323232"
    property color hover:   "#3D3D3D"
    property color sunken:  "#202020"

    property color text:         "#F3F3F3"
    property color textDim:      "#D1D1D1"
    property color textMuted:    "#B3B3B3"
    property color textDisabled: "#777777"

    property color hairline:    "#383838"
    property color border:      "#555555"
    property color borderHover: "#8A8A8A"

    readonly property color ok:     "#46C26B"
    readonly property color warn:   "#F5A524"
    readonly property color danger: "#E5484D"

    // Audio channel colours can be overridden in Preferences.
    property var channelColorOverrides: ({})
    readonly property var channelColors: ({
        "BAS": "#FF5A36", "KIK": "#FF3D40", "BASS": "#FF5A36", "KICK": "#FF3D40", "SUB": "#FF5A36",
        "MID": "#FFB020", "SNR": "#FFB020", "MELODY": "#FFB020", "MIDS": "#FFB020", "SNARE": "#FFB020",
        "HIG": "#3CC8FF", "CEN": "#3CC8FF", "HIGH": "#3CC8FF", "HIGHS": "#3CC8FF", "CENTROID": "#3CC8FF",
        "DRM": "#307D07", "TRN": "#5BE08A", "DRUMS": "#307D07", "TRANSIENT": "#5BE08A",
        "BPM": "#FF6FB5", "TIM": "#FF6FB5", "PITCH": "#FF6FB5"
    })
    function channelColor(name) {
        const key = String(name).toUpperCase()
        const c = channelColorOverrides[key] || channelColors[key]
        return c ? c : textDim
    }

    function setChannelColor(name, value) {
        const next = Object.assign({}, channelColorOverrides)
        if (value) next[String(name).toUpperCase()] = value
        else delete next[String(name).toUpperCase()]
        channelColorOverrides = next
    }

    property var effectColorOverrides: ({})
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
        "fracture":        "#E76F51",
        "noise_field":     "#7B2EFF",
        "contour":         "#FF0054",
        "prism_split":     "#00F5D4",
        "shockwave":       "#FA1E21",
        "halation_grain": "#D4A373",
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
        const key = String(name).toLowerCase()
        const c = effectColorOverrides[key] || effectColors[key]
        return c ? c : accent
    }

    function setEffectColor(name, value) {
        const next = Object.assign({}, effectColorOverrides)
        if (value) next[String(name).toLowerCase()] = value
        else delete next[String(name).toLowerCase()]
        effectColorOverrides = next
    }

    // ── type ──
    // Use Windows typography; keep fixed-width values for timecode and fields.
    property string fontUI:   "Segoe UI Variable"
    property string fontMono: "Consolas"
    property url assetsUrl: ""
    function asset(subpath) {
        if (!assetsUrl || assetsUrl.toString() === "") return ""
        var base = assetsUrl.toString()
        if (!base.endsWith("/")) base += "/"
        return base + subpath
    }
    readonly property url logo: asset("logo_wordmark.png")
    readonly property url monogram: asset("logo_monogram.png")

    // Sizes at the "Small" setting; applyScale multiplies.
    property int sizeBig:   24   // timecode, fps
    property int sizeTitle: 20   // dialog title
    property int size:      14   // body
    property int sizeSmall: 12   // label / value
    property int sizeTiny:  12   // micro label (UPPERCASE, +0.08em)
    readonly property int labelSize: size
    readonly property real microSpacing: sizeTiny * 0.08

    // ── themes ──
    // A preset only overrides surface/line/text tokens; accent stays the user's.
    readonly property var presets: ({
        "darker":   { bg: "#181818", panel: "#202020", raised: "#292929", hover: "#333333",
                      hairline: "#383838", border: "#555555", borderHover: "#8A8A8A",
                      text: "#F3F3F3", textDim: "#D1D1D1", textMuted: "#AAAAAA", textDisabled: "#777777" },
        "dark":     { bg: "#202020", panel: "#272727", raised: "#323232", hover: "#3D3D3D",
                      hairline: "#383838", border: "#555555", borderHover: "#8A8A8A",
                      text: "#F3F3F3", textDim: "#D1D1D1", textMuted: "#B3B3B3", textDisabled: "#777777" },
        "contrast": { bg: "#000000", panel: "#000000", raised: "#0A0A0A", hover: "#1A1A1A",
                      hairline: "#2A2A2A", border: "#FFFFFF", borderHover: "#FFFFFF",
                      text: "#FFFFFF", textDim: "#E0E0E0", textMuted: "#B8B8B8", textDisabled: "#666666" },
        "light":    { bg: "#F3F3F3", panel: "#FFFFFF", raised: "#F9F9F9", hover: "#EAEAEA",
                      hairline: "#DEDEDE", border: "#B5B5B5", borderHover: "#767676",
                      text: "#1B1B1B", textDim: "#434343", textMuted: "#606060", textDisabled: "#888888" }
    })

    property string preset: "system"
    property real   textScale: 1
    readonly property int systemColorScheme: Qt.styleHints.colorScheme
    onSystemColorSchemeChanged: if (preset === "system") applyPreset("system")

    function applyPreset(name) {
        const p = presets[name === "system" ? (systemColorScheme === Qt.Dark ? "dark" : "light") : name]
        if (!p) return
        preset = name
        bg = p.bg; sunken = p.bg; panel = p.panel; raised = p.raised; hover = p.hover
        hairline = p.hairline; border = p.border; borderHover = p.borderHover
        text = p.text; textDim = p.textDim; textMuted = p.textMuted; textDisabled = p.textDisabled
        Qt.styleHints.colorScheme = name === "system" ? Qt.Unknown : name === "light" ? Qt.Light : Qt.Dark
    }
    Component.onCompleted: applyPreset(preset)

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
        if (!isFinite(s) || s <= 0) return
        textScale = Math.max(1, Math.min(s, 1.75))
        sizeBig   = Math.round(24 * textScale)
        sizeTitle = Math.round(20 * textScale)
        size      = Math.round(14 * textScale)
        sizeSmall = Math.round(12 * textScale)
        sizeTiny  = Math.round(12 * textScale)
        control   = Math.round(32 * textScale / 4) * 4
        rowHeight = control + 8
        toolbar   = control + 8
    }

    // ── shape / spacing (4px grid: 4 8 12 16 24 32) ──
    property int control:   32   // button / field / dropdown height
    property int rowHeight: 40   // list rows, chain rows, panel headers
    property int toolbar:   40   // top bar / toolbars (32 x scale)
    readonly property int header: toolbar
    readonly property int padding:  12
    readonly property int gap:      8
    readonly property int gapTight: 4
    readonly property int labelCol: 44
    readonly property int groupGap: 16
    readonly property int radius:   4
    readonly property int panelRadius: 8
    readonly property int focusWidth: 2

    // ── motion ──
    property bool reduceMotion: false
    readonly property int fast: reduceMotion ? 0 : 80    // hover / press / toggle
    readonly property int fade: reduceMotion ? 0 : 100   // popovers / dialogs

    // ── grain (0 = off) ──
    property int grain: 4
}
