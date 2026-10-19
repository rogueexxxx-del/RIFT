import QtQuick
import QtQuick.Window
import Rift

// Run only in a separate rebuilt shell with RIFT_UI_TESTQML set to this file.
// Pass --probe-project with a disposable .rt path. No user project is opened.
// Hidden viewports exercise synchronous UI/history state, not decoder playback.
Window {
    id: probe
    visible: false
    property int checks: 0
    property int publications: 0
    property int historySignals: 0
    property string shaders: argument("--probe-shaders", decodeURIComponent(
        Qt.resolvedUrl("../build-release/Release/shaders").toString().replace(/^file:\/\/\//, "")))

    function argument(key, fallback) {
        const index = Qt.application.arguments.indexOf(key)
        return index >= 0 ? Qt.application.arguments[index + 1] : fallback
    }
    function check(condition, message) {
        if (!condition) throw new Error(message)
        checks++
    }
    function equal(actual, expected, message) {
        check(JSON.stringify(actual) === JSON.stringify(expected), message
            + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function state(view) {
        return JSON.stringify({ clips: view.clips, audio: view.audioClips,
            edited: view.editedClip, node: view.selectedNode, chain: view.chain,
            params: view.params, grade: view.grade, name: view.projectName,
            hasMedia: view.hasMedia, hasAudio: view.hasAudio, mediaName: view.mediaName })
    }
    function countPublication() { publications++ }
    function countHistory() { historySignals++ }
    function position(view, audio, start, lane, message) {
        const clip = audio ? view.audioClips[0] : view.clips[1]
        equal([clip.start, clip.lane], [start, lane], message)
    }

    Component {
        id: viewportFactory
        RiftViewport { shaderDir: probe.shaders }
    }

    function run() {
        const file = argument("--probe-project", "")
        check(file !== "", "--probe-project must name a disposable .rt file")
        const view = viewportFactory.createObject(probe.contentItem)
        check(view !== null, "create RiftViewport")
        check(typeof view.moveClip === "function" && typeof view.moveAudioClip === "function",
              "rebuild required: atomic move API missing")
        check(view.grade.length > 0, "shader manifests must be available")
        const range = viewportFactory.createObject(probe.contentItem)
        check(typeof range.setSequenceRange === "function", "atomic sequence range API available")
        check(!range.setSequenceRange(NaN, 8) && !range.setSequenceRange(5, 4)
            && !range.setSequenceRange(1, 0) && !range.canUndo, "invalid ranges leave state and history unchanged")
        check(range.setSequenceRange(2, 8), "custom range accepted")
        equal([range.sequenceDuration, range.markIn, range.markOut], [8, 2, 8], "duration and marks update together")
        range.undo()
        equal([range.sequenceDuration, range.markIn, range.markOut], [0, 0, 0], "one undo restores the complete range")
        range.redo()
        equal([range.sequenceDuration, range.markIn, range.markOut], [8, 2, 8], "redo restores range")
        check(range.setSequenceRange(0, 0), "automatic range accepted")
        range.undo()
        check(range.setSequenceRange(2, 8) && range.canRedo, "unchanged range preserves redo")
        range.newProject()
        equal([range.sequenceDuration, range.markIn, range.markOut], [0, 0, 0], "new project clears old range")
        range.undo()
        equal([range.sequenceDuration, range.markIn, range.markOut], [8, 2, 8], "undo new restores range")
        range.destroy()
        view.historyChanged.connect(countHistory)
        view.clipsChanged.connect(countPublication)

        view.resetGrade()
        check(!view.canUndo, "reset default grade creates no history")
        view.resetParams()
        check(!view.canUndo, "reset absent effect creates no history")
        view.addKey(-1)
        view.moveKey(0, 0, 1)
        view.addKeyAt(0, 0, 1, 0)
        view.removeKeyAt(0)
        view.clearKeys(0)
        view.cycleKeyInterp(0)
        view.setNodeBlend(-1, 0, 1)
        check(!view.canUndo && !view.canRedo, "empty and invalid edits create no history")

        view.addTextClip("base", 0, 4)
        view.moveClip(0, 0, 0)
        view.addTextClip("selected", 1, 4)
        view.selectClip(1)
        view.addNode("ascii")
        view.addNode("halftone")
        equal(view.selectedNode, 1, "nonzero selected effect")
        check(view.params.length > 0, "selected effect has parameters")
        view.moveClip(1, 2, 1)
        // No render surface exists: this source is metadata only, never decoded.
        view.loadAudio(Qt.resolvedUrl("history-probe-not-decoded.wav"))
        view.moveAudioClip(0, 1, 0)
        check(view.saveProject(file, true), "save disposable identity fixture")
        const name = view.projectName
        const before = state(view)

        publications = 0
        view.moveClip(1, 7, 4)
        equal(publications, 1, "video move publishes once")
        position(view, false, 7, 4, "video atomic coordinates")
        const movedVideo = state(view)
        view.undo()
        equal(state(view), before, "video undo restores complete state and selection")
        check(view.canRedo && view.canUndo, "restore preserves both history queues")
        for (let i = 0; i < 3; ++i) {
            view.redo()
            equal(state(view), movedVideo, "repeat video redo " + i)
            view.undo()
            equal(state(view), before, "repeat video undo " + i)
        }
        view.redo()

        const beforeAudio = state(view)
        publications = 0
        view.moveAudioClip(0, 5, 3)
        equal(publications, 1, "audio move publishes once")
        position(view, true, 5, 3, "audio atomic coordinates")
        const movedAudio = state(view)
        view.undo()
        equal(state(view), beforeAudio, "audio undo restores both coordinates")
        view.redo()
        equal(state(view), movedAudio, "audio redo restores both coordinates")
        view.undo()
        view.undo()
        equal(state(view), before, "two undo steps reverse two drags, not four setters")

        const redoLabel = view.redoLabel
        historySignals = 0
        view.moveClip(1, 2, 1)
        view.moveAudioClip(0, 1, 0)
        view.moveClip(-1, 9, 9)
        view.moveClip(1, NaN, 9)
        view.moveClip(1, Infinity, 9)
        view.moveAudioClip(0, -Infinity, 9)
        view.setClipStart(1, NaN)
        view.setAudioClipStart(0, Infinity)
        view.setClipLane(1, 1)
        view.setAudioClipLane(0, 0)
        view.setAudioClipGain(0, 1)
        view.setBinding(0, 999, 1)
        view.clearKeys(0)
        view.removeKeyAt(0)
        view.moveKey(999, 0, 1)
        view.resetParams()
        equal(historySignals, 0, "no-op and invalid edits emit no history change")
        check(view.canRedo && view.redoLabel === redoLabel, "no-op preserves redo")

        view.setClipStart(1, 3)
        view.setClipStart(1, 4)
        check(!view.canRedo, "new coalesced edit clears stale redo")
        view.undo()
        position(view, false, 2, 1, "coalesced old setter undoes to first pre-state")
        view.setClipStart(1, 6)
        check(!view.canRedo, "same-tag branch invalidates redo")
        view.undo()
        position(view, false, 2, 1, "same-tag branch has its own restore point")
        view.redo()
        view.setClipStart(1, 8)
        view.undo()
        position(view, false, 6, 1, "redo ends coalescing before next gesture")
        equal(view.projectName, name, "ordinary history retains saved project identity")

        view.moveClip(1, -3, -4)
        position(view, false, 0, 0, "video clamps negative coordinates")
        view.undo()
        view.moveAudioClip(0, -3, -4)
        position(view, true, 0, 0, "audio clamps negative coordinates")
        view.undo()

        const param = Number(view.params[0].value)
        const changed = param === Number(view.params[0].max)
            ? Number(view.params[0].min) : Number(view.params[0].max)
        view.setParam(0, changed)
        view.resetParams()
        view.undo()
        check(Math.abs(Number(view.params[0].value) - changed) < 0.00001,
              "reset params syncs selected clip before snapshot")
        view.redo()
        view.setNodeBlend(1, 0, 0.9995)
        const mix = Number(view.chain[1].mix)
        view.moveClip(1, 9, 2)
        view.undo()
        equal(Number(view.chain[1].mix), mix, "history retains near-unity blend mix exactly")
        const beforeNew = state(view)
        view.newProject()
        check(view.clips.length === 0 && view.audioClips.length === 0
              && !view.hasMedia && !view.hasAudio, "new project clears source flags and models")
        view.undo()
        equal(state(view), beforeNew, "undo new restores identity, sources, selected chain")
        view.redo()
        check(view.clips.length === 0 && view.audioClips.length === 0,
              "redo new restores empty audio, not stale audio")
        view.undo()
        const beforeLoad = state(view)
        check(view.loadProject(file), "load disposable fixture")
        view.undo()
        equal(state(view), beforeLoad, "undo load restores selected clip and chain")
        view.redo()
        check(view.canUndo, "redo load retains undo queue")

        // Independently verify add-audio undo clears an absent audio array.
        const empty = viewportFactory.createObject(probe.contentItem)
        empty.addAudioClip(Qt.resolvedUrl("history-probe-not-decoded.wav"), 0, -1)
        empty.undo()
        check(empty.audioClips.length === 0 && !empty.hasAudio, "undo first audio addition empties model")
        empty.redo()
        check(empty.audioClips.length === 1 && empty.hasAudio, "redo first audio addition")
        empty.removeAudioClip(0)
        check(empty.audioClips.length === 0 && !empty.hasAudio, "remove final audio clears source state")
        empty.undo()
        check(empty.audioClips.length === 1 && empty.hasAudio, "undo final audio removal")
        empty.redo()
        check(empty.audioClips.length === 0 && !empty.hasAudio, "redo final audio removal")
        empty.destroy()
        view.destroy()
        console.log("HISTORY_PROBE_PASS checks=" + checks)
        Qt.exit(0)
    }

    Component.onCompleted: Qt.callLater(function() {
        try { run() }
        catch (error) {
            console.error("HISTORY_PROBE_FAIL " + error.message + " " + error.stack)
            Qt.exit(1)
        }
    })
}
