import QtQuick

// Figma-styled Timeline Tool Button (matches Figma node 7:123):
// - 28x24 rectangle with 4px corner radius
// - Solid grey background (#9A9A9A) with lighter hover (#D0D0D0)
// - Solid black icon art (#000000)
// - Supports: select, text, razor, fill/stretch_end, copy, paste, add_clip, add_audio, remove
Rectangle {
    id: btn
    property string kind: "select"
    property string tip: ""
    property bool active: false
    signal clicked()

    implicitWidth: 28
    implicitHeight: 24
    radius: 4
    color: !btn.enabled ? "#101010"
         : (btn.active ? Theme.accentSoft : (hover.hovered ? "#262626" : "#181818"))
    border.width: 1
    border.color: !btn.enabled ? "#1A1A1A"
                : (btn.active ? Theme.accent : (hover.hovered ? "#3A3A3A" : "#242424"))
    opacity: btn.enabled ? 1.0 : 0.4

    readonly property color fg: !btn.enabled ? "#555555"
                              : (btn.active ? Theme.accent : (hover.hovered ? "#FFFFFF" : "#CCCCCC"))

    Canvas {
        id: art
        anchors.centerIn: parent
        width: 16; height: 14

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = btn.fg
            ctx.fillStyle = btn.fg
            ctx.lineWidth = 1.3

            if (btn.kind === "select") {
                // Horizontal double-headed arrow <->
                ctx.beginPath()
                ctx.moveTo(1.5, 7); ctx.lineTo(14.5, 7)
                ctx.stroke()
                // Left arrow head
                ctx.beginPath()
                ctx.moveTo(1.5, 7); ctx.lineTo(5, 4.5); ctx.lineTo(5, 9.5)
                ctx.closePath(); ctx.fill()
                // Right arrow head
                ctx.beginPath()
                ctx.moveTo(14.5, 7); ctx.lineTo(11, 4.5); ctx.lineTo(11, 9.5)
                ctx.closePath(); ctx.fill()
            } else if (btn.kind === "text") {
                // Bold serif T
                ctx.font = "bold 11px sans-serif"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.fillText("T", 8, 7.5)
            } else if (btn.kind === "razor" || btn.kind === "cut") {
                // Razor / scissors icon
                ctx.beginPath()
                ctx.moveTo(2.5, 1.5); ctx.lineTo(10.5, 9.5)
                ctx.moveTo(13.5, 1.5); ctx.lineTo(5.5, 9.5)
                ctx.stroke()
                ctx.beginPath(); ctx.arc(4.5, 11, 2, 0, 6.2832); ctx.stroke()
                ctx.beginPath(); ctx.arc(11.5, 11, 2, 0, 6.2832); ctx.stroke()
            } else if (btn.kind === "fill" || btn.kind === "stretch_end") {
                // Stretch until end: | <-> |
                ctx.lineWidth = 1.5
                // Left vertical bar
                ctx.beginPath(); ctx.moveTo(1.5, 2); ctx.lineTo(1.5, 12); ctx.stroke()
                // Right vertical bar
                ctx.beginPath(); ctx.moveTo(14.5, 2); ctx.lineTo(14.5, 12); ctx.stroke()
                // Center double arrow
                ctx.lineWidth = 1.2
                ctx.beginPath(); ctx.moveTo(3.5, 7); ctx.lineTo(12.5, 7); ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(3.5, 7); ctx.lineTo(6, 4.5); ctx.lineTo(6, 9.5)
                ctx.closePath(); ctx.fill()
                ctx.beginPath()
                ctx.moveTo(12.5, 7); ctx.lineTo(10, 4.5); ctx.lineTo(10, 9.5)
                ctx.closePath(); ctx.fill()
            } else if (btn.kind === "copy") {
                // Two overlapping sheets
                ctx.strokeRect(4.5, 4.5, 9.5, 8.5)
                ctx.beginPath()
                ctx.moveTo(2, 10.5); ctx.lineTo(2, 2); ctx.lineTo(10.5, 2)
                ctx.stroke()
            } else if (btn.kind === "paste") {
                // Clipboard with clip on top
                ctx.strokeRect(2.5, 3.5, 11, 9.5)
                ctx.fillRect(5.5, 1, 5, 3.5)
            } else if (btn.kind === "add_clip") {
                // Video frame with +
                ctx.strokeRect(1.5, 2, 13, 10)
                ctx.beginPath()
                ctx.moveTo(8, 4.5); ctx.lineTo(8, 9.5)
                ctx.moveTo(5.5, 7); ctx.lineTo(10.5, 7)
                ctx.stroke()
            } else if (btn.kind === "add_audio") {
                // Audio waveform with +
                ctx.beginPath()
                ctx.moveTo(3, 4); ctx.lineTo(3, 10)
                ctx.moveTo(6, 2); ctx.lineTo(6, 12)
                ctx.moveTo(9, 5); ctx.lineTo(9, 9)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(13, 4); ctx.lineTo(13, 8)
                ctx.moveTo(11, 6); ctx.lineTo(15, 6)
                ctx.stroke()
            } else if (btn.kind === "remove") {
                // Clean ×
                ctx.lineWidth = 1.5
                ctx.beginPath()
                ctx.moveTo(3.5, 2.5); ctx.lineTo(12.5, 11.5)
                ctx.moveTo(12.5, 2.5); ctx.lineTo(3.5, 11.5)
                ctx.stroke()
            }
        }

        Connections {
            target: btn
            function onFgChanged() { art.requestPaint() }
            function onKindChanged() { art.requestPaint() }
        }
    }

    HoverHandler { id: hover; cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { onTapped: if (btn.enabled) btn.clicked() }
    ToolTipArea { text: btn.tip }
}
