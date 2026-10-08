import QtQuick

// Flat control. Sits ON a panel, so its resting state is one surface step up
// rather than a transparent box outlined in a hairline - an outline around
// every button is what made the old UI read as a wireframe.
Item {
    id: ctl
    property string label: ""
    property bool   active: false
    property bool   enabledLook: true
    // Compact form for the rows that carry several buttons at once - the
    // keyframe and patch strips. Full-size controls there filled the panel
    // edge to edge with no air between them.
    property bool   small: false
    property string tip: ""
    signal clicked()

    implicitHeight: ctl.small ? Theme.control - 7 : Theme.control
    implicitWidth: txt.implicitWidth + (ctl.small ? 14 : 22)

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: ctl.active ? (tap.pressed ? Theme.accent : (hover.hovered ? Theme.accentPressed : Theme.accent))
                          : (tap.pressed ? Theme.bg
                                         : (hover.hovered ? Theme.hover
                                                          : Theme.raised))
        border.width: ctl.active ? 0 : (hover.hovered ? 1 : 0)
        border.color: hover.hovered ? Theme.borderHover : "transparent"
    }
    Text {
        id: txt
        anchors.centerIn: parent
        text: ctl.label
        color: ctl.active ? Theme.onAccent : (ctl.enabledLook ? Theme.text : Theme.textDisabled)
        font.family: Theme.fontUI
        font.pixelSize: ctl.small ? Theme.sizeSmall : Theme.size
    }
    HoverHandler { id: hover }
    TapHandler { id: tap; onTapped: ctl.clicked() }
    ToolTipArea { text: ctl.tip }
}
