import QtQuick
import QtTest
import "../qml"

Item {
    width: 1000
    height: 680

    QtObject {
        id: viewport
        property int laneCount: 1
        property int audioLaneCount: 1
        property real trackDuration: 100
        property real playhead: 80
        property real markIn: 0
        property real markOut: 0
        property real sequenceDuration: 0
        property bool snapToMarkers: true
        property bool clipDragging: false
        property int activeClipIndex: -1
        property int selectedClip: -1
        property bool hasClipboard: false
        property var params: []
        property var keyframes: []
        property var waveform: [0.1, 0.6, 0.2, 0.8]
        property var markers: []
        property var clips: []
        property var audioClips: []
        property bool playing: false
        property bool exporting: false
        property string exportStatus: ""
        property int projectAspect: 0
        property real fps: 60
        property real frameMax: 16
        property real frameP95: 16
        property var edits: []
        property int copiedClip: -1
        property int textInsertions: 0
        property var splits: []
        property var rangeCalls: []
        function copyClip(index) { copiedClip = index; hasClipboard = true }
        function pasteClip(at, lane) { edits = edits.concat([{kind: "paste", start: at, lane: lane}]) }
        function removeClip(index) { edits = edits.concat([{kind: "remove", index: index}]) }
        function removeAudioClip(index) { edits = edits.concat([{kind: "removeAudio", index: index}]) }
        function splitClip(index, at) { splits = splits.concat([{audio: false, index: index, at: at}]) }
        function splitAudioClip(index, at) { splits = splits.concat([{audio: true, index: index, at: at}]) }
        function addTextClip(text, lane, span) { textInsertions += 1 }
        function setSequenceRange(start, end) {
            if (!Number.isFinite(start) || !Number.isFinite(end)
                || !((start === 0 && end === 0) || (start >= 0 && end > start && end <= 86400))) return false
            rangeCalls = rangeCalls.concat([{start: start, end: end}])
            sequenceDuration = end; markIn = start; markOut = end
            return true
        }
        function recordEdit(kind, index, start, lane) {
            edits = edits.concat([{kind: kind, index: index, start: start, lane: lane}])
            const source = kind === "video" ? clips : audioClips
            const next = JSON.parse(JSON.stringify(source))
            next[index].start = start
            next[index].lane = lane
            // Match snapshot restore/model rebuild, not an in-place mock mutation.
            if (kind === "video") clips = next
            else audioClips = next
        }
        function moveClip(index, start, lane) { recordEdit("video", index, start, lane) }
        function moveAudioClip(index, start, lane) { recordEdit("audio", index, start, lane) }
        function setClipTrim(index, inTime, outTime) { edits = edits.concat([{kind: "trim"}]) }
        function setAudioClipTrim(index, inTime, outTime) { edits = edits.concat([{kind: "audioTrim"}]) }
        function seek(t) { playhead = t }
        function setMarkIn(t) { markIn = t }
        function setMarkOut(t) { markOut = t }
        function clearMarks() { markIn = 0; markOut = 0 }
        function selectClip(index) { selectedClip = index }
        function pause() { playing = false }
        function play() { playing = true }
    }

    TimelinePanel {
        id: timeline
        viewport: viewport
        width: 1000
        height: 480
    }
    TransportBar {
        id: transport
        viewport: viewport
        y: 500
        width: 1000
        height: implicitHeight
    }

    TextInput { id: editor; y: 650; width: 200; height: 24 }
    TestCase {
        name: "Timeline"
        when: windowShown

        function findTool(item, kind) {
            if (item.kind === kind) return item
            for (let i = 0; i < item.children.length; ++i) {
                const found = findTool(item.children[i], kind)
                if (found) return found
            }
            return null
        }
        function init() {
            editor.focus = false
            editor.text = ""
            timeline.shortcutsSuspended = false
            viewport.copiedClip = -1
            viewport.textInsertions = 0
            viewport.splits = []
            viewport.rangeCalls = []
            viewport.hasClipboard = false
            viewport.activeClipIndex = -1
            timeline.width = 1000
            timeline.height = 480
            findChild(timeline, "timelineToolStrip").contentX = 0
            transport.width = 1000
            viewport.trackDuration = 100
            viewport.playhead = 80
            viewport.clearMarks()
            viewport.markers = []
            viewport.clips = []
            viewport.audioClips = []
            viewport.snapToMarkers = true
            viewport.exporting = false
            viewport.exportStatus = ""
            timeline.zoom = 1
            timeline.viewStart = 0
            timeline.activeTool = "select"
            timeline.visible = true
            timeline.trackScrollY = 0
            viewport.laneCount = 1
            viewport.audioLaneCount = 1
            viewport.edits = []
            viewport.selectedClip = -1
            wait(20)
        }
        function cleanup() {
            for (const name of ["clipContextMenu", "removeClipDialog", "sequenceRangeDialog"]) {
                const popup = findChild(timeline, name)
                if (popup) { popup.close(); tryCompare(popup, "visible", false) }
            }
        }
        function media(start, span, lane) {
            return {start: start, span: span, lane: lane || 0, name: "test", in: 0, out: span}
        }
        function test_compactUsefulTracks_data() {
            return [{tag: "150 percent", width: 1100, height: 222},
                {tag: "200 percent", width: 780, height: 222}]
        }
        function test_compactUsefulTracks(data) {
            timeline.width = data.width; timeline.height = data.height
            viewport.clips = [media(0, 100)]
            viewport.audioClips = [media(0, 100)]
            wait(30)
            compare(timeline.lanes, 1, "no empty video lane crowds out audio")
            const tracks = findChild(timeline, "tracksViewport")
            for (const name of ["videoClip0", "audioClip0"]) {
                const clip = findChild(timeline, name)
                const point = clip.mapToItem(tracks, 0, 0)
                verify(point.y >= 0 && point.y + clip.height <= tracks.height,
                    name + " remains fully visible")
            }
            compare(timeline.maxTrackScrollY, 0)
            timeline.height = 480
            wait(20)
            compare(timeline.lanes, 2, "spare drop lane returns when space permits")
        }
        function test_typingDoesNotActivateTools() {
            editor.forceActiveFocus()
            keyClick(Qt.Key_I)
            keyClick(Qt.Key_C)
            compare(editor.text, "ic")
            compare(viewport.markIn, 0)
            compare(timeline.activeTool, "select")
        }
        function test_razorCutsAtPointer_data() { return test_moveAtomicReset_data() }
        function test_razorCutsAtPointer(data) {
            viewport.clips = [media(10, 20)]
            viewport.audioClips = [media(10, 20)]
            wait(20)
            editor.focus = false
            const razor = findTool(timeline, "razor")
            mouseClick(razor, 14, 14)
            compare(timeline.activeTool, "razor")
            const clip = findChild(timeline, data.audio ? "audioClip0" : "videoClip0")
            const x = 55
            const expected = timeline.timeAt(clip.x + x)
            mouseClick(clip, x, 20)
            compare(viewport.splits.length, 1)
            compare(viewport.splits[0].audio, data.audio)
            compare(viewport.splits[0].index, 0)
            fuzzyCompare(viewport.splits[0].at, expected, 0.001)
            compare(viewport.textInsertions, 0)
            compare(viewport.edits.length, 0)
            verify(!viewport.clipDragging)
        }
        function test_copyUsesSelectionNotPlayhead() {
            viewport.activeClipIndex = 0
            viewport.selectedClip = 2
            keyClick(Qt.Key_C, Qt.ControlModifier)
            compare(viewport.copiedClip, 2)
            verify(findTool(timeline, "copy") === null)
            verify(findTool(timeline, "paste") === null)
            verify(findTool(timeline, "remove") === null)
        }
        function dragScene(item, x, y, dx, dy) {
            const p = item.mapToItem(timeline, x, y)
            mousePress(timeline, p.x, p.y)
            mouseMove(timeline, p.x + dx / 2, p.y + dy / 2, 10)
            mouseMove(timeline, p.x + dx, p.y + dy, 10)
            mouseRelease(timeline, p.x + dx, p.y + dy)
            wait(10)
        }
        function test_visibleExtent() {
            viewport.sequenceDuration = 20
            viewport.trackDuration = 20
            viewport.clips = [media(35, 12)]
            viewport.audioClips = [media(80, 25)]
            compare(timeline.editExtent, 105)
            verify(timeline.fullSpan > 105)
            compare(viewport.trackDuration, 20)
            const video = findChild(timeline, "videoLaneArea")
            const audio = findChild(timeline, "audioLaneArea")
            verify(video.clip && audio.clip)
            verify(timeline.xOf(105) <= audio.width)
        }
        function test_scrollbarsAndHeadersDoNotEdit() {
            viewport.clips = [media(0, 100)]
            viewport.audioClips = [media(0, 100)]
            timeline.zoom = 4
            wait(20)
            const thumb = findChild(timeline, "navThumb")
            dragScene(thumb, thumb.width / 2, 4, 80, 0)
            verify(timeline.viewStart > 0)
            const expected = timeline.viewStart
            const nav = findChild(timeline, "navScrollbar")
            fuzzyCompare(thumb.x, (nav.width - thumb.width) * expected / (timeline.fullSpan - timeline.span), 0.01)
            timeline.viewStart = 0
            fuzzyCompare(thumb.x, 0, 0.01)
            dragScene(findChild(timeline, "videoHeader1"), 20, 16, 90, 40)
            dragScene(findChild(timeline, "audioHeader0"), 20, 16, 90, -30)
            compare(viewport.edits.length, 0)
            compare(viewport.selectedClip, -1)
        }
        function test_clippedEdgesRejectInput_data() { return test_moveAtomicReset_data() }
        function test_clippedEdgesRejectInput(data) {
            viewport.clips = [media(0, 100)]
            viewport.audioClips = [media(0, 100)]
            timeline.zoom = 4
            timeline.viewStart = 20
            wait(20)
            const lane = findChild(timeline, data.audio ? "audioLaneArea" : "videoLaneArea")
            const clip = findChild(timeline, data.audio ? "audioClip0" : "videoClip0")
            const p = clip.mapToItem(timeline, 0, 16)
            const edge = lane.mapToItem(timeline, 0, 0)
            mouseClick(timeline, edge.x - 15, p.y)
            compare(viewport.selectedClip, -1)
            mouseClick(timeline, edge.x + lane.width + 5, p.y)
            compare(viewport.selectedClip, -1)
            mouseClick(timeline, edge.x + 20, p.y)
            compare(viewport.selectedClip, data.audio ? -1 : 0)
            compare(viewport.edits.length, 0)
        }
        function test_clipContextMenu_data() { return test_moveAtomicReset_data() }
        function test_clipContextMenu(data) {
            viewport.clips = [media(10, 20)]
            viewport.audioClips = [media(10, 20)]
            viewport.playhead = 15
            wait(20)
            const clip = findChild(timeline, data.audio ? "audioClip0" : "videoClip0")
            mouseClick(clip, 35, 20, Qt.RightButton)
            const menu = findChild(timeline, "clipContextMenu")
            verify(menu !== null)
            tryCompare(menu, "opened", true)
            compare(viewport.edits.length, 0)
            compare(viewport.splits.length, 0)
            const copy = findChild(timeline, "clipCopyAction")
            compare(copy.enabled, !data.audio)
            const split = findChild(timeline, "clipSplitAction")
            verify(split.enabled)
            mouseClick(split, 80, 14)
            tryCompare(menu, "visible", false)
            compare(viewport.splits.length, 1)
            compare(viewport.splits[0].audio, data.audio)
            compare(viewport.splits[0].at, 15)
            mouseClick(clip, 35, 20, Qt.RightButton)
            tryCompare(menu, "opened", true)
            const remove = findChild(timeline, "clipDeleteAction")
            mouseClick(remove, 70, 14)
            compare(viewport.edits.length, 0)
            const confirm = findChild(timeline, "removeClipDialog")
            verify(confirm.visible)
            confirm.accept()
            compare(viewport.edits.length, 1)
            compare(viewport.edits[0].kind, data.audio ? "removeAudio" : "remove")
        }
        function test_dragPreviewFollowsPointer_data() { return test_moveAtomicReset_data() }
        function test_dragPreviewFollowsPointer(data) {
            viewport.snapToMarkers = false
            viewport.laneCount = 2
            viewport.audioLaneCount = 2
            if (data.audio) viewport.audioClips = [media(10, 20)]
            else viewport.clips = [media(10, 20)]
            wait(20)
            const clip = findChild(timeline, data.audio ? "audioClip0" : "videoClip0")
            const x = clip.x, y = clip.y
            const p = clip.mapToItem(timeline, 30, 20)
            const dy = data.audio ? 17 : -17
            mousePress(timeline, p.x, p.y)
            mouseMove(timeline, p.x + 33, p.y + dy, 10)
            fuzzyCompare(clip.x, x + 33, 1)
            fuzzyCompare(clip.y, y + dy, 0.01)
            compare(clip.z, 400)
            compare(viewport.edits.length, 0)
            mouseRelease(timeline, p.x + 33, p.y + dy)
            compare(viewport.edits.length, 1)
        }
        function test_moveAtomicReset_data() { return [{tag:"video", audio:false}, {tag:"audio", audio:true}] }
        function test_moveAtomicReset(data) {
            viewport.snapToMarkers = false
            viewport.laneCount = 2
            viewport.audioLaneCount = 2
            if (data.audio) viewport.audioClips = [media(10, 20)]
            else viewport.clips = [media(10, 20)]
            wait(20)
            const clip = findChild(timeline, data.audio ? "audioClip0" : "videoClip0")
            dragScene(clip, 30, 16, 60, data.audio ? 39 : -39)
            compare(viewport.edits.length, 1)
            verify(viewport.edits[0].start > 10)
            compare(viewport.edits[0].lane, 1)
            verify(!viewport.clipDragging)
            verify(findChild(timeline, data.audio ? "audioClip0" : "videoClip0") !== null)
        }
        function test_resetCancelsGesture_data() { return test_moveAtomicReset_data() }
        function test_resetCancelsGesture(data) {
            viewport.snapToMarkers = false
            if (data.audio) viewport.audioClips = [media(10, 20)]
            else viewport.clips = [media(10, 20)]
            wait(20)
            const clip = findChild(timeline, data.audio ? "audioClip0" : "videoClip0")
            const p = clip.mapToItem(timeline, 30, 16)
            mousePress(timeline, p.x, p.y)
            mouseMove(timeline, p.x + 40, p.y, 10)
            verify(viewport.clipDragging)
            // Undo restores a snapshot while this delegate owns the grab.
            if (data.audio) viewport.audioClips = [media(5, 20)]
            else viewport.clips = [media(5, 20)]
            wait(20)
            mouseRelease(timeline, p.x + 40, p.y)
            compare(viewport.edits.length, 0)
            compare(viewport.selectedClip, -1)
            verify(!viewport.clipDragging)
            verify(findChild(timeline, data.audio ? "audioClip0" : "videoClip0") !== null)
        }
        function test_navigationHandlesKeepBindings() {
            viewport.clips = [media(0, 100)]
            viewport.audioClips = [media(0, 100)]
            timeline.zoom = 4
            timeline.viewStart = 20
            wait(20)
            const end = timeline.viewStart + timeline.span
            dragScene(findChild(timeline, "navLeftHandle"), 5, 4, 20, 0)
            fuzzyCompare(timeline.viewStart + timeline.span, end, 0.001)
            const before = timeline.span
            dragScene(findChild(timeline, "navRightHandle"), 5, 4, 20, 0)
            verify(timeline.span > before)
            compare(viewport.edits.length, 0)
            timeline.zoomBy(0.00001, 100)
            const thumb = findChild(timeline, "navThumb")
            const nav = findChild(timeline, "navScrollbar")
            fuzzyCompare(thumb.width, nav.width, 0.001)
            fuzzyCompare(thumb.x, 0, 0.001)
        }
        function test_fixedHeaders() {
            viewport.clips = [media(0, 100)]
            viewport.audioClips = [media(0, 100)]
            wait(20)
            const video = findChild(timeline, "videoHeader1")
            const audio = findChild(timeline, "audioHeader0")
            const videoX = video.mapToItem(timeline, 0, 0).x
            const audioX = audio.mapToItem(timeline, 0, 0).x
            timeline.zoomBy(8, 300)
            timeline.viewStart = 20
            compare(video.mapToItem(timeline, 0, 0).x, videoX)
            compare(audio.mapToItem(timeline, 0, 0).x, audioX)
            const videoLane = findChild(timeline, "videoLaneArea")
            verify(videoX + video.width < videoLane.mapToItem(timeline, 0, 0).x)
        }
        function test_noopMoveAndTrimReset() {
            viewport.snapToMarkers = false
            viewport.clips = [media(10, 20)]
            wait(20)
            let clip = findChild(timeline, "videoClip0")
            const p = clip.mapToItem(timeline, 30, 16)
            mousePress(timeline, p.x, p.y)
            mouseMove(timeline, p.x + 35, p.y, 10)
            mouseMove(timeline, p.x, p.y, 10)
            mouseRelease(timeline, p.x, p.y)
            compare(viewport.edits.length, 0)
            const edge = clip.mapToItem(timeline, clip.width - 3, 16)
            mousePress(timeline, edge.x, edge.y)
            mouseMove(timeline, edge.x + 25, edge.y, 10)
            viewport.clips = [media(10, 20)]
            wait(20)
            mouseRelease(timeline, edge.x + 25, edge.y)
            compare(viewport.edits.length, 0)
            clip = findChild(timeline, "videoClip0")
            verify(clip !== null)
            dragScene(clip, clip.width - 3, 16, 25, 0)
            compare(viewport.edits.length, 1)
            compare(viewport.edits[0].kind, "trim")
        }
        function test_verticalScrollbarDoesNotEdit() {
            viewport.laneCount = 12
            viewport.audioLaneCount = 3
            viewport.clips = [media(0, 100)]
            viewport.audioClips = [media(0, 100)]
            wait(20)
            const scrollbar = findChild(timeline, "verticalScrollbar")
            verify(scrollbar.visible)
            dragScene(scrollbar, 4, 15, 0, 70)
            verify(timeline.trackScrollY > 0)
            compare(viewport.edits.length, 0)
        }
        function test_shortcutsOnlyVisible() {
            timeline.activeTool = "razor"
            keyClick(Qt.Key_V)
            compare(timeline.activeTool, "select")
            viewport.playhead = 12
            keyClick(Qt.Key_I)
            viewport.playhead = 25
            keyClick(Qt.Key_O)
            compare(viewport.markIn, 12)
            compare(viewport.markOut, 25)
            timeline.visible = false
            viewport.playhead = 40
            keyClick(Qt.Key_I)
            keyClick(Qt.Key_O)
            keyClick(Qt.Key_V)
            compare(viewport.markIn, 12)
            compare(viewport.markOut, 25)
        }
        function test_rangeHandleDrag() {
            viewport.markIn = 10
            viewport.markOut = 30
            wait(20)
            const handle = findChild(timeline, "rangeIn")
            dragScene(handle, 6, 10, 30, 0)
            verify(viewport.markIn > 10)
            verify(viewport.markIn < viewport.markOut)
        }
        function verifyFlow(flow) {
            for (let i = 0; i < flow.children.length; ++i) {
                const a = flow.children[i]
                if (!a.visible || a.width <= 0 || a.height <= 0) continue
                verify(a.x >= 0 && a.x + a.width <= flow.width + 0.1, "flow child fits horizontally")
                for (let j = i + 1; j < flow.children.length; ++j) {
                    const b = flow.children[j]
                    if (!b.visible || b.width <= 0 || b.height <= 0) continue
                    verify(a.x + a.width <= b.x || b.x + b.width <= a.x
                        || a.y + a.height <= b.y || b.y + b.height <= a.y, "flow children do not collide")
                }
            }
        }
        function test_narrowLayout() {
            timeline.width = 340
            transport.width = 340
            viewport.exporting = true
            viewport.exportStatus = "Exporting a long sequence status message"
            wait(30)
            const select = findTool(timeline, "select")
            const mark = findTool(timeline, "mark_in")
            compare(mark.mapToItem(timeline, 0, 0).y, select.mapToItem(timeline, 0, 0).y)
            const strip = findChild(timeline, "timelineToolStrip")
            verify(strip.clip)
            verify(strip.contentWidth > strip.width)
            strip.contentX = strip.contentWidth - strip.width
            verify(strip.contentX > 0)
            compare(findChild(transport, "monitorScrub"), null)
            verifyFlow(findChild(timeline, "timelineToolsRow"))
            verifyFlow(findChild(transport, "transportFlow"))
        }
        function test_solidIconsShareOneRow() {
            const tools = ["select", "text", "razor", "stretch_end",
                "add_clip", "add_audio", "keyframe", "mark_in", "mark_out",
                "go_in", "go_out", "clear_marks"]
            const first = findTool(timeline, tools[0])
            const y = first.mapToItem(timeline, 0, 0).y
            for (const kind of tools) {
                const tool = findTool(timeline, kind)
                compare(tool.mapToItem(timeline, 0, 0).y, y, kind + " stays in the tool row")
                compare(tool.border.width, tool.activeFocus ? Theme.focusWidth : 0,
                    kind + " is unboxed except for the keyboard focus ring")
                compare(tool.color, "#00000000", kind + " has no button fill")
                verify(tool.iconPath.length > 0, kind + " has a solid symbol")
            }
        }
        function test_waveformUsesSourcePeaksAndNativeLabels() {
            const audio = media(0, 4)
            audio.waveform = [0, 0.8, 0, 0.2]
            audio.sourceDuration = 4
            viewport.audioClips = [audio]
            viewport.clips = [media(0, 4)]
            wait(20)
            const wave = findChild(timeline, "audioWaveform0")
            verify(wave.height >= 32, "Audio peaks have enough vertical resolution")
            compare(findChild(timeline, "audioClip0").height, findChild(timeline, "videoClip0").height + 24)
            compare(wave.peaks, audio.waveform)
            compare(wave.sourceDuration, 4)
            verify(wave.outline.length > 0)
            verify(wave.width <= findChild(timeline, "audioLaneArea").width)
            const label = findChild(timeline, "audioClipLabel0")
            compare(label.renderType, Text.NativeRendering)
            compare(findChild(timeline, "videoClipLabel0").renderType, Text.NativeRendering)
            verify(label.y + label.height <= wave.y)
            compare(timeline.peakBetween(audio.waveform, 4, 0, 2), 0.8)
            compare(timeline.peakBetween(audio.waveform, 4, 2, 3), 0)
            compare(timeline.peakBetween(audio.waveform, 4, 8, 9), 0)
            timeline.zoom = 4
            timeline.viewStart = 1
            wait(20)
            verify(label.mapToItem(findChild(timeline, "audioLaneArea"), 0, 0).x >= 8)
        }
        function test_selectionExitsRazor() {
            const razor = findTool(timeline, "razor")
            const select = findTool(timeline, "select")
            verify(razor !== null)
            mouseClick(razor, razor.width / 2, razor.height / 2)
            compare(timeline.activeTool, "razor")
            verify(razor.active)
            mouseClick(select, select.width / 2, select.height / 2)
            compare(timeline.activeTool, "select")
            verify(select.active)
            verify(!razor.active)
        }
        function test_marksValidUnset() {
            compare(timeline.hasRange, false)
            const goOut = findTool(timeline, "go_out")
            compare(goOut.enabled, false)
            viewport.playhead = 10
            const markIn = findTool(timeline, "mark_in")
            mouseClick(markIn, 14, 13)
            compare(viewport.markIn, 10)
            compare(timeline.hasRange, false)
            viewport.playhead = 30
            mouseClick(findTool(timeline, "mark_out"), 14, 13)
            compare(timeline.hasRange, true)
            compare(goOut.enabled, true)
            mouseClick(goOut, 14, 13)
            compare(viewport.playhead, 30)
            mouseClick(findTool(timeline, "clear_marks"), 14, 13)
            compare(timeline.hasRange, false)
            compare(goOut.enabled, false)
            viewport.markIn = 20
            viewport.markOut = 10
            compare(timeline.hasRange, false)
            viewport.markOut = 20
            compare(timeline.hasRange, false)
        }
        function test_snapEdges_data() {
            return [
                {tag: "video head", audio: false, tail: false},
                {tag: "video tail", audio: false, tail: true},
                {tag: "audio head", audio: true, tail: false},
                {tag: "audio tail", audio: true, tail: true}
            ]
        }
        function test_snapEdges(data) {
            const own = [{start: 10, span: 5, lane: 0, name: "own", in: 0, out: 5}]
            const target = [{start: 30, span: 8, lane: 0, name: "target", in: 0, out: 8}]
            viewport.clips = data.audio ? target : own
            viewport.audioClips = data.audio ? own : target
            const desired = data.tail ? 25 : 30
            const dx = (desired - 10) * timeline.pxPerSec + 2
            fuzzyCompare(timeline.snapPx(10, dx, 0, 5, data.audio), (desired - 10) * timeline.pxPerSec, 0.001)
            const smallMove = 2
            compare(timeline.snapPx(10, smallMove, 0, 5, data.audio), smallMove)
            viewport.snapToMarkers = false
            compare(timeline.snapPx(10, dx, 0, 5, data.audio), dx)
        }
        function test_zoomAnchorClamp() {
            const anchor = 300
            const before = timeline.timeAt(anchor)
            timeline.zoomBy(2, anchor)
            fuzzyCompare(timeline.timeAt(anchor), before, 0.0001)
            timeline.zoomBy(1000, anchor)
            compare(timeline.zoom, 60)
            timeline.viewStart = 100000
            timeline.clampView()
            fuzzyCompare(timeline.viewStart, timeline.fullSpan - timeline.span, 0.0001)
            viewport.trackDuration = 5
            verify(timeline.viewStart <= timeline.fullSpan - timeline.span)
            timeline.zoomBy(0.0001, anchor)
            compare(timeline.zoom, 1)
            compare(timeline.viewStart, 0)
            timeline.viewStart = -10
            timeline.clampView()
            compare(timeline.viewStart, 0)
        }
        function test_timeRounding() {
            compare(timeline.formatTime(59.999), "1:00.00")
        }
        function test_rangeWorkflow() {
            compare(timeline.parseTime("1:02.5"), 62.5)
            compare(timeline.parseTime("12.75"), 12.75)
            for (const value of ["", "1:60", "abc", "-1", "Infinity", "1:2", "1e3"])
                verify(!Number.isFinite(timeline.parseTime(value)))
            const dialog = findChild(timeline, "sequenceRangeDialog")
            const start = findChild(timeline, "rangeStartField")
            const end = findChild(timeline, "rangeEndField")
            dialog.open()
            start.text = "10"; end.text = "bad"
            dialog.applyRange()
            verify(dialog.visible)
            verify(dialog.error.length > 0)
            compare(viewport.rangeCalls.length, 0)
            end.text = "1:20"
            dialog.applyRange()
            compare(viewport.rangeCalls.length, 1)
            compare(viewport.markIn, 10)
            compare(viewport.markOut, 80)
            compare(viewport.sequenceDuration, 80)
            compare(timeline.songEnd, 0)
            const audio = media(12, 25)
            audio.sourceDuration = 40
            viewport.audioClips = [audio, media(100, 5)]
            compare(timeline.songEnd, 37)
            dialog.open()
            findChild(timeline, "songEndButton").clicked()
            compare(timeline.parseTime(end.text), 37)
            dialog.applyRange()
            compare(viewport.markOut, 37)
            dialog.open()
            findChild(timeline, "entireTimelineButton").clicked()
            compare(viewport.rangeCalls[2].start, 0)
            compare(viewport.rangeCalls[2].end, 0)
        }
        function test_navigationBelowTracks() {
            const tracks = findChild(timeline, "tracksViewport")
            const nav = findChild(timeline, "navScrollbar")
            compare(tracks.height, timeline.totalTracksH)
            compare(nav.y, tracks.y + tracks.height + 3)
            verify(nav.y + nav.height < timeline.height)
            viewport.laneCount = 20
            verify(timeline.maxTrackScrollY > 0)
            verify(nav.y + nav.height <= timeline.height)
        }
        function test_monitorRangeWithoutSeekStrip() {
            compare(findChild(transport, "monitorScrub"), null)
            const playhead = viewport.playhead
            viewport.markIn = 10
            viewport.markOut = 30
            compare(transport.hasRange, true)
            compare(transport.rangeDuration, 20)
            viewport.clearMarks()
            compare(transport.hasRange, false)
            compare(transport.rangeDuration, 0)
            compare(viewport.playhead, playhead)
        }
    }
}
