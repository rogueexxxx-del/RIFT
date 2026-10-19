import QtQuick
import QtQuick.Controls

MenuItem {
    id: item
    implicitHeight: Math.max(28, Math.ceil((Theme.size + 12) / 4) * 4)
    implicitWidth: Math.max(136, menuLabel.implicitWidth + shortcutLabel.implicitWidth
        + leftPadding + rightPadding + (shortcutText !== "" ? Theme.gap : 0))
    leftPadding: 24
    rightPadding: subMenu ? 24 : 12
    focusPolicy: Qt.StrongFocus
    property string shortcutText: action && action.shortcut ? action.shortcut.toString() : ""
    contentItem: Item {
        Text {
            id: menuLabel
            objectName: "menuItemLabel"
            anchors.left: parent.left
            anchors.right: shortcutLabel.left
            anchors.rightMargin: item.shortcutText !== "" ? Theme.gap : 0
            anchors.verticalCenter: parent.verticalCenter
            text: item.text
            color: item.enabled ? Theme.text : Theme.textDisabled
            font.family: Theme.fontUI
            font.pixelSize: Math.max(12, Theme.size)
            elide: Text.ElideRight
        }
        Text {
            id: shortcutLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: item.shortcutText
            color: item.enabled ? Theme.textMuted : Theme.textDisabled
            font.family: Theme.fontUI
            font.pixelSize: Math.max(12, Theme.sizeSmall)
        }
    }
    indicator: Text {
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        text: item.checked ? "✓" : ""
        color: item.enabled ? Theme.text : Theme.textDisabled
        font.family: Theme.fontUI
        font.pixelSize: Math.max(12, Theme.sizeSmall)
    }
    arrow: Text {
        x: item.width - Theme.padding - 12
        anchors.verticalCenter: parent.verticalCenter
        text: item.subMenu ? "›" : ""
        color: item.enabled ? Theme.textDim : Theme.textDisabled
        font.family: Theme.fontUI
        font.pixelSize: Math.max(12, Theme.sizeSmall)
    }
    background: Rectangle {
        radius: Theme.radius
        color: item.highlighted ? Theme.hover : "transparent"
        border.width: item.visualFocus ? Theme.focusWidth : 0
        border.color: Theme.focusRing
    }
}
