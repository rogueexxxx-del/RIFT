import QtQuick

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

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 4
        color: btn.borderless
               ? (btn.active ? Theme.accent : (tap.pressed ? "transparent" : (hover.hovered ? "#222222" : "transparent")))
               : (btn.active ? (tap.pressed ? Theme.accent : (hover.hovered ? Theme.accentPressed : Theme.accent))
                             : (tap.pressed ? Theme.bg
                                            : (hover.hovered ? Theme.hover : Theme.raised)))
        border.width: btn.borderless || btn.active ? 0 : 1
        border.color: hover.hovered ? Theme.borderHover : Theme.border
    }

    readonly property color fg: active ? Theme.onAccent
                                       : (hover.hovered ? Theme.text : Theme.textDim)

    Canvas {
        id: art
        anchors.centerIn: parent
        width: 12; height: 12
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = btn.fg
            if (btn.kind === "play") {
                ctx.beginPath()
                ctx.moveTo(1, 0); ctx.lineTo(12, 6); ctx.lineTo(1, 12)
                ctx.closePath(); ctx.fill()
            } else if (btn.kind === "pause") {
                ctx.fillRect(1, 0, 4, 12)
                ctx.fillRect(8, 0, 4, 12)
            } else if (btn.kind === "stop") {
                ctx.fillRect(1, 1, 10, 10)
            } else if (btn.kind === "back") {
                // Two left triangles against a bar.
                ctx.beginPath()
                ctx.moveTo(11, 0); ctx.lineTo(11, 12); ctx.lineTo(5, 6)
                ctx.closePath(); ctx.fill()
                ctx.beginPath()
                ctx.moveTo(6, 0); ctx.lineTo(6, 12); ctx.lineTo(2, 6)
                ctx.closePath(); ctx.fill()
            } else if (btn.kind === "fwd") {
                ctx.beginPath()
                ctx.moveTo(1, 0); ctx.lineTo(1, 12); ctx.lineTo(7, 6)
                ctx.closePath(); ctx.fill()
                ctx.beginPath()
                ctx.moveTo(6, 0); ctx.lineTo(6, 12); ctx.lineTo(10, 6)
                ctx.closePath(); ctx.fill()
            } else {
                ctx.fillRect(1, 1, 10, 10)
            }
        }
        // Canvas caches its drawing, so a colour change needs an explicit repaint.
        Connections {
            target: btn
            function onFgChanged() { art.requestPaint() }
            function onKindChanged() { art.requestPaint() }
        }
    }

    HoverHandler { id: hover }
    TapHandler { id: tap; onTapped: btn.clicked() }
    ToolTipArea { text: btn.tip }
}
