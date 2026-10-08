import QtQuick
import QtQuick.Layouts

// External controllers: MIDI CC in, OSC over UDP. Collapsed by default -
// most sessions never touch it, and the header says whether anything is live.
Rectangle {
    id: panel
    required property var viewport
    property bool expanded: false
    // Populated by SCAN. Plain property, not a dummy Item holding a model.
    property var midiDevices: []

    color: Theme.panel
    // Only what is on screen. A closed panel is its header and nothing else.
    implicitHeight: hdr.height
                    + (expanded ? col.implicitHeight + Theme.padding * 2 : 0)
    // A closed panel used to draw its content past its own bottom edge.
    clip: true

    readonly property bool active: viewport.midiOpen || viewport.oscOpen

    SectionHeader {
        id: hdr
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        title: "MIDI control"
        hint: panel.active ? "connected" : ""
        marked: panel.active
        expanded: panel.expanded
        onToggled: panel.expanded = !panel.expanded

        // Last control seen - the only way to tell a dead cable from a
        // wrong mapping without leaving the app.
        Text {
            text: panel.viewport.lastControl
            color: panel.viewport.learning >= 0 ? Theme.accent : Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
            elide: Text.ElideLeft
            Layout.maximumWidth: 130
        }
    }

    ColumnLayout {
        id: col
        visible: panel.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: hdr.bottom
        anchors.margins: Theme.padding
        spacing: Theme.gap

        // ── MIDI ──
        RowLayout {
            visible: panel.expanded
            Layout.fillWidth: true
            spacing: Theme.gapTight
            Text {
                text: "MIDI"
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
                Layout.preferredWidth: 34
            }
            FlatButton {
                label: panel.viewport.midiOpen ? "Close" : "Scan"
                active: panel.viewport.midiOpen
                onClicked: {
                    if (panel.viewport.midiOpen) panel.viewport.closeMidi()
                    else panel.midiDevices = panel.viewport.midiDevices()
                }
            }
        }
        Repeater {
            model: panel.expanded && !panel.viewport.midiOpen
                   ? panel.midiDevices : []
            delegate: FlatButton {
                required property int index
                required property string modelData
                Layout.fillWidth: true
                label: modelData
                onClicked: panel.viewport.openMidi(index)
            }
        }

        // ── OSC ──
        RowLayout {
            visible: panel.expanded
            Layout.fillWidth: true
            spacing: Theme.gapTight
            Text {
                text: "OSC"
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
                Layout.preferredWidth: 34
            }
            Rectangle {
                Layout.preferredWidth: 56
                implicitHeight: 20
                color: Theme.bg
                border.color: Theme.hairline
                TextInput {
                    id: portField
                    anchors.fill: parent
                    anchors.margins: 3
                    text: "9000"
                    enabled: !panel.viewport.oscOpen
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeSmall
                    validator: IntValidator { bottom: 1; top: 65535 }
                    selectByMouse: true
                }
            }
            FlatButton {
                label: panel.viewport.oscOpen ? "Stop" : "Listen"
                active: panel.viewport.oscOpen
                onClicked: {
                    if (panel.viewport.oscOpen) panel.viewport.stopOsc()
                    else panel.viewport.startOsc(parseInt(portField.text))
                }
            }
        }

        Text {
            visible: panel.expanded
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Press MAP on a param, then move a knob or send an OSC float."
            color: Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeTiny
        }
    }
}
