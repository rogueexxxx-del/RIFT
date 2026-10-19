import QtQuick
import QtQuick.Window
import Rift

Main {
    id: probe
    shaderDir: argument("--probe-shaders", "")
    assetsUrl: argument("--probe-assets", "")
    initialAudio: argument("--probe-audio", "")
    initialChain: "ascii"
    initialTexts: ["RIFT FLUENT CHECK|0|12|0.16"]
    title: "RIFT disposable Fluent verification"
    property var testWorkspace: null
    property var testView: null
    property int stage: 0
    property bool pending: false
    function argument(key, fallback) {
        const index = Qt.application.arguments.indexOf(key)
        return index >= 0 ? Qt.application.arguments[index + 1] : fallback
    }
    function find(item, predicate) {
        if (predicate(item)) return item
        for (const child of item.children || []) {
            const found = find(child, predicate)
            if (found) return found
        }
        return null
    }
    function capture(mode) {
        const t = testWorkspace.panels.timeline
        const tracks = find(t, item => item.objectName === "tracksViewport")
        let clips = []
        if (mode === "react" && tracks) {
            for (const name of ["videoClip0", "audioClip0"]) {
                const clip = find(t, item => item.objectName === name)
                if (clip) {
                    const y = clip.mapToItem(tracks, 0, 0).y
                    clips.push({name: name, y: y, height: clip.height,
                        available: tracks.height, fits: y >= -1 && y + clip.height <= tracks.height + 1})
                }
            }
        }
        console.log("FLUENT_METRICS " + JSON.stringify({mode: mode, width: width, height: height,
            screenWidth: Screen.width, screenHeight: Screen.height, dpr: Screen.devicePixelRatio,
            timelineHeight: t.height, previewHeight: testView.height, tracks: clips, bodySize: Theme.size, theme: Theme.preset}))
        pending = true
        if (!testWorkspace.parent.grabToImage(function(result) {
            if (!result.saveToFile(argument("--probe-output", "") + "/" + mode + ".png")) Qt.exit(1)
            pending = false
        })) Qt.exit(1)
    }
    Component.onCompleted: Qt.callLater(function() {
        testWorkspace = find(contentItem, item => item.objectName === "workspace")
        if (!testWorkspace) { console.error("FLUENT_FAIL workspace"); Qt.exit(1); return }
        testWorkspace.persistLayout = false
        testWorkspace.layoutLocation = argument("--probe-layout", "")
        testWorkspace.resetLayout()
        testView = find(contentItem, item => typeof item.moveClip === "function")
        if (!testView) { console.error("FLUENT_FAIL viewport"); Qt.exit(1); return }
        timer.start()
    })
    Timer {
        id: timer
        interval: 1300
        repeat: true
        onTriggered: {
            if (probe.pending) return
            switch (probe.stage++) {
            case 0: probe.capture("react"); break
            case 1: probe.testView.mode = 1; break
            case 2: probe.capture("live"); break
            case 3: console.log("FLUENT_COMPLETE"); Qt.exit(0); break
            }
        }
    }
}
