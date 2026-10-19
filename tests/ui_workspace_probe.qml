import QtQuick
import QtQuick.Window
import Rift

// Run in a separate rebuilt shell with RIFT_UI_TESTQML set to this file.
// All fixture, capture and layout paths must point to disposable scratch files.
Main {
    id: probe
    shaderDir: argument("--probe-shaders", "")
    assetsUrl: argument("--probe-assets", "")
    initialMedia: argument("--probe-media", "")
    initialAudio: argument("--probe-audio", "")
    initialChain: "ascii"
    initialTexts: initialMedia === "" ? ["RIFT UI CHECK|0|4|0.16"] : []
    visibility: Window.Windowed
    width: 1440
    height: 900
    title: "RIFT disposable workspace verification"
    property var workspaceUnderTest: null
    property var view: null
    property var timelineUnderTest: null
    property int stage: 0
    property int checks: 0
    property int frames: 0
    property var originalClip: null
    property int originalNode: -1
    property string floatingId: ""
    property bool capturePending: false
    onFrameSwapped: frames++

    function argument(key, fallback) {
        const index = Qt.application.arguments.indexOf(key)
        return index >= 0 ? Qt.application.arguments[index + 1] : fallback
    }
    function check(condition, message) {
        if (!condition) throw new Error(message)
        checks++
    }
    function find(item, predicate) {
        if (predicate(item)) return item
        for (const child of item.children) {
            const found = find(child, predicate)
            if (found) return found
        }
        return null
    }
    function capture(name, after, item) {
        const path = argument("--probe-captures", "")
        check(path !== "", "--probe-captures must name a scratch directory")
        capturePending = true
        check((item || workspaceUnderTest.parent).grabToImage(function(result) {
            if (!result.saveToFile(path + "/" + name + ".png")) {
                console.error("WORKSPACE_PROBE_FAIL could not save " + name)
                Qt.exit(1)
            }
            if (after) after()
            capturePending = false
        }), "request capture " + name)
    }
    function runStage() {
        if (capturePending) return
        const w = workspaceUnderTest, v = view, t = timelineUnderTest
        switch (stage++) {
        case 0:
            check(v.clips.length === 1 && v.hasMedia, "real clip initialized")
            check(v.hasAudio && v.audioClips.length === 1, "audio fixture initialized")
            check(v.audioClips[0].span > 1.5, "audio fixture decoded")
            check(v.fps > 0 && frames > 0, "preview renders through the integrated shell")
            originalClip = {start: v.clips[0].start, lane: v.clips[0].lane}
            originalNode = v.selectedNode
            v.moveClip(0, 3, 2)
            break
        case 1:
            check(v.clips[0].start === 3 && v.clips[0].lane === 2, "real atomic video move")
            v.undo()
            break
        case 2:
            check(v.clips[0].start === originalClip.start && v.clips[0].lane === originalClip.lane,
                  "real move undo restores both coordinates")
            check(v.canRedo && v.selectedNode === originalNode && v.hasAudio,
                  "undo retains redo, selected effect and audio")
            v.redo()
            break
        case 3:
            check(v.clips[0].start === 3 && v.clips[0].lane === 2, "real move redo")
            v.undo()
            v.sequenceDuration = 1
            v.setMarkIn(0.25)
            v.setMarkOut(1.5)
            break
        case 4:
            check(t.fullSpan >= v.audioClips[0].start + v.audioClips[0].span,
                  "editing extent includes audio beyond export duration")
            check(t.hasRange && find(t, item => typeof item.text === "string"
                && item.text.indexOf("DURATION 0:01.25") >= 0) !== null, "timeline marked duration")
            capture("react-default", function() {
                w.floatPanel("queue", 80, 80)
                floatingId = w.state.floating[0].id
            })
            break
        case 5:
            check(w.isFloating(floatingId), "integrated panel floats")
            check(find(contentItem, item => item === v) === v, "floating another panel retains preview")
            capture("react-floating", function() { w.returnGroup(floatingId) })
            break
        case 6:
            check(w.state.floating.length === 0, "floating panel returns to its group")
            w.showPanel("clip")
            v.mode = 1
            break
        case 7:
            check(w.live && w.panels.preview !== null, "live workspace initializes")
            check(find(contentItem, item => item === v) === v, "live mode preserves the viewport instance")
            capture("live-default", function() { v.mode = 0 })
            break
        case 8:
            check(!w.live && w.panels.timeline === t, "react mode preserves the timeline instance")
            w.resetLayout()
            t.zoomBy(4, 200)
            break
        case 9:
            check(t.zoom > 1 && t.viewStart >= 0, "real timeline zoom")
            capture("react-zoomed")
            break
        case 10:
            w.floatPanel("preview", 300, 100)
            check(w.state.floating.length === 0, "GPU preview stays in its owning window")
            break
        case 11:
            check(v.hasMedia, "refused preview detach retains its source")
            break
        case 12:
            check(find(contentItem, item => item === v) === v, "workspace retains the viewport instance")
            check(v.audioClips[0].waveform.length > 0 && v.audioClips[0].sourceDuration > 1.5,
                  "decoded source waveform reaches the timeline model")
            v.setAudioClipGain(0, 0)
            v.sequenceDuration = 4
            v.clearMarks()
            v.seek(0.2)
            v.play()
            break
        case 13:
            check(v.playhead > 0.2, "playback advances after history restore and workspace changes")
            v.pause()
            v.setAudioClipGain(0, 1)
            break
        case 14:
            capture("react-returned")
            break
        case 15:
            console.log("WORKSPACE_PROBE_PASS checks=" + checks + " frames=" + frames)
            Qt.exit(0)
        }
    }
    Component.onCompleted: Qt.callLater(function() {
        try {
            workspaceUnderTest = find(contentItem, item => item.objectName === "workspace")
            check(workspaceUnderTest !== null, "integrated workspace exists")
            workspaceUnderTest.persistLayout = false
            workspaceUnderTest.layoutLocation = argument("--probe-layout", "")
            workspaceUnderTest.resetLayout()
            view = find(contentItem, item => typeof item.moveClip === "function")
            check(view !== null, "integrated viewport exists")
            timelineUnderTest = workspaceUnderTest.panels.timeline
            timer.start()
        } catch (error) {
            console.error("WORKSPACE_PROBE_FAIL " + error.stack)
            Qt.exit(1)
        }
    })
    Timer {
        id: timer
        interval: 1000
        repeat: true
        onTriggered: {
            try { runStage() }
            catch (error) {
                console.error("WORKSPACE_PROBE_FAIL " + error.message + " " + error.stack)
                Qt.exit(1)
            }
        }
    }
}
