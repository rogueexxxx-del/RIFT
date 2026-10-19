import QtQuick
import QtQuick.Layouts

// Live mode's transport strip. Mappings live in ControllerView above this, so
// this is only the things you reach for mid-set: audio in, playback, level.
Rectangle {
    id: bar
    required property var viewport

    implicitHeight: controls.implicitHeight + Theme.padding * 2
    color: Theme.panel
    radius: Theme.panelRadius

    Canvas {
        id: listeningGlow
        objectName: "audioListeningGlow"
        x: controls.x + audioListen.x - 12
        y: controls.y + audioListen.y - 12
        width: audioListen.width + 24
        height: audioListen.height + 24
        visible: bar.viewport.liveInput && Theme.glowAllowed
        opacity: 0.3
        onVisibleChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections { target: Theme; function onAccentChanged() { listeningGlow.requestPaint() } }
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.scale(width / 2, height / 2)
            const glow = ctx.createRadialGradient(1, 1, 0.2, 1, 1, 1)
            glow.addColorStop(0, Theme.accent.toString())
            glow.addColorStop(1, "transparent")
            ctx.fillStyle = glow
            ctx.fillRect(0, 0, 2, 2)
        }
    }
    Flow {
        id: controls
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.padding
        spacing: Theme.gap

        // No transport here. It already sits under the viewport, and having it
        // twice on screen in Live mode meant two controls that looked alike and
        // did the same thing.

        FlatButton {
            id: audioListen
            objectName: "audioListeningButton"
            label: bar.viewport.liveInput ? "Audio: listening" : "Audio: stopped"
            active: bar.viewport.liveInput
            implicitWidth: 156
            onClicked: bar.viewport.liveInput = !bar.viewport.liveInput
            ToolTipArea { text: "React to the mic or loopback device instead of a file" }
        }

        // The one reading that matters on stage: is anything getting in.
        Rectangle {
            width: Math.min(180, controls.width)
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

        Text {
            text: bar.viewport.midiOpen ? "MIDI: " + bar.viewport.midiName : "MIDI: not connected"
            color: bar.viewport.midiOpen ? Theme.accentText : Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
            width: Math.min(260, controls.width)
            wrapMode: Text.WordWrap
        }
    }
}
