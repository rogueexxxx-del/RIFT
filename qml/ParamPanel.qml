import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

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

    color: Theme.panel
    radius: Theme.panelRadius

    function blendLabel(name) {
        const labels = { "NRM": "Normal", "NORM": "Normal", "ADD": "Add", "SCR": "Screen", "MUL": "Multiply", "OVR": "Overlay", "DIFF": "Difference", "SUB": "Subtract", "LGT": "Lighten", "DRK": "Darken" }
        return labels[String(name).toUpperCase()] || Theme.nice(name)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        ListView {
            id: parameters
            objectName: "effectParameters"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: panel.viewport.params
            ScrollBar.vertical: ScrollBar {}
            boundsBehavior: Flickable.StopAtBounds

            footer: Text {
                width: parameters.width
                visible: parameters.count === 0
                padding: Theme.padding
                wrapMode: Text.WordWrap
                text: panel.viewport.selectedNode < 0
                    ? "Select an effect to edit its parameters. Add an effect from the effects browser to start."
                    : "This effect has no adjustable parameters."
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }

            header: Column {
                width: ListView.view ? ListView.view.width : 0
                spacing: 6
                bottomPadding: 4

                // Effect Node Blending Header (moved from NodeRail)
                Rectangle {
                    id: nodeBlendBox
                    width: parent.width
                    height: blendControls.implicitHeight + 16
                    radius: Theme.panelRadius
                    color: "transparent"
                    visible: panel.viewport && panel.viewport.selectedNode >= 0
                             && panel.viewport.selectedNode < panel.viewport.chain.length

                    readonly property var nodeData: visible ? panel.viewport.chain[panel.viewport.selectedNode] : null
                    readonly property int bMode: nodeData ? (nodeData.blend || 0) : 0
                    readonly property real bMix: nodeData ? (nodeData.mix === undefined ? 1.0 : nodeData.mix) : 1.0

                    ColumnLayout {
                        id: blendControls
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: Theme.gapTight
                        RowLayout {
                            Layout.fillWidth: true
                            ComboBox {
                                id: effectBlend
                                objectName: "effectBlendSelector"
                                Layout.fillWidth: true
                                implicitHeight: Theme.control
                                font.family: Theme.fontUI
                                font.pixelSize: Theme.sizeSmall
                                palette.text: Theme.text
                                palette.buttonText: Theme.text
                                palette.base: Theme.raised
                                palette.window: Theme.flyout
                                palette.highlight: Theme.accent
                                palette.highlightedText: Theme.foregroundFor(Theme.accent)
                                background: Rectangle {
                                    color: Theme.raised
                                    radius: Theme.radius
                                    border.width: effectBlend.activeFocus ? Theme.focusWidth : 1
                                    border.color: effectBlend.activeFocus ? Theme.focusRing : Theme.border
                                }
                                model: panel.viewport.blendNames().map(panel.blendLabel)
                                currentIndex: nodeBlendBox.bMode
                                Accessible.name: "Effect blend mode"
                                onActivated: panel.viewport.setNodeBlend(panel.viewport.selectedNode, currentIndex, nodeBlendBox.bMix)
                            }
                            FlatButton {
                                label: "Remove"
                                tip: "Remove this effect"
                                onClicked: panel.viewport.removeNode(panel.viewport.selectedNode)
                            }
                        }
                        ParamSlider {
                            Layout.fillWidth: true
                            label: "Effect mix"
                            from: 0; to: 1; stepSize: 0.01
                            value: nodeBlendBox.bMix
                            onMoved: (v) => panel.viewport.setNodeBlend(panel.viewport.selectedNode, nodeBlendBox.bMode, v)
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
                Flow {
                    width: parent.width
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
                        plain: true
                        // Filled when a key sits at the playhead: pressing then
                        // re-records it rather than adding a second one.
                        label: parent.here ? "Set key" : "Add key"
                        active: parent.here
                        onClicked: panel.viewport.addKey(index)
                    }
                    FlatButton {
                        small: true
                        plain: true
                        visible: parent.here
                        label: ["Linear", "Ease", "Step"][Math.max(0, parent.interp)]
                        onClicked: panel.viewport.cycleKeyInterp(index)
                    }
                    FlatButton {
                        small: true
                        plain: true
                        visible: parent.here
                        label: "Delete"
                        onClicked: panel.viewport.removeKeyAt(index)
                    }
                    Text {
                        visible: (modelData.keyCount || 0) > 0
                        text: (modelData.keyCount || 0) + " keys"
                        color: Theme.accent
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                    }
                    FlatButton {
                        small: true
                        plain: true
                        visible: (modelData.keyCount || 0) > 0
                        label: "Clear"
                        onClicked: panel.viewport.clearKeys(index)
                    }
                    // Key this parameter on every detected beat at once - the
                    // reason markers exist. Hidden when nothing is detected.
                    FlatButton {
                        small: true
                        plain: true
                        visible: panel.viewport.markers.length > 0
                        label: "Beats"
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
                               ? "Learning MIDI / OSC" : (parent.ctl !== "" ? parent.ctl : "Map")
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
