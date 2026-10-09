import QtQuick

// Audio Channel & Master Meters (Premiere Pro style):
// - Mode 0: Main musical bands (Bass, Mid, High, Drums) with distinct colors
// - Mode 1: Stereo Master (L, R) with dB ticks and headroom gradient
// - Click header to toggle between band meters and stereo master
Rectangle {
    id: meters
    required property var viewport
    property int highlight: -1
    property int mode: 0 // 0 = Bands, 1 = Master L/R

    color: "#000000"
    implicitHeight: 120

    // Top hairline border
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hairline
    }

    // Filter down to the main 4 bands from viewport.channelNames
    readonly property var mainBands: [
        { name: "BASS", abbrev: "BAS", color: Theme.channelColor("BASS"), index: 0 },
        { name: "MIDS", abbrev: "MID", color: Theme.channelColor("MIDS"), index: 1 },
        { name: "HIGHS", abbrev: "HIG", color: Theme.channelColor("HIGHS"), index: 2 },
        { name: "DRUMS", abbrev: "DRM", color: Theme.channelColor("DRUMS"), index: 3 }
    ]

    // ── Header (Click to toggle Mode) ──
    Item {
        id: cap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 20

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: meters.mode === 0 ? "BANDS" : "MASTER L/R"
            color: headHover.hovered ? Theme.accent : Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeTiny
            font.weight: Font.Bold
            font.letterSpacing: 0.5
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: meters.mode === 0 ? "⇄ L/R" : "⇄ BANDS"
            color: headHover.hovered ? "#FFFFFF" : Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: 9
        }

        HoverHandler { id: headHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: meters.mode = (meters.mode === 0 ? 1 : 0) }
    }

    // ── Mode 0: Main Bands (Bass, Mid, High, Drums) ──
    Row {
        visible: meters.mode === 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.top: cap.bottom
        anchors.topMargin: 4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        spacing: 8

        Repeater {
            model: meters.mainBands

            delegate: Item {
                id: bandItem
                required property int index
                required property var modelData
                width: Math.max(16, (parent.width - 3 * 8) / 4)
                height: parent.height

                readonly property real level: modelData.index < meters.viewport.channelLevels.length
                    ? meters.viewport.channelLevels[modelData.index] : 0
                readonly property bool lit: meters.highlight === modelData.index

                // Track well
                Rectangle {
                    id: bandWell
                    anchors.fill: parent
                    radius: 2
                    color: "#121212"
                    border.width: 1
                    border.color: bandItem.lit ? "#FFFFFF" : "#242424"

                    // Upward level fill
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Math.max(0, parent.height * Math.max(0, Math.min(1, bandItem.level)))
                        radius: 2
                        color: bandItem.modelData.color
                    }

                    ToolTipArea {
                        text: bandItem.modelData.name + " (" + bandItem.modelData.abbrev + ")"
                    }
                }
            }
        }
    }

    // ── Mode 1: Stereo Master (L / R) ──
    Row {
        visible: meters.mode === 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.top: cap.bottom
        anchors.topMargin: 4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        spacing: 8

        // Left Channel
        Item {
            id: leftChannel
            width: (parent.width - 8) / 2
            height: parent.height

            readonly property real level: meters.viewport.channelLevels.length > 0
                ? meters.viewport.channelLevels[0] : 0

            Rectangle {
                id: lWell
                anchors.fill: parent
                radius: 2
                color: "#141414"

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.max(0, parent.height * Math.max(0, Math.min(1, leftChannel.level)))
                    radius: 2
                    color: leftChannel.level > 0.9 ? "#FF4040" : (leftChannel.level > 0.75 ? "#FFD000" : "#40FF60")
                }

                ToolTipArea { text: "Master L" }
            }
        }

        // Right Channel
        Item {
            id: rightChannel
            width: (parent.width - 8) / 2
            height: parent.height

            readonly property real level: meters.viewport.channelLevels.length > 1
                ? meters.viewport.channelLevels[1] : 0

            Rectangle {
                id: rWell
                anchors.fill: parent
                radius: 2
                color: "#141414"

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.max(0, parent.height * Math.max(0, Math.min(1, rightChannel.level)))
                    radius: 2
                    color: rightChannel.level > 0.9 ? "#FF4040" : (rightChannel.level > 0.75 ? "#FFD000" : "#40FF60")
                }

                ToolTipArea { text: "Master R" }
            }
        }
    }
}
