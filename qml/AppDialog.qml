import QtQuick
import QtQuick.Controls

// Shared, screen-bounded dialog chrome. Long forms supply a ScrollView.
Dialog {
    id: dlg
    modal: true
    anchors.centerIn: Overlay.overlay
    popupType: Popup.Item
    padding: Theme.groupGap
    height: Math.min(implicitHeight, Overlay.overlay ? Overlay.overlay.height - Theme.groupGap * 2 : implicitHeight)
    font.family: Theme.fontUI
    font.pixelSize: Theme.size

    background: Rectangle {
        color: Theme.flyout
        radius: Theme.panelRadius
        border.width: 1
        border.color: Theme.popupBorder
    }

    header: Item {
        visible: dlg.title !== ""
        implicitHeight: dlg.title !== "" ? Theme.header + Theme.gap : 0

        Rectangle {
            anchors.fill: parent
            color: "transparent"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.hairline
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.groupGap
            anchors.right: parent.right
            anchors.rightMargin: Theme.groupGap
            anchors.verticalCenter: parent.verticalCenter
            text: dlg.title
            color: Theme.text
            elide: Text.ElideRight
            font.family: Theme.fontUI
            font.pixelSize: Math.max(12, Theme.sizeTitle)
            font.weight: Font.DemiBold
        }
    }

    footer: DialogButtonBox {
        visible: dlg.standardButtons !== 0
        implicitHeight: dlg.standardButtons !== 0 ? Theme.control + Theme.groupGap * 2 : 0
        padding: Theme.groupGap
        spacing: Theme.gap
        alignment: Qt.AlignRight
        background: Rectangle { color: "transparent" }

        delegate: Button {
            id: btn
            implicitHeight: Theme.control
            implicitWidth: Math.max(96, implicitContentWidth + leftPadding + rightPadding)
            leftPadding: Theme.groupGap
            rightPadding: Theme.groupGap
            contentItem: Text {
                text: btn.text
                color: btn.enabled ? Theme.text : Theme.textDisabled
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                color: btn.down ? Theme.sunken : (btn.hovered ? Theme.hover : Theme.raised)
                radius: Theme.radius
                border.width: btn.visualFocus ? Theme.focusWidth : 1
                border.color: btn.visualFocus ? Theme.focusRing : Theme.popupBorder
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
    }
}
