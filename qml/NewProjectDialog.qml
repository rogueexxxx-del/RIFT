import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// First thing you see. Name the project, point it at some audio and some
// footage, start.
//
// The alternative - dropping straight into an empty timeline - leaves a new
// user looking at a black rectangle with no indication that the app wants a
// file before it can do anything. Everything here is optional; "Start empty"
// exists for people who already know where they are going.
AppDialog {
    id: dlg
    required property var viewport

    title: "New project"
    width: 560
    closePolicy: Popup.NoAutoClose
    standardButtons: Dialog.NoButton

    property string mediaPath: ""
    property string audioPath: ""
    // Index into the same ratio list the export dialog uses.
    property int    aspect: 0

    function shortName(url) {
        const s = String(url)
        return s.substring(s.lastIndexOf("/") + 1)
    }

    // Anything FFmpeg can open, which is the actual limit - the file dialog
    // should not be narrower than the decoder. The named filter is a
    // convenience; "All files" is the honest one.
    FileDialog {
        id: mediaDialog
        title: "Choose video or image"
        nameFilters: ["Video (*.mp4 *.mov *.mkv *.avi *.webm *.m4v *.wmv *.flv *.mpg *.mpeg *.ts *.gif)",
                      "Images (*.png *.jpg *.jpeg *.webp *.bmp *.tif *.tiff *.tga *.exr *.dds)",
                      "All files (*)"]
        onAccepted: dlg.mediaPath = String(selectedFile)
    }
    FileDialog {
        id: audioDialog
        title: "Choose audio"
        nameFilters: ["Audio (*.wav *.mp3 *.flac *.ogg *.m4a *.aac *.opus *.wma *.aiff)",
                      "All files (*)"]
        onAccepted: dlg.audioPath = String(selectedFile)
    }

    function start(empty) {
        viewport.newProject()
        viewport.setProjectTitle(nameField.text.trim() === ""
                                 ? "Untitled" : nameField.text.trim())
        viewport.projectAspect = aspect
        if (!empty) {
            if (audioPath !== "") viewport.loadAudio(audioPath)
            if (mediaPath !== "") viewport.addClip(mediaPath)
        }
        close()
    }

    contentItem: ColumnLayout {
        spacing: Theme.groupGap

        // ── name ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gapTight
            Text {
                text: "Project name"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }
            TextField {
                id: nameField
                Layout.fillWidth: true
                implicitHeight: Theme.control + 6
                text: "Untitled"
                selectByMouse: true
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
                leftPadding: 10
                background: Rectangle {
                    color: "#161616"
                    radius: Theme.radius
                    border.width: 1
                    border.color: nameField.activeFocus ? Theme.accent : "#2E2E2E"
                }
                onAccepted: dlg.start(false)
            }
        }

        // ── shape ──
        // Asked here because composing against the wrong frame and discovering
        // it at export means redoing the work.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gapTight
            RowLayout {
                spacing: Theme.gapTight
                Text {
                    text: "Shape"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.size
                }
                Text {
                    text: "what you are composing for"
                    color: Theme.textMuted
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeTiny
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap
                Repeater {
                    model: [
                        { label: "16:9", hint: "widescreen" },
                        { label: "1:1",  hint: "square" },
                        { label: "4:3",  hint: "classic" },
                        { label: "9:16", hint: "vertical" },
                        { label: "21:9", hint: "ultrawide" }
                    ]
                    delegate: FlatButton {
                        required property var modelData
                        required property int index
                        label: modelData.label
                        active: dlg.aspect === index
                        onClicked: dlg.aspect = index
                        ToolTipArea { text: modelData.hint }
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }

        // ── files ──
        Repeater {
            model: [
                { label: "Audio",           hint: "drives everything reactive" },
                { label: "Video or image",  hint: "what the effects run on" }
            ]
            delegate: ColumnLayout {
                id: row
                required property var modelData
                required property int index
                readonly property bool isAudio: index === 0
                readonly property string picked: isAudio ? dlg.audioPath : dlg.mediaPath

                Layout.fillWidth: true
                spacing: Theme.gapTight

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gapTight
                    Text {
                        text: modelData.label
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.size
                    }
                    Text {
                        text: modelData.hint
                        color: Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeTiny
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "optional"
                        color: Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeTiny
                        visible: row.picked === ""
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gap
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.control + 6
                        color: "#161616"
                        radius: Theme.radius
                        border.width: 1
                        border.color: "#2E2E2E"
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideMiddle
                            text: row.picked === "" ? "nothing chosen"
                                                    : dlg.shortName(row.picked)
                            color: row.picked === "" ? Theme.textMuted : Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.size
                        }
                    }
                    FlatButton {
                        label: "Choose…"
                        onClicked: row.isAudio ? audioDialog.open()
                                               : mediaDialog.open()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.hairline
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            FlatButton {
                label: "Start empty"
                onClicked: dlg.start(true)
            }
            Item { Layout.fillWidth: true }
            FlatButton {
                label: "Open a project…"
                onClicked: { dlg.close(); dlg.openExisting() }
            }
            FlatButton {
                label: "Create"
                active: true
                onClicked: dlg.start(false)
            }
        }
    }

    // Wired by Main so "Open a project…" reaches the menu's file dialog rather
    // than duplicating it here.
    signal openExisting()
}
