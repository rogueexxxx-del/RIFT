import QtQuick
import QtQuick.Controls
import QtTest
import "../qml"

Item {
    id: root
    width: 960
    height: 505

    QtObject {
        id: viewport
        property bool canUndo: true
        property bool canRedo: true
        property string undoLabel: "Move clip"
        property string redoLabel: "Trim clip"
        property string projectPath: ""
        property int projectAspect: 0
        property int mode: 0
        property bool snapToMarkers: false
        property var channelNames: [{ name: "BAS" }]
        property bool exporting: false
        property string exportStatus: ""
        property int exportPercent: 0
        property int detections: 0
        property bool linkAllVisualizers: false
        function systemFonts() { return [] }
        function detectMarkers() { detections++ }
        function visualizerColorStyle(index) {
            return {mode: "solid", solid: "#38bdf8", stops: [
                {position: 0, color: "#38bdf8"}, {position: 1, color: "#f472b6"}]}
        }
        signal visualizerColorStyleChanged(int index)
        signal exportChanged()
    }
    AppMenu { id: bar; viewport: viewport }
    ShortcutSheet { id: shortcuts }
    AboutDialog { id: about }
    NewProjectDialog { id: project; viewport: viewport }
    ExportDialog { id: output; viewport: viewport }
    PreferencesDialog { id: preferences; viewport: viewport; effectIds: ["blur"] }
    ColorStyleEditor { id: colors; viewport: viewport; visible: false }
    SignalSpy { id: panelSpy; target: bar; signalName: "requestPanel" }

    TestCase {
        name: "FluentMenus"
        when: windowShown

        function entry(menu, text) {
            for (let i = 0; i < menu.count; ++i) {
                const item = menu.itemAt(i)
                if (item && item.text === text) return item
            }
            return null
        }
        function cleanup() {
            for (const dialog of [shortcuts, about, project, output, preferences]) dialog.close()
            for (let i = 0; i < bar.count; ++i) bar.menuAt(i).close()
            Theme.applyScale(1)
            panelSpy.clear()
        }
        function test_taskMenusAndShortcutHints() {
            const file = bar.menuAt(0)
            const edit = bar.menuAt(1)
            const view = bar.menuAt(2)
            verify(entry(edit, "Detect beats") !== null)
            compare(entry(view, "Detect beats"), null)
            entry(edit, "Detect beats").triggered()
            compare(viewport.detections, 1)
            const audio = entry(view, "Audio input")
            verify(audio !== null)
            audio.triggered()
            compare(panelSpy.count, 1)
            compare(panelSpy.signalArguments[0][0], "audio")
            for (const label of ["New project", "Open…", "Save", "Export video…"]) {
                const item = entry(file, label)
                verify(item.shortcutText.length > 0)
                compare(item.action, null)
            }
            verify(entry(edit, "Undo Move clip").shortcutText.length > 0)
            verify(entry(edit, "Redo Trim clip").shortcutText.length > 0)
            compare(entry(view, "React mode").shortcutText, "1")
            compare(entry(view, "Live mode").shortcutText, "2")
        }
        function test_dialogBounds_data() {
            return [{tag: "default", scale: 1}, {tag: "largest", scale: 1.3}]
        }
        function test_dialogBounds(data) {
            Theme.applyScale(data.scale)
            for (const dialog of [shortcuts, about, project, output, preferences]) {
                dialog.open()
                tryCompare(dialog, "opened", true)
                verify(dialog.height <= root.height - 32, dialog.toString() + " height")
                verify(dialog.width <= root.width - 32, dialog.toString() + " width")
                verify(dialog.contentItem.height > 0)
                const scroll = dialog.contentItem
                verify(scroll.contentHeight > 0)
                verify(scroll.contentWidth <= scroll.availableWidth)
                dialog.close()
                tryCompare(dialog, "visible", false)
            }
        }
        function test_shortcutFinalRowVisible() {
            shortcuts.open()
            tryCompare(shortcuts, "opened", true)
            const scroll = findChild(shortcuts.contentItem, "shortcutScroll") || shortcuts.contentItem
            verify(scroll.contentHeight > scroll.availableHeight)
            compare(scroll.ScrollBar.vertical.policy, ScrollBar.AlwaysOn)
            const flick = scroll.contentItem
            flick.contentY = flick.contentHeight - flick.height
            wait(30)
            const row = findChild(scroll, "shortcutRow" + (shortcuts.shortcuts.length - 1))
            verify(row !== null)
            const point = row.mapToItem(scroll, 0, 0)
            verify(point.y >= 0)
            verify(point.y + row.height <= scroll.height, "last row above footer")
            verify(row.width <= scroll.availableWidth - Theme.groupGap)
        }
        function test_neutralFlyouts() {
            const menu = bar.menuAt(0)
            menu.open()
            tryCompare(menu, "opened", true)
            compare(menu.background.radius, Theme.panelRadius)
            compare(menu.background.color, Theme.flyout)
            verify(menu.height <= root.height)
            const item = entry(menu, "Save")
            compare(item.leftPadding, 24)
            compare(menu.spacing, 0)
            compare(menu.background.border.color, Theme.popupBorder)
            verify(item.height >= Math.max(28, Theme.size + 12))
            compare(item.background.color, "#00000000")
            menu.close()
            tryCompare(menu, "visible", false)
            const help = bar.menuAt(3)
            help.open()
            tryCompare(help, "opened", true)
            let widest = 136
            for (let i = 0; i < help.count; ++i) {
                const row = help.itemAt(i)
                widest = Math.max(widest, row.implicitWidth)
            }
            verify(help.width <= widest + help.leftPadding + help.rightPadding + 2,
                "Menu must fit its labels without a reserved empty column")
            const helpRow = entry(help, "Keyboard shortcuts")
            const label = findChild(helpRow, "menuItemLabel")
            verify(!label.truncated, "Compact menus must still show the full command")
            verify(help.height <= help.count * Theme.control + help.topPadding + help.bottomPadding + 1)
        }
        function test_systemThemePreservesColorOverrides() {
            verify(findChild(preferences.contentItem, "theme-system") !== null)
            const preset = Theme.preset
            const accent = Theme.accent
            const effects = Theme.effectColorOverrides
            const channels = Theme.channelColorOverrides
            try {
                Theme.setEffectColor("blur", "#38bdf8")
                Theme.setChannelColor("BAS", "#f472b6")
                Theme.applyPreset("system")
                compare(Theme.preset, "system")
                compare(Theme.accent, accent)
                compare(Theme.effectColor("blur"), "#38bdf8")
                compare(Theme.channelColor("BAS"), "#f472b6")
                compare(colors.solidColor, "#38bdf8")
                compare(colors.stops[1].color, "#f472b6")
            } finally {
                Theme.effectColorOverrides = effects
                Theme.channelColorOverrides = channels
                Theme.applyPreset(preset)
            }
        }
    }
}
