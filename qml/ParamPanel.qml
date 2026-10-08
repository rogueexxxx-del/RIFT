import QtQuick
import QtQuick.Layouts

// Right-hand parameter rack for the selected effect. Ranges, labels and
// defaults come from the shader manifest, which was generated from the
// prototype - so a slider here spans the same range as the Python app.
Rectangle {
    id: panel
    required property var viewport
    // Open by default: this is the panel the app is for.
    property bool expanded: true
    // Which parameter has its controls open, -1 for none. One at a time:
    // opening every row at once is what made this panel unreadable.
    //
    // MUST live on the root. Declared on the inner ColumnLayout it was a
    // different object from the `panel` the delegates assign to, so every
    // click on the three dots silently did nothing.
    property int openRow: -1
    // Raised when a uniform is patched, so the channel rack can highlight the
    // source that now drives it.
    signal channelPicked(int ch)

    readonly property bool isVisualizer: panel.viewport.effect === "oscilloscope"
    readonly property int currentVisIndex: {
        if (!isVisualizer) return 0
        const ps = panel.viewport.params
        for (let i = 0; i < ps.length; ++i) {
            if (ps[i].name === "mode") return Math.min(Math.max(Math.round(ps[i].value), 0), 3)
        }
        return 0
    }

    color: "#000000"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 10
            model: panel.viewport.params

            header: Column {
                width: ListView.view ? ListView.view.width : 0
                spacing: 10
                bottomPadding: 8

                // Effect Node Blending Header (moved from NodeRail)
                Rectangle {
                    id: nodeBlendBox
                    width: parent.width
                    height: 38
                    radius: 4
                    color: "#161616"
                    visible: panel.viewport && panel.viewport.selectedNode >= 0
                             && panel.viewport.selectedNode < panel.viewport.chain.length

                    readonly property var nodeData: visible ? panel.viewport.chain[panel.viewport.selectedNode] : null
                    readonly property int bMode: nodeData ? (nodeData.blend || 0) : 0
                    readonly property real bMix: nodeData ? (nodeData.mix === undefined ? 1.0 : nodeData.mix) : 1.0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: "BLEND"
                            color: Theme.textDim
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeTiny
                            font.weight: Font.Bold
                        }

                        FlatButton {
                            small: true
                            implicitWidth: 54
                            label: panel.viewport.blendNames()[nodeBlendBox.bMode]
                            onClicked: panel.viewport.cycleNodeBlend(panel.viewport.selectedNode)
                        }

                        Text {
                            text: "MIX"
                            color: Theme.textDim
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeTiny
                            font.weight: Font.Bold
                        }

                        // Interactive mix slider
                        Rectangle {
                            Layout.fillWidth: true
                            height: 10
                            radius: 2
                            color: "#2B2B2B"

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Math.max(0, parent.width * nodeBlendBox.bMix)
                                radius: 2
                                color: "#FFFFFF"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPositionChanged: (mouse) => {
                                    if (pressed) {
                                        const f = Math.max(0, Math.min(1, mouse.x / width))
                                        panel.viewport.setNodeBlend(panel.viewport.selectedNode, nodeBlendBox.bMode, f)
                                    }
                                }
                                onPressed: (mouse) => {
                                    const f = Math.max(0, Math.min(1, mouse.x / width))
                                    panel.viewport.setNodeBlend(panel.viewport.selectedNode, nodeBlendBox.bMode, f)
                                }
                            }
                        }

                        Text {
                            text: Math.round(nodeBlendBox.bMix * 100) + "%"
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.sizeTiny
                            Layout.preferredWidth: 32
                        }

                        FlatButton {
                            small: true
                            implicitWidth: 24
                            label: "×"
                            onClicked: panel.viewport.removeNode(panel.viewport.selectedNode)
                            ToolTipArea { text: "Delete this effect" }
                        }
                    }
                }

                ColorStyleEditor {
                    id: cse
                    width: parent.width
                    visible: panel.isVisualizer
                    viewport: panel.viewport
                    visIndex: panel.currentVisIndex
                }
            }

            delegate: Column {
                id: row
                required property int index
                required property var modelData
                width: ListView.view.width
                spacing: Theme.gapTight

                // Only the parameter you are working on shows its controls.
                readonly property bool open: panel.openRow === row.index

                Item {
                    width: parent.width
                    height: slider.implicitHeight

                    ParamSlider {
                        id: slider
                        anchors.left: parent.left
                        anchors.right: parent.right
                        label: Theme.nice(modelData.label !== "" ? modelData.label
                                                                : modelData.name)
                        from: modelData.min
                        to: modelData.max
                        stepSize: modelData.step
                        discrete: modelData.discrete
                        value: index < panel.viewport.controlValues.length
                               ? panel.viewport.controlValues[index]
                               : modelData.value
                        patched: modelData.channel >= 0
                        channelName: (modelData.channel >= 0 && panel.viewport.channelNames[modelData.channel])
                                     ? panel.viewport.channelNames[modelData.channel].name : ""
                        tint: Theme.channelColor(channelName)
                        keyed: (modelData.keyCount || 0) > 0
                        availableChannels: panel.viewport.channelNames
                        onMoved: (v) => panel.viewport.setParam(index, v)
                        onLinkRequested: (ch) => {
                            panel.viewport.setBinding(index, ch, 1.0)
                            panel.channelPicked(ch)
                        }
                        onLabelClicked: {
                            panel.openRow = row.open ? -1 : row.index
                        }
                    }
                }
                // Keyframes: record the value at the playhead, step through
                // interpolation, clear. Shown per parameter so animating one
                // thing does not mean hunting for it in a separate panel.
                Row {
                    visible: row.open
                    // Air between the buttons: at 4 they touched and read as
                    // one segmented control rather than separate actions.
                    spacing: Theme.gapTight
                    readonly property bool here:
                        index < panel.viewport.keyedNow.length
                        && panel.viewport.keyedNow[index] === true
                    readonly property int interp:
                        index < panel.viewport.keyInterpNow.length
                        ? panel.viewport.keyInterpNow[index] : -1

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // Same column width as the patch row below.
                        width: Theme.labelCol
                        text: "Key"
                        color: Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                    }
                    // keyedNow/keyInterpNow rather than the params model: they
                    // change as the playhead moves, and rebinding the model
                    // every frame rebuilt every delegate.
                    FlatButton {
                        small: true
                        // Filled when a key sits at the playhead: pressing then
                        // re-records it rather than adding a second one.
                        label: parent.here ? "Set" : "+"
                        active: parent.here
                        implicitWidth: 34
                        onClicked: panel.viewport.addKey(index)
                    }
                    FlatButton {
                        small: true
                        visible: parent.here
                        label: ["Linear", "Ease", "Step"][Math.max(0, parent.interp)]
                        implicitWidth: 44
                        onClicked: panel.viewport.cycleKeyInterp(index)
                    }
                    FlatButton {
                        small: true
                        visible: parent.here
                        label: "Delete"
                        implicitWidth: 34
                        onClicked: panel.viewport.removeKeyAt(index)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (modelData.keyCount || 0) > 0
                        text: (modelData.keyCount || 0) + " keys"
                        color: Theme.accent
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                    }
                    FlatButton {
                        small: true
                        visible: (modelData.keyCount || 0) > 0
                        label: "Clear"
                        implicitWidth: 34
                        onClicked: panel.viewport.clearKeys(index)
                    }
                    // Key this parameter on every detected beat at once - the
                    // reason markers exist. Hidden when nothing is detected.
                    FlatButton {
                        small: true
                        visible: panel.viewport.markers.length > 0
                        label: "Beats"
                        implicitWidth: 44
                        onClicked: panel.viewport.keyOnMarkers(index)
                    }

                    // External control. MAP arms learn mode; the next CC or OSC
                    // message that arrives binds itself here, so there is no
                    // typing of CC numbers.
                    readonly property string ctl:
                        index < panel.viewport.controlMap.length
                        ? panel.viewport.controlMap[index] : ""
                    FlatButton {
                        small: true
                        label: panel.viewport.learning === index
                               ? "..." : (parent.ctl !== "" ? parent.ctl : "Map")
                        active: panel.viewport.learning === index || parent.ctl !== ""
                        implicitWidth: Math.max(40, label.length * 7 + 10)
                        onClicked: {
                            if (parent.ctl !== "") panel.viewport.clearControl(index)
                            else panel.viewport.learnControl(
                                panel.viewport.learning === index ? -1 : index)
                        }
                    }
                }

                PatchRow {
                    visible: row.open
                    width: parent.width
                    viewport: panel.viewport
                    paramIndex: index
                    channel: modelData.channel
                    depth: modelData.depth
                    depthMax: modelData.depthMax
                    onChannelPicked: (ch) => panel.channelPicked(ch)
                }
            }
        }
    }
}
