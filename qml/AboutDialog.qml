import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AppDialog {
    id: dlg
    title: ""
    width: Math.min(420, Overlay.overlay ? Overlay.overlay.width - Theme.groupGap * 2 : 420)
    standardButtons: Dialog.Close

    contentItem: ScrollView {
        id: formScroll
        clip: true
        implicitHeight: form.implicitHeight
        contentWidth: availableWidth
        contentHeight: form.implicitHeight
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ColumnLayout {
        id: form
        width: formScroll.availableWidth - Theme.groupGap
        spacing: Theme.groupGap

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 180
            Layout.preferredHeight: 64

            Image {
                id: logoImg
                anchors.fill: parent
                source: Theme.logo
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Text {
                visible: logoImg.status !== Image.Ready
                anchors.centerIn: parent
                text: "RIFT"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeBig
                font.weight: Font.DemiBold
                font.letterSpacing: 2.0
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "Sound into picture."
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeTitle
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: "Edit clips, shape them with effects, and create visuals that move with your audio."
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "By"
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
            }
            Text {
                text: "Revanth Rangisetti"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "v1.0.5"
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: Theme.sizeSmall
            }
        }

        // The logo typeface is free to use on the condition that its author is
        // credited. This line is that credit - do not drop it.
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Wordmark set in Yessie's brother by Adele Markova, "
                + "SUVA Type Foundry. Full notices in THIRD-PARTY-NOTICES.md."
            color: Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Math.max(12, Theme.size)
        }
        }
    }
}
