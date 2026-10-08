import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Preset library, at the top of the effect chain.
//
// Saving a preset already worked, but it lived behind a file dialog in the File
// menu and there was nowhere to see one afterwards, so nobody would ever find
// it. A preset is the whole look - chain, parameters, audio patches, keyframes
// and grade - with no clips, so applying one drops it onto whatever footage is
// already loaded.
Item {
    id: bar
    required property var viewport
    implicitHeight: 26

    RowLayout {
        anchors.fill: parent
        spacing: Theme.gapTight

        Text {
            text: "Presets"
            color: Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
        }
        Item { Layout.fillWidth: true }

        FlatButton {
            label: "Save"
            onClicked: { nameField.text = ""; saveDlg.open() }
            ToolTipArea { text: "Save this whole look as a preset" }
        }
        FlatButton {
            label: "Load"
            active: listPopup.opened
            onClicked: listPopup.opened ? listPopup.close() : listPopup.open()
            ToolTipArea { text: "Apply a saved preset" }
        }
    }

    // ── name it ──
    AppDialog {
        id: saveDlg
        title: "Save preset"
        width: 380
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: bar.viewport.savePresetNamed(nameField.text)

        contentItem: ColumnLayout {
            spacing: Theme.gap
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Saves the effect chain, settings, audio patches, "
                    + "keyframes and colour grade. Clips are not included, so "
                    + "this can be applied to any footage."
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
            }
            TextField {
                id: nameField
                Layout.fillWidth: true
                implicitHeight: Theme.control
                placeholderText: "preset name"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
                leftPadding: 8
                background: Rectangle {
                    color: Theme.sunken
                    radius: Theme.radius
                    border.width: 1
                    border.color: nameField.activeFocus ? Theme.accent : Theme.hairline
                }
                onAccepted: { saveDlg.accept() }
            }
        }
    }

    // ── pick one ──
    // A Popup in the overlay, not an inline list: the effects panel clips its
    // contents, so anything drawn in place would be cut off.
    Popup {
        id: listPopup
        parent: Overlay.overlay
        modal: false
        focus: true
        padding: 1
        width: 260
        x: {
            const g = bar.mapToItem(Overlay.overlay, 0, bar.height + 4)
            return Math.min(g.x, Overlay.overlay.width - width - 8)
        }
        y: {
            const g = bar.mapToItem(Overlay.overlay, 0, bar.height + 4)
            return Math.min(g.y, Overlay.overlay.height - height - 8)
        }
        onOpened: bar.viewport.presetList   // re-read on open

        background: Rectangle {
            color: Theme.bg
            radius: Theme.radius
            border.width: 1
            border.color: Theme.accent
        }

        contentItem: ColumnLayout {
            spacing: 0

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 300)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                model: bar.viewport.presetList

                delegate: Item {
                    required property var modelData
                    width: list.width
                    height: 30

                    Rectangle {
                        anchors.fill: parent
                        color: hover.hovered ? Theme.raised : "transparent"
                    }
                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        // Not over the delete glyph. Nested TapHandlers both
                        // receive a tap, so pressing x ALSO ran this - the preset
                        // was applied to the session on its way out of the
                        // library.
                        onTapped: (pt) => {
                            if (pt.position.x > parent.width - 36) return
                            bar.viewport.applyPreset(modelData.path)
                            listPopup.close()
                        }
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 46
                        elide: Text.ElideRight
                        text: modelData.name
                        color: Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.size
                    }
                    // Delete. Small and on the right so it is not the thing you
                    // hit when reaching for the name.
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "×"
                        color: delHover.hovered ? Theme.danger : Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.size
                        HoverHandler { id: delHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: bar.viewport.deletePreset(modelData.path) }
                        ToolTipArea { text: "Delete this preset" }
                    }
                }
            }

            Text {
                visible: list.count === 0
                Layout.fillWidth: true
                Layout.margins: 10
                wrapMode: Text.WordWrap
                text: "No presets yet. Build a look, then press Save."
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
            }
        }
    }
}
