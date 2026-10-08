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
    DragHandler {
        id: drag
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        // Beat the clip body's own drag handler to the grab. Without this a
        // trim that starts a few pixels in turns into a move.
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        property real dx: 0
        onCentroidChanged: {
            if (!active) return
            // scenePosition, NOT position. This handle is anchored to the clip
            // edge it is dragging, so the moment the clip resizes the handle
            // moves too - and a delta measured against the handle's own
            // origin then subtracts its own effect. The edge crawled along at
            // a fraction of the pointer's speed and never caught up.
            dx = centroid.scenePosition.x - centroid.scenePressPosition.x
            h.moved(dx)
        }
        onActiveChanged: {
            if (active) return
            h.dragged(dx)
            dx = 0
            h.moved(0)
        }
    }
}
