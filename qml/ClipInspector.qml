import QtQuick
import QtQuick.Layouts

// Settings for the clip whose stack is being edited: how it lays over the
// layers beneath (blend + opacity) and where it sits in the frame (position +
// scale). Only meaningful once a clip is selected, so it hides otherwise.
Rectangle {
    id: insp
    required property var viewport

    readonly property int targetIdx: viewport.editedClip >= 0
                                     ? viewport.editedClip
                                     : (viewport.activeClipIndex >= 0
                                        ? viewport.activeClipIndex
                                        : (viewport.clips.length > 0 ? 0 : -1))
    readonly property int idx: targetIdx
    readonly property var clip: (idx >= 0 && idx < viewport.clips.length)
                                ? viewport.clips[idx] : null

    property bool expanded: true
    visible: clip !== null
    color: "#000000"
    implicitHeight: visible
        ? hdr.height + (expanded ? col.implicitHeight + Theme.padding * 2 : 0)
        : 0

    SectionHeader {
        id: hdr
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        title: "Clip"
        // The name goes on the header, so a closed inspector still says which
        // clip the effect rack is pointed at.
        hint: insp.clip ? insp.clip.name : ""
        marked: true
        expanded: insp.expanded
        onToggled: insp.expanded = !insp.expanded

        FlatButton {
            visible: insp.viewport.editedClip >= 0
            label: "Deselect"
            tip: "Deselect this clip"
            onClicked: insp.viewport.selectClip(-1)
        }
    }

    ColumnLayout {
        id: col
        visible: insp.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: hdr.bottom
        anchors.margins: Theme.padding
        spacing: Theme.gap

        // ── text source ──
        // Only for text clips. Everything else about a text clip (blend,
        // position, its effect stack) uses the same controls as footage,
        // because a rasterized caption IS just another source layer.
        ColumnLayout {
            id: textBox
            visible: insp.clip !== null && insp.clip.isText === true
            Layout.fillWidth: true
            spacing: Theme.gapTight

            // clipText() is a Q_INVOKABLE, and a binding to a call only
            // re-evaluates when something it READS changes - that was idx
            // alone, so `st` froze at whatever the clip held when selected.
            // Every control below sends the WHOLE style back, so the stale copy
            // meant moving Size and then Text X snapped Size straight back.
            // Reading `clips` ties it to the model pushClips_() republishes on
            // every style change.
            readonly property var st: {
                void insp.viewport.clips      // dependency only
                return insp.idx >= 0 ? insp.viewport.clipText(insp.idx) : ({})
            }

            Text {
                text: "Text"
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 24
                color: Theme.bg
                border.color: field.activeFocus ? Theme.accent : Theme.hairline
                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.margins: 4
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.size
                    selectByMouse: true
                    clip: true
                    // Bound only when not being edited, so re-publishing the
                    // clip model mid-typing cannot yank the caret back.
                    text: activeFocus ? text : (parent.parent.st.text || "")
                    onTextChanged: if (activeFocus)
                        insp.viewport.setClipText(insp.idx, text)
                }
            }

            Text {
                text: "Font"
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
            }
            FontPicker {
                Layout.fillWidth: true
                fonts: insp.viewport.systemFonts()
                // Empty means the rasteriser's own fallback, which is Consolas.
                defaultLabel: "Consolas (default)"
                selected: parent.st.font !== undefined ? parent.st.font : ""
                onPicked: function (family) {
                    const t = insp.viewport.clipText(insp.idx)
                    insp.viewport.setClipTextStyle(
                        insp.idx, t.size, t.x, t.y, t.r, t.g, t.b, t.bold,
                        t.letterSpacing, t.wrapWidth, family)
                }
            }

            ParamSlider {
                Layout.fillWidth: true
                label: "Size"
                from: 0.02; to: 1.0; stepSize: 0.005
                value: parent.st.size !== undefined ? parent.st.size : 0.18
                onMoved: (v) => insp.viewport.setClipTextStyle(
                    insp.idx, v, parent.st.x, parent.st.y,
                    parent.st.r, parent.st.g, parent.st.b, parent.st.bold,
                    parent.st.letterSpacing, parent.st.wrapWidth)
            }
            ParamSlider {
                Layout.fillWidth: true
                label: "Text X"
                from: 0.0; to: 1.0; stepSize: 0.005
                value: parent.st.x !== undefined ? parent.st.x : 0.5
                onMoved: (v) => insp.viewport.setClipTextStyle(
                    insp.idx, parent.st.size, v, parent.st.y,
                    parent.st.r, parent.st.g, parent.st.b, parent.st.bold,
                    parent.st.letterSpacing, parent.st.wrapWidth)
            }
            ParamSlider {
                Layout.fillWidth: true
                label: "Text Y"
                from: 0.0; to: 1.0; stepSize: 0.005
                value: parent.st.y !== undefined ? parent.st.y : 0.5
                onMoved: (v) => insp.viewport.setClipTextStyle(
                    insp.idx, parent.st.size, parent.st.x, v,
                    parent.st.r, parent.st.g, parent.st.b, parent.st.bold,
                    parent.st.letterSpacing, parent.st.wrapWidth)
            }
            ParamSlider {
                Layout.fillWidth: true
                label: "Tracking"
                from: -10.0; to: 60.0; stepSize: 0.5
                value: parent.st.letterSpacing !== undefined
                       ? parent.st.letterSpacing : 0.0
                onMoved: (v) => insp.viewport.setClipTextStyle(
                    insp.idx, parent.st.size, parent.st.x, parent.st.y,
                    parent.st.r, parent.st.g, parent.st.b, parent.st.bold,
                    v, parent.st.wrapWidth)
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gapTight
                FlatButton {
                    label: "Bold"
                    active: parent.parent.st.bold === true
                    onClicked: insp.viewport.setClipTextStyle(
                        insp.idx, parent.parent.st.size, parent.parent.st.x,
                        parent.parent.st.y, parent.parent.st.r,
                        parent.parent.st.g, parent.parent.st.b,
                        !parent.parent.st.bold,
                        parent.parent.st.letterSpacing,
                        parent.parent.st.wrapWidth)
                }
                // Presets rather than a colour picker: this is a mono terminal
                // UI, and text over footage is nearly always one of these.
                Repeater {
                    model: [[1,1,1,"WHT"], [1,0.27,0.2,"RED"],
                            [0.2,1,0.6,"GRN"], [0.3,0.6,1,"BLU"],
                            [0,0,0,"BLK"]]
                    delegate: FlatButton {
                        required property var modelData
                        label: modelData[3]
                        implicitWidth: 36
                        onClicked: insp.viewport.setClipTextStyle(
                            insp.idx, textBox.st.size,
                            textBox.st.x, textBox.st.y,
                            modelData[0], modelData[1], modelData[2],
                            textBox.st.bold,
                            textBox.st.letterSpacing,
                            textBox.st.wrapWidth)
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true; height: 1; color: Theme.hairline
            }
        }

        // Blend mode against the layers below.
        Text {
            text: "Blend"
            color: Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.gapTight
            Repeater {
                model: insp.viewport.blendNames()
                delegate: FlatButton {
                    required property int index
                    required property string modelData
                    label: modelData
                    active: insp.clip && insp.clip.blend === index
                    onClicked: insp.viewport.setClipBlend(
                        insp.idx, index, insp.clip ? insp.clip.opacity : 1.0)
                }
            }
        }

        ParamSlider {
            Layout.fillWidth: true
            label: "Opacity"
            from: 0; to: 1; stepSize: 0.01
            value: insp.clip ? insp.clip.opacity : 1.0
            onMoved: (v) => insp.viewport.setClipBlend(
                insp.idx, insp.clip ? insp.clip.blend : 0, v)
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }

        // Placement in the frame - what makes a stacked clip usable as an
        // overlay rather than something that hides everything under it.
        //
        // The arrangements below are the reason the transform exists, and
        // reaching them by hand means solving for scale and offset together.
        // Half layouts crop the frame so each clip keeps its own framing and
        // they meet at an edge; corner scales the whole clip down over what is
        // underneath.
        Text {
            text: "Layout"
            color: Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.gapTight
            Repeater {
                model: [
                    { label: "Full",   crop: [0, 0, 1, 1],       xf: [0, 0, 1] },
                    { label: "Left",   crop: [0, 0, 0.5, 1],     xf: [0, 0, 1] },
                    { label: "Right",  crop: [0.5, 0, 0.5, 1],   xf: [0, 0, 1] },
                    { label: "Top",    crop: [0, 0, 1, 0.5],     xf: [0, 0, 1] },
                    { label: "Bottom", crop: [0, 0.5, 1, 0.5],   xf: [0, 0, 1] },
                    { label: "Corner", crop: [0, 0, 1, 1],       xf: [0.91, 0.91, 0.35] }
                ]
                delegate: FlatButton {
                    required property var modelData
                    label: modelData.label
                    onClicked: {
                        insp.viewport.setClipCrop(insp.idx, modelData.crop[0],
                                                  modelData.crop[1],
                                                  modelData.crop[2],
                                                  modelData.crop[3])
                        insp.viewport.setClipTransform(insp.idx, modelData.xf[0],
                                                       modelData.xf[1],
                                                       modelData.xf[2])
                    }
                }
            }
        }

        ParamSlider {
            Layout.fillWidth: true
            label: "Position X"
            from: -2; to: 2; stepSize: 0.01
            value: insp.clip ? insp.clip.posX : 0
            onMoved: (v) => insp.viewport.setClipTransform(
                insp.idx, v, insp.clip.posY, insp.clip.scale)
        }
        ParamSlider {
            Layout.fillWidth: true
            label: "Position Y"
            from: -2; to: 2; stepSize: 0.01
            value: insp.clip ? insp.clip.posY : 0
            onMoved: (v) => insp.viewport.setClipTransform(
                insp.idx, insp.clip.posX, v, insp.clip.scale)
        }
        ParamSlider {
            Layout.fillWidth: true
            label: "Scale"
            from: 0.05; to: 2; stepSize: 0.01
            value: insp.clip ? insp.clip.scale : 1
            onMoved: (v) => insp.viewport.setClipTransform(
                insp.idx, insp.clip.posX, insp.clip.posY, v)
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            FlatButton {
                label: "Reset Transform"
                tip: "Reset clip position to center and scale to 1.0"
                onClicked: {
                    if (insp.clip)
                        insp.viewport.setClipTransform(insp.idx, 0, 0, 1.0)
                }
            }
        }
    }
}
