import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Where Live mode gets its sound.
//
// The important case is NOT a microphone. Pick an OUTPUT device and Windows
// hands us the mix that device is playing, so the visuals follow Ableton, FL,
// a browser, a media player - anything making noise on this machine. No virtual
// cable, no plugin, no routing. That is what makes this a live tool rather than
// a thing that listens to the room.
Rectangle {
    id: panel
    required property var viewport
    property bool expanded: true

    function deviceLabel(device) {
        const name = String(device.name).replace(/\s*\(playing\)\s*$/i, "")
        return (device.loopback ? "Output (loopback): " : "Input: ") + name
    }

    color: Theme.panel
    radius: Theme.panelRadius
    // Only what is on screen. A closed panel is its header and nothing else.
    implicitHeight: hdr.height
                    + (expanded ? col.implicitHeight + Theme.padding * 2 : 0)
    // A closed panel used to draw its content past its own bottom edge.
    clip: true

    SectionHeader {
        id: hdr
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        title: "Audio input"
        hint: panel.viewport.liveInput ? "listening" : ""
        marked: panel.viewport.liveInput
        expanded: panel.expanded
        onToggled: panel.expanded = !panel.expanded

        // Live level, so you can see it is hearing something before
        // wondering why nothing moves.
        Rectangle {
            visible: panel.viewport.liveInput && panel.width >= 400
            implicitWidth: 54
            implicitHeight: 6
            radius: 0
            color: Theme.sunken
            Rectangle {
                width: parent.width * Math.min(1, panel.viewport.liveLevel * 1.5)
                height: parent.height
                radius: 0
                color: Theme.ok
            }
        }
        FlatButton {
            label: panel.viewport.liveInput ? "Stop audio" : "Listen to audio"
            enabled: panel.viewport.liveInput || srcPick.devs.length > 0
            active: panel.viewport.liveInput
            onClicked: panel.viewport.liveInput = !panel.viewport.liveInput
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

        ColumnLayout {
            visible: panel.expanded
            Layout.fillWidth: true
            spacing: Theme.gapTight

            ComboBox {
                id: srcPick
                objectName: "audioCaptureDevice"
                Layout.fillWidth: true
                implicitHeight: Theme.control
                // Re-queried, not bound once. liveDevices() is a plain call, so the
                // list was whatever existed when the window was built - empty if
                // the engine had not started, and stale the moment a DAW opens.
                property var devs: []
                function refresh() { devs = panel.viewport.liveDevices() }
                Component.onCompleted: refresh()
                onPressedChanged: if (pressed) refresh()
                // Outputs are marked, because "capture what this device is
                // playing" is not what people expect a device list to mean.
                model: devs.map(panel.deviceLabel)
                Accessible.name: "Audio capture device"
                displayText: count === 0 ? "No audio devices found" : (currentIndex < 0 ? "Select an audio device" : currentText)
                currentIndex: panel.viewport.liveDevice
                onActivated: panel.viewport.liveDevice = currentIndex

                contentItem: Text {
                    leftPadding: 8
                    text: srcPick.displayText
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeSmall
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                background: Rectangle {
                    color: Theme.raised
                    radius: Theme.radius
                    border.width: 1
                    border.color: srcPick.activeFocus ? Theme.accent : Theme.hairline
                }
                popup: Popup {
                    y: srcPick.height
                    width: srcPick.width
                    implicitHeight: Math.min(contentItem.implicitHeight, 300)
                    padding: 1
                    background: Rectangle {
                        color: Theme.flyout
                        radius: Theme.panelRadius
                        border.width: 1
                        border.color: Theme.hairline
                    }
                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: srcPick.delegateModel
                        currentIndex: srcPick.highlightedIndex
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                    }
                }
                delegate: ItemDelegate {
                    id: deviceOption
                    required property string modelData
                    required property int index
                    width: srcPick.width
                    height: Theme.rowHeight
                    highlighted: srcPick.highlightedIndex === index
                    background: Rectangle {
                        color: deviceOption.hovered || deviceOption.highlighted ? Theme.accent : "transparent"
                    }
                    contentItem: Text {
                        leftPadding: 8
                        text: modelData
                        color: deviceOption.hovered || deviceOption.highlighted ? Theme.foregroundFor(Theme.accent) : Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: srcPick.devs.length === 0
                    ? "Connect an audio device, then refresh the device list."
                    : "Output (loopback) captures what a DAW or browser plays through that output. Input captures a microphone or audio interface."
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeTiny
            }
            FlatButton {
                label: "Refresh devices"
                onClicked: srcPick.refresh()
            }
        }
    }
}
