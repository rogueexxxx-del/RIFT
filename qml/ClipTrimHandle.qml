import QtQuick

// Grab strip on a clip edge.
//
// It reports its drag CONTINUOUSLY as well as on release. Reporting only on
// release is what made trimming feel broken: the pointer moved, the clip did
// not, and there was no way to tell the grab had registered until you let go.
Item {
    id: h
    // While dragging. The clip uses this to preview the new edge.
    signal moved(real dx)
    // On release. The clip commits the trim.
    signal dragged(real dx)
    signal started()
    property int revision: 0
    onRevisionChanged: cancelGesture()
    function cancelGesture() {
        drag.armed = false
        drag.dx = 0
        h.moved(0)
    }

    readonly property bool active: drag.active

    // Ten, not seven. Seven is under the width of a mouse cursor's hot zone,
    // so the edge had to be hit almost exactly.
    width: 10

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        radius: Theme.radius
        color: drag.active ? Theme.accentPressed
                           : (hover.hovered ? Theme.accent : "transparent")
        opacity: drag.active ? 1.0 : 0.75

        // Two grip lines, so the strip reads as a handle before it is hovered.
        Column {
            anchors.centerIn: parent
            spacing: 3
            visible: hover.hovered || drag.active
            Repeater {
                model: 2
                delegate: Rectangle {
                    width: 1; height: 9
                    color: Theme.bg
                }
            }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.SizeHorCursor
    }
    MouseArea {
        id: drag
        anchors.fill: parent
        preventStealing: true
        readonly property bool active: armed && Math.abs(dx) >= 1
        property bool armed: false
        property real dx: 0
        property real pressX: 0
        onPressed: (mouse) => {
            dx = 0
            pressX = mapToItem(null, mouse.x, mouse.y).x
            armed = true
            h.started()
        }
        onPositionChanged: (mouse) => {
            if (!pressed || !armed) return
            // The moving edge is not a stable coordinate frame.
            dx = mapToItem(null, mouse.x, mouse.y).x - pressX
            h.moved(dx)
        }
        onReleased: {
            const commit = armed && Math.abs(dx) > 0.000001
            const finalDx = dx
            armed = false
            dx = 0
            h.moved(0)
            if (commit) h.dragged(finalDx)
        }
        onCanceled: {
            armed = false
            dx = 0
            h.moved(0)
        }
    }
}
