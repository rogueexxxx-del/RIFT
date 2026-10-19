import QtQuick
import QtTest
import "../qml"

Item {
    width: 520; height: 300
    FlatButton { id: button; label: "Apply" }
    IconButton { id: icon; x: 160; tip: "Play preview" }
    EditToolButton { id: tool; x: 220; tip: "Selection tool" }
    ChainBlock { id: effect; y: 64; width: 300; label: "ASCII"; effectId: "ascii" }
    SignalSpy { id: clicked; target: button; signalName: "clicked" }
    TestCase {
        name: "FluentTheme"
        when: windowShown
        property var original
        function initTestCase() {
            original = {preset: Theme.preset, scale: Theme.textScale, accent: String(Theme.accent), motion: Theme.reduceMotion}
        }
        function init() {
            Theme.applyPreset("dark")
            Theme.applyScale(1)
            Theme.reduceMotion = false
            Theme.accent = original.accent
            button.active = false
            button.enabledLook = true
            clicked.clear()
        }
        function cleanupTestCase() {
            Theme.accent = original.accent
            Theme.reduceMotion = original.motion
            Theme.applyPreset(original.preset)
            Theme.applyScale(original.scale)
        }
        function test_paletteContrast() {
            fuzzyCompare(Theme.contrastRatio("#000000", "#FFFFFF"), 21, 0.001)
            for (const preset of Object.keys(Theme.presets)) {
                Theme.applyPreset(preset)
                for (const surface of [Theme.bg, Theme.panel, Theme.raised, Theme.hover]) {
                    for (const ink of [Theme.text, Theme.textDim, Theme.textMuted])
                        verify(Theme.contrastRatio(ink, surface) >= 4.5, preset + " text contrast")
                }
                verify(Theme.contrastRatio(Theme.focusRing, Theme.panel) >= 3)
            }
        }
        function test_semanticColors() {
            compare(Theme.effectColor("ascii"), "#E5D633")
            compare(Theme.channelColor("BAS"), "#FF5A36")
            for (const color of Object.values(Theme.effectColors).concat(Object.values(Theme.channelColors)))
                verify(Theme.contrastRatio(Theme.foregroundFor(color), color) >= 4.5, color)
            for (const accent of ["#FFFFFF", "#000000", "#A78BFA", "#307D07", "#0078D4"]) {
                Theme.accent = accent
                tryVerify(() => Theme.contrastRatio(Theme.onAccent, Theme.accent) >= 4.5, 250,
                    accent + " foreground=" + Theme.onAccent + " canonical=" + Theme.accentForeground
                    + " direct=" + Theme.foregroundFor(Theme.accent))
                tryVerify(() => Theme.contrastRatio(Theme.accentText, Theme.panel) >= 4.5, 250, accent)
            }
        }
        function test_readableScaleAndTargets() {
            for (const scale of [0.5, 1, 1.1, 1.5]) {
                Theme.applyScale(scale)
                verify(Theme.size >= 14 && Theme.sizeSmall >= 12 && Theme.sizeTiny >= 12)
                verify(button.implicitHeight >= 32 && icon.implicitHeight >= 32 && tool.implicitHeight >= 32)
                compare(Theme.control % 4, 0)
            }
        }
        function test_keyboardAndDisabledControl() {
            button.forceActiveFocus()
            keyClick(Qt.Key_Space)
            keyClick(Qt.Key_Return)
            compare(clicked.count, 2)
            button.enabledLook = false
            keyClick(Qt.Key_Return)
            compare(clicked.count, 2)
        }
        function test_glowAccessibility() {
            verify(Theme.glowAllowed)
            Theme.applyPreset("contrast")
            compare(Theme.glowAllowed, false)
            Theme.applyPreset("dark")
            Theme.reduceMotion = true
            compare(Theme.glowAllowed, false)
        }
        function test_activeControlContrast() {
            button.active = true
            const surface = findChild(button, "control-surface")
            const label = findChild(button, "control-label")
            for (const accent of ["#FFFFFF", "#000000", "#A78BFA", "#307D07", "#0078D4"]) {
                Theme.accent = accent
                mousePress(button, button.width / 2, button.height / 2)
                wait(Theme.fast + 10)
                verify(Theme.contrastRatio(label.color, surface.color) >= 4.5, accent)
                mouseRelease(button, button.width / 2, button.height / 2)
            }
        }
        function test_accessibleEffect() {
            compare(effect.Accessible.name, "ASCII")
            verify(effect.Accessible.description.indexOf("characters") >= 0)
        }
    }
}
