import QtQuick
import QtQuick.Layouts

// Live mode's transport strip. Mappings live in ControllerView above this, so
// this is only the things you reach for mid-set: audio in, playback, level.
Rectangle {
    id: bar
    required property var viewport

    implicitHeight: 52
    color: Theme.panel

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padding
        anchors.rightMargin: Theme.padding
        spacing: Theme.groupGap

        // No transport here. It already sits under the viewport, and having it
        // twice on screen in Live mode meant two controls that looked alike and
        // did the same thing.

        FlatButton {
            label: bar.viewport.liveInput ? "Listening" : "Not listening"
            active: bar.viewport.liveInput
            implicitWidth: 132
            onClicked: bar.viewport.liveInput = !bar.viewport.liveInput
            ToolTipArea { text: "React to the mic or loopback device instead of a file" }
        }

        // The one reading that matters on stage: is anything getting in.
        Rectangle {
            Layout.fillWidth: true
            Layout.maximumWidth: 260
            implicitHeight: 14
            color: Theme.bg
            border.color: Theme.hairline
            Rectangle {
                width: parent.width * Math.min(1, bar.viewport.liveLevel)
                height: parent.height
                color: bar.viewport.liveLevel > 0.95 ? "#E05555" : Theme.accent
            }
            ToolTipArea { text: "Audio input level" }
        }

        // No source picker here. It is the same control as the one on the
        // Audio input panel in the dock, and two pickers for one setting is
        // just a way to leave them disagreeing.

        Item { Layout.fillWidth: true }

        Text {
            text: bar.viewport.midiOpen ? bar.viewport.midiName : "no controller"
            color: bar.viewport.midiOpen ? Theme.accent : Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
            elide: Text.ElideRight
            Layout.maximumWidth: 260
        }
    }
}
