import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Left Dock: Effect Chain & Presets View
// - Tab switcher: "Effect Chain" / "Presets"
// - Solid colored node blocks with centered black text and preview thumbnails
// - White bracket connector lines
// - Categorized preset groups with square thumbnails and "+" add preset
Rectangle {
    id: rail
    required property var viewport
    property var effectIds: []

    property int currentTab: 0 // 0 = Effect Chain, 1 = Presets
    signal nodeSelected(int index)

    readonly property int nodeH: 48
    readonly property int gap: 16
    readonly property int slotH: nodeH + gap

    color: "#000000"

    function openAdd() {
        if (addPopup.opened) { addPopup.close(); return }
        addPopup.replaceIndex = -1
        addPopup.open()
    }
    function openSavePreset() {
        nameField.text = ""
        saveDlg.open()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // ══════════════════════════════════════════════════════════════════
        // TAB 0: EFFECT CHAIN
        // ══════════════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: rail.currentTab === 0
            spacing: 8

            // Banner shown when a clip is selected and being edited
            Rectangle {
                visible: rail.viewport && rail.viewport.editedClip >= 0
                Layout.fillWidth: true
                height: 26
                radius: 3
                color: Theme.accentSoft
                border.width: 1
                border.color: Theme.accent

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: "CLIP " + (rail.viewport.editedClip + 1) + " FX"
                        color: Theme.accent
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    FlatButton {
                        label: "Master FX"
                        tip: "Deselect clip and return to Master Effects"
                        implicitHeight: 18
                        onClicked: rail.viewport.selectClip(-1)
                    }
                }
            }

            ScrollView {
                id: chainScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                Column {
                    id: chainCol
                    width: chainScroll.width
                    spacing: 0

                    // Placeholder when no effects exist
                    Item {
                        visible: chainRep.count === 0
                        width: chainCol.width
                        height: 120
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (rail.viewport && rail.viewport.editedClip >= 0) ? "No effects on this clip" : "No master effects"
                                color: Theme.textMuted
                                font.family: Theme.fontUI
                                font.pixelSize: Theme.sizeSmall
                            }
                            FlatButton {
                                anchors.horizontalCenter: parent.horizontalCenter
                                label: "+ Add Effect"
                                active: true
                                onClicked: rail.openAdd()
                            }
                        }
                    }

                    // Effect Chain Nodes
                    Repeater {
                        id: chainRep
                        model: rail.viewport ? rail.viewport.chain : []

                        delegate: Column {
                            id: holder
                            required property int index
                            required property var modelData
                            width: chainCol.width
                            spacing: 0

                            property real dy: 0
                            property real dx: 0
                            property int  shift: Math.round(dy / (50 + 24))
                            property bool removing: Math.abs(dx) > 60
                            readonly property int  blendMode: holder.modelData.blend || 0
                            readonly property real mixAmt:
                                holder.modelData.mix === undefined ? 1.0 : holder.modelData.mix

                            ChainBlock {
                                id: block
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(260, Math.max(180, chainCol.width - 24))
                                height: 50
                                badge: (holder.blendMode !== 0 || holder.mixAmt < 0.999)
                                       ? rail.viewport.blendNames()[holder.blendMode]
                                         + " " + Math.round(holder.mixAmt * 100) + "%"
                                       : ""
                                label: holder.modelData.label
                                active: holder.modelData.selected || drag.active
                                opacity: holder.removing ? 0.45 : 1.0

                                TapHandler {
                                    onTapped: {
                                        rail.viewport.selectedNode = holder.index
                                        rail.nodeSelected(holder.index)
                                    }
                                }
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: {
                                        rail.viewport.selectedNode = holder.index
                                        rail.nodeSelected(holder.index)
                                        nodeMenu.targetIndex = holder.index
                                        nodeMenu.open()
                                    }
                                }
                                DragHandler {
                                    id: drag
                                    target: null
                                    onActiveChanged: {
                                        if (active) {
                                            rail.viewport.selectedNode = holder.index
                                            rail.nodeSelected(holder.index)
                                            return
                                        }
                                        if (holder.removing) rail.viewport.removeNode(holder.index)
                                        else if (holder.shift !== 0)
                                            rail.viewport.moveNode(holder.index, holder.shift)
                                        holder.dx = 0; holder.dy = 0
                                    }
                                    onCentroidChanged: {
                                        if (!active) return
                                        holder.dx = centroid.position.x - centroid.pressPosition.x
                                        holder.dy = centroid.position.y - centroid.pressPosition.y
                                    }
                                }
                            }

                            // Connector wire between blocks (only between adjacent nodes)
                            Rectangle {
                                visible: holder.index < (chainRep.count - 1)
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 1
                                height: 24
                                color: "#FFFFFF"
                            }
                        }
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════
        // TAB 1: PRESETS
        // ══════════════════════════════════════════════════════════════════
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: rail.currentTab === 1

            ScrollView {
                id: presetScroll
                anchors.fill: parent
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    width: presetScroll.width
                    spacing: 12

                    // Preset Category Folders matching Figma:
                    // 1. "v FAV"
                    PresetGroup {
                        Layout.fillWidth: true
                        groupTitle: "FAV"
                        expanded: true
                        viewport: rail.viewport
                        filterTag: "fav"
                    }

                    // 2. "> NEW STUFF"
                    PresetGroup {
                        Layout.fillWidth: true
                        groupTitle: "NEW STUFF"
                        expanded: false
                        viewport: rail.viewport
                        filterTag: "new"
                    }

                    // 3. "v Top Secrettttttttt"
                    PresetGroup {
                        Layout.fillWidth: true
                        groupTitle: "Top Secrettttttttt"
                        expanded: true
                        viewport: rail.viewport
                        filterTag: "all"
                    }
                }
            }
        }
    }

    // ── Save Preset Dialog ──
    AppDialog {
        id: saveDlg
        title: "Save preset"
        width: 340
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: rail.viewport.savePresetNamed(nameField.text)

        contentItem: ColumnLayout {
            spacing: Theme.gap
            TextField {
                id: nameField
                Layout.fillWidth: true
                implicitHeight: 32
                placeholderText: "preset name"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
                background: Rectangle {
                    color: Theme.sunken
                    border.width: 1
                    border.color: nameField.activeFocus ? Theme.accent : Theme.hairline
                }
                onAccepted: saveDlg.accept()
            }
        }
    }

    // ── Add Effect Popup ──
    Popup {
        id: addPopup
        parent: Overlay.overlay
        modal: false
        focus: true
        padding: 8
        width: 260
        x: {
            if (!Overlay.overlay) return 260
            const g = rail.mapToItem(Overlay.overlay, rail.width + 6, 0)
            return Math.max(8, Math.min(g.x, Overlay.overlay.width - width - 12))
        }
        y: {
            if (!Overlay.overlay) return 52
            const g = rail.mapToItem(Overlay.overlay, 0, 48)
            const minY = 52  // Keep safely below the top menu bar
            const maxY = Math.max(minY, Overlay.overlay.height - height - 16)
            return Math.max(minY, Math.min(g.y, maxY))
        }

        background: Rectangle {
            color: Theme.panel
            border.width: 1
            border.color: Theme.border
            radius: 4
        }

        onOpened: { filter.text = ""; filter.forceActiveFocus() }

        contentItem: ColumnLayout {
            spacing: 8

            TextField {
                id: filter
                Layout.fillWidth: true
                placeholderText: "Search effects..."
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
                background: Rectangle {
                    color: Theme.bg
                    implicitHeight: 28
                    border.width: 1
                    border.color: filter.activeFocus ? Theme.accent : Theme.border
                    radius: 3
                }
                onAccepted: if (hits.count > 0) addPopup.pick(hits.itemAtIndex(0).id)
                Keys.onEscapePressed: addPopup.close()
            }

            ListView {
                id: hits
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 380)
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                model: rail.effectIds.filter(function (e) {
                    return filter.text === ""
                        || e.indexOf(filter.text.toLowerCase()) !== -1
                        || Theme.nice(e).toLowerCase().indexOf(filter.text.toLowerCase()) !== -1
                })

                // Delegate styled matching Effect Chain blocks (solid color, preview image, centered text)
                delegate: Rectangle {
                    id: effectCard
                    required property string modelData
                    readonly property string id: modelData
                    width: hits.width - 6
                    height: 42
                    radius: 3
                    color: Theme.effectColor(modelData)
                    border.width: hover.hovered ? 2 : 1
                    border.color: hover.hovered ? "#FFFFFF" : Qt.rgba(0, 0, 0, 0.4)
                    clip: true

                    // Preview thumbnail overlay
                    Image {
                        anchors.fill: parent
                        source: Theme.asset("effect_previews/" + modelData + ".png")
                        fillMode: Image.PreserveAspectCrop
                        opacity: 0.28
                    }

                    readonly property color cardTextColor: {
                        const c = Theme.effectColor(modelData)
                        const lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
                        return lum > 0.45 ? "#000000" : "#FFFFFF"
                    }

                    // Top bracket cap
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: -2
                        width: 13
                        height: 4
                        color: "#FFFFFF"
                        border.width: 1
                        border.color: "#000000"
                    }

                    // Bottom bracket cap
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -2
                        width: 13
                        height: 4
                        color: "#FFFFFF"
                        border.width: 1
                        border.color: "#000000"
                    }

                    // Centered title matching Effect Chain with dynamic contrast
                    Text {
                        anchors.centerIn: parent
                        text: Theme.nice(modelData).toLowerCase()
                        color: parent.cardTextColor
                        font.family: Theme.fontUI
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.4
                    }

                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: addPopup.pick(modelData) }
                }
            }
        }

        property int replaceIndex: -1

        function pick(id) {
            if (replaceIndex >= 0) {
                rail.viewport.selectedNode = replaceIndex
                rail.viewport.effect = id
                rail.nodeSelected(replaceIndex)
            } else {
                rail.viewport.addNode(id)
                rail.nodeSelected(rail.viewport.chain.length - 1)
            }
            close()
        }
    }

    // ── Node Right-Click Context Menu ──
    StyledMenu {
        id: nodeMenu
        property int targetIndex: -1

        Action {
            text: "Change Effect..."
            onTriggered: {
                if (nodeMenu.targetIndex >= 0) {
                    addPopup.replaceIndex = nodeMenu.targetIndex
                    addPopup.open()
                }
            }
        }
        Action {
            text: "Duplicate Effect"
            onTriggered: {
                if (nodeMenu.targetIndex >= 0 && rail.viewport && rail.viewport.chain) {
                    const node = rail.viewport.chain[nodeMenu.targetIndex]
                    if (node && node.effect) {
                        rail.viewport.addNode(node.effect)
                        rail.nodeSelected(rail.viewport.chain.length - 1)
                    }
                }
            }
        }
        Action {
            text: "Reset Parameters"
            onTriggered: {
                if (rail.viewport && nodeMenu.targetIndex >= 0) {
                    rail.viewport.selectedNode = nodeMenu.targetIndex
                    rail.viewport.resetParams()
                }
            }
        }
        MenuSeparator {}
        Action {
            text: "Delete Effect"
            onTriggered: {
                if (nodeMenu.targetIndex >= 0 && rail.viewport) {
                    rail.viewport.removeNode(nodeMenu.targetIndex)
                }
            }
        }
    }
}
