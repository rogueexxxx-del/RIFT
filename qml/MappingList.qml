import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Every control binding in the project, on one list.
//
// The drawn controller next to this is a convenience for hardware we recognise.
// This is the part that works with ANYTHING: the binding key is whatever
// actually arrived - "cc:74", "note:36", an OSC address - so a controller with
// no profile, a DAW forwarding CCs down a virtual MIDI port, or a phone sending
// OSC all land here identically.
Rectangle {
    id: list
    required property var viewport

    color: Theme.panel

    // "cc:74" reads as jargon in a list you scan during a set.
    function pretty(key) {
        if (key.indexOf("cc:") === 0)   return "CC " + key.substring(3)
        if (key.indexOf("note:") === 0) return "Pad " + key.substring(5)
        return key
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: Theme.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            Text {
                text: "Mappings"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }
            Text {
                text: list.viewport.allMappings.length + " bound"
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeTiny
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: list.viewport.learning >= 0
                text: "move a control to bind it"
                color: Theme.accent
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
            }
        }

        // Nothing bound yet: say how to bind something rather than showing an
        // empty box.
        Text {
            visible: list.viewport.allMappings.length === 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Nothing mapped yet. Open an effect, press Map beside a "
                + "setting, then move a knob, pad or fader. Any controller "
                + "works - RIFT binds whatever message arrives, so it does not "
                + "need to know your hardware.\n\n"
                + "Running a DAW at the same time? A controller can usually "
                + "only talk to one program. Either give RIFT its own "
                + "controller, or send CCs from the DAW down a virtual MIDI "
                + "port (loopMIDI on Windows) and pick that port here."
            color: Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeTiny
            lineHeight: 1.3
        }

        ListView {
            visible: list.viewport.allMappings.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: list.viewport.allMappings
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 26
                radius: Theme.radius
                color: rowHover.hovered ? Theme.raised : "transparent"
                HoverHandler { id: rowHover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 6
                    spacing: Theme.gap

                    Text {
                        text: list.pretty(modelData.key)
                        color: Theme.accent
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.sizeSmall
                        Layout.preferredWidth: 72
                    }
                    Text {
                        text: "→"
                        color: Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                    }
                    Text {
                        text: Theme.nice(modelData.effect) + "  "
                            + Theme.nice(modelData.label)
                        color: Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: "×"
                        color: clrHover.hovered ? Theme.danger : Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.size
                        HoverHandler { id: clrHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: list.viewport.clearMappingKey(modelData.key)
                        }
                        ToolTipArea { text: "Unbind this control" }
                    }
                }
            }
        }
    }
}
