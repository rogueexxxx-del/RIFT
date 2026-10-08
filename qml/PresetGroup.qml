import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Categorized group of presets matching Figma layout:
// - Header with "▼ <TITLE>" or "▶ <TITLE>" (back button / chevron style)
// - Grid of square preset preview cards with rich hover/active states
// - Right-click context menu: Rename, Duplicate, Copy, Delete, Open in Folder
Rectangle {
    id: group
    required property var viewport
    property string groupTitle: ""
    property bool expanded: true
    property string filterTag: "all"

    color: "transparent"
    implicitWidth: 200
    implicitHeight: col.implicitHeight

    // Active item for context actions
    property var contextItem: null

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 6

        // Folder Header Row
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 24
            radius: 3
            color: headerHover.hovered ? Theme.hover : "transparent"

            Row {
                anchors.fill: parent
                anchors.leftMargin: 4
                spacing: 8

                // Chevron icon (clean vector indicator matching dock header style)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: group.expanded ? "▼" : "▶"
                    color: headerHover.hovered ? Theme.accent : Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 10
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: group.groupTitle
                    color: headerHover.hovered ? Theme.text : Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeSmall
                    font.weight: Font.DemiBold
                }
            }

            HoverHandler { id: headerHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: group.expanded = !group.expanded }
        }

        // Preset Grid (4 columns matching Figma 5_147.png)
        Grid {
            visible: group.expanded
            Layout.fillWidth: true
            columns: 4
            spacing: 6

            Repeater {
                model: {
                    const all = group.viewport.presetList
                    if (!all || all.length === 0) {
                        if (group.filterTag === "fav") {
                            return [
                                { name: "neon_acid", path: "", effect: "ascii" },
                                { name: "cyber_grid", path: "", effect: "tunnel" }
                            ]
                        }
                        if (group.filterTag === "new") {
                            return [
                                { name: "tape_mosh", path: "", effect: "datamosh" }
                            ]
                        }
                        return [
                            { name: "risorift", path: "", effect: "risograph" }
                        ]
                    }
                    // Filter if user has presets
                    if (group.filterTag === "fav") {
                        const favs = all.filter(p => p.name.toLowerCase().indexOf("fav") !== -1 || p.name.indexOf("1") !== -1)
                        return favs.length > 0 ? favs : all.slice(0, 2)
                    }
                    if (group.filterTag === "new") {
                        const news = all.filter(p => p.name.toLowerCase().indexOf("new") !== -1)
                        return news.length > 0 ? news : (all.length > 2 ? [all[2]] : [])
                    }
                    return all
                }

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: Math.max(36, Math.floor((group.width - 24) / 4))
                    height: width
                    radius: 4
                    color: Theme.raised
                    border.width: cardHover.hovered ? 2 : 1
                    border.color: cardHover.hovered ? Theme.accent : Theme.border

                    // Preview thumbnail
                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        source: Theme.asset("effect_previews/" + (modelData.effect || "ascii") + ".png")
                        fillMode: Image.PreserveAspectCrop
                        opacity: 0.4
                    }

                    // Bottom name bar
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 20
                        color: Qt.rgba(0, 0, 0, 0.82)

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 4
                            text: (modelData.name || "preset").toLowerCase()
                            color: Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }

                    // Left click: Apply preset
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: {
                            if (modelData.path) {
                                group.viewport.applyPreset(modelData.path)
                            }
                        }
                    }

                    // Right click: Context menu
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: (point) => {
                            group.contextItem = modelData
                            presetMenu.popup()
                        }
                    }

                    ToolTipArea {
                        text: modelData.name + (modelData.path ? " (Right-click for options)" : "")
                    }
                }
            }
        }
    }

    // ── Right-Click Context Menu ──
    Menu {
        id: presetMenu

        MenuItem {
            text: "Apply Preset"
            onTriggered: {
                if (group.contextItem && group.contextItem.path) {
                    group.viewport.applyPreset(group.contextItem.path)
                }
            }
        }

        MenuItem {
            text: "Rename..."
            enabled: group.contextItem && group.contextItem.path !== ""
            onTriggered: {
                if (group.contextItem) {
                    renameField.text = group.contextItem.name || ""
                    renameDlg.open()
                }
            }
        }

        MenuItem {
            text: "Duplicate"
            enabled: group.contextItem && group.contextItem.path !== ""
            onTriggered: {
                if (group.contextItem && group.contextItem.path) {
                    group.viewport.duplicatePreset(group.contextItem.path)
                }
            }
        }

        MenuItem {
            text: "Copy Preset Name"
            onTriggered: {
                if (group.contextItem) {
                    // Quick clip copy
                    renameField.text = group.contextItem.name || ""
                    renameField.selectAll()
                    renameField.copy()
                }
            }
        }

        MenuSeparator {}

        MenuItem {
            text: "Delete Preset"
            enabled: group.contextItem && group.contextItem.path !== ""
            onTriggered: {
                if (group.contextItem && group.contextItem.path) {
                    group.viewport.deletePreset(group.contextItem.path)
                }
            }
        }

        MenuSeparator {}

        MenuItem {
            text: "Show in File Explorer"
            onTriggered: {
                const folder = group.viewport.presetsFolder()
                Qt.openUrlExternally("file:///" + folder.replace(/\\/g, "/"))
            }
        }
    }

    // ── Rename Preset Dialog ──
    AppDialog {
        id: renameDlg
        title: "Rename Preset"
        width: 320
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: {
            if (group.contextItem && group.contextItem.path && renameField.text.trim() !== "") {
                group.viewport.renamePreset(group.contextItem.path, renameField.text.trim())
            }
        }

        contentItem: ColumnLayout {
            spacing: 8
            Text {
                text: "New name for preset:"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
            }
            TextField {
                id: renameField
                Layout.fillWidth: true
                implicitHeight: 30
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
                background: Rectangle {
                    color: Theme.panel
                    border.width: 1
                    border.color: Theme.border
                    radius: 3
                }
                onAccepted: renameDlg.accept()
            }
        }
    }
}
