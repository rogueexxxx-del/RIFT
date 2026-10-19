import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Rift

ApplicationWindow {
    id: window
    title: "RIFT Phase 1 component review"
    visible: true
    width: Theme.galleryWidth
    height: Theme.galleryHeight
    color: Theme.bg
    function argument(key, fallback) {
        const i = Qt.application.arguments.indexOf(key)
        return i >= 0 ? Qt.application.arguments[i + 1] : fallback
    }
    Component.onCompleted: Theme.assetsUrl = argument("--probe-assets", "")
    ComponentGallery { id: gallery; anchors.fill: parent }
    Timer { interval: 1000; running: true; onTriggered: window.showNormal() }
    Timer {
        interval: 5000
        running: window.argument("--probe-image", "") !== ""
        onTriggered: gallery.grabToImage(function(result) {
            console.log("COMPONENT_CAPTURE", result.saveToFile(window.argument("--probe-image", "")))
            Qt.quit()
        })
    }
}
