import QtQuick
import QtQuick.Layouts

Rectangle {
    id: bar
    required property var viewport

    readonly property bool hasRange: viewport.markOut > viewport.markIn
    readonly property real rangeDuration: hasRange ? viewport.markOut - viewport.markIn : 0
    function formatTime(t) {
        const cs = Math.round(Math.max(0, t) * 100)
        return Math.floor(cs / 6000) + ":" + (Math.floor(cs / 100) % 60).toString().padStart(2, "0")
            + "." + (cs % 100).toString().padStart(2, "0")
    }
    readonly property bool narrow: width < 500
    implicitHeight: transportFlow.height + 8
    color: Theme.panel

    Item {
        id: transportFlow
        objectName: "transportFlow"
        width: Math.max(0, parent.width - Theme.padding * 2)
        x: Theme.padding
        y: 4
        height: (bar.narrow ? Theme.control * 2 + Theme.gapTight : Theme.control)
            + (exportRow.visible ? Theme.control + Theme.gapTight : 0)

        Row {
            id: exportRow
            y: (bar.narrow ? Theme.control * 2 + Theme.gapTight : Theme.control) + Theme.gapTight
            width: parent.width
            height: Theme.control
            visible: bar.viewport.exportStatus !== "" || bar.viewport.exporting
            spacing: Theme.gap

            Text {
                visible: bar.viewport.exportStatus !== ""
                text: bar.viewport.exportStatus
                color: bar.viewport.exporting ? Theme.accentText : Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
                elide: Text.ElideMiddle
                width: Math.max(0, transportFlow.width
                    - (cancelExport.visible ? cancelExport.width + Theme.gap : 0))
            }
            FlatButton {
                id: cancelExport
                visible: bar.viewport.exporting
                label: "Cancel"
                active: true
                onClicked: bar.viewport.cancelExport()
            }
        }

        Text {
            id: timeReadout
            objectName: "transportTimecode"
            y: (Theme.control - height) / 2
            width: Math.max(0, bar.narrow ? parent.width - rightInfo.width - 8
                : (parent.width - playback.width) / 2 - 8)
            text: bar.formatTime(bar.viewport.playhead)
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.fontMono
            font.pixelSize: Math.max(12, Theme.sizeSmall)
        }
        Row {
            id: playback
            objectName: "transportPlayback"
            anchors.horizontalCenter: parent.horizontalCenter
            y: bar.narrow ? Theme.control + Theme.gapTight : 0
            spacing: 4

            IconButton {
                kind: "back"
                width: Theme.control
                height: Theme.control
                borderless: true
                tip: "Back 5 seconds"
                onClicked: bar.viewport.seek(Math.max(0, bar.viewport.playhead - 5))
            }
            IconButton {
                kind: bar.viewport.playing ? "pause" : "play"
                width: Theme.control
                height: Theme.control
                borderless: true
                active: bar.viewport.playing
                tip: bar.viewport.playing ? "Pause (Space)" : "Play (Space)"
                onClicked: bar.viewport.playing ? bar.viewport.pause()
                                                : bar.viewport.play()
            }
            IconButton {
                kind: "fwd"
                width: Theme.control
                height: Theme.control
                borderless: true
                tip: "Forward 5 seconds"
                onClicked: bar.viewport.seek(bar.viewport.playhead + 5)
            }
            IconButton {
                kind: "stop"
                width: Theme.control
                height: Theme.control
                borderless: true
                tip: "Stop and return to the start"
                onClicked: { bar.viewport.pause(); bar.viewport.seek(0) }
            }

        }

        Row {
            id: rightInfo
            objectName: "transportInfo"
            anchors.right: parent.right
            height: Theme.control
            spacing: Theme.gap

            FlatButton {
                anchors.verticalCenter: parent.verticalCenter
                plain: true
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
