import QtQuick
import QtTest
import "../qml"

Item {
    width: 1000; height: 400
    QtObject {
        id: viewport
        property real trackDuration: 100
        property real sequenceDuration: 0
        property real playhead: 25
        property real markIn: 10
        property real markOut: 30
        property var clips: []
        property var audioClips: []
        property bool playing: false
        property bool exporting: false
        property string exportStatus: ""
        property int projectAspect: 0
        property real fps: 60
        property real frameMax: 16
        property real frameP95: 16
        function seek(t) { playhead = t }
        function pause() { playing = false }
        function play() { playing = true }
        function cancelExport() { exporting = false }
    }
    TransportBar { id: bar; viewport: viewport; width: 1000; height: implicitHeight }
    TestCase {
        name: "Transport"
        when: windowShown
        function init() {
            bar.width = 1000
            viewport.trackDuration = 100
            viewport.sequenceDuration = 0
            viewport.clips = []
            viewport.audioClips = []
            viewport.playhead = 25
            viewport.markIn = 10
            viewport.markOut = 30
            viewport.exportStatus = ""
            viewport.exporting = false
            wait(10)
        }
        function test_sharedComponents() {
            const menuComponent = Qt.createComponent("../qml/StyledMenu.qml")
            compare(menuComponent.status, Component.Ready, menuComponent.errorString())
            const menu = menuComponent.createObject(bar)
            verify(menu !== null)
            const row = Qt.createQmlObject('import QtQuick; import "../qml"; StyledMenuItem { text: "Checked row"; checkable: true; checked: true }', bar)
            verify(row.implicitHeight >= 28)
            compare(row.leftPadding, 24)
            verify(row.contentItem.children[0].font.pixelSize >= 12)
            row.destroy()
            menu.destroy()
            for (const file of ["ShortcutSheet.qml", "AboutDialog.qml"]) {
                const component = Qt.createComponent("../qml/" + file)
                compare(component.status, Component.Ready, component.errorString())
                const dialog = component.createObject(bar)
                verify(dialog !== null)
                dialog.destroy()
            }
        }
        function test_alignment() {
            const controls = findChild(bar, "transportPlayback")
            const info = findChild(bar, "transportInfo")
            for (const w of [1000, 500, 340, 240]) {
                bar.width = w
                wait(10)
                fuzzyCompare(controls.mapToItem(bar, controls.width / 2, 0).x, w / 2, 0.1)
                fuzzyCompare(info.mapToItem(bar, info.width, 0).x, w - 12, 0.1)
                for (const button of controls.children) {
                    compare(button.width, controls.children[0].width)
                    compare(button.height, Theme.control)
                }
                compare(findChild(bar, "monitorScrub"), null)
            }
        }
        function test_emptyAndClampedRange() {
            viewport.trackDuration = 0
            compare(bar.hasRange, true)
            compare(bar.rangeDuration, 20)
            viewport.markIn = 0
            viewport.markOut = 0
            compare(bar.hasRange, false)
        }
        function test_noBottomSeekBar() {
            compare(bar.implicitHeight, Theme.control + 8)
            for (const item of findChild(bar, "transportFlow").children)
                if (typeof item.text === "string") verify(item.text.indexOf("IN / OUT") < 0)
            compare(findChild(bar, "monitorScrub"), null)
            compare(findChild(bar, "monitorRail"), null)
            compare(findChild(bar, "monitorPlayhead"), null)
            compare(bar.implicitHeight, findChild(bar, "transportFlow").height + 8)
        }
    }
}
