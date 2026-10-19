import QtQuick
import QtQuick.Controls

// Figma-styled Parameter Slider:
// - Title on left, channel name + LINK button on right
// - Thick rectangular track (#2B2B2B)
// - Modulated fill uses channel color, unlinked fill is solid white (#FFFFFF)
// - 0px radius, clean minimal aesthetic
Item {
    id: ctl

    property string label: ""
    property real from: 0
    property real to: 1
    property real stepSize: 0.01
    property bool discrete: false
    property real value: 0
    property bool patched: false
    property string channelName: ""
    property color tint: Theme.channelColor(channelName)
    readonly property color channelInk: {
        const lighten = Theme.luminance(Theme.panel) < 0.5
        for (let factor = 1; factor <= 4; factor += 0.1) {
            const ink = lighten ? Qt.lighter(ctl.tint, factor) : Qt.darker(ctl.tint, factor)
            if (Theme.contrastRatio(ink, Theme.panel) >= 4.5) return ink
        }
        return Theme.foregroundFor(Theme.panel)
    }
    property bool keyed: false
    property var availableChannels: []

    signal moved(real v)
    signal linkRequested(int channelIndex)
    signal labelClicked()

    readonly property bool stackedHeader: width < nameText.implicitWidth + readouts.implicitWidth + Theme.gap
    implicitHeight: headerRow.height + 24
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: titleCase(label)
    Accessible.description: shown.toFixed(2) + (patched ? ", linked to " + channelName : "")
    Accessible.onIncreaseAction: adjust(1)
    Accessible.onDecreaseAction: adjust(-1)
    Keys.onRightPressed: adjust(1)
    Keys.onUpPressed: adjust(1)
    Keys.onLeftPressed: adjust(-1)
    Keys.onDownPressed: adjust(-1)
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Home) { commit(from); event.accepted = true }
        else if (event.key === Qt.Key_End) { commit(to); event.accepted = true }
    }
    Keys.onReturnPressed: labelClicked()

    function commit(v) { shown = snap(v); moved(shown) }
    function adjust(direction) {
        commit(shown + direction * (stepSize > 0 ? stepSize : (to - from) / 100))
    }

    function snap(v) {
        const clamped = Math.max(ctl.from, Math.min(ctl.to, v))
        if (ctl.stepSize <= 0) return clamped
        const s = Math.round((clamped - ctl.from) / ctl.stepSize) * ctl.stepSize + ctl.from
        return Math.max(ctl.from, Math.min(ctl.to, s))
    }
    function fraction() {
        return ctl.to > ctl.from ? (ctl.shown - ctl.from) / (ctl.to - ctl.from) : 0
    }
    function apply(px) {
        const f = Math.max(0, Math.min(1, px / track.width))
        const v = ctl.snap(ctl.from + f * (ctl.to - ctl.from))
        ctl.shown = v
        ctl.moved(v)
    }

    function titleCase(s) {
        if (!s) return ""
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    property real shown: value
    onValueChanged: shown = value

    // ── Header Row: Label on left, Channel + LINK on right ──
    Item {
        id: headerRow
        objectName: "parameterHeader"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: ctl.stackedHeader ? nameText.implicitHeight + 2 + Theme.control : Theme.control

        Text {
            id: nameText
            objectName: "parameterName"
            anchors.left: parent.left
            anchors.right: ctl.stackedHeader ? parent.right : readouts.left
            anchors.rightMargin: ctl.stackedHeader ? 0 : Theme.gap
            anchors.top: parent.top
            anchors.topMargin: ctl.stackedHeader ? 0 : (parent.height - implicitHeight) / 2
            elide: Text.ElideRight
            text: ctl.titleCase(ctl.label) + (ctl.keyed ? " ◆" : "")
            color: ctl.patched ? Theme.readableText(ctl.tint, Theme.panel) : (nameHover.hovered ? Theme.accentText : Theme.text)
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
            font.weight: Font.Normal

            HoverHandler { id: nameHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ctl.labelClicked() }
        }

        Row {
            id: readouts
            objectName: "parameterReadouts"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: Theme.gapTight

            // Value readout
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ctl.discrete ? Math.round(ctl.shown) : ctl.shown.toFixed(2)
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.sizeSmall
            }

            // Patched channel text indicator
            Text {
                objectName: "parameterChannelName"
                visible: ctl.patched && ctl.channelName !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: ctl.channelName.toLowerCase()
                color: ctl.channelInk
                width: Math.min(implicitWidth, 80, ctl.width * 0.2)
                elide: Text.ElideRight
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeTiny
                font.weight: Font.Bold
                font.underline: true
            }

            // LINK Button
            Rectangle {
                id: linkBtn
                objectName: "parameterAudioLink"
                anchors.verticalCenter: parent.verticalCenter
                width: ctl.patched ? 64 : 48
                height: Theme.control
                radius: Theme.radius
                color: ctl.patched ? ctl.tint : (linkHover.hovered ? Theme.hover : Theme.raised)
                border.width: activeFocus ? Theme.focusWidth : 1
                border.color: activeFocus ? Theme.focusRing : (ctl.patched ? ctl.tint : Theme.border)
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Link " + ctl.label + " to audio channel"
                Accessible.onPressAction: linkMenu.open()
                Keys.onSpacePressed: linkMenu.open()
                Keys.onReturnPressed: linkMenu.open()

                readonly property color linkTextColor: {
                    return ctl.patched ? Theme.foregroundFor(ctl.tint) : Theme.text
                }

                Text {
                    anchors.centerIn: parent
                    text: ctl.patched ? "Linked" : "Link"
                    color: linkBtn.linkTextColor
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeTiny
                    font.weight: Font.Bold
                    font.letterSpacing: 0.5
                }

                HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (linkMenu.visible) {
                            linkMenu.close()
                        } else {
                            linkMenu.open()
                        }
                    }
                }

                StyledMenu {
                    id: linkMenu
                    y: linkBtn.height + 2
                    x: linkBtn.width - width

                    StyledMenuItem {
                        text: "None (Unlink)"
                        onTriggered: ctl.linkRequested(-1)
                    }
                    StyledMenuSeparator {}
                    Repeater {
                        model: ctl.availableChannels
                        StyledMenuItem {
                            required property int index
                            required property var modelData
                            text: (modelData.name || modelData).toString().toLowerCase()
                            onTriggered: ctl.linkRequested(index)
                        }
                    }
                }
            }
        }
    }

    // ── Track Bar: machined track with subtle highlight ──
    Rectangle {
        id: track
        objectName: "parameterTrack"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        height: 12
        radius: Theme.radius
        color: Theme.sunken
        border.width: ctl.activeFocus ? Theme.focusWidth : 1
        border.color: ctl.activeFocus ? Theme.focusRing : (hover.hovered ? Theme.borderHover : Theme.border)

        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(0, parent.width * ctl.fraction())
            radius: 0
            color: ctl.patched ? ctl.tint : "#E0E0E0"

            // Machined end-cap highlight
            Rectangle {
                visible: fill.width > 3
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 2
                radius: 0
                color: "#FFFFFF"
                opacity: 0.85
            }
        }

        // Hit / Drag area
        Item {
            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -10

            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: (pt) => { ctl.forceActiveFocus(); ctl.apply(pt.position.x) }
            }
            DragHandler {
                id: drag
                target: null
                onCentroidChanged: if (active) ctl.apply(centroid.position.x)
            }
        }
    }
}
