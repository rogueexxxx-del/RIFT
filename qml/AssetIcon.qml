import QtQuick

Item {
    id: icon
    property url source: ""
    property color color: Theme.text
    property bool ready: false
    implicitWidth: 18
    implicitHeight: 18

    function reload() {
        ready = false
        if (ink && String(source) !== "") {
            ink.loadImage(source)
            ready = ink.isImageLoaded(source)
        }
        if (ink) ink.requestPaint()
    }
    onSourceChanged: reload()
    onColorChanged: if (ink) ink.requestPaint()
    Component.onCompleted: reload()

    Canvas {
        id: ink
        objectName: "assetIconInk"
        anchors.centerIn: parent
        width: 48; height: 48
        scale: Math.min(icon.width / width, icon.height / height)
        antialiasing: true
        smooth: true
        // Keep the original glyph resolution and filter it when drawn smaller.
        layer.enabled: true
        layer.smooth: true
        layer.mipmap: true
        onAvailableChanged: if (available) icon.reload()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onImageLoaded: {
            icon.ready = isImageLoaded(icon.source)
            requestPaint()
        }
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (String(icon.source) === "" || !isImageLoaded(icon.source) || width < 1 || height < 1) return
            ctx.drawImage(String(icon.source), 0, 0, width, height)
            ctx.globalCompositeOperation = "source-in"
            ctx.fillStyle = icon.color
            ctx.fillRect(0, 0, width, height)
        }
    }
}
