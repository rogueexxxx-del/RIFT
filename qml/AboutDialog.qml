import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AppDialog {
    id: dlg
    title: ""
    width: 480
    standardButtons: Dialog.Close

    contentItem: ColumnLayout {
        spacing: 14

        // Official RIFT Wordmark Logo
        Item {
            Layout.preferredWidth: 140
            Layout.preferredHeight: 36

            Image {
                id: logoImg
                anchors.fill: parent
                source: Theme.logo
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Text {
                visible: logoImg.status !== Image.Ready
                anchors.verticalCenter: parent.verticalCenter
                text: "RIFT"
                color: "#FFFFFF"
                font.family: Theme.fontUI
                font.pixelSize: 26
                font.weight: Font.Bold
                font.letterSpacing: 2.0
            }
        }

        Text {
            text: "Sound into picture"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeTitle
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            lineHeight: 1.4
            text: "Every tool for this is either a toy or a second job. The "
                + "simple ones make one look and stop. The serious ones expect "
                + "you to already know what a feedback buffer is."
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            lineHeight: 1.4
            text: "RIFT is the middle. Nothing hidden behind jargon, nothing "
                + "dumbed down, and you should get somewhere good on the first "
                + "evening - without giving up the ceiling later."
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            lineHeight: 1.4
            text: "Made because the thing I wanted to use did not exist."
            color: Theme.textDim
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
                text: "v1.0.0"
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: Theme.sizeSmall
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Designed by a human, written with AI."
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Qt RHI (Direct3D 11) · FFmpeg · miniaudio · pffft"
            color: Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeTiny
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
            font.pixelSize: Theme.sizeTiny
        }
    }
}
