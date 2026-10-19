import QtQuick
import QtQuick.Shapes

// Transport icons, drawn rather than typed. The UI font has no media glyphs
// (its arrows render as unrelated letters), and pulling in an icon font for
// three shapes is not worth a dependency.
Item {
    id: btn
    property string kind: "play"      // play | pause | stop | back | fwd
    property bool   active: false
    property bool   borderless: false
    property string tip: ""
    signal clicked()

    implicitWidth: Theme.control
    implicitHeight: Theme.control
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: tip || kind
    Accessible.onPressAction: if (enabled) clicked()
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) clicked() }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) clicked() }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.radius
        color: btn.borderless
               ? (tap.pressed ? Theme.hover : (hover.hovered ? Theme.hover : "transparent"))
               : (btn.active ? (tap.pressed ? Theme.accent : (hover.hovered ? Theme.accentPressed : Theme.accent))
                             : (tap.pressed ? Theme.bg
                                            : (hover.hovered ? Theme.hover : Theme.raised)))
        border.width: btn.activeFocus ? Theme.focusWidth : (btn.borderless || btn.active ? 0 : 1)
        border.color: btn.activeFocus ? Theme.focusRing : hover.hovered ? Theme.borderHover : Theme.border
    }

    readonly property color fg: active ? (borderless ? Theme.accentText : Theme.foregroundFor(bg.color))
                                       : (hover.hovered ? Theme.text : Theme.textDim)

    Item {
        id: art
        anchors.centerIn: parent
        width: 12; height: 12
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillColor: btn.kind === "play" ? btn.fg : "transparent"
                startX: 1; startY: 0
                PathLine { x: 12; y: 6 }
                PathLine { x: 1; y: 12 }
                PathLine { x: 1; y: 0 }
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: btn.kind === "back" ? btn.fg : "transparent"
                startX: 11; startY: 0
                PathLine { x: 5; y: 6 }
                PathLine { x: 11; y: 12 }
                PathLine { x: 11; y: 0 }
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: btn.kind === "back" ? btn.fg : "transparent"
                startX: 6; startY: 0
                PathLine { x: 2; y: 6 }
                PathLine { x: 6; y: 12 }
                PathLine { x: 6; y: 0 }
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: btn.kind === "fwd" ? btn.fg : "transparent"
                startX: 1; startY: 0
                PathLine { x: 7; y: 6 }
                PathLine { x: 1; y: 12 }
                PathLine { x: 1; y: 0 }
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: btn.kind === "fwd" ? btn.fg : "transparent"
                startX: 6; startY: 0
                PathLine { x: 10; y: 6 }
                PathLine { x: 6; y: 12 }
                PathLine { x: 6; y: 0 }
            }
        }
        Rectangle {
            visible: btn.kind === "pause"
            x: 1; width: 4; height: 12; color: btn.fg
        }
        Rectangle {
            visible: btn.kind === "pause"
            x: 8; width: 4; height: 12; color: btn.fg
        }
        Rectangle {
            visible: btn.kind === "stop"
            x: 1; y: 1; width: 10; height: 10; color: btn.fg
        }
    }

    HoverHandler { id: hover }
    TapHandler { id: tap; onTapped: { btn.forceActiveFocus(Qt.MouseFocusReason); btn.clicked() } }
    ToolTipArea { text: btn.tip }
}
