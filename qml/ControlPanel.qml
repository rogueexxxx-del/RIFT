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
    property bool scanned: false

    color: Theme.panel
    radius: Theme.panelRadius
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
        title: "MIDI / OSC control"
        hint: (panel.viewport.midiOpen ? "MIDI connected" : "MIDI disconnected")
              + (panel.viewport.oscOpen ? " · OSC listening" : "")
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
                    else { panel.midiDevices = panel.viewport.midiDevices(); panel.scanned = true }
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

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: panel.viewport.midiOpen
                ? "MIDI connected: " + panel.viewport.midiName + ". Audio listening is separate."
                : (panel.scanned && panel.midiDevices.length === 0
                   ? "No MIDI controllers found. Connect a controller, then scan again."
                   : "Scan for MIDI controllers, then select one to connect. Audio listening is separate.")
            color: Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
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
                Layout.preferredWidth: 72
                implicitHeight: Theme.control
                radius: Theme.radius
                color: Theme.bg
                border.color: portField.activeFocus ? Theme.focusRing : Theme.hairline
                TextInput {
                    id: portField
                    activeFocusOnTab: true
                    Accessible.name: "OSC UDP port"
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
                label: panel.viewport.oscOpen ? "Stop OSC" : "Listen to OSC"
                enabled: panel.viewport.oscOpen || portField.acceptableInput
                active: panel.viewport.oscOpen
                onClicked: {
                    if (panel.viewport.oscOpen) panel.viewport.stopOsc()
                    else if (portField.acceptableInput) panel.viewport.startOsc(parseInt(portField.text))
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
