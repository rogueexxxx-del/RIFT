import QtQuick
import QtQuick.Controls   // AppDialog's base, for the remove prompt
import QtQuick.Dialogs

// Full-width timeline: a timestamp ruler over stacked clip lanes (V1, V2, ...),
// like a standard editor. Time runs left to right; higher lanes sit on top when
// clips overlap, which is the order the engine composites in.
//
// Clips drag horizontally to move in time and vertically to change lane. Edge
// handles trim. Everything commits on release, so a drag is one engine update.
Rectangle {
    id: panel
    required property var viewport

    property int laneH: 36
    readonly property int laneGap: 3
    readonly property int headW: 54
    // Lanes shown: whatever is in use, plus one empty lane to drop into.
    readonly property int lanes: Math.max(2, panel.viewport.laneCount + 1)
    readonly property int audioLanes: Math.max(1, panel.viewport.audioLaneCount)

    // ── view window ──
    // zoom 1 fits the whole track; higher zooms in. viewStart is the leftmost
    // visible second. Both are plain state so scrubbing and zooming stay
    // independent of what the engine is doing.
    // Lane a clip is currently being dragged onto, -1 when nothing is moving.
    property int dropLane: -1
    property int dropAudioLane: -1

    property real zoom: 1.0
    property real viewStart: 0.0
    readonly property real fullSpan: Math.max(10, panel.viewport.trackDuration * 1.08)
    readonly property real span: fullSpan / zoom
    readonly property real pxPerSec: laneArea.width / span

    // Lowest lane with nothing on it, so a new clip lands somewhere visible
    // instead of behind or after an existing one.
    function nextFreeLane() {
        const cl = panel.viewport.clips
        const used = {}
        for (let i = 0; i < cl.length; ++i) used[cl[i].lane] = true
        let l = 0
        while (used[l]) l += 1
        return l
    }

    function nextFreeAudioLane() {
        const cl = panel.viewport.audioClips
        const used = {}
        for (let i = 0; i < cl.length; ++i) used[cl[i].lane] = true
        let l = 0
        while (used[l]) l += 1
        return l
    }

    function timeAt(px) { return viewStart + px / pxPerSec }
    function xOf(t)     { return (t - viewStart) * pxPerSec }

    // Vertical track scrolling
    property real trackScrollY: 0
    readonly property real totalTracksH: lanes * (laneH + laneGap) + audioLanes * (laneH + laneGap) + 16
    readonly property real visibleTracksH: Math.max(60, panel.height - (Theme.control + 24) - 20 - 18)
    readonly property real maxTrackScrollY: Math.max(0, totalTracksH - visibleTracksH)

    property string activeTool: "select"
    property real razorMouseX: -1

    // Snap a clip drag to the things an edit usually wants to line up with:
    // the start of the piece, the playhead, and the head or tail of any other
    // clip. Respects panel.viewport.snap toggle so dragging is never sticky when off.
    function snapPx(startSec, dx, skipIndex) {
        if (!panel.viewport.snap) return dx
        const want = startSec + dx / pxPerSec
        let best = dx
        let bestPx = 6
        const targets = [0, panel.viewport.playhead]
        const cl = panel.viewport.clips
        for (let i = 0; i < cl.length; ++i) {
            if (i === skipIndex) continue    // its own edges are not a target
            targets.push(cl[i].start)
            targets.push(cl[i].start + cl[i].span)
        }
        const acl = panel.viewport.audioClips
        for (let i = 0; i < acl.length; ++i) {
            targets.push(acl[i].start)
            targets.push(acl[i].start + acl[i].span)
        }
        for (let k = 0; k < targets.length; ++k) {
            const d = Math.abs(want - targets[k]) * pxPerSec
            if (d < bestPx) {
                bestPx = d
                best = (targets[k] - startSec) * pxPerSec
            }
        }
        return best
    }
    function clampView() {
        viewStart = Math.max(0, Math.min(viewStart, fullSpan - span))
    }
    function zoomBy(f, anchorPx) {
        const tAnchor = timeAt(anchorPx)
        zoom = Math.max(1, Math.min(60, zoom * f))
        // Keep whatever was under the cursor pinned there.
        viewStart = tAnchor - anchorPx / (laneArea.width / (fullSpan / zoom))
        clampView()
    }

    // Premiere Pro style timeline wheel navigation:
    // - Plain vertical wheel: scroll tracks up and down vertically!
    // - Shift + wheel or horizontal wheel: pan left and right
    // - Ctrl / Alt + wheel: zoom centered at mouse cursor
    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (ev) => {
            if (ev.modifiers & Qt.AltModifier || ev.modifiers & Qt.ControlModifier) {
                const mouseRelX = Math.max(0, ev.x - (Theme.padding + panel.headW))
                panel.zoomBy(ev.angleDelta.y > 0 ? 1.25 : 0.8, mouseRelX)
            } else if (ev.modifiers & Qt.ShiftModifier || ev.angleDelta.x !== 0) {
                const delta = ev.angleDelta.x !== 0 ? ev.angleDelta.x : ev.angleDelta.y
                panel.viewStart -= (delta / 120) * panel.span * 0.15
                panel.clampView()
            } else {
                // Vertical track scrolling
                panel.trackScrollY = Math.max(0, Math.min(panel.maxTrackScrollY, panel.trackScrollY - (ev.angleDelta.y / 120) * 36))
            }
        }
    }

    // Which clip a right-click is asking to delete, -1 for none.
    property int pendingRemove: -1
    property int pendingRemoveAudio: -1

    color: Theme.bg
    // toolbar + ruler + video lanes + audio lanes + bottom scrollbar
    implicitHeight: Theme.control + 20 + (lanes + audioLanes) * (laneH + laneGap) + 30

    FileDialog {
        id: addDialog
        title: "Add clip"
        nameFilters: ["Video/Image (*.mp4 *.mov *.mkv *.avi *.webm *.png *.jpg *.jpeg)",
                      "All files (*)"]
        // Onto its own lane, not appended after whatever is already on V1.
        // Stacking is the point of having lanes - a second source dropped in
        // line with the first is a cut, which is what the razor is for.
        onAccepted: {
            panel.viewport.addClip(selectedFile, panel.nextFreeLane())
            panel.viewport.selectClip(panel.viewport.clips.length - 1)
        }
    }

    FileDialog {
        id: addAudioDialog
        title: "Add audio"
        nameFilters: ["Audio files (*.wav *.mp3 *.m4a *.aac *.ogg *.flac)",
                      "All files (*)"]
        onAccepted: {
            panel.viewport.addAudioClip(selectedFile, panel.nextFreeAudioLane())
        }
    }

    // ── toolbar ──
    // Its own row. Anchoring it over the ruler meant it sat on top of the tick
    // labels, and there was no width left for it once the text was readable.
    Item {
        id: toolbar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.padding
        anchors.rightMargin: Theme.padding
        anchors.topMargin: 8
        height: Theme.control

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            // Selection Tool (<->)
            EditToolButton {
                kind: "select"
                tip: "Selection Tool (V)"
            }

            // Text Tool (T)
            EditToolButton {
                kind: "text"
                tip: "Text Tool (T)"
                onClicked: {
                    panel.viewport.addTextClip("Text", 1, 5.0)
                    panel.viewport.selectClip(panel.viewport.clips.length - 1)
                }
            }

            // Razor Tool (Cut)
            EditToolButton {
                kind: "razor"
                active: panel.activeTool === "razor"
                tip: panel.activeTool === "razor" ? "Razor Tool active - click clips to cut (or press C / Esc to exit)" : "Razor Tool - Cut / split clips (C)"
                onClicked: {
                    panel.activeTool = (panel.activeTool === "razor" ? "select" : "razor")
                }
            }

            // Stretch Until End Tool (| <-> |)
            EditToolButton {
                kind: "stretch_end"
                enabled: panel.viewport.activeClipIndex >= 0
                tip: "Stretch clip until track end"
                onClicked: panel.viewport.fillTrack(panel.viewport.activeClipIndex)
            }

            // Copy
            EditToolButton {
                kind: "copy"
                enabled: panel.viewport.activeClipIndex >= 0
                tip: "Copy selected clip (Ctrl+C)"
                onClicked: panel.viewport.copyClip(panel.viewport.activeClipIndex)
            }

            // Paste
            EditToolButton {
                kind: "paste"
                enabled: panel.viewport.hasClipboard
                tip: "Paste at playhead (Ctrl+V)"
                onClicked: panel.viewport.pasteClip(panel.viewport.playhead, -1)
            }

            // Add Video Clip Icon
            EditToolButton {
                kind: "add_clip"
                tip: "Add Video Clip"
                onClicked: addDialog.open()
            }

            // Add Audio Track Icon
            EditToolButton {
                kind: "add_audio"
                tip: "Add Audio Track"
                onClicked: addAudioDialog.open()
            }

            // Remove Clip
            EditToolButton {
                kind: "remove"
                enabled: panel.viewport.activeClipIndex >= 0
                tip: "Remove selected clip (Delete)"
                onClicked: {
                    panel.pendingRemove = panel.viewport.activeClipIndex
                    removeConfirm.open()
                }
            }
        }

        Row {
            id: controls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap

            // Keyframe add button
            Rectangle {
                width: 26; height: 22
                radius: 4
                color: keyHover.hovered ? "#262626" : "#181818"
                border.width: 1
                border.color: keyHover.hovered ? "#3A3A3A" : "#242424"
                Text {
                    anchors.centerIn: parent
                    text: "◆"
                    color: keyHover.hovered ? "#FFFFFF" : "#CCCCCC"
                    font.pixelSize: 11
                }
                HoverHandler { id: keyHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (panel.viewport.params && panel.viewport.params.length > 0)
                            panel.viewport.addKey(0)
                    }
                }
                ToolTipArea { text: "Add keyframe at playhead (K)" }
            }

            // Lane Height adjustment toggle (compact / expand)
            FlatButton {
                label: panel.laneH > 40 ? "Compact" : "Expand"
                implicitWidth: 62
                onClicked: panel.laneH = (panel.laneH > 40 ? 34 : 52)
                ToolTipArea { text: "Toggle vertical lane height" }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const fmt = (x) => Math.floor(x / 60) + ":"
                                     + String(Math.floor(x % 60)).padStart(2, '0')
                    return fmt(panel.viewport.playhead) + " / "
                         + fmt(panel.viewport.trackDuration)
                }
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: Theme.sizeSmall
            }

            FlatButton {
                label: "−"; implicitWidth: 28
                onClicked: panel.zoomBy(0.8, laneArea.width / 2)
                ToolTipArea { text: "Zoom out" }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.zoom.toFixed(1) + "x"
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.sizeSmall
            }
            FlatButton {
                label: "+"; implicitWidth: 28
                onClicked: panel.zoomBy(1.25, laneArea.width / 2)
                ToolTipArea { text: "Zoom in" }
            }
        }
    }

    // ── ruler ──
    Item {
        id: ruler
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: toolbar.bottom
        anchors.leftMargin: Theme.padding
        anchors.rightMargin: Theme.padding
        anchors.topMargin: 6
        height: 20

        Item {
            id: rulerArea
            anchors.left: parent.left
            anchors.leftMargin: panel.headW
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height

            // Tick every N seconds, N chosen so labels never crowd.
            readonly property real step: {
                const target = 90 / Math.max(0.0001, panel.pxPerSec)  // ~90 px apart
                const steps = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]
                for (let i = 0; i < steps.length; ++i)
                    if (steps[i] >= target) return steps[i]
                return 600
            }

            // Scrub: click or drag anywhere on the ruler to move the playhead.
            TapHandler {
                onTapped: (pt) => panel.viewport.seek(
                    Math.max(0, panel.timeAt(pt.position.x)))
            }
            DragHandler {
                target: null
                xAxis.enabled: true
                yAxis.enabled: false
                onCentroidChanged: if (active)
                    panel.viewport.seek(Math.max(0, panel.timeAt(centroid.position.x)))
            }
            WheelHandler {
                // Ctrl+wheel zooms about the cursor; plain wheel pans.
                onWheel: (ev) => {
                    if (ev.modifiers & Qt.ControlModifier)
                        panel.zoomBy(ev.angleDelta.y > 0 ? 1.25 : 0.8, ev.x)
                    else {
                        panel.viewStart -= (ev.angleDelta.y / 120) * panel.span * 0.1
                        panel.clampView()
                    }
                }
            }

            Repeater {
                // First tick at or before the left edge, so labels stay aligned
                // to absolute time rather than to the scroll offset.
                model: Math.floor(panel.span / rulerArea.step) + 2
                delegate: Item {
                    required property int index
                    readonly property real t:
                        Math.floor(panel.viewStart / rulerArea.step) * rulerArea.step
                        + index * rulerArea.step
                    x: panel.xOf(t)
                    visible: x >= 0 && x <= rulerArea.width
                    height: rulerArea.height

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: 1; height: 6
                        color: Theme.hairline
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 7
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        text: {
                            const m = Math.floor(parent.t / 60)
                            const s = Math.floor(parent.t % 60)
                            // Sub-second ticks need decimals or every label
                            // reads the same when zoomed in.
                            return rulerArea.step < 1
                                 ? (parent.t).toFixed(1)
                                 : m + ":" + String(s).padStart(2, '0')
                        }
                        color: Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeTiny
                    }
                }
            }

            // Beat markers. Drawn on the ruler rather than in a lane of their
            // own: they are timeline landmarks, and a separate lane would push
            // the clips down for something that is one pixel wide.
            // Beat markers: subtle 5px tick marks at bottom of ruler (not full-height bright blue barcode)
            Repeater {
                model: panel.viewport.markers
                delegate: Rectangle {
                    required property real modelData
                    x: panel.xOf(modelData)
                    visible: x >= 0 && x <= rulerArea.width
                    anchors.bottom: parent.bottom
                    width: 1
                    height: 5
                    color: Theme.textMuted
                    opacity: 0.4
                }
            }

        }
    }

    // ── Track Viewport: vertically scrollable container for all video and audio lanes ──
    Item {
        id: tracksViewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: ruler.bottom
        anchors.topMargin: 2
        anchors.bottom: navScrollbar.top
        anchors.bottomMargin: 3
        clip: true

        HoverHandler {
            id: trackHover
            cursorShape: panel.activeTool === "razor" ? Qt.CrossCursor : Qt.ArrowCursor
            onPointChanged: {
                if (panel.activeTool === "razor") {
                    const localX = point.position.x - (Theme.padding + panel.headW)
                    panel.razorMouseX = localX
                }
            }
        }

        TapHandler {
            onTapped: {
                if (panel.activeTool !== "razor") {
                    panel.viewport.selectClip(-1)
                }
            }
        }

        Item {
            id: tracksContent
            anchors.left: parent.left
            anchors.right: parent.right
            y: -panel.trackScrollY
            height: panel.totalTracksH

            // Razor tool visual cut guide line
            Rectangle {
                id: razorGuide
                visible: panel.activeTool === "razor" && trackHover.hovered && panel.razorMouseX >= 0
                x: Theme.padding + panel.headW + panel.razorMouseX
                y: 0
                width: 2
                height: parent.height
                color: "#FF3344"
                z: 300

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 2
                    width: 38
                    height: 16
                    radius: 3
                    color: "#FF3344"
                    Text {
                        anchors.centerIn: parent
                        text: "RAZOR"
                        color: "#FFFFFF"
                        font.family: Theme.fontUI
                        font.pixelSize: 8
                        font.bold: true
                    }
                }
            }

            // ── lanes ──
            Column {
                id: laneStack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Theme.padding
                anchors.rightMargin: Theme.padding
                spacing: panel.laneGap

        Repeater {
            model: panel.lanes
            delegate: Item {
                required property int index
                width: laneStack.width
                height: panel.laneH

                readonly property int laneNum: panel.lanes - index
                readonly property bool isV1: laneNum === 1

                // Track Header Box: solid, neutral (no permanent blue V1 highlight)
                Rectangle {
                    anchors.left: parent.left
                    width: panel.headW - 4
                    height: parent.height
                    radius: 3
                    color: Theme.panel
                    border.width: 1
                    border.color: Theme.border

                    Text {
                        anchors.centerIn: parent
                        text: "V" + parent.parent.laneNum
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        font.weight: Font.Bold
                    }
                }

                Rectangle {                 // lane bed
                    anchors.left: parent.left
                    anchors.leftMargin: panel.headW
                    anchors.right: parent.right
                    height: parent.height
                    radius: 3
                    color: Theme.bg
                    border.width: (panel.viewport.clipDragging && panel.dropLane === (panel.lanes - 1 - index)) ? 2 : 1
                    border.color: (panel.viewport.clipDragging && panel.dropLane === (panel.lanes - 1 - index))
                                  ? Theme.accent : Theme.hairline
                }
            }
        }
    }

    // Clips are positioned over the lane stack rather than inside a lane, so a
    // vertical drag can cross lanes without leaving its parent item.
    Item {
        id: laneArea
        anchors.left: parent.left
        anchors.leftMargin: Theme.padding + panel.headW
        anchors.right: parent.right
        anchors.rightMargin: Theme.padding
        anchors.top: laneStack.top
        height: panel.lanes * (panel.laneH + panel.laneGap)

        // Lane 0 is the BOTTOM row, matching V1 at the bottom of an editor.
        function laneY(lane) {
            return (panel.lanes - 1 - lane) * (panel.laneH + panel.laneGap)
        }

        // Time grid, aligned to the ruler so clip edges read against it.
        // Declared first so it draws BEHIND the clips, and once rather than
        // per lane - the per-lane version multiplied the item count by the
        // number of lanes for an identical result.
        Repeater {
            model: Math.max(0, Math.floor(panel.span / rulerArea.step) + 1)
            delegate: Rectangle {
                required property int index
                readonly property real t:
                    Math.ceil(panel.viewStart / rulerArea.step) * rulerArea.step
                    + index * rulerArea.step
                x: panel.xOf(t)
                visible: x >= 0 && x <= laneArea.width
                width: 1
                height: laneArea.height
                color: Theme.hairline
                opacity: 0.5
            }
        }

        Repeater {
            model: panel.viewport.clips

            delegate: Item {
                id: clip
                required property int index
                required property var modelData

                readonly property real spanSec: modelData.span > 0 ? modelData.span : 5.0

                // The two trim gestures move the edges live. Without this the
                // clip sat still until the mouse came up, which reads as the
                // handle not having taken the grab at all.
                property real trimL: 0
                property real trimR: 0

                x: panel.xOf(modelData.start) + dragDx + trimL
                // Snapped to whole lanes while dragging: a clip floating
                // between two rows gives no answer to "which lane will this
                // land on".
                y: laneArea.laneY(dropLaneIdx)
                width: Math.max(26, spanSec * panel.pxPerSec - trimL + trimR)
                height: panel.laneH

                property real dragDx: 0
                property real dragDy: 0
                // Lanes the vertical drag would cross (screen down = lane down).
                property int laneShift: -Math.round(dragDy / (panel.laneH + panel.laneGap))
                // Where the clip would land, clamped to the lanes that exist.
                // Lane 0 is the bottom row, so dragging DOWN lowers the index.
                readonly property int dropLaneIdx: Math.max(0, Math.min(
                    panel.lanes - 1, modelData.lane + laneShift))

                readonly property bool isSelected: clip.index === panel.viewport.selectedClip

                // Clip Body with tactile bevel depth
                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: clip.isSelected ? Qt.lighter(Theme.raised, 1.25) : Theme.raised
                    border.width: clip.isSelected ? 2 : 1
                    border.color: clip.isSelected ? Theme.accent : Theme.border
                    opacity: body.active ? 0.85 : 1.0

                    // Top highlight bevel (stops clips from looking flat)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.12)
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 16
                        elide: Text.ElideMiddle
                        visible: clip.width >= 32
                        text: body.active && clip.laneShift !== 0
                              ? "V" + (clip.modelData.lane + clip.laneShift + 1)
                              : clip.modelData.name
                        color: Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                    }

                    // Prominent Keyframe diamonds on the clip for automation
                    Repeater {
                        model: panel.viewport.keyframes
                        delegate: Item {
                            required property var modelData
                            readonly property real keyTime: modelData.time
                            readonly property real clipStart: clip.modelData.start
                            readonly property real clipEnd: clipStart + clip.spanSec
                            visible: keyTime >= clipStart && keyTime <= clipEnd
                            x: (keyTime - clipStart) * panel.pxPerSec - 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12; height: 12
                            z: 10

                            Rectangle {
                                anchors.centerIn: parent
                                width: 9; height: 9
                                rotation: 45
                                color: "#FFB020"
                                border.width: 1
                                border.color: "#FFFFFF"
                            }

                            ToolTipArea {
                                text: (modelData.paramLabel || "Key") + " @ " + modelData.time.toFixed(2) + "s"
                            }

                            TapHandler {
                                onTapped: panel.viewport.playhead = modelData.time
                            }
                        }
                    }
                }

                // The cursor is the only hint a clip can be dragged at all.
                HoverHandler {
                    cursorShape: panel.activeTool === "razor" ? Qt.CrossCursor
                                : (body.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                }

                DragHandler {
                    id: body
                    target: null
                    enabled: panel.activeTool !== "razor"
                    onActiveChanged: {
                        panel.viewport.clipDragging = active
                        panel.dropLane = active
                            ? clip.dropLaneIdx : -1
                        if (active) return
                        if (clip.laneShift !== 0)
                            panel.viewport.setClipLane(
                                clip.index, clip.modelData.lane + clip.laneShift)
                        panel.viewport.setClipStart(
                            clip.index,
                            clip.modelData.start + clip.dragDx / panel.pxPerSec)
                        clip.dragDx = 0; clip.dragDy = 0
                    }
                    onCentroidChanged: {
                        if (!active) return
                        // Scene coordinates: this handler lives on the clip
                        // it is moving, so a delta taken in the clip's own
                        // frame cancels out the movement it just caused and
                        // the clip trails the pointer instead of following it.
                        const dx = centroid.scenePosition.x
                                 - centroid.scenePressPosition.x
                        // Never let a clip be dragged before zero: the engine
                        // clamps it anyway, so allowing it just means the clip
                        // stops following the mouse with no explanation.
                        const minDx = -clip.modelData.start * panel.pxPerSec
                        clip.dragDx = panel.snapPx(
                            clip.modelData.start, Math.max(minDx, dx),
                            clip.index)
                        clip.dragDy = centroid.scenePosition.y
                                    - centroid.scenePressPosition.y
                        panel.dropLane = clip.dropLaneIdx
                    }
                }
                // Click selects the clip (or cuts it if Razor tool is active)
                TapHandler {
                    onTapped: (pt) => {
                        if (panel.activeTool === "razor") {
                            const cutT = panel.timeAt(clip.x + pt.position.x)
                            panel.viewport.splitClip(clip.index, cutT)
                        } else {
                            panel.viewport.selectClip(clip.index)
                        }
                    }
                }
                // Right-click asks first. It used to delete instantly, which
                // is a lot of lost work one stray click away.
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: {
                        panel.pendingRemove = clip.index
                        removeConfirm.open()
                    }
                }

                ClipTrimHandle {
                    anchors.left: parent.left
                    height: parent.height
                    // Clamped so the head cannot pass the tail: a clip trimmed
                    // to nothing is unselectable and looks like it was deleted.
                    onMoved: (dx) => clip.trimL =
                        Math.min(dx, clip.width - 26)
                    onDragged: (dx) => {
                        clip.trimL = 0
                        panel.viewport.setClipTrim(
                            clip.index, clip.modelData.in + dx / panel.pxPerSec,
                            clip.modelData.out)
                    }
                }
                ClipTrimHandle {
                    anchors.right: parent.right
                    height: parent.height
                    onMoved: (dx) => clip.trimR =
                        Math.max(dx, 26 - clip.width)
                    onDragged: (dx) => {
                        clip.trimR = 0
                        const cur = clip.modelData.out > clip.modelData.in
                                  ? clip.modelData.out
                                  : clip.modelData.in + clip.spanSec
                        panel.viewport.setClipTrim(clip.index, clip.modelData.in,
                                                   cur + dx / panel.pxPerSec)
                    }
                }
            }
        }

        // Playhead across every lane. Scrub from the ruler above.
        Rectangle {
            width: 1
            height: parent.height
            color: Theme.text
            visible: x >= 0 && x <= parent.width
            x: {
                const d = panel.viewport.trackDuration
                const t = d > 0 ? panel.viewport.playhead % d : panel.viewport.playhead
                return panel.xOf(t)
            }
        }
    }

    // ── audio lanes ──
    Column {
        id: audioLaneStack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: laneStack.bottom
        anchors.leftMargin: Theme.padding
        anchors.rightMargin: Theme.padding
        anchors.topMargin: panel.laneGap
        spacing: panel.laneGap

        Repeater {
            model: panel.audioLanes
            delegate: Item {
                required property int index
                width: audioLaneStack.width
                height: panel.laneH

                readonly property bool isA1: index === 0

                // Audio Track Header Box: solid, dark, clean green channel tag
                Rectangle {
                    anchors.left: parent.left
                    width: panel.headW - 4
                    height: parent.height
                    radius: 3
                    color: Theme.panel
                    border.width: 1
                    border.color: Theme.border

                    Text {
                        anchors.centerIn: parent
                        text: "A" + (parent.parent.index + 1)
                        color: "#5BE08A"
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        font.weight: Font.Bold
                    }
                }

                Rectangle {                 // lane bed
                    anchors.left: parent.left
                    anchors.leftMargin: panel.headW
                    anchors.right: parent.right
                    height: parent.height
                    radius: 3
                    color: Theme.bg
                    border.width: (panel.viewport.clipDragging && panel.dropAudioLane === index) ? 2 : 1
                    border.color: (panel.viewport.clipDragging && panel.dropAudioLane === index) ? Theme.ok : Theme.hairline
                }
            }
        }
    }

    Item {
        id: audioLaneArea
        anchors.left: parent.left
        anchors.leftMargin: Theme.padding + panel.headW
        anchors.right: parent.right
        anchors.rightMargin: Theme.padding
        anchors.top: audioLaneStack.top
        height: panel.audioLanes * (panel.laneH + panel.laneGap)

        function laneY(lane) {
            return lane * (panel.laneH + panel.laneGap)
        }

        // Time grid, aligned to the ruler so clip edges read against it.
        Repeater {
            model: Math.max(0, Math.floor(panel.span / rulerArea.step) + 1)
            delegate: Rectangle {
                required property int index
                readonly property real t:
                    Math.ceil(panel.viewStart / rulerArea.step) * rulerArea.step
                    + index * rulerArea.step
                x: panel.xOf(t)
                visible: x >= 0 && x <= audioLaneArea.width
                width: 1
                height: audioLaneArea.height
                color: Theme.hairline
                opacity: 0.5
            }
        }

        Repeater {
            model: panel.viewport.audioClips

            delegate: Item {
                id: audioClip
                required property int index
                required property var modelData

                readonly property real spanSec: modelData.span > 0 ? modelData.span : 5.0
                property real trimL: 0
                property real trimR: 0

                x: panel.xOf(modelData.start) + dragDx + trimL
                y: audioLaneArea.laneY(dropLaneIdx)
                width: Math.max(26, spanSec * panel.pxPerSec - trimL + trimR)
                height: panel.laneH

                property real dragDx: 0
                property real dragDy: 0
                property int laneShift: Math.round(dragDy / (panel.laneH + panel.laneGap))
                readonly property int dropLaneIdx: Math.max(0, Math.min(
                    panel.audioLanes - 1, modelData.lane + laneShift))

                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: "#142618"
                    border.width: 1
                    border.color: "#24522E"
                    opacity: audioBody.active ? 0.85 : 1.0

                    // Top highlight bevel (stops clips from looking flat)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.12)
                    }

                    Rectangle {
                        width: 3
                        height: parent.height
                        radius: 0
                        color: Theme.ok
                    }

                    // Waveform rendered directly inside the audio clip - crisp, high-density antialiased lines
                    Canvas {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        property var peaks: panel.viewport.waveform
                        onPeaksChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const n = peaks ? peaks.length : 0
                            if (n === 0 || width <= 0) return
                            const mid = height / 2.0
                            const clipIn = audioClip.modelData.in || 0
                            const clipSpan = audioClip.spanSec

                            ctx.fillStyle = "#5BE08A"
                            for (let px = 0; px < width; px += 1.5) {
                                const t = clipIn + (px / width) * clipSpan
                                const b = Math.floor((t / Math.max(1, panel.fullSpan)) * n)
                                if (b < 0 || b >= n) continue
                                const amp = Math.max(1.2, peaks[b] * (mid - 2) * 0.95)
                                ctx.fillRect(px, mid - amp, 1.2, amp * 2)
                            }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 16
                        elide: Text.ElideMiddle
                        text: audioBody.active && audioClip.laneShift !== 0
                              ? "A" + (audioClip.modelData.lane + audioClip.laneShift + 1)
                              : audioClip.modelData.name
                        color: Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        font.weight: Font.DemiBold
                    }
                }

                HoverHandler {
                    cursorShape: panel.activeTool === "razor" ? Qt.CrossCursor
                                : (audioBody.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                }

                DragHandler {
                    id: audioBody
                    target: null
                    enabled: panel.activeTool !== "razor"
                    onActiveChanged: {
                        panel.viewport.clipDragging = active
                        panel.dropAudioLane = active ? audioClip.dropLaneIdx : -1
                        if (active) return
                        if (audioClip.laneShift !== 0)
                            panel.viewport.setAudioClipLane(
                                audioClip.index, audioClip.modelData.lane + audioClip.laneShift)
                        panel.viewport.setAudioClipStart(
                            audioClip.index,
                            audioClip.modelData.start + audioClip.dragDx / panel.pxPerSec)
                        audioClip.dragDx = 0; audioClip.dragDy = 0
                    }
                    onCentroidChanged: {
                        if (!active) return
                        const rawDx = centroid.scenePosition.x - centroid.scenePressPosition.x
                        audioClip.dragDx = panel.snapPx(audioClip.modelData.start, rawDx, -1)
                        audioClip.dragDy = centroid.scenePosition.y - centroid.scenePressPosition.y
                    }
                }

                TapHandler {
                    onTapped: (pt) => {
                        if (panel.activeTool === "razor") {
                            const cutT = panel.timeAt(audioClip.x + pt.position.x)
                            panel.viewport.splitAudioClip(audioClip.index, cutT)
                        }
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: {
                        panel.pendingRemoveAudio = audioClip.index
                        removeConfirm.open()
                    }
                }

                ClipTrimHandle {
                    anchors.left: parent.left
                    height: parent.height
                    onMoved: (dx) => audioClip.trimL = Math.min(dx, audioClip.width - 26)
                    onDragged: (dx) => {
                        audioClip.trimL = 0
                        panel.viewport.setAudioClipTrim(
                            audioClip.index,
                            audioClip.modelData.in + dx / panel.pxPerSec,
                            audioClip.modelData.out)
                    }
                }
                ClipTrimHandle {
                    anchors.right: parent.right
                    height: parent.height
                    onMoved: (dx) => audioClip.trimR = Math.max(dx, 26 - audioClip.width)
                    onDragged: (dx) => {
                        audioClip.trimR = 0
                        const cur = audioClip.modelData.out > audioClip.modelData.in
                                  ? audioClip.modelData.out
                                  : audioClip.modelData.in + audioClip.spanSec
                        panel.viewport.setAudioClipTrim(
                            audioClip.index,
                            audioClip.modelData.in,
                            cur + dx / panel.pxPerSec)
                    }
                }
            }
        }

        // Playhead stem across audio lanes
        Rectangle {
            width: 1
            height: parent.height
            color: Theme.text
            visible: x >= 0 && x <= parent.width
            x: {
                const d = panel.viewport.trackDuration
                const t = d > 0 ? panel.viewport.playhead % d : panel.viewport.playhead
                return panel.xOf(t)
            }
        }
    }
    } // tracksContent

    // Vertical scroll indicator when tracks overflow
    Rectangle {
        id: vScrollTrack
        visible: panel.maxTrackScrollY > 0
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.08)

        Rectangle {
            width: parent.width
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.35)
            y: (panel.trackScrollY / Math.max(1, panel.maxTrackScrollY)) * (parent.height - height)
            height: Math.max(16, parent.height * (tracksViewport.height / Math.max(1, tracksContent.height)))
        }
    }
    } // tracksViewport

    // ── Bottom Navigator Scrollbar (matches Figma 7_146.png & Premiere Pro style navigation) ──
    Rectangle {
        id: navScrollbar
        anchors.left: parent.left
        anchors.leftMargin: Theme.padding + panel.headW
        anchors.right: parent.right
        anchors.rightMargin: Theme.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        height: 10
        radius: 5
        color: Theme.panel

        readonly property real viewFrac: Math.max(0.06, Math.min(1, panel.span / Math.max(1, panel.fullSpan)))
        readonly property real startFrac: Math.max(0, Math.min(1, panel.viewStart / Math.max(1, panel.fullSpan)))

        // Click track to jump
        TapHandler {
            onTapped: (pt) => {
                const frac = pt.position.x / navScrollbar.width
                panel.viewStart = Math.max(0, Math.min(panel.fullSpan - panel.span, frac * panel.fullSpan - panel.span / 2))
                panel.clampView()
            }
        }

        Rectangle {
            id: navThumb
            x: Math.max(0, Math.min(parent.width - width, parent.width * navScrollbar.startFrac))
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(48, parent.width * navScrollbar.viewFrac)
            height: 8
            radius: 4
            color: thumbDrag.drag.active ? "#FFFFFF" : (thumbHover.hovered ? "#EEEEEE" : "#888888")

            HoverHandler { id: thumbHover; cursorShape: Qt.PointingHandCursor }

            // Smooth horizontal panning drag
            MouseArea {
                id: thumbDrag
                anchors.fill: parent
                drag.target: navThumb
                drag.axis: Drag.XAxis
                drag.minimumX: 0
                drag.maximumX: navScrollbar.width - navThumb.width
                cursorShape: Qt.PointingHandCursor

                onPositionChanged: {
                    if (drag.active && (navScrollbar.width - navThumb.width) > 0) {
                        const frac = navThumb.x / (navScrollbar.width - navThumb.width)
                        panel.viewStart = Math.max(0, Math.min(panel.fullSpan - panel.span, frac * (panel.fullSpan - panel.span)))
                    }
                }
            }

            // Left zoom handle (Premiere Pro style resize edge)
            Item {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 10

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeHorCursor
                    property real pressX: 0
                    property real pressSpan: 0
                    property real pressView: 0

                    onPressed: (mouse) => {
                        pressX = mouse.x
                        pressSpan = panel.span
                        pressView = panel.viewStart
                    }
                    onPositionChanged: (mouse) => {
                        if (pressed) {
                            const deltaSec = (mouse.x - pressX) / navScrollbar.width * panel.fullSpan
                            const newSpan = Math.max(1, Math.min(panel.fullSpan, pressSpan - deltaSec))
                            panel.zoom = Math.max(1, Math.min(60, panel.fullSpan / newSpan))
                            panel.viewStart = Math.max(0, Math.min(panel.fullSpan - panel.span, pressView + deltaSec))
                            panel.clampView()
                        }
                    }
                }
            }

            // Right zoom handle (Premiere Pro style resize edge)
            Item {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 10

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeHorCursor
                    property real pressX: 0
                    property real pressSpan: 0

                    onPressed: (mouse) => {
                        pressX = mouse.x
                        pressSpan = panel.span
                    }
                    onPositionChanged: (mouse) => {
                        if (pressed) {
                            const deltaSec = (mouse.x - pressX) / navScrollbar.width * panel.fullSpan
                            const newSpan = Math.max(1, Math.min(panel.fullSpan, pressSpan + deltaSec))
                            panel.zoom = Math.max(1, Math.min(60, panel.fullSpan / newSpan))
                            panel.clampView()
                        }
                    }
                }
            }
        }
    }

    // Deleting a clip is easy to do by accident with a right-click and there is
    // no undo prompt at the moment it happens, so it asks.
    AppDialog {
        id: removeConfirm
        title: "Remove clip"
        width: 340
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: {
            if (panel.pendingRemove >= 0)
                panel.viewport.removeClip(panel.pendingRemove)
            if (panel.pendingRemoveAudio >= 0)
                panel.viewport.removeAudioClip(panel.pendingRemoveAudio)
            panel.pendingRemove = -1
            panel.pendingRemoveAudio = -1
        }
        onRejected: {
            panel.pendingRemove = -1
            panel.pendingRemoveAudio = -1
        }

        contentItem: Text {
            text: "Remove this clip from the timeline?"
            color: Theme.text
            wrapMode: Text.WordWrap
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
        }
    }

    Shortcut {
        sequence: "C"
        onActivated: panel.activeTool = (panel.activeTool === "razor" ? "select" : "razor")
    }
    Shortcut {
        sequence: "Escape"
        onActivated: panel.activeTool = "select"
    }
}
