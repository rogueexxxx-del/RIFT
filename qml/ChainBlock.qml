import QtQuick

// Figma-styled Effect Chain Block (matches Figma node 7:126):
// - Solid colored card 225x50, radius: 0 using unique effect color (Theme.effectColor)
// - Centered black text (Arial/Geist style, tight letter spacing)
// - Background preview thumbnail image overlay
// - 13x4 white caps with 1px black stroke on top and bottom edges
Rectangle {
    id: blk

    property string label: ""
    property string sub: ""
    property bool   active: false
    property string badge: ""
    property bool   isSource: false
    property bool   isOutput: false

    readonly property string effectId: label.toLowerCase().replace(/ /g, "_")
    readonly property color nodeColor: isSource ? "#333333"
                                     : (isOutput ? "#1F1F1F" : Theme.effectColor(effectId))

    implicitWidth: 225
    implicitHeight: 50
    radius: 0
    color: nodeColor
    border.width: blk.active ? 2 : 0
    border.color: blk.active ? "#FFFFFF" : "transparent"

    // Preview thumbnail background with subtle blend
    Image {
        id: previewImg
        anchors.fill: parent
        visible: !blk.isSource && !blk.isOutput
        source: visible ? Theme.asset("effect_previews/" + blk.effectId + ".png") : ""
        fillMode: Image.PreserveAspectCrop
        opacity: 0.28
        clip: true
    }

    // Top cap (13x4 white rectangle with 1px black stroke centered at top edge)
    Rectangle {
        visible: !blk.isSource
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -2
        width: 13
        height: 4
        radius: 0
        color: "#FFFFFF"
        border.width: 1
        border.color: "#000000"
        z: 2
    }

    // Bottom cap (13x4 white rectangle with 1px black stroke centered at bottom edge)
    Rectangle {
        visible: !blk.isOutput
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -2
        width: 13
        height: 4
        radius: 0
        color: "#FFFFFF"
        border.width: 1
        border.color: "#000000"
        z: 2
    }

    // Centered label (Figma: font size 24, letter spacing -1.92, black)
    Column {
        id: txt
        anchors.centerIn: parent
        spacing: 2
        z: 3

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: blk.label.toLowerCase()
            color: blk.isSource || blk.isOutput ? "#FFFFFF" : "#000000"
            font.family: Theme.fontUI
            font.pixelSize: blk.isSource || blk.isOutput ? 14 : (text.length > 12 ? 15 : 18)
            font.weight: Font.DemiBold
            font.letterSpacing: -0.4
        }

        Text {
            visible: blk.sub !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: blk.sub
            color: blk.isSource || blk.isOutput ? "#AAAAAA" : "#222222"
            font.family: Theme.fontUI
            font.pixelSize: 10
            elide: Text.ElideMiddle
            width: Math.min(implicitWidth, 200)
        }
    }

    // Mix / blend mode badge (if altered)
    Rectangle {
        visible: blk.badge !== ""
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 4
        height: 14
        width: badgeText.implicitWidth + 6
        radius: 0
        color: "#000000"
        z: 4

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: blk.badge
            color: "#FFFFFF"
            font.family: Theme.fontUI
            font.pixelSize: 8
            font.weight: Font.Bold
        }
    }
}
