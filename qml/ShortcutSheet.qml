import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AppDialog {
    id: sheet
    title: "Keyboard shortcuts"
    width: Math.min(640, Overlay.overlay ? Overlay.overlay.width - Theme.groupGap * 2 : 640)
    height: Math.min(680, Overlay.overlay ? Overlay.overlay.height - Theme.groupGap * 2 : 680)
    standardButtons: Dialog.Close
    readonly property var shortcuts: [
        { k: "Space", n: "Play / pause" },
        { k: "1 / 2", n: "React / Live mode" },
        { k: "Ctrl + N", n: "New project" },
        { k: "Ctrl + O", n: "Open project" },
        { k: "Ctrl + S", n: "Save project" },
        { k: "Ctrl + E", n: "Export video" },
        { k: "Ctrl + Z", n: "Undo" },
        { k: "Ctrl + Y / Ctrl + Shift + Z", n: "Redo" },
        { k: "V / Esc", n: "Select tool" },
        { k: "C", n: "Razor tool" },
        { k: "T", n: "Text tool" },
        { k: "K", n: "Add keyframe" },
        { k: "I / O", n: "Mark In / Out" },
        { k: "Ctrl + C / Ctrl + V", n: "Copy / paste clip" },
        { k: "Delete", n: "Remove selected clip" },
        { k: "Drag a clip", n: "Move it in time" },
        { k: "Drag a clip edge", n: "Trim it" },
        { k: "Drag up / down", n: "Change its lane" },
        { k: "Ctrl + wheel", n: "Zoom the timeline" },
        { k: "Wheel", n: "Scroll tracks vertically" },
        { k: "Shift + wheel", n: "Pan the timeline" },
        { k: "Drag panel tab", n: "Center groups; edge splits" },
        { k: "Drop outside", n: "Float the panel" },
        { k: "View > Reset workspace", n: "Restore panel layout" }
    ]
    contentItem: ScrollView {
        id: scroll
        objectName: "shortcutScroll"
        clip: true
        contentWidth: availableWidth
        contentHeight: rows.implicitHeight
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AlwaysOn
        Column {
            id: rows
            width: scroll.availableWidth - Theme.groupGap
            spacing: Theme.gapTight
            Repeater {
                model: sheet.shortcuts
                delegate: Item {
                    required property var modelData
                    required property int index
                    objectName: "shortcutRow" + index
                    width: rows.width
                    height: Math.max(Theme.rowHeight, binding.height + Theme.gap, label.height + Theme.gap)
                    Text {
                        id: binding
                        width: parent.width * 0.48 - 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.k
                        wrapMode: Text.WordWrap
                        color: Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: Math.max(12, Theme.size)
                    }
                    Text {
                        id: label
                        x: parent.width * 0.48 + 8
                        width: parent.width - x - 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.n
                        wrapMode: Text.WordWrap
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: Math.max(12, Theme.size)
                    }
                }
            }
            Item { width: 1; height: Theme.gap }
        }
    }
}
