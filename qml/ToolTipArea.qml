import QtQuick
import QtQuick.Controls

// Hover tooltip over the whole parent. Kept separate so plain Items can carry
// an explanation without every caller repeating the handler wiring.
Item {
    property alias text: tip.text
    anchors.fill: parent

    HoverHandler { id: hh }
    ToolTip {
        id: tip
        visible: hh.hovered && text !== ""
        delay: 400
    }
}
