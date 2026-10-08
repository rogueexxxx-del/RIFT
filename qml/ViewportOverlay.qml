import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Viewport overlay providing:
// 1. Aspect ratio badge & quick switcher
// 2. Interactive on-screen clip transform (drag to move posX/posY, wheel or corner handles to scale)
// 3. Transform readout & quick reset HUD
Item {
    id: overlay
    required property var viewport

    readonly property rect fr: viewport.framedRect
    readonly property int targetIdx: viewport.editedClip >= 0
                                     ? viewport.editedClip
                                     : (viewport.activeClipIndex >= 0
                                        ? viewport.activeClipIndex
                                        : (viewport.clips.length > 0 ? 0 : -1))
    readonly property var clip: (targetIdx >= 0 && targetIdx < viewport.clips.length)
                                ? viewport.clips[targetIdx] : null

    // Transform mode: allows dragging clip on viewport
    property bool transformEnabled: true

    readonly property var aspectNames: ["16:9", "1:1", "4:3", "9:16", "21:9"]

    // ── Aspect ratio & Transform HUD (top-right of viewport) ──
    RowLayout {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        spacing: 6
        z: 10

        // Transform controls readout (visible when clip present and transform enabled)
        Rectangle {
            visible: overlay.transformEnabled && overlay.clip !== null
            implicitHeight: 28
            implicitWidth: hudRow.implicitWidth + 16
            color: Qt.rgba(0.05, 0.05, 0.08, 0.85)
            radius: 0
            border.width: 1
            border.color: Theme.hairline

            RowLayout {
                id: hudRow
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: overlay.clip
                          ? "X: " + Number(overlay.clip.posX).toFixed(2) +
                            "  Y: " + Number(overlay.clip.posY).toFixed(2) +
                            "  S: " + Math.round(overlay.clip.scale * 100) + "%"
                          : ""
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.sizeSmall
                }

                Text {
                    text: "Reset"
                    color: resetHover.hovered ? Theme.accent : Theme.textMuted
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeSmall
                    font.bold: true

                    HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (overlay.clip)
                                overlay.viewport.setClipTransform(overlay.targetIdx, 0, 0, 1.0)
                        }
                    }
                }
            }
        }

        // Toggle interactive transform mode
        Rectangle {
            visible: overlay.clip !== null
            implicitHeight: 28
            implicitWidth: 32
            color: overlay.transformEnabled ? Theme.accent : Qt.rgba(0.05, 0.05, 0.08, 0.85)
            radius: 0
            border.width: 1
            border.color: overlay.transformEnabled ? Theme.accent : Theme.hairline

            Text {
                anchors.centerIn: parent
                text: "✛"
                font.pixelSize: 14
                color: overlay.transformEnabled ? Theme.bg : Theme.textDim
            }

            HoverHandler { id: xfHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: overlay.transformEnabled = !overlay.transformEnabled }
            ToolTipArea { text: overlay.transformEnabled ? "Transform handles ON (drag to move, wheel to zoom)" : "Transform handles OFF" }
        }

    }

    // ── Interactive Transform Manipulator on Framed Video Area ──
    Item {
        id: framedArea
        x: overlay.fr.x
        y: overlay.fr.y
        width: overlay.fr.width
        height: overlay.fr.height
        clip: true
        visible: overlay.transformEnabled && overlay.clip !== null

        // Visual bounding box for the clip
        readonly property real clipCenterX: width * 0.5 + (overlay.clip ? overlay.clip.posX * width : 0)
        readonly property real clipCenterY: height * 0.5 - (overlay.clip ? overlay.clip.posY * height : 0)
        readonly property real clipW: width * (overlay.clip ? overlay.clip.scale : 1.0)
        readonly property real clipH: height * (overlay.clip ? overlay.clip.scale : 1.0)

        Rectangle {
            id: clipBoundingBox
            x: framedArea.clipCenterX - framedArea.clipW * 0.5
            y: framedArea.clipCenterY - framedArea.clipH * 0.5
            width: framedArea.clipW
            height: framedArea.clipH
            color: "transparent"
            border.width: (overlay.clip && (Math.abs(overlay.clip.posX) > 0.001 ||
                                            Math.abs(overlay.clip.posY) > 0.001 ||
                                            Math.abs(overlay.clip.scale - 1.0) > 0.001 ||
                                            dragArea.containsMouse || dragArea.pressed)) ? 1 : 0
            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)

            // Center reticle
            Rectangle {
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 0
                color: Theme.accent
                opacity: clipBoundingBox.border.width > 0 ? 0.8 : 0
            }

            // Top-left handle
            Rectangle {
                x: -4; y: -4; width: 8; height: 8; radius: 0
                color: Theme.accent
                visible: clipBoundingBox.border.width > 0
            }
            // Top-right handle
            Rectangle {
                x: parent.width - 4; y: -4; width: 8; height: 8; radius: 0
                color: Theme.accent
                visible: clipBoundingBox.border.width > 0
            }
            // Bottom-left handle
            Rectangle {
                x: -4; y: parent.height - 4; width: 8; height: 8; radius: 0
                color: Theme.accent
                visible: clipBoundingBox.border.width > 0
            }
            // Bottom-right handle (drag to scale)
            Rectangle {
                id: brHandle
                x: parent.width - 5; y: parent.height - 5; width: 10; height: 10; radius: 0
                color: Theme.accent
                visible: clipBoundingBox.border.width > 0

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.SizeFDiagCursor
                    preventStealing: true

                    property real startDist: 1
                    property real origScale: 1
                    onPressed: (mouse) => {
                        const dx = (parent.x + mouse.x) - parent.parent.width * 0.5
                        const dy = (parent.y + mouse.y) - parent.parent.height * 0.5
                        startDist = Math.max(10, Math.sqrt(dx * dx + dy * dy))
                        origScale = overlay.clip ? overlay.clip.scale : 1.0
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed || !overlay.clip) return
                        const p = mapToItem(clipBoundingBox, mouse.x, mouse.y)
                        const dx = p.x - clipBoundingBox.width * 0.5
                        const dy = p.y - clipBoundingBox.height * 0.5
                        const curDist = Math.max(10, Math.sqrt(dx * dx + dy * dy))
                        const factor = curDist / startDist
                        const s = Math.max(0.05, Math.min(4.0, origScale * factor))
                        overlay.viewport.setClipTransform(overlay.targetIdx,
                                                          overlay.clip.posX,
                                                          overlay.clip.posY,
                                                          s)
                    }
                }
            }
        }

        // Mouse manipulation over the framed area
        MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            property real startX: 0
            property real startY: 0
            property real origX: 0
            property real origY: 0

            onPressed: (mouse) => {
                startX = mouse.x
                startY = mouse.y
                origX = overlay.clip ? overlay.clip.posX : 0
                origY = overlay.clip ? overlay.clip.posY : 0
            }

            onPositionChanged: (mouse) => {
                if (!pressed || !overlay.clip) return
                const dx = (mouse.x - startX) / Math.max(1, framedArea.width)
                const dy = (mouse.y - startY) / Math.max(1, framedArea.height)
                overlay.viewport.setClipTransform(overlay.targetIdx,
                                                  origX + dx,
                                                  origY - dy,
                                                  overlay.clip.scale)
            }

            onWheel: (wheel) => {
                if (!overlay.clip) return
                const factor = wheel.angleDelta.y > 0 ? 1.05 : 0.95
                const s = Math.max(0.05, Math.min(4.0, overlay.clip.scale * factor))
                overlay.viewport.setClipTransform(overlay.targetIdx,
                                                  overlay.clip.posX,
                                                  overlay.clip.posY,
                                                  s)
            }
        }
    }
}
