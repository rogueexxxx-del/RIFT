import QtQuick
import QtQuick.Controls

// Figma-styled Parameter Slider:
// - Title on left, channel name + LINK button on right
// - Thick rectangular track (#2B2B2B)
// - Modulated fill uses channel color, unlinked fill is solid white (#FFFFFF)
// - 0px radius, clean minimal aesthetic
Item {
    id: ctl

    property string label: ""
    property real from: 0
    property real to: 1
    property real stepSize: 0.01
    property bool discrete: false
    property real value: 0
    property bool patched: false
    property string channelName: ""
    property color tint: Theme.channelColor(channelName)
    property bool keyed: false
    property var availableChannels: []

    signal moved(real v)
    signal linkRequested(int channelIndex)
    signal labelClicked()

    implicitHeight: 44

    function snap(v) {
        const clamped = Math.max(ctl.from, Math.min(ctl.to, v))
        if (ctl.stepSize <= 0) return clamped
        const s = Math.round((clamped - ctl.from) / ctl.stepSize) * ctl.stepSize + ctl.from
        return Math.max(ctl.from, Math.min(ctl.to, s))
    }
    function fraction() {
        return ctl.to > ctl.from ? (ctl.shown - ctl.from) / (ctl.to - ctl.from) : 0
    }
    function apply(px) {
        const f = Math.max(0, Math.min(1, px / track.width))
        const v = ctl.snap(ctl.from + f * (ctl.to - ctl.from))
        ctl.shown = v
        ctl.moved(v)
    }

    function titleCase(s) {
        if (!s) return ""
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    property real shown: value
    onValueChanged: shown = value

    // ── Header Row: Label on left, Channel + LINK on right ──
    Item {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 18

        Text {
            id: nameText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: ctl.titleCase(ctl.label) + (ctl.keyed ? " ◆" : "")
            color: ctl.patched ? ctl.tint : (nameHover.hovered ? Theme.accent : Theme.text)
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
            font.weight: Font.Normal

            HoverHandler { id: nameHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ctl.labelClicked() }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            // Value readout
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ctl.discrete ? Math.round(ctl.shown) : ctl.shown.toFixed(2)
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.sizeSmall
            }

            // Patched channel text indicator
            Text {
                visible: ctl.patched && ctl.channelName !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: ctl.channelName.toLowerCase()
                color: ctl.tint
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeTiny
                font.weight: Font.Bold
                font.underline: true
            }

            // LINK Button
            Rectangle {
                id: linkBtn
                anchors.verticalCenter: parent.verticalCenter
                width: ctl.patched ? 46 : 36
                height: 18
                radius: 3
                color: ctl.patched ? ctl.tint : (linkHover.hovered ? "#383838" : "#222222")
                border.width: 1
                border.color: ctl.patched ? ctl.tint : "#444444"

                Text {
                    anchors.centerIn: parent
                    text: ctl.patched ? "LINKED" : "LINK"
                    color: ctl.patched ? "#000000" : (linkHover.hovered ? "#FFFFFF" : "#888888")
                    font.family: Theme.fontUI
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 0.5
                }

                HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (linkMenu.visible) {
                            linkMenu.close()
                        } else {
                            linkMenu.open()
                        }
                    }
                }

                Menu {
                    id: linkMenu
                    y: linkBtn.height + 2
                    x: linkBtn.width - width

                    MenuItem {
                        text: "None (Unlink)"
                        onTriggered: ctl.linkRequested(-1)
                    }
                    MenuSeparator {}
                    Repeater {
                        model: ctl.availableChannels
                        MenuItem {
                            required property int index
                            required property var modelData
                            text: (modelData.name || modelData).toString().toLowerCase()
                            onTriggered: ctl.linkRequested(index)
                        }
                    }
                }
            }
        }
    }

    // ── Track Bar: #2B2B2B background, colored / white fill ──
    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        height: 12
        radius: 3
        color: "#2B2B2B"

        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(0, parent.width * ctl.fraction())
            radius: 3
            color: ctl.patched ? ctl.tint : "#FFFFFF"
        }

        // Hit / Drag area
        Item {
            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -6

            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: (pt) => ctl.apply(pt.position.x)
            }
            DragHandler {
                id: drag
                target: null
                onCentroidChanged: if (active) ctl.apply(centroid.position.x)
            }
        }
    }
}
