import QtQuick

// Flat control. Sits ON a panel, so its resting state is one surface step up
// rather than a transparent box outlined in a hairline - an outline around
// every button is what made the old UI read as a wireframe.
Item {
    id: ctl
    property string label: ""
    property bool   active: false
    property bool   enabledLook: true
    enabled: enabledLook
    // Compact form for the rows that carry several buttons at once - the
    // keyframe and patch strips. Full-size controls there filled the panel
    // edge to edge with no air between them.
    property bool   small: false
    property bool   plain: false
    property string tip: ""
    signal clicked()

    implicitHeight: Theme.control
    implicitWidth: Math.max(32, txt.implicitWidth + (ctl.plain ? 16 : 24))
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: tip
    Accessible.onPressAction: if (enabled && enabledLook) clicked()
    Keys.onSpacePressed: event => { if (enabled && !event.isAutoRepeat) clicked() }
    Keys.onReturnPressed: event => { if (enabled && !event.isAutoRepeat) clicked() }

    Repeater {
        model: ctl.active && Theme.glowAllowed && !ctl.plain ? 3 : 0
        Rectangle {
            required property int index
            anchors.fill: parent
            anchors.margins: -2 * (index + 1)
            radius: Theme.radius + 2 * (index + 1)
            color: "transparent"
            border.width: 2
            border.color: Qt.alpha(Theme.accent, 0.12 / (index + 1))
            z: -1
        }
    }

    Rectangle {
        id: bgRect
        objectName: "control-surface"
        anchors.fill: parent
        radius: Theme.radius
        color: ctl.plain ? (hover.hovered ? Theme.hover : "transparent")
             : ctl.active ? (tap.pressed ? Theme.accentPressed : (hover.hovered ? Theme.accentPressed : Theme.accent))
                          : (tap.pressed ? Theme.bg
                                         : (hover.hovered ? Theme.hover
                                                          : Theme.raised))
        border.width: ctl.activeFocus ? Theme.focusWidth : (ctl.plain ? 0 : 1)
        border.color: ctl.activeFocus ? Theme.focusRing : ctl.active ? Theme.accent
                     : (hover.hovered ? Theme.borderHover : Theme.hairline)

        scale: ctl.plain ? 1.0 : (tap.pressed ? 0.97 : (hover.hovered ? 1.01 : 1.0))
        Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.fast } }
    }
    Text {
        id: txt
        objectName: "control-label"
        anchors.centerIn: parent
        text: ctl.label
        color: ctl.active ? (ctl.plain ? Theme.accentText : Theme.foregroundFor(bgRect.color))
                          : (ctl.enabled && ctl.enabledLook ? Theme.text : Theme.textDisabled)
        font.family: Theme.fontUI
        font.pixelSize: ctl.small ? Theme.sizeSmall : Theme.size
        font.weight: ctl.active ? Font.DemiBold : Font.Normal
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: if (ctl.enabledLook) { ctl.forceActiveFocus(Qt.MouseFocusReason); ctl.clicked() } }
    ToolTipArea { text: ctl.tip }
}
