import QtQuick
import QtQuick.Layouts

// Transport only: the controls you touch while watching the picture.
// Clean, minimal, centered transport controls and timecode.
Rectangle {
    id: bar
    required property var viewport

    signal importRequested()

    implicitHeight: Theme.toolbar
    color: "#000000"

    Item {
        anchors.fill: parent
        anchors.leftMargin: Theme.padding
        anchors.rightMargin: Theme.padding

        // ── Left: Media name & Export status ──
        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap

            Text {
                readonly property bool empty: bar.viewport.mediaName === ""
                text: empty ? "no media - click to import" : bar.viewport.mediaName
                color: empty && importHover.hovered ? Theme.accent : Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
                elide: Text.ElideMiddle
                width: Math.min(implicitWidth, 220)

                HoverHandler {
                    id: importHover
                    enabled: parent.empty
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    enabled: parent.empty
                    onTapped: bar.importRequested()
                }
            }

            Text {
                visible: bar.viewport.exportStatus !== ""
                text: bar.viewport.exportStatus
                color: bar.viewport.exporting ? Theme.accent : Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
                elide: Text.ElideMiddle
                width: Math.min(implicitWidth, 200)
            }
            FlatButton {
                visible: bar.viewport.exporting
                label: "Cancel"
                active: true
                onClicked: bar.viewport.cancelExport()
            }
        }

        // ── Center: Minimal Transport Buttons & Timecode ──
        Row {
            anchors.centerIn: parent
            spacing: 6

            IconButton {
                kind: "back"
                borderless: true
                tip: "Back 5 seconds"
                onClicked: bar.viewport.seek(Math.max(0, bar.viewport.playhead - 5))
            }
            IconButton {
                kind: bar.viewport.playing ? "pause" : "play"
                borderless: true
                active: bar.viewport.playing
                tip: bar.viewport.playing ? "Pause (Space)" : "Play (Space)"
                onClicked: bar.viewport.playing ? bar.viewport.pause()
                                                : bar.viewport.play()
            }
            IconButton {
                kind: "fwd"
                borderless: true
                tip: "Forward 5 seconds"
                onClicked: bar.viewport.seek(bar.viewport.playhead + 5)
            }
            IconButton {
                kind: "stop"
                borderless: true
                tip: "Stop and return to the start"
                onClicked: { bar.viewport.pause(); bar.viewport.seek(0) }
            }

            Item { width: 12; height: 1 }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // mm:ss.cc timecode readout
                text: {
                    const t = bar.viewport.playhead
                    const m = Math.floor(t / 60)
                    const s = Math.floor(t % 60)
                    const c = Math.floor((t * 100) % 100)
                    return String(m).padStart(2, '0') + ":" +
                           String(s).padStart(2, '0') + "." +
                           String(c).padStart(2, '0')
                }
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: Theme.sizeBig
            }
        }

        // ── Right: Aspect ratio & Plain FPS readout ──
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap

            FlatButton {
                readonly property var names: ["16:9", "1:1", "4:3", "9:16", "21:9"]
                label: (bar.viewport.projectAspect >= 0 && bar.viewport.projectAspect < names.length)
                       ? names[bar.viewport.projectAspect] : "16:9"
                tip: "Aspect ratio (click to cycle)"
                onClicked: {
                    bar.viewport.projectAspect = (bar.viewport.projectAspect + 1) % names.length
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: bar.viewport.fps.toFixed(0) + " fps"
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.sizeSmall

                ToolTipArea {
                    text: "FPS: " + bar.viewport.fps.toFixed(0)
                        + "\nworst frame " + bar.viewport.frameMax.toFixed(1) + " ms"
                        + "\np95 " + bar.viewport.frameP95.toFixed(1) + " ms"
                }
            }
        }
    }
}
