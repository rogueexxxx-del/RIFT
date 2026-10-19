import QtQuick
import QtQuick.Controls

// Compact effect row shared by the chain and effect picker.
Rectangle {
    id: blk

    property string label: ""
    property string sub: ""
    property bool   active: false
    property string badge: ""
    property bool   isSource: false
    property bool   isOutput: false
    property bool   connectors: true
    signal activated()
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: [sub, badge, effectDescription].filter(value => value !== "").join(". ")
    Accessible.onPressAction: activated()
    Keys.onReturnPressed: activated()
    Keys.onSpacePressed: activated()

    property string effectId: label.toLowerCase().replace(/ /g, "_")
    readonly property string effectDescription: descriptions[effectId] || "Adjust this effect using its parameter controls."
    readonly property var descriptions: ({
        ascii: "Rebuilds the image using characters and symbols.",
        halftone: "Turns light and shade into print-style dots.",
        dither: "Uses patterned pixels to create limited-color shading.",
        glitch: "Shifts image blocks and bleeds colors for digital interference.",
        pixel_sort: "Stretches and rearranges pixels into directional streaks.",
        oscilloscope: "Draws audio-reactive waveforms and glowing signal traces.",
        datamosh: "Smears image blocks with compression-style artifacts.",
        risograph: "Layers ink colors, print dots and slight misalignment.",
        electron_scan: "Adds scanning-beam edges, drift and electronic texture.",
        kaleido: "Repeats and mirrors the image into radial patterns.",
        flow_warp: "Bends the image with flowing, animated distortion.",
        voronoi_shatter: "Splits the image into irregular, separated cells.",
        fracture: "Breaks the image into offset slices and sharp distortions.",
        noise_field: "Creates animated noise textures with flowing distortion.",
        dot_field: "Builds a shaded field of dots with depth and tilt.",
        contour: "Traces tonal boundaries as layered contour lines.",
        tunnel: "Creates a moving tunnel with depth, twist and color.",
        lens: "Adds lens distortion, color fringing and light streaks.",
        prism_split: "Separates color channels into directional prism fringes.",
        shockwave: "Sends a circular ripple of distortion through the image.",
        bloom: "Softens bright areas into a spreading light bloom.",
        feedback: "Feeds previous frames back into the image as motion trails.",
        halation_grain: "Adds bright-edge light bleed and film-like grain.",
        slit_scan: "Combines time slices to stretch and distort motion.",
        post_fx: "Finishes the image with grain, scanlines and a vignette.",
        film_grain: "Adds a fine film-like grain texture."
    })
    readonly property color nodeColor: isSource ? "#333333"
                                     : (isOutput ? "#1F1F1F" : Theme.effectColor(effectId))

    readonly property color textColor: Theme.foregroundFor(nodeColor)
    readonly property color subColor: textColor

    implicitWidth: 240
    implicitHeight: Math.max(64, txt.implicitHeight + 16)
    radius: Theme.radius
    color: blk.active ? Theme.hover : Theme.raised
    border.width: activeFocus ? Theme.focusWidth : 1
    border.color: activeFocus ? Theme.focusRing : blk.active ? Theme.accent : Theme.hairline

    // Fade the supplied colored pattern into a quiet, opaque text area.
    Item {
        objectName: "effect-pattern"
        anchors.fill: parent
        anchors.margins: blk.border.width
        clip: true

        Image {
            id: previewImage
            objectName: "effect-preview"
            anchors.fill: parent
            visible: false
            source: !blk.isSource && !blk.isOutput ? Theme.asset("effect_previews/" + blk.effectId + ".png") : ""
            fillMode: Image.PreserveAspectCrop
            smooth: false
            mipmap: false
            opacity: 0.32
            onStatusChanged: if (patternInk) patternInk.requestPaint()
        }
        Canvas {
            id: patternInk
            objectName: "effect-colored-pattern"
            anchors.fill: parent
            opacity: 0.32
            property url patternSource: previewImage.source
            property color inkColor: blk.nodeColor
            property int paintRevision: 0
            onPatternSourceChanged: {
                if (String(patternSource) !== "") loadImage(patternSource)
                requestPaint()
            }
            onInkColorChanged: requestPaint()
            onImageLoaded: requestPaint()
            onAvailableChanged: {
                if (available && String(patternSource) !== "") loadImage(patternSource)
                requestPaint()
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                if (previewImage.status !== Image.Ready || !isImageLoaded(patternSource)
                        || width < 1 || height < 1) return
                const scale = Math.max(width / previewImage.sourceSize.width,
                    height / previewImage.sourceSize.height)
                const w = previewImage.sourceSize.width * scale
                const h = previewImage.sourceSize.height * scale
                ctx.drawImage(String(patternSource), (width - w) / 2, (height - h) / 2, w, h)
                // Existing artwork already supplies the transparent pattern mask.
                ctx.globalCompositeOperation = "source-in"
                ctx.fillStyle = inkColor
                ctx.fillRect(0, 0, width, height)
                paintRevision++
            }
        }
        Rectangle {
            objectName: "effect-text-mask"
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: blk.color }
                GradientStop { position: 0.72; color: blk.color }
                GradientStop { position: 1; color: Qt.rgba(blk.color.r, blk.color.g, blk.color.b, 0.15) }
            }
        }
    }

    HoverHandler { id: previewHover }
    ToolTip {
        id: fullPreview
        objectName: "effect-preview-popup"
        visible: previewHover.hovered && !blk.isSource && !blk.isOutput
        delay: 350
        timeout: -1
        width: Math.max(160, Math.min(360, blk.width))
        padding: 12
        contentItem: Column {
            spacing: 8
            Text {
                text: blk.label
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Math.max(12, Theme.size)
            }
            Text {
                objectName: "effect-description"
                text: blk.effectDescription
                width: fullPreview.availableWidth
                wrapMode: Text.WordWrap
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Math.max(12, Theme.size)
                renderType: Text.NativeRendering
            }
        }
        background: Rectangle { color: Theme.flyout; border.color: Theme.popupBorder; border.width: 1; radius: Theme.panelRadius }
    }

    Column {
        id: txt
        objectName: "effect-text"
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: Math.max(12, blk.width * 0.28)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Text {
            width: parent.width
            text: blk.label
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: [blk.sub, blk.badge].filter(function(value) { return value !== "" }).join(" · ")
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
            elide: Text.ElideRight
        }
    }
}
