import QtQuick

// Four live audio bands shown as narrow, segmented level meters.
Rectangle {
    id: meters
    required property var viewport
    property int highlight: -1

    color: Theme.panel
    radius: Theme.panelRadius
    implicitHeight: 120

    Row {
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.gap

        Repeater {
            model: ["Bass", "Mids", "Highs", "Drums"]

            delegate: Item {
                id: band
                required property int index
                required property string modelData
                width: Math.max(0, (meters.width - Theme.padding * 2 - Theme.gap * 3) / 4)
                height: parent.height
                Accessible.role: Accessible.ProgressBar
                Accessible.name: modelData + " audio level"
                Accessible.description: Math.round(level * 100) + " percent"
                readonly property real level: band.index < meters.viewport.channelLevels.length
                    ? Math.max(0, Math.min(1, meters.viewport.channelLevels[band.index])) : 0

                Column {
                    id: segments
                    anchors.top: parent.top
                    anchors.bottom: label.top
                    anchors.bottomMargin: 7
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: 20
                        delegate: Rectangle {
                            width: segments.width
                            height: Math.max(1, (segments.height - 38) / 20)
                            color: index >= 20 - Math.ceil(band.level * 20)
                                   ? (meters.highlight === band.index ? "#FFFFFF" : "#D8D8D8")
                                   : "#252525"
                        }
                    }
                }

                Text {
                    id: label
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: band.modelData
                    color: Theme.textMuted
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeTiny
                }

                ToolTipArea { text: band.modelData + " level" }
            }
        }
    }
}
