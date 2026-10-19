import QtQuick
import QtQuick.Controls   // AppDialog's base, for the remove prompt
import QtQuick.Dialogs
import QtQuick.Window
import QtQuick.Shapes

// Full-width timeline: a timestamp ruler over stacked clip lanes (V1, V2, ...),
// like a standard editor. Time runs left to right; higher lanes sit on top when
// clips overlap, which is the order the engine composites in.
//
// Clips drag horizontally to move in time and vertically to change lane. Edge
// handles trim. Everything commits on release, so a drag is one engine update.
Rectangle {
    id: panel
    required property var viewport
    property bool shortcutsSuspended: false
    readonly property var focusedEditor: Window.window ? Window.window.activeFocusItem : null
    readonly property bool shortcutsEnabled: visible && !shortcutsSuspended
        && !(focusedEditor instanceof TextInput) && !(focusedEditor instanceof TextEdit)
    readonly property int targetClip: viewport.selectedClip >= 0 ? viewport.selectedClip : viewport.activeClipIndex

    property int laneH: 40
    readonly property int audioLaneH: laneH + 24
    readonly property int laneGap: 3
    readonly property int headW: 54
    // Keep useful tracks first; offer a spare drop lane only when it fits.
    readonly property int usedVideoLanes: Math.max(1, panel.viewport.laneCount)
    readonly property real availableTracksH: Math.max(0, height - tracksViewport.y - 16)
    readonly property real usedTracksH: usedVideoLanes * (laneH + laneGap)
        + audioLanes * (audioLaneH + laneGap) + 16
    readonly property int lanes: usedVideoLanes + (panel.viewport.clips.length > 0
        && availableTracksH >= usedTracksH + laneH + laneGap ? 1 : 0)
    readonly property int audioLanes: Math.max(1, panel.viewport.audioLaneCount)

    // ── view window ──
    // zoom 1 fits the whole track; higher zooms in. viewStart is the leftmost
    // visible second. Both are plain state so scrubbing and zooming stay
    // independent of what the engine is doing.
    // Lane a clip is currently being dragged onto, -1 when nothing is moving.
    property int dropLane: -1
    property int dropAudioLane: -1
    // Undo may rebuild a model while a delegate still owns the mouse grab.
    property int editRevision: 0
    Connections {
        target: panel.viewport
        function onClipsChanged() { panel.editRevision += 1 }
        function onAudioClipsChanged() { panel.editRevision += 1 }
    }

    property real zoom: 1.0
    property real viewStart: 0.0
    // Editing includes media beyond the export sequence bounds.
    readonly property real editExtent: {
        let end = Math.max(0, viewport.trackDuration)
        const all = viewport.clips.concat(viewport.audioClips)
        for (let i = 0; i < all.length; ++i)
            end = Math.max(end, all[i].start + (all[i].span > 0 ? all[i].span : 5))
        return end
    }
    readonly property real fullSpan: Math.max(10, editExtent * 1.08)
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
    function parseTime(text) {
        const value = text.trim()
        if (/^\d+(\.\d+)?$/.test(value)) return Number(value)
        const parts = /^(\d+):([0-5]\d(?:\.\d+)?)$/.exec(value)
        return parts ? Number(parts[1]) * 60 + Number(parts[2]) : NaN
    }
    readonly property real songEnd: {
        let end = 0
        const clips = viewport.audioClips
        for (let i = 0; i < clips.length; ++i) {
            const clip = clips[i]
            if (Number.isFinite(clip.start) && clip.start >= 0 && Number.isFinite(clip.span)
                && clip.span > 0 && clip.sourceDuration > 0)
                end = Math.max(end, clip.start + clip.span)
        }
        return end
    }

    function peakBetween(peaks, duration, from, to) {
        if (!peaks || !peaks.length || duration <= 0 || to <= 0 || from >= duration) return 0
        const first = Math.max(0, Math.floor(from / duration * peaks.length))
        const last = Math.min(peaks.length, Math.max(first + 1, Math.ceil(to / duration * peaks.length)))
        let peak = 0
        for (let i = first; i < last; ++i)
            if (Number.isFinite(peaks[i])) peak = Math.max(peak, Math.abs(peaks[i]))
        return Math.min(1, peak)
    }

    readonly property bool hasRange: viewport.markOut > viewport.markIn
    readonly property real rangeLeft: Math.max(0, Math.min(laneArea.width, xOf(viewport.markIn)))
    readonly property real rangeRight: Math.max(0, Math.min(laneArea.width, xOf(viewport.markOut)))
    function formatTime(t) {
        const cs = Math.round(Math.max(0, t) * 100)
        return Math.floor(cs / 6000) + ":" + (Math.floor(cs / 100) % 60).toString().padStart(2, "0")
            + "." + (cs % 100).toString().padStart(2, "0")
    }

    // Vertical track scrolling
    property real trackScrollY: 0
    readonly property real totalTracksH: lanes * (laneH + laneGap) + audioLanes * (audioLaneH + laneGap) + 16
    readonly property real visibleTracksH: tracksViewport.height
    readonly property real maxTrackScrollY: Math.max(0, totalTracksH - visibleTracksH)
    onMaxTrackScrollYChanged: trackScrollY = Math.min(trackScrollY, maxTrackScrollY)

    property string activeTool: "select"
    property real razorMouseX: -1

    // Snap a clip drag to the things an edit usually wants to line up with:
    // the start of the piece, the playhead, and the head or tail of any other
    // clip. Respects the beat snap toggle so dragging is free when off.
    function snapPx(startSec, dx, skipIndex, duration, audio) {
        if (!panel.viewport.snapToMarkers) return dx
        const want = startSec + dx / pxPerSec
        const edges = [0, duration || 0]
        let best = dx
        let bestPx = 4
        const targets = [0, panel.viewport.playhead]
        if (panel.hasRange) targets.push(panel.viewport.markIn, panel.viewport.markOut)
        const beats = panel.viewport.markers
        for (let i = 0; i < beats.length; ++i) targets.push(beats[i])
        const cl = panel.viewport.clips
        for (let i = 0; i < cl.length; ++i) {
            if (!audio && i === skipIndex) continue    // its own edges are not a target
            targets.push(cl[i].start)
            targets.push(cl[i].start + cl[i].span)
        }
        const acl = panel.viewport.audioClips
        for (let i = 0; i < acl.length; ++i) {
            if (audio && i === skipIndex) continue
            targets.push(acl[i].start)
            targets.push(acl[i].start + acl[i].span)
        }
        for (let k = 0; k < targets.length; ++k) {
            for (let e = 0; e < edges.length; ++e) {
                const candidate = targets[k] - edges[e]
                const d = Math.abs(want - candidate) * pxPerSec
                if (candidate >= 0 && d < bestPx) {
                    bestPx = d
                    best = (candidate - startSec) * pxPerSec
                }
            }
        }
        return best
    }
    function clampView() {
        viewStart = Math.max(0, Math.min(viewStart, fullSpan - span))
    }
    onFullSpanChanged: clampView()
    function navigateWheel(ev, anchorPx) {
        const horizontal = ev.pixelDelta.x || ev.angleDelta.x
        const vertical = ev.pixelDelta.y || ev.angleDelta.y
        if (ev.modifiers & (Qt.AltModifier | Qt.ControlModifier)) {
            const delta = vertical || horizontal
            if (delta !== 0) zoomBy(Math.pow(1.25, delta / 120), anchorPx)
        } else if (ev.modifiers & Qt.ShiftModifier || horizontal !== 0) {
            const delta = horizontal || vertical
            viewStart -= (ev.pixelDelta.x || ev.pixelDelta.y)
                       ? delta / Math.max(1, pxPerSec) : delta / 120 * span * 0.15
            clampView()
        } else {
            trackScrollY = Math.max(0, Math.min(maxTrackScrollY,
                trackScrollY - (ev.pixelDelta.y || ev.angleDelta.y / 120 * 36)))
        }
        ev.accepted = true
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
            // Vertical track scrolling
            panel.navigateWheel(ev, Math.max(0, Math.min(laneArea.width,
                ev.x - (Theme.padding + panel.headW))))
        }
    }

    // Which clip a right-click is asking to delete, -1 for none.
    property int pendingRemove: -1
    property int pendingRemoveAudio: -1
    property int selectedAudioClip: -1
    property int contextIndex: -1
    property bool contextAudio: false
    function requestRemove(index, audio) {
        pendingRemove = audio ? -1 : index
        pendingRemoveAudio = audio ? index : -1
        removeConfirm.open()
    }
    function openClipMenu(index, audio, item, point) {
        contextIndex = index
        contextAudio = audio
        selectedAudioClip = audio ? index : -1
        if (!audio) viewport.selectClip(index)
        clipMenu.popup(item, point)
    }
    onEditRevisionChanged: {
        clipMenu.close()
        removeConfirm.close()
        pendingRemove = -1
        pendingRemoveAudio = -1
        selectedAudioClip = -1
        contextIndex = -1
    }
    StyledMenu {
        id: clipMenu
        objectName: "clipContextMenu"
        readonly property var source: panel.contextAudio ? panel.viewport.audioClips : panel.viewport.clips
        readonly property var clipData: panel.contextIndex >= 0 ? source[panel.contextIndex] : null
        StyledMenuItem {
            objectName: "clipCopyAction"
            implicitHeight: 28
            leftPadding: 14
            rightPadding: 14
            text: "Copy"
            shortcutText: "Ctrl+C"
            enabled: !panel.contextAudio && panel.contextIndex >= 0
            onTriggered: panel.viewport.copyClip(panel.contextIndex)
        }
        StyledMenuItem {
            objectName: "clipPasteAction"
            implicitHeight: 28
            leftPadding: 14
            rightPadding: 14
            text: "Paste at playhead"
            shortcutText: "Ctrl+V"
            // The engine clipboard supports video/text clips only.
            enabled: !panel.contextAudio && panel.viewport.hasClipboard
            onTriggered: panel.viewport.pasteClip(panel.viewport.playhead, clipMenu.clipData.lane)
        }
        StyledMenuItem {
            objectName: "clipSplitAction"
            implicitHeight: 28
            leftPadding: 14
            rightPadding: 14
            text: "Split at playhead"
            enabled: clipMenu.clipData !== null && clipMenu.clipData !== undefined
                && panel.viewport.playhead > clipMenu.clipData.start + 0.1
                && panel.viewport.playhead < clipMenu.clipData.start + clipMenu.clipData.span - 0.1
            onTriggered: {
                if (panel.contextAudio) panel.viewport.splitAudioClip(panel.contextIndex, panel.viewport.playhead)
                else panel.viewport.splitClip(panel.contextIndex, panel.viewport.playhead)
            }
        }
        StyledMenuItem {
            objectName: "clipDeleteAction"
            implicitHeight: 28
            leftPadding: 14
            rightPadding: 14
            text: "Delete"
            shortcutText: "Delete"
            enabled: panel.contextIndex >= 0
            onTriggered: panel.requestRemove(panel.contextIndex, panel.contextAudio)
        }
    }

    color: Theme.bg
    // toolbar + ruler + video lanes + audio lanes + bottom scrollbar
    implicitHeight: 84 + usedTracksH

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
        height: 32
        Flickable {
            id: toolStrip
            objectName: "timelineToolStrip"
            width: parent.width
            height: parent.height
            contentWidth: toolRow.width
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            WheelHandler {
                target: null
                onWheel: (event) => {
                    const delta = event.pixelDelta.x || event.pixelDelta.y
                        || (event.angleDelta.x || event.angleDelta.y) / 2
                    toolStrip.contentX = Math.max(0, Math.min(toolStrip.contentWidth - toolStrip.width,
                        toolStrip.contentX - delta))
                    event.accepted = true
                }
            }
            Row {
                id: toolRow
                objectName: "timelineToolsRow"
                height: toolbar.height
                spacing: 12

        Row {
            height: toolbar.height
            spacing: 2

            // Selection Tool (<->)
            EditToolButton {
                kind: "select"
                active: panel.activeTool === "select"
                tip: "Selection Tool (V)"
                onClicked: panel.activeTool = "select"
            }

            // Text Tool (T)
            EditToolButton {
                id: textTool
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
                enabled: panel.targetClip >= 0
                tip: "Stretch clip until track end"
                onClicked: panel.viewport.fillTrack(panel.targetClip)
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


        }

        Row {
            id: controls
            height: toolbar.height
            spacing: Theme.gap

            EditToolButton {
                id: keyTool
                kind: "keyframe"
                tip: "Add keyframe to first effect parameter (K)"
                enabled: panel.viewport.params && panel.viewport.params.length > 0
                onClicked: {
                    if (panel.viewport.params && panel.viewport.params.length > 0)
                        panel.viewport.addKey(0)
                }
            }

            FlatButton {
                anchors.verticalCenter: parent.verticalCenter
                plain: true
                small: true
                label: panel.laneH > 40 ? "Compact" : "Expand"
                onClicked: panel.laneH = (panel.laneH > 40 ? 34 : 52)
                ToolTipArea { text: "Toggle vertical lane height" }
            }

            FlatButton {
                anchors.verticalCenter: parent.verticalCenter
                plain: true
                small: true
                objectName: "rangeButton"
                label: "Range"
                onClicked: {
                    rangeStart.text = panel.formatTime(panel.viewport.markIn)
                    rangeEnd.text = panel.formatTime(panel.hasRange ? panel.viewport.markOut : panel.viewport.trackDuration)
                    sequenceSettings.error = ""
                    sequenceSettings.open()
                }
                ToolTipArea { text: "Set export Start / End, Song end, or Entire timeline" }
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
                anchors.verticalCenter: parent.verticalCenter
                plain: true
                small: true
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
                anchors.verticalCenter: parent.verticalCenter
                plain: true
                small: true
                label: "+"; implicitWidth: 28
                onClicked: panel.zoomBy(1.25, laneArea.width / 2)
                ToolTipArea { text: "Zoom in" }
            }
        }
        Row {
            height: toolbar.height
            spacing: 2
            EditToolButton {
                kind: "mark_in"
                tip: "Mark In at playhead (I)"
                onClicked: panel.viewport.setMarkIn(panel.viewport.playhead)
            }
            EditToolButton {
                kind: "mark_out"
                tip: "Mark Out at playhead (O)"
                onClicked: panel.viewport.setMarkOut(panel.viewport.playhead)
            }
            EditToolButton {
                kind: "go_in"
                tip: "Go to In"
                onClicked: panel.viewport.seek(panel.viewport.markIn)
            }
            EditToolButton {
                kind: "go_out"
                enabled: panel.hasRange
                tip: "Go to Out"
                onClicked: panel.viewport.seek(panel.viewport.markOut)
            }
            EditToolButton {
                kind: "clear_marks"
                enabled: panel.viewport.markIn > 0 || panel.viewport.markOut > 0
                tip: "Clear In and Out"
                onClicked: panel.viewport.clearMarks()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: panel.hasRange ? "IN " + panel.formatTime(panel.viewport.markIn)
                    + "   OUT " + panel.formatTime(panel.viewport.markOut)
                    + "   DURATION " + panel.formatTime(panel.viewport.markOut - panel.viewport.markIn)
                    : "IN " + panel.formatTime(panel.viewport.markIn) + "   OUT not set"
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: Theme.sizeSmall
            }
        }
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
            clip: true
            anchors.left: parent.left
            anchors.leftMargin: panel.headW
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height

            Rectangle {
                visible: panel.hasRange
                x: panel.rangeLeft
                width: Math.max(0, panel.rangeRight - panel.rangeLeft)
                height: parent.height
                color: Qt.rgba(1, 1, 1, 0.14)
            }

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
                // Same modifiers and scroll direction as the track area.
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (ev) => panel.navigateWheel(ev, ev.x)
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

            Rectangle {
                x: panel.xOf(panel.viewport.playhead) - width / 2
                anchors.bottom: parent.bottom
                width: 9
                height: 10
                color: "#FFFFFF"
                visible: x + width >= 0 && x <= parent.width
                z: 250
            }

            Repeater {
                model: 2
                delegate: Item {
                    required property int index
                    objectName: index === 0 ? "rangeIn" : "rangeOut"
                    readonly property bool isIn: index === 0
                    x: panel.xOf(isIn ? panel.viewport.markIn : panel.viewport.markOut) - width / 2
                    width: 12
                    height: rulerArea.height
                    visible: isIn || panel.hasRange
                    z: 260
                    Rectangle {
                        x: parent.width / 2
                        width: 1; height: parent.height
                        color: Theme.text
                    }
                    Rectangle {
                        x: parent.isIn ? parent.width / 2 : 0
                        width: parent.width / 2; height: 3
                        color: Theme.text
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.SizeHorCursor
                        preventStealing: true
                        onPositionChanged: (mouse) => {
                            if (!pressed) return
                            const t = Math.max(0, Math.min(panel.editExtent,
                                panel.timeAt(mapToItem(rulerArea, mouse.x, mouse.y).x)))
                            if (parent.isIn)
                                panel.viewport.setMarkIn(panel.hasRange ? Math.min(t, panel.viewport.markOut - 0.01) : t)
                            else
                                panel.viewport.setMarkOut(Math.max(panel.viewport.markIn + 0.01, t))
                        }
                    }
                }
            }
        }
    }

    // ── Track Viewport: vertically scrollable container for all video and audio lanes ──
    Item {
        id: tracksViewport
        objectName: "tracksViewport"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: ruler.bottom
        anchors.topMargin: 2
        height: Math.max(0, Math.min(panel.totalTracksH, panel.height - y - 16))
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
                color: Theme.text
                z: 300


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
                    objectName: "videoHeader" + index
                    anchors.left: parent.left
                    width: panel.headW - 4
                    height: parent.height
                    radius: 0
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
                    radius: 0
                    color: Theme.bg
                    border.width: 1
                    border.color: Theme.hairline
                }
            }
        }
    }

    // Clips are positioned over the lane stack rather than inside a lane, so a
    // vertical drag can cross lanes without leaving its parent item.
    Item {
        id: laneArea
        objectName: "videoLaneArea"
        clip: true
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
                objectName: "videoClip" + index
                required property int index
                required property var modelData

                readonly property real spanSec: modelData.span > 0 ? modelData.span : 5.0

                // The two trim gestures move the edges live. Without this the
                // clip sat still until the mouse came up, which reads as the
                // handle not having taken the grab at all.
                property real trimL: 0
                property real trimR: 0

                x: Math.round(panel.xOf(modelData.start) + dragDx + trimL)
                // Preview follows the pointer; only the committed lane is quantized.
                y: laneArea.laneY(modelData.lane) + dragDy
                z: body.active ? 400 : 0
                width: Math.max(26, Math.round(spanSec * panel.pxPerSec - trimL + trimR))
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

                // Clip body uses one sharp outline and a separate name band.
                Rectangle {
                    anchors.fill: parent
                    radius: 0
                    clip: true
                    color: clip.isSelected ? Qt.lighter(Theme.raised, 1.25) : Theme.raised
                    border.width: body.active ? 2 : 1
                    border.color: body.active || clip.isSelected ? Theme.accent : Theme.border
                    opacity: body.active ? 0.85 : 1.0

                    // A quiet name band separates clip labels from their content.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 1
                        height: 18
                        color: Qt.lighter(Theme.raised, 1.35)
                    }

                    Text {
                        objectName: "videoClipLabel" + clip.index
                        anchors.left: parent.left
                        anchors.leftMargin: Math.max(8, 8 - clip.x)
                        y: 2
                        height: 16
                        width: Math.max(0, parent.width - anchors.leftMargin - 8)
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                        visible: clip.width >= 32
                        text: body.active && clip.laneShift !== 0
                              ? "V" + (clip.modelData.lane + clip.laneShift + 1)
                              : clip.modelData.name
                        color: Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: Math.max(11, Theme.sizeSmall)
                        font.weight: Font.Medium
                        renderType: Text.NativeRendering
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

                MouseArea {
                    id: body
                    anchors.fill: parent
                    Connections {
                        target: panel
                        function onEditRevisionChanged() { if (body.armed) body.resetGesture() }
                    }
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    readonly property bool active: armed && moved
                    property bool armed: false
                    property bool moved: false
                    property int originalIndex: -1
                    property int pressRevision: 0
                    property real originalStart: 0
                    property real originalDuration: 0
                    property real originalScale: 1
                    property int originalLane: 0
                    property point pressScene
                    function resetGesture() {
                        armed = false
                        moved = false
                        clip.dragDx = 0; clip.dragDy = 0
                        panel.dropLane = -1
                        panel.viewport.clipDragging = false
                    }
                    onPressed: (mouse) => {
                        pressRevision = panel.editRevision
                        originalIndex = clip.index
                        originalStart = clip.modelData.start
                        originalDuration = clip.spanSec
                        originalScale = panel.pxPerSec
                        originalLane = clip.modelData.lane
                        pressScene = mapToItem(null, mouse.x, mouse.y)
                        moved = false
                        armed = panel.activeTool === "select"
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed || !armed) return
                        const scene = mapToItem(null, mouse.x, mouse.y)
                        const dx = scene.x - pressScene.x
                        const dy = scene.y - pressScene.y
                        if (!moved && Math.abs(dx) + Math.abs(dy) < 8) return
                        moved = true
                        clip.dragDx = panel.snapPx(originalStart,
                            Math.max(-originalStart * originalScale, dx),
                            originalIndex, originalDuration, false)
                        clip.dragDy = dy
                        panel.viewport.clipDragging = true
                        panel.dropLane = clip.dropLaneIdx
                    }
                    onReleased: (mouse) => {
                        if (pressRevision !== panel.editRevision || (!armed && panel.activeTool !== "razor")) return
                        const commit = armed && moved
                        const idx = originalIndex
                        const start = originalStart + clip.dragDx / originalScale
                        const lane = clip.dropLaneIdx
                        const cutTime = panel.timeAt(mapToItem(laneArea, mouse.x, mouse.y).x)
                        const changed = Math.abs(start - originalStart) > 0.000001 || lane !== originalLane
                        // A model reset can destroy this delegate synchronously.
                        resetGesture()
                        if (commit && changed) panel.viewport.moveClip(idx, start, lane)
                        else if (!commit) {
                            if (panel.activeTool === "razor") panel.viewport.splitClip(idx, cutTime)
                            else { panel.selectedAudioClip = -1; panel.viewport.selectClip(clip.index) }
                        }
                    }
                    onCanceled: resetGesture()
                    Component.onDestruction: if (armed) resetGesture()
                }
                // Right-click asks first. It used to delete instantly, which
                // is a lot of lost work one stray click away.
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: (point) => panel.openClipMenu(clip.index, false, clip, point.position)
                }

                ClipTrimHandle {
                    revision: panel.editRevision
                    anchors.left: parent.left
                    height: parent.height
                    enabled: panel.activeTool === "select"
                    property int originalIndex: -1
                    property real originalIn: 0
                    property real originalOut: 0
                    property real originalScale: 1
                    property real originalWidth: 0
                    onStarted: {
                        originalIndex = clip.index
                        originalIn = clip.modelData.in
                        originalOut = clip.modelData.out > originalIn
                            ? clip.modelData.out : originalIn + clip.spanSec
                        originalScale = panel.pxPerSec
                        originalWidth = clip.width
                    }
                    onMoved: (dx) => clip.trimL = Math.min(dx, originalWidth - 26)
                    onDragged: (dx) => {
                        const idx = originalIndex
                        const value = Math.min(dx, originalWidth - 26) / originalScale
                        const inTime = originalIn + value
                        const outTime = originalOut
                        clip.trimL = 0
                        if (Math.abs(value) > 0.000001)
                            panel.viewport.setClipTrim(idx, inTime, outTime)
                    }
                }
                ClipTrimHandle {
                    revision: panel.editRevision
                    anchors.right: parent.right
                    height: parent.height
                    enabled: panel.activeTool === "select"
                    property int originalIndex: -1
                    property real originalIn: 0
                    property real originalOut: 0
                    property real originalScale: 1
                    property real originalWidth: 0
                    onStarted: {
                        originalIndex = clip.index
                        originalIn = clip.modelData.in
                        originalOut = clip.modelData.out > originalIn
                            ? clip.modelData.out : originalIn + clip.spanSec
                        originalScale = panel.pxPerSec
                        originalWidth = clip.width
                    }
                    onMoved: (dx) => clip.trimR = Math.max(dx, 26 - originalWidth)
                    onDragged: (dx) => {
                        const idx = originalIndex
                        const value = Math.max(dx, 26 - originalWidth) / originalScale
                        const inTime = originalIn
                        const outTime = originalOut + value
                        clip.trimR = 0
                        if (Math.abs(value) > 0.000001)
                            panel.viewport.setClipTrim(idx, inTime, outTime)
                    }
                }
            }
        }

        // Playhead across every lane. Scrub from the ruler above.
        Rectangle {
            width: 2
            height: parent.height
            color: "#FFFFFF"
            visible: x >= 0 && x <= parent.width
            z: 250
            x: panel.xOf(panel.viewport.playhead)
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
                height: panel.audioLaneH

                readonly property bool isA1: index === 0

                // Audio Track Header Box: solid, dark, clean green channel tag
                Rectangle {
                    objectName: "audioHeader" + index
                    anchors.left: parent.left
                    width: panel.headW - 4
                    height: parent.height
                    radius: 0
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
                    radius: 0
                    color: Theme.bg
                    border.width: 1
                    border.color: Theme.hairline
                }
            }
        }
    }

    Item {
        id: audioLaneArea
        objectName: "audioLaneArea"
        clip: true
        anchors.left: parent.left
        anchors.leftMargin: Theme.padding + panel.headW
        anchors.right: parent.right
        anchors.rightMargin: Theme.padding
        anchors.top: audioLaneStack.top
        height: panel.audioLanes * (panel.audioLaneH + panel.laneGap)

        function laneY(lane) {
            return lane * (panel.audioLaneH + panel.laneGap)
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
                objectName: "audioClip" + index
                required property int index
                required property var modelData

                readonly property real spanSec: modelData.span > 0 ? modelData.span : 5.0
                property real trimL: 0
                property real trimR: 0

                x: Math.round(panel.xOf(modelData.start) + dragDx + trimL)
                y: audioLaneArea.laneY(modelData.lane) + dragDy
                z: audioBody.active ? 400 : 0
                width: Math.max(26, Math.round(spanSec * panel.pxPerSec - trimL + trimR))
                height: panel.audioLaneH

                property real dragDx: 0
                property real dragDy: 0
                property int laneShift: Math.round(dragDy / (panel.audioLaneH + panel.laneGap))
                readonly property int dropLaneIdx: Math.max(0, Math.min(
                    panel.audioLanes - 1, modelData.lane + laneShift))

                Rectangle {
                    anchors.fill: parent
                    radius: 0
                    clip: true
                    color: "#142618"
                    border.width: audioBody.active ? 2 : 1
                    border.color: audioBody.active ? Theme.ok : "#24522E"
                    opacity: audioBody.active ? 0.85 : 1.0

                    // Keep the name above the waveform instead of painting over it.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 1
                        height: 18
                        color: "#183320"
                    }

                    Rectangle {
                        width: 3
                        height: parent.height
                        radius: 0
                        color: Theme.ok
                    }

                    // Vector geometry stays sharp at native DPI and only covers visible pixels.
                    Shape {
                        id: waveformShape
                        objectName: "audioWaveform" + audioClip.index
                        x: Math.max(4, -audioClip.x)
                        y: 20
                        width: Math.max(0, Math.min(audioClip.width - 4,
                            audioLaneArea.width - audioClip.x) - x)
                        height: Math.max(0, parent.height - 23)
                        preferredRendererType: Shape.CurveRenderer
                        readonly property var peaks: audioClip.modelData.waveform || []
                        readonly property real sourceDuration: audioClip.modelData.sourceDuration || 0
                        readonly property real displayGain: audioClip.modelData.gain === undefined
                            ? 1 : Math.max(0, audioClip.modelData.gain)
                        readonly property var outline: {
                            if (!peaks.length || sourceDuration <= 0 || width <= 0 || height <= 0) return []
                            const top = [], bottom = []
                            const mid = Math.floor(height / 2)
                            const sourceIn = (audioClip.modelData.in || 0) + audioClip.trimL / panel.pxPerSec
                            for (let px = 0; px < Math.ceil(width); px += 2) {
                                const time = sourceIn + (x + px) / panel.pxPerSec
                                const peak = panel.peakBetween(peaks, sourceDuration, time, time + 2 / panel.pxPerSec)
                                const amp = Math.round(Math.min(1, peak * displayGain) * Math.max(0, mid - 1))
                                const end = Math.min(width, px + 1)
                                const gap = Math.min(width, px + 2)
                                top.push(Qt.point(px, mid - amp), Qt.point(end, mid - amp), Qt.point(end, mid), Qt.point(gap, mid))
                                bottom.push(Qt.point(px, mid + amp), Qt.point(end, mid + amp), Qt.point(end, mid), Qt.point(gap, mid))
                            }
                            return top.concat(bottom.reverse(), [top[0]])
                        }
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: "#5BE08A"
                            PathPolyline { path: waveformShape.outline }
                        }
                    }

                    Text {
                        objectName: "audioClipLabel" + audioClip.index
                        anchors.left: parent.left
                        anchors.leftMargin: Math.max(8, 8 - audioClip.x)
                        y: 2
                        height: 16
                        width: Math.max(0, parent.width - anchors.leftMargin - 8)
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                        text: audioBody.active && audioClip.laneShift !== 0
                              ? "A" + (audioClip.modelData.lane + audioClip.laneShift + 1)
                              : audioClip.modelData.name
                        color: Theme.text
                        font.family: Theme.fontUI
                        font.pixelSize: Math.max(11, Theme.sizeSmall)
                        font.weight: Font.Medium
                        renderType: Text.NativeRendering
                    }
                }

                HoverHandler {
                    cursorShape: panel.activeTool === "razor" ? Qt.CrossCursor
                                : (audioBody.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                }

                MouseArea {
                    id: audioBody
                    anchors.fill: parent
                    Connections {
                        target: panel
                        function onEditRevisionChanged() { if (audioBody.armed) audioBody.resetGesture() }
                    }
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    readonly property bool active: armed && moved
                    property bool armed: false
                    property bool moved: false
                    property int originalIndex: -1
                    property int pressRevision: 0
                    property real originalStart: 0
                    property real originalDuration: 0
                    property real originalScale: 1
                    property int originalLane: 0
                    property point pressScene
                    function resetGesture() {
                        armed = false
                        moved = false
                        audioClip.dragDx = 0; audioClip.dragDy = 0
                        panel.dropAudioLane = -1
                        panel.viewport.clipDragging = false
                    }
                    onPressed: (mouse) => {
                        pressRevision = panel.editRevision
                        originalIndex = audioClip.index
                        panel.selectedAudioClip = audioClip.index
                        originalStart = audioClip.modelData.start
                        originalDuration = audioClip.spanSec
                        originalScale = panel.pxPerSec
                        originalLane = audioClip.modelData.lane
                        pressScene = mapToItem(null, mouse.x, mouse.y)
                        moved = false
                        armed = panel.activeTool === "select"
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed || !armed) return
                        const scene = mapToItem(null, mouse.x, mouse.y)
                        const dx = scene.x - pressScene.x
                        const dy = scene.y - pressScene.y
                        if (!moved && Math.abs(dx) + Math.abs(dy) < 8) return
                        moved = true
                        audioClip.dragDx = panel.snapPx(originalStart,
                            Math.max(-originalStart * originalScale, dx),
                            originalIndex, originalDuration, true)
                        audioClip.dragDy = dy
                        panel.viewport.clipDragging = true
                        panel.dropAudioLane = audioClip.dropLaneIdx
                    }
                    onReleased: (mouse) => {
                        if (pressRevision !== panel.editRevision || (!armed && panel.activeTool !== "razor")) return
                        const commit = armed && moved
                        const idx = originalIndex
                        const start = originalStart + audioClip.dragDx / originalScale
                        const lane = audioClip.dropLaneIdx
                        const cutTime = panel.timeAt(mapToItem(audioLaneArea, mouse.x, mouse.y).x)
                        const changed = Math.abs(start - originalStart) > 0.000001 || lane !== originalLane
                        // A model reset can destroy this delegate synchronously.
                        resetGesture()
                        if (commit && changed) panel.viewport.moveAudioClip(idx, start, lane)
                        else if (!commit) {
                            if (panel.activeTool === "razor") panel.viewport.splitAudioClip(idx, cutTime)
                        }
                    }
                    onCanceled: resetGesture()
                    Component.onDestruction: if (armed) resetGesture()
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: (point) => panel.openClipMenu(audioClip.index, true, audioClip, point.position)
                }

                ClipTrimHandle {
                    revision: panel.editRevision
                    anchors.left: parent.left
                    height: parent.height
                    enabled: panel.activeTool === "select"
                    property int originalIndex: -1
                    property real originalIn: 0
                    property real originalOut: 0
                    property real originalScale: 1
                    property real originalWidth: 0
                    onStarted: {
                        originalIndex = audioClip.index
                        originalIn = audioClip.modelData.in
                        originalOut = audioClip.modelData.out > originalIn
                            ? audioClip.modelData.out : originalIn + audioClip.spanSec
                        originalScale = panel.pxPerSec
                        originalWidth = audioClip.width
                    }
                    onMoved: (dx) => audioClip.trimL = Math.min(dx, originalWidth - 26)
                    onDragged: (dx) => {
                        const idx = originalIndex
                        const value = Math.min(dx, originalWidth - 26) / originalScale
                        const inTime = originalIn + value
                        const outTime = originalOut
                        audioClip.trimL = 0
                        if (Math.abs(value) > 0.000001)
                            panel.viewport.setAudioClipTrim(idx, inTime, outTime)
                    }
                }
                ClipTrimHandle {
                    revision: panel.editRevision
                    anchors.right: parent.right
                    height: parent.height
                    enabled: panel.activeTool === "select"
                    property int originalIndex: -1
                    property real originalIn: 0
                    property real originalOut: 0
                    property real originalScale: 1
                    property real originalWidth: 0
                    onStarted: {
                        originalIndex = audioClip.index
                        originalIn = audioClip.modelData.in
                        originalOut = audioClip.modelData.out > originalIn
                            ? audioClip.modelData.out : originalIn + audioClip.spanSec
                        originalScale = panel.pxPerSec
                        originalWidth = audioClip.width
                    }
                    onMoved: (dx) => audioClip.trimR = Math.max(dx, 26 - originalWidth)
                    onDragged: (dx) => {
                        const idx = originalIndex
                        const value = Math.max(dx, 26 - originalWidth) / originalScale
                        const inTime = originalIn
                        const outTime = originalOut + value
                        audioClip.trimR = 0
                        if (Math.abs(value) > 0.000001)
                            panel.viewport.setAudioClipTrim(idx, inTime, outTime)
                    }
                }
            }
        }

        // Playhead stem across audio lanes
        Rectangle {
            width: 2
            height: parent.height
            color: "#FFFFFF"
            visible: x >= 0 && x <= parent.width
            z: 250
            x: panel.xOf(panel.viewport.playhead)
        }
    }
    } // tracksContent

    Item {
        anchors.left: parent.left
        anchors.leftMargin: Theme.padding + panel.headW
        anchors.right: parent.right
        anchors.rightMargin: Theme.padding
        height: parent.height
        clip: true
        z: 200
        Rectangle {
            visible: panel.hasRange
            x: panel.rangeLeft
            width: Math.max(0, panel.rangeRight - panel.rangeLeft)
            height: parent.height
            color: Qt.rgba(1, 1, 1, 0.07)
        }
        Repeater {
            model: 2
            delegate: Rectangle {
                required property int index
                x: panel.xOf(index === 0 ? panel.viewport.markIn : panel.viewport.markOut)
                visible: index === 0 || panel.hasRange
                width: 1; height: parent.height
                color: Theme.textMuted
            }
        }
    }

    // Vertical scroll indicator when tracks overflow
    Rectangle {
        id: vScrollTrack
        objectName: "verticalScrollbar"
        visible: panel.maxTrackScrollY > 0
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 8
        radius: 0
        color: Qt.rgba(1, 1, 1, 0.08)

        MouseArea {
            anchors.fill: parent
            preventStealing: true
            property real pressY: 0
            property real pressScroll: 0
            onPressed: (mouse) => {
                pressY = mapToItem(null, mouse.x, mouse.y).y
                pressScroll = panel.trackScrollY
            }
            onPositionChanged: (mouse) => {
                if (!pressed) return
                const dy = mapToItem(null, mouse.x, mouse.y).y - pressY
                panel.trackScrollY = Math.max(0, Math.min(panel.maxTrackScrollY,
                    pressScroll + dy / Math.max(1, height - verticalThumb.height) * panel.maxTrackScrollY))
            }
        }
        Rectangle {
            id: verticalThumb
            width: parent.width
            radius: 0
            color: Qt.rgba(1, 1, 1, 0.35)
            y: (panel.trackScrollY / Math.max(1, panel.maxTrackScrollY)) * (parent.height - height)
            height: Math.max(16, parent.height * (tracksViewport.height / Math.max(1, tracksContent.height)))
        }
    }
    } // tracksViewport

    // ── Bottom Navigator Scrollbar (matches Figma 7_146.png & Premiere Pro style navigation) ──
    Rectangle {
        id: navScrollbar
        objectName: "navScrollbar"
        anchors.left: parent.left
        anchors.leftMargin: Theme.padding + panel.headW
        anchors.right: parent.right
        anchors.rightMargin: Theme.padding
        anchors.top: tracksViewport.bottom
        anchors.topMargin: 3
        height: 10
        radius: 0
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
            objectName: "navThumb"
            x: (parent.width - width) * panel.viewStart / Math.max(0.0001, panel.fullSpan - panel.span)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width, Math.max(48, parent.width * navScrollbar.viewFrac))
            height: 8
            radius: 0
            color: thumbDrag.pressed ? "#FFFFFF" : (thumbHover.hovered ? "#EEEEEE" : "#888888")

            HoverHandler { id: thumbHover; cursorShape: Qt.PointingHandCursor }

            // Smooth horizontal panning drag
            MouseArea {
                id: thumbDrag
                anchors.fill: parent
                property real pressX: 0
                property real pressView: 0
                onPressed: (mouse) => {
                    pressX = mapToItem(null, mouse.x, mouse.y).x
                    pressView = panel.viewStart
                }
                cursorShape: Qt.PointingHandCursor

                onPositionChanged: (mouse) => {
                    if (pressed && (navScrollbar.width - navThumb.width) > 0) {
                        panel.viewStart = pressView + (mapToItem(null, mouse.x, mouse.y).x - pressX)
                            / (navScrollbar.width - navThumb.width) * (panel.fullSpan - panel.span)
                        panel.clampView()
                    }
                }
            }

            // Left zoom handle (Premiere Pro style resize edge)
            Item {
                objectName: "navLeftHandle"
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
                        pressX = mapToItem(null, mouse.x, mouse.y).x
                        pressSpan = panel.span
                        pressView = panel.viewStart
                    }
                    onPositionChanged: (mouse) => {
                        if (pressed) {
                            const deltaSec = (mapToItem(null, mouse.x, mouse.y).x - pressX) / navScrollbar.width * panel.fullSpan
                            const newSpan = Math.max(1, Math.min(panel.fullSpan, pressSpan - deltaSec))
                            panel.zoom = Math.max(1, Math.min(60, panel.fullSpan / newSpan))
                            panel.viewStart = pressView + pressSpan - panel.span
                            panel.clampView()
                        }
                    }
                }
            }

            // Right zoom handle (Premiere Pro style resize edge)
            Item {
                objectName: "navRightHandle"
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
                        pressX = mapToItem(null, mouse.x, mouse.y).x
                        pressSpan = panel.span
                    }
                    onPositionChanged: (mouse) => {
                        if (pressed) {
                            const deltaSec = (mapToItem(null, mouse.x, mouse.y).x - pressX) / navScrollbar.width * panel.fullSpan
                            const newSpan = Math.max(1, Math.min(panel.fullSpan, pressSpan + deltaSec))
                            panel.zoom = Math.max(1, Math.min(60, panel.fullSpan / newSpan))
                            panel.clampView()
                        }
                    }
                }
            }
        }
    }

    AppDialog {
        id: sequenceSettings
        objectName: "sequenceRangeDialog"
        title: "Sequence range"
        width: 360
        property string error: ""
        function applyRange() {
            const start = panel.parseTime(rangeStart.text)
            const end = panel.parseTime(rangeEnd.text)
            if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end <= start || end > 86400) {
                error = "Enter a valid Start before End (maximum 24 hours)."
                return
            }
            if (!panel.viewport.setSequenceRange(start, end)) {
                error = "Range could not be applied."
                return
            }
            close()
        }
        contentItem: Column {
            spacing: 8
            Text {
                text: "Start / End (mm:ss or seconds)"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
            }
            TextField {
                id: rangeStart
                objectName: "rangeStartField"
                width: parent.width
                placeholderText: "Start"
                color: Theme.text
                font.family: Theme.fontUI
                onAccepted: sequenceSettings.applyRange()
                background: Rectangle { color: Theme.raised; border.width: 1; border.color: Theme.border }
            }
            TextField {
                id: rangeEnd
                objectName: "rangeEndField"
                width: parent.width
                placeholderText: "End"
                color: Theme.text
                font.family: Theme.fontUI
                onAccepted: sequenceSettings.applyRange()
                background: Rectangle { color: Theme.raised; border.width: 1; border.color: Theme.border }
            }
            Text {
                width: parent.width
                text: sequenceSettings.error
                visible: text.length > 0
                wrapMode: Text.WordWrap
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 12
            }
            Row {
                spacing: 8
                FlatButton {
                    objectName: "songEndButton"
                    label: "Song end"
                    enabled: panel.songEnd > 0 && panel.songEnd <= 86400
                    onClicked: { rangeStart.text = "0"; rangeEnd.text = panel.formatTime(panel.songEnd) }
                }
                FlatButton {
                    objectName: "entireTimelineButton"
                    label: "Entire timeline"
                    onClicked: if (panel.viewport.setSequenceRange(0, 0)) sequenceSettings.close()
                }
            }
            Row {
                spacing: 8
                FlatButton { label: "Cancel"; onClicked: sequenceSettings.close() }
                FlatButton { objectName: "applyRangeButton"; label: "Apply"; onClicked: sequenceSettings.applyRange() }
            }
        }
    }

    // Deleting a clip is easy to do by accident with a right-click and there is
    // no undo prompt at the moment it happens, so it asks.
    AppDialog {
        id: removeConfirm
        objectName: "removeClipDialog"
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
        enabled: panel.shortcutsEnabled
        onActivated: panel.activeTool = (panel.activeTool === "razor" ? "select" : "razor")
    }
    Shortcut {
        sequence: "Escape"
        enabled: panel.shortcutsEnabled
        onActivated: panel.activeTool = "select"
    }
    Shortcut { sequence: "V"; enabled: panel.shortcutsEnabled; onActivated: panel.activeTool = "select" }
    Shortcut { sequence: "I"; enabled: panel.shortcutsEnabled; onActivated: panel.viewport.setMarkIn(panel.viewport.playhead) }
    Shortcut { sequence: "O"; enabled: panel.shortcutsEnabled; onActivated: panel.viewport.setMarkOut(panel.viewport.playhead) }
    Shortcut { sequence: "T"; enabled: panel.shortcutsEnabled; onActivated: textTool.clicked() }
    Shortcut { sequence: "K"; enabled: panel.shortcutsEnabled && keyTool.enabled; onActivated: keyTool.clicked() }
    Shortcut { sequence: "Ctrl+C"; enabled: panel.shortcutsEnabled && panel.selectedAudioClip < 0 && panel.targetClip >= 0; onActivated: panel.viewport.copyClip(panel.targetClip) }
    Shortcut { sequence: "Ctrl+V"; enabled: panel.shortcutsEnabled && panel.viewport.hasClipboard; onActivated: panel.viewport.pasteClip(panel.viewport.playhead, -1) }
    Shortcut { sequence: "Delete"; enabled: panel.shortcutsEnabled && (panel.selectedAudioClip >= 0 || panel.targetClip >= 0); onActivated: panel.requestRemove(panel.selectedAudioClip >= 0 ? panel.selectedAudioClip : panel.targetClip, panel.selectedAudioClip >= 0) }
}
