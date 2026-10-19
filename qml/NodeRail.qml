import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Effect chain and presets content. DockWorkspace owns the tab header.
// Compact colored preview rows share the searchable effect browser.
Rectangle {
    id: rail
    required property var viewport
    property var effectIds: []

    property int currentTab: 0 // 0 = Effect Chain, 1 = Presets
    signal nodeSelected(int index)

    readonly property int nodeH: Math.max(56, Theme.size + Theme.sizeSmall + 20)
    readonly property int gap: 4
    readonly property int slotH: nodeH + gap

    color: Theme.panel

    function openAdd() {
        if (!rail.viewport) return
        if (rail.viewport.editedClip < 0 && rail.viewport.clips.length > 0)
            rail.viewport.selectClip(0)
        if (addPopup.opened) { addPopup.close(); return }
        addPopup.replaceIndex = -1
        addPopup.open()
    }
    function openSavePreset() {
        if (!rail.viewport || rail.viewport.editedClip < 0) return
        nameField.text = ""
        saveDlg.open()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // ══════════════════════════════════════════════════════════════════
        // TAB 0: EFFECT CHAIN
        // ══════════════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: rail.currentTab === 0
            spacing: 8

            // Show which effect chain is being edited.
            Rectangle {
                visible: !!rail.viewport
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: 0
                color: "transparent"
                border.width: 0

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: rail.viewport.editedClip >= 0
                              ? "CLIP " + (rail.viewport.editedClip + 1) + " FX" : "SELECT A CLIP"
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    FlatButton {
                        visible: rail.viewport.editedClip >= 0 && rail.viewport.chain.length > 0
                        label: "Change"
                        tip: "Change selected effect"
                        implicitHeight: 18
                        onClicked: {
                            addPopup.replaceIndex = Math.max(0, rail.viewport.selectedNode)
                            addPopup.open()
                        }
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
                    width: chainScroll.availableWidth
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
                                text: (rail.viewport && rail.viewport.editedClip >= 0)
                                      ? "No effects on this clip" : "Select a clip to edit effects"
                                color: Theme.textMuted
                                font.family: Theme.fontUI
                                font.pixelSize: Theme.sizeSmall
                            }
                            FlatButton {
                                visible: rail.viewport && rail.viewport.editedClip >= 0
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

                        delegate: Item {
                            id: holder
                            objectName: "chain-holder-" + index
                            required property int index
                            required property var modelData
                            width: chainCol.width
                            height: block.height + rail.gap

                            property real dy: 0
                            property real dx: 0
                            property int shift: Math.round(dy / height)
                            property bool removing: Math.abs(dx) > 60
                            readonly property int  blendMode: holder.modelData.blend || 0
                            readonly property real mixAmt:
                                holder.modelData.mix === undefined ? 1.0 : holder.modelData.mix

                            ChainBlock {
                                id: block
                                objectName: "chain-row-" + holder.index
                                width: Math.max(0, holder.width - Theme.control)
                                height: Math.max(rail.nodeH, implicitHeight)
                                badge: (holder.blendMode !== 0 || holder.mixAmt < 0.999)
                                       ? rail.viewport.blendNames()[holder.blendMode]
                                         + " " + Math.round(holder.mixAmt * 100) + "%"
                                       : ""
                                label: holder.modelData.label
                                effectId: holder.modelData.effect
                                active: rail.viewport.selectedNode === holder.index || drag.active
                                opacity: holder.removing ? 0.45 : 1.0
                                onActivated: {
                                    rail.viewport.selectedNode = holder.index
                                    rail.nodeSelected(holder.index)
                                }

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

                            FlatButton {
                                id: chainMenuButton
                                objectName: "chain-menu-" + holder.index
                                anchors.right: parent.right
                                anchors.verticalCenter: block.verticalCenter
                                width: Theme.control
                                height: Theme.control
                                plain: true
                                label: "..."
                                tip: "Effect actions"
                                onClicked: {
                                    rail.viewport.selectedNode = holder.index
                                    rail.nodeSelected(holder.index)
                                    nodeMenu.targetIndex = holder.index
                                    nodeMenu.popup(chainMenuButton, 0, chainMenuButton.height)
                                }
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
    Rectangle {
        id: addPopup
        anchors.fill: parent
        z: 20
        visible: opened
        color: Theme.panel
        property bool opened: false
        property int replaceIndex: -1
        function open() { opened = true; filter.text = ""; filter.forceActiveFocus() }
        function close() { opened = false }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: addPopup.replaceIndex >= 0 ? "CHANGE EFFECT" : "ADD EFFECT"
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeSmall
                }
                FlatButton { plain: true; small: true; label: "Close"; onClicked: addPopup.close() }
            }

            Text {
                visible: !rail.viewport || rail.viewport.editedClip < 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Add or select a clip before applying an effect."
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
            }

            TextField {
                id: filter
                objectName: "effect-search"
                Accessible.name: "Search effects"
                Layout.fillWidth: true
                placeholderText: "Search effects..."
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
                background: Rectangle {
                    color: Theme.bg
                    implicitHeight: Theme.control
                    border.width: 1
                    border.color: filter.activeFocus ? Theme.focusRing : Theme.inputBorder
                    radius: Theme.radius
                }
                onAccepted: if (hits.count > 0) addPopup.pick(hits.model[Math.max(0, hits.currentIndex)])
                Keys.onDownPressed: hits.incrementCurrentIndex()
                Keys.onUpPressed: hits.decrementCurrentIndex()
                Keys.onEscapePressed: addPopup.close()
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            ListView {
                id: hits
                objectName: "effect-results"
                width: parent.width
                height: Math.max(0, Math.floor((parent.height + spacing) / (64 + spacing)) * (64 + spacing) - spacing)
                clip: true
                spacing: 4
                snapMode: ListView.SnapToItem
                currentIndex: count > 0 ? 0 : -1
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                model: rail.effectIds.filter(function (e) {
                    return filter.text === ""
                        || e.indexOf(filter.text.toLowerCase()) !== -1
                        || Theme.nice(e).toLowerCase().indexOf(filter.text.toLowerCase()) !== -1
                })

                delegate: ChainBlock {
                    id: effectCard
                    required property string modelData
                    effectId: modelData
                    width: hits.width
                    height: implicitHeight
                    connectors: false
                    label: Theme.nice(modelData)
                    active: hover.hovered || ListView.isCurrentItem
                    onActivated: addPopup.pick(effectCard.effectId)

                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: addPopup.pick(effectCard.effectId) }
                }
            }
            }
        }

        function pick(id) {
            if (!rail.viewport || rail.viewport.editedClip < 0) return
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
