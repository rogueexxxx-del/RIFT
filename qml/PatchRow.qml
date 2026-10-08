import QtQuick
import QtQuick.Layouts

// Patch controls for one uniform: which channel drives it, and by how much.
// Collapsed it shows the current patch; expanded it offers every channel.
// "STATIC" means unbound - the slider value is used as-is.
Item {
    id: row
    required property var viewport
    required property int paramIndex
    required property int channel        // -1 = static
    required property real depth
    required property real depthMax
    // Drive the master grade instead of the selected effect's uniform. Same
    // controls either way - the grade resolves through the same patch bay - so
    // this routes to the grade calls rather than cloning the row.
    property bool grade: false
    signal channelPicked(int ch)

    function patch(ch, d) {
        if (row.grade) row.viewport.setGradeBinding(row.paramIndex, ch, d)
        else           row.viewport.setBinding(row.paramIndex, ch, d)
    }

    property bool expanded: false

    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.gapTight

        RowLayout {
            Layout.fillWidth: true
            // Air between the buttons; at 6 they touched.
            spacing: Theme.gapTight

            Text {
                // Fixed column so this row's buttons start at the same x as
                // the keyframe row's above it.
                Layout.preferredWidth: Theme.labelCol
                text: "Patch"
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
            }

            // Current patch, click to open the channel list.
            FlatButton {
                small: true
                label: row.channel < 0
                       ? "Static"
                       : row.viewport.channelNames[row.channel].name
                active: row.channel >= 0
                onClicked: row.expanded = !row.expanded
            }

            Item { Layout.fillWidth: true }

            FlatButton {
                small: true
                visible: row.channel >= 0
                label: "Unpatch"
                onClicked: row.patch(-1, 0)
            }
        }

        // Depth: how far the channel pushes the value from its base.
        ParamSlider {
            visible: row.channel >= 0
            Layout.fillWidth: true
            label: "Depth"
            from: -row.depthMax
            to: row.depthMax
            stepSize: row.depthMax / 100
            value: row.depth
            onMoved: (v) => row.patch(row.channel, v)
        }

        // Channel picker.
        Flow {
            visible: row.expanded
            Layout.fillWidth: true
            spacing: Theme.gapTight

            Repeater {
                model: row.viewport.channelNames
                delegate: FlatButton {
                    small: true
                    required property int index
                    required property var modelData
                    label: modelData.name
                    active: row.channel === index
                    onClicked: {
                        // Keep the existing depth when re-patching; give a
                        // sensible default when coming from STATIC.
                        const d = row.depth !== 0 ? row.depth : row.depthMax * 0.5
                        row.patch(index, d)
                        row.expanded = false
                        row.channelPicked(index)
                    }
                }
            }
        }
    }
}
