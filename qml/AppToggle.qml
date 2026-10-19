import QtQuick
import QtQuick.Controls

CheckBox {
    id: control
    implicitHeight: Theme.control
    spacing: Theme.gap
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : Theme.disabledOpacity
    indicator: Rectangle {
        width: Theme.icon
        height: Theme.icon
        anchors.verticalCenter: parent.verticalCenter
        radius: Theme.radius
        color: control.down ? Theme.sunken : control.hovered ? Theme.hover : Theme.raised
        border.width: Theme.line
        border.color: control.visualFocus ? Theme.accent : control.checked ? Theme.selection : Theme.borderHover
        Text {
            anchors.centerIn: parent
            text: control.checked ? "✓" : ""
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
        }
    }
    contentItem: Text {
        text: control.text
        leftPadding: Theme.icon + Theme.gap
        verticalAlignment: Text.AlignVCenter
        color: Theme.text
        font.family: Theme.fontUI
        font.pixelSize: Theme.size
    }
}
