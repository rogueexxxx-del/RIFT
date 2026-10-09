import QtQuick
import QtQuick.Controls

// A Menu in the app's own palette.
//
// The Basic style draws menus as a light panel with a hard 1px frame, which is
// the white border showing through on a dark UI. Restyling has to cover the
// popup background AND the item delegate - the item paints its own background,
// so theming only the menu leaves white rows inside a dark box.
Menu {
    id: menu

    // Popup.Item keeps the menu inside the scene graph instead of spawning a
    // native window, so it inherits the window's theme and cannot be clipped.
    popupType: Popup.Item
    padding: 6
    implicitWidth: 260

    background: Rectangle {
        color: "#141414"
        radius: 4
        border.width: 1
        border.color: "#2A2A2A"
    }

    delegate: MenuItem {
        id: mi
        implicitHeight: 28
        leftPadding: 14
        rightPadding: 14

        contentItem: Text {
            text: mi.text
            color: !mi.enabled ? "#555555"
                 : mi.highlighted ? "#FFFFFF" : "#CCCCCC"
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
            font.weight: mi.highlighted ? Font.Medium : Font.Normal
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: mi.highlighted ? "#222222" : "transparent"
            radius: 3
            border.width: mi.highlighted ? 1 : 0
            border.color: "#333333"
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }
}
