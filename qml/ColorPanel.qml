import QtQuick
import QtQuick.Layouts

// Master colour grade - applied after every effect, to the whole frame.
// Collapsed by default so it does not crowd the effect params; the header
// shows whether the grade is doing anything.
Rectangle {
    id: panel
    required property var viewport
    // Open by default, like the parameter rack. Grading is part of the look,
    // not a thing you go and find.
    property bool expanded: true
    // Which grade row has its keyframe/patch controls open, -1 for none. One at
    // a time, as in ParamPanel. MUST live on the root: declared on the inner
    // ColumnLayout it is a different object from the `panel` the delegates
    // assign to, and every click would silently do nothing.
    property int openRow: -1
    // Raised when a grade uniform is patched, so the channel rack can highlight
    // the source now driving it.
    signal channelPicked(int ch)

    color: Theme.panel
    radius: Theme.panelRadius
    // Only what is on screen. A closed panel is its header and nothing else.
    implicitHeight: hdr.height
                    + (expanded ? col.implicitHeight + Theme.padding * 2 : 0)
    // A closed panel used to draw its content past its own bottom edge.
    clip: true

    // Active means the grade is doing something: a slider off its default, OR a
    // uniform driven by audio, OR one carrying keyframes. Values alone would
    // read "not graded" while an audio patch was visibly moving the picture.
    readonly property bool active: {
        const g = viewport.grade
        for (let i = 0; i < g.length; ++i) {
            if (Math.abs(g[i].value - g[i].default) > 1e-4) return true
            if (g[i].channel >= 0) return true
            if ((g[i].keyCount || 0) > 0) return true
        }
        return false
    }

    SectionHeader {
        id: hdr
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        title: "Colour"
        hint: panel.active ? "graded" : ""
        marked: panel.active
        expanded: panel.expanded
        onToggled: panel.expanded = !panel.expanded

        FlatButton {
            visible: panel.expanded
            label: "Reset"
            onClicked: panel.viewport.resetGrade()
        }
    }

    ColumnLayout {
        id: col
        visible: panel.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: hdr.bottom
        anchors.margins: Theme.padding
        spacing: Theme.gap

        Repeater {
            model: panel.expanded ? panel.viewport.grade : []

            // Same row anatomy as the effect rack: slider, a disclosure that
            // opens keyframe + patch controls, and PatchRow itself reused with
            // grade: true. The grade goes through the same resolve() an effect
            // uniform does, so it gets the same controls rather than its own.
            delegate: Column {
                id: gradeRow
                required property int index
                required property var modelData
                // The ColumnLayout owns the width; binding width to parent.width
                // as well would fight it.
                Layout.fillWidth: true
                spacing: Theme.gapTight

                readonly property bool open: panel.openRow === gradeRow.index
                readonly property int keyCount: modelData.keyCount || 0

                Item {
                    width: parent.width
                    // height, NOT implicitHeight: a Column does not size
                    // children from their implicit height, and at zero height
                    // this still DRAWS but receives no pointer events.
                    height: gslider.height

                    ParamSlider {
                        id: gslider
                        width: parent.width
                        label: Theme.nice(modelData.label)
                        from: modelData.min
                        to: modelData.max
                        stepSize: modelData.step
                        value: modelData.value
                        patched: modelData.channel >= 0
                        keyed: gradeRow.keyCount > 0
                        onMoved: (v) => panel.viewport.setGradeParam(index, v)
                        onLabelClicked: panel.openRow = gradeRow.open ? -1 : gradeRow.index
                    }
                }

                // Says so while collapsed, so the panel still reads at a glance.
                Text {
                    visible: !gradeRow.open && gradeRow.modelData.channel >= 0
                    text: "audio · "
                        + (panel.viewport.channelNames[gradeRow.modelData.channel]
                           ? panel.viewport.channelNames[gradeRow.modelData.channel].name
                           : "")
                    color: Theme.accent
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeTiny
                }

                Flow {
                    width: parent.width
                    visible: gradeRow.open
                    spacing: Theme.gapTight
                    // gradeKeyedNow/gradeKeyInterpNow rather than the grade
                    // model: they change as the playhead moves, and rebinding
                    // the model every frame would rebuild every slider.
                    readonly property bool here:
                        index < panel.viewport.gradeKeyedNow.length
                        && panel.viewport.gradeKeyedNow[index] === true
                    readonly property int interp:
                        index < panel.viewport.gradeKeyInterpNow.length
                        ? panel.viewport.gradeKeyInterpNow[index] : -1

                    Text {
                        width: Theme.labelCol
                        text: "Key"
                        color: Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                    }
                    FlatButton {
                        small: true
                        plain: true
                        label: parent.here ? "Set key" : "Add key"
                        active: parent.here
                        onClicked: panel.viewport.addGradeKey(index)
                    }
                    FlatButton {
                        small: true
                        plain: true
                        visible: parent.here
                        label: ["Linear", "Ease", "Step"][Math.max(0, parent.interp)]
                        onClicked: panel.viewport.cycleGradeKeyInterp(index)
                    }
                    FlatButton {
                        small: true
                        plain: true
                        visible: parent.here
                        label: "Delete"
                        onClicked: panel.viewport.removeGradeKeyAt(index)
                    }
                    Text {
                        visible: gradeRow.keyCount > 0
                        text: gradeRow.keyCount + " keys"
                        color: Theme.accent
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                    }
                    FlatButton {
                        small: true
                        plain: true
                        visible: gradeRow.keyCount > 0
                        label: "Clear"
                        onClicked: panel.viewport.clearGradeKeys(index)
                    }
                    FlatButton {
                        small: true
                        plain: true
                        visible: panel.viewport.markers.length > 0
                        label: "Beats"
                        onClicked: panel.viewport.keyGradeOnMarkers(index)
                    }
                }

                PatchRow {
                    visible: gradeRow.open
                    width: parent.width
                    viewport: panel.viewport
                    grade: true
                    paramIndex: index
                    channel: modelData.channel
                    depth: modelData.depth
                    depthMax: modelData.depthMax
                    onChannelPicked: (ch) => panel.channelPicked(ch)
                }

                Rectangle {          // separator between grade uniforms
                    width: parent.width; height: 1; color: Theme.hairline
                }
            }
        }
    }
}
