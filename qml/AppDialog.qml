import QtQuick
import QtQuick.Controls

// Figma-styled Base Dialog:
// - 0px radius, dark brutalist surface (#0D0D0D)
// - Minimal 1px border (#2A2A2A)
// - Header with crisp typography and hairline separator
// - Footer with styled buttons
Dialog {
    id: dlg
    modal: true
    anchors.centerIn: Overlay.overlay
    padding: Theme.padding
    topPadding: Theme.padding
    bottomPadding: Theme.padding

    background: Rectangle {
        color: "#111111"
        radius: Theme.radius
        border.width: 1
        border.color: "#2E2E2E"
    }

    header: Item {
        visible: dlg.title !== ""
        implicitHeight: dlg.title !== "" ? 42 : 0

        Rectangle {
            anchors.fill: parent
            color: "#0D0D0D"
            radius: Theme.radius

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
            anchors.leftMargin: Theme.padding
            anchors.verticalCenter: parent.verticalCenter
            text: dlg.title.toLowerCase()
            color: "#FFFFFF"
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeTitle
            font.weight: Font.SemiBold
        }
    }

    footer: DialogButtonBox {
        visible: dlg.standardButtons !== 0
        implicitHeight: dlg.standardButtons !== 0 ? 46 : 0
        padding: Theme.padding
        alignment: Qt.AlignRight
        background: Rectangle { color: "transparent" }

        delegate: Button {
            id: btn
            implicitHeight: 28
            leftPadding: 16
            rightPadding: 16
            contentItem: Text {
                text: btn.text
                color: btn.hovered ? "#FFFFFF" : "#CCCCCC"
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
                font.weight: Font.SemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                color: btn.down ? "#000000" : (btn.hovered ? "#333333" : "#222222")
                radius: Theme.radius
                border.width: 1
                border.color: btn.hovered ? "#444444" : "#2A2A2A"
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
    }
}
