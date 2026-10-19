import QtQuick
import QtQuick.Window
import Rift

// Runs the shipped shell so preview measurements include the real dock UI.
Main {
    id: probe
    function argument(key, fallback) {
        const i = Qt.application.arguments.indexOf(key)
        return i >= 0 ? Qt.application.arguments[i + 1] : fallback
    }
    shaderDir: argument("--probe-shaders", "")
    assetsUrl: argument("--probe-assets", "")
    initialMedia: argument("--probe-media", "")
    initialAudio: argument("--probe-audio", "")
    initialChain: "ascii,halftone,glitch"
    initialPlay: true
    visibility: Window.Windowed
    title: "RIFT Phase 1 preview probe"
    width: Number(argument("--probe-width", "2560"))
    height: Number(argument("--probe-height", "1440"))
    property var view: null
    property int seconds: 0
    property int frames: 0
    property double lastSample: Date.now()
    function findView(item) {
        if (typeof item.setParam === "function" && typeof item.fps === "number") return item
        for (let i = 0; i < item.children.length; ++i) {
            const found = findView(item.children[i])
            if (found) return found
        }
        return null
    }
    onFrameSwapped: frames++
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            probe.seconds++
            if (probe.seconds === 1) probe.showNormal()
            if (!probe.view) probe.view = probe.findView(probe.contentItem)
            if (!probe.view) throw new Error("Preview item not found")
            const v = probe.view
            if (probe.seconds <= 3 && probe.argument("--probe-width", "") === "") {
                probe.width += Math.max(0, 1920 - v.framedRect.width)
                probe.height += Math.max(0, 1080 - v.framedRect.height)
            }
            const now = Date.now()
            if (probe.seconds > 8) console.log("PREVIEW_SAMPLE " + JSON.stringify({
                second: probe.seconds, presentedFps: probe.frames * 1000 / (now - probe.lastSample),
                engineFps: v.fps, p95Ms: v.frameP95, gpuMs: v.gpuMs,
                width: v.framedRect.width, height: v.framedRect.height
            }))
            probe.frames = 0
            probe.lastSample = now
            if (probe.seconds === 24) {
                probe.contentItem.children[0].grabToImage(function(result) {
                    result.saveToFile(probe.argument("--probe-image", "preview.png"))
                    Qt.quit()
                })
            }
            if (probe.seconds === 26) Qt.quit()
        }
    }
}
