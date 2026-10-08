import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Shown while a render runs. The transport bar already carries a percentage,
// but a long export is a modal-feeling operation and people want one obvious
// place that says how far along it is and how to stop it.
//
// Not actually modal: the viewport keeps rendering during an export, and
// blocking the window would hide the thing being rendered.
AppDialog {
    id: dlg
    required property var viewport

    title: "Exporting"
    modal: false
    closePolicy: Popup.NoAutoClose
    width: 380
    standardButtons: Dialog.NoButton

    // Follows the engine: opens when a render starts, closes when it ends.
    Connections {
        target: dlg.viewport
        function onExportChanged() {
            if (dlg.viewport.exporting) dlg.open()
            else if (dlg.opened) closeSoon.restart()
        }
    }
    // Hold the finished state on screen for a moment: a dialog that vanishes
    // the instant it hits 100% reads as a crash.
    Timer {
        id: closeSoon
        interval: 1400
        onTriggered: dlg.close()
    }

    contentItem: ColumnLayout {
        spacing: Theme.gap

        Text {
            Layout.fillWidth: true
            text: dlg.viewport.exportStatus
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
            elide: Text.ElideMiddle
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 10
            radius: 0
            color: "#2B2B2B"
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1,
                        dlg.viewport.exportPercent / 100))
                height: parent.height
                radius: 0
                color: dlg.viewport.exporting ? "#E5D634" : Theme.ok
                Behavior on width { NumberAnimation { duration: 140 } }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: dlg.viewport.exportPercent + "%"
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.size
            }
            Item { Layout.fillWidth: true }
            FlatButton {
                visible: dlg.viewport.exporting
                label: "Cancel"
                onClicked: dlg.viewport.cancelExport()
            }
            FlatButton {
                visible: !dlg.viewport.exporting
                label: "Close"
                onClicked: dlg.close()
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "You can keep working - the render uses its own engine."
            color: Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeTiny
            visible: dlg.viewport.exporting
        }
    }
}
