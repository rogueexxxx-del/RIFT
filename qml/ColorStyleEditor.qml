import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs

// Shared Color Customization component for all four visualizers:
// Oscilloscope (0), Spectrum Analyzer (1), Spectrogram (2), Lissajous Vectorscope (3).
// Live baking into GPU LUT, solid/gradient modes, stop handle editing, presets, and link-all.
Item {
    id: editor
    required property var viewport
    property int visIndex: 0

    // Mapping option lists per visualizer
    readonly property var mappingOptions: [
        // 0: Oscilloscope
        [{ key: "horizontal", label: "Horizontal (L → R)" }, { key: "amplitude", label: "Amplitude (Center → Peak)" }],
        // 1: Spectrum Analyzer
        [{ key: "frequency", label: "Frequency (Low → High)" }, { key: "level", label: "Level (Bottom → Top)" }],
        // 2: Spectrogram
        [{ key: "db", label: "dB (Floor → Peak)" }],
        // 3: Vectorscope
        [{ key: "distance", label: "Distance (Center → Out)" }, { key: "age", label: "Age (Newest → Oldest)" }, { key: "angle", label: "Angle (Phase)" }]
    ]

    property var currentMappings: mappingOptions[Math.min(Math.max(visIndex, 0), 3)]

    // Internal state mirrored from viewport
    property string styleMode: "gradient"
    property string solidColor: "#00ffffff"
    property var stops: [
        { position: 0.0, color: "#00ffffff" },
        { position: 1.0, color: "#ffffffff" }
    ]
    property string mappingKey: "horizontal"
    property string glowColor: "match"
    property int selectedStop: 0

    implicitWidth: 320
    implicitHeight: mainCol.implicitHeight + Theme.padding * 2

    function loadFromViewport() {
        const s = viewport.visualizerColorStyle(visIndex)
        if (!s || Object.keys(s).length === 0) return
        styleMode = s.mode || "gradient"
        solidColor = s.solid || "#00ffffff"
        if (s.stops && s.stops.length >= 2) {
            let st = []
            for (let i = 0; i < s.stops.length; ++i) {
                st.push({ position: Number(s.stops[i].position), color: String(s.stops[i].color) })
            }
            st.sort((a, b) => a.position - b.position)
            stops = st
        }
        mappingKey = s.mapping || currentMappings[0].key
        glowColor = s.glow_color || "match"
        if (selectedStop >= stops.length) selectedStop = Math.max(0, stops.length - 1)
        gradientCanvas.requestPaint()
    }

    function pushToViewport() {
        let s = {
            mode: styleMode,
            solid: solidColor,
            stops: stops,
            mapping: mappingKey,
            glow_color: glowColor
        }
        viewport.setVisualizerColorStyle(visIndex, s)
        gradientCanvas.requestPaint()
    }

    Connections {
        target: viewport
        function onVisualizerColorStyleChanged(idx) {
            if (idx === editor.visIndex || viewport.linkAllVisualizers) {
                editor.loadFromViewport()
            }
        }
        function onLinkAllVisualizersChanged() {
            editor.loadFromViewport()
        }
    }

    onVisIndexChanged: loadFromViewport()
    Component.onCompleted: loadFromViewport()

    // Native Color Dialog for pickers
    ColorDialog {
        id: colorPicker
        title: "Select Color"
        property string target: "solid" // "solid", "stop", "glow"
        onAccepted: {
            const hex = selectedColor.toString()
            if (target === "solid") {
                editor.solidColor = hex
            } else if (target === "glow") {
                editor.glowColor = hex
            } else if (target === "stop") {
                if (editor.selectedStop >= 0 && editor.selectedStop < editor.stops.length) {
                    let st = editor.stops.slice()
                    st[editor.selectedStop].color = hex
                    editor.stops = st
                }
            }
            editor.pushToViewport()
        }
    }

    FileDialog {
        id: savePresetDialog
        title: "Save Color Preset"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: ["JSON Files (*.json)"]
        onAccepted: viewport.saveVisualizerPreset(visIndex, selectedFile)
    }

    FileDialog {
        id: loadPresetDialog
        title: "Load Color Preset"
        fileMode: FileDialog.OpenFile
        defaultSuffix: "json"
        nameFilters: ["JSON Files (*.json)"]
        onAccepted: {
            viewport.loadVisualizerPreset(visIndex, selectedFile)
            editor.loadFromViewport()
        }
    }

    ColumnLayout {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.padding
        spacing: Theme.gap

        // ── Title & Link All Row ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap

            Text {
                text: "COLOR STYLE"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
                font.bold: true
                Layout.fillWidth: true
            }

            FlatButton {
                small: true
                label: viewport.linkAllVisualizers ? "Linked (All)" : "Link All"
                active: viewport.linkAllVisualizers
                onClicked: viewport.linkAllVisualizers = !viewport.linkAllVisualizers
            }
        }

        // ── Mode Toggle & Reverse Row ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapTight

            FlatButton {
                small: true
                label: "Solid"
                active: editor.styleMode === "solid"
                onClicked: {
                    editor.styleMode = "solid"
                    editor.pushToViewport()
                }
            }

            FlatButton {
                small: true
                label: "Gradient"
                active: editor.styleMode === "gradient"
                onClicked: {
                    editor.styleMode = "gradient"
                    editor.pushToViewport()
                }
            }

            Item { Layout.fillWidth: true }

            FlatButton {
                small: true
                visible: editor.styleMode === "gradient"
                label: "Reverse"
                onClicked: {
                    let st = editor.stops.slice()
                    st.reverse()
                    for (let i = 0; i < st.length; ++i) {
                        st[i].position = Math.round((1.0 - st[i].position) * 1000) / 1000
                    }
                    st.sort((a, b) => a.position - b.position)
                    editor.stops = st
                    editor.pushToViewport()
                }
            }
        }

        // ── Solid Mode Controls ──
        ColumnLayout {
            visible: editor.styleMode === "solid"
            Layout.fillWidth: true
            spacing: Theme.gapTight

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap

                Text {
                    text: "Color"
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.size
                }

                Rectangle {
                    width: 36
                    height: 22
                    color: editor.solidColor
                    border.width: 1
                    border.color: Theme.border

                    TapHandler {
                        onTapped: {
                            colorPicker.target = "solid"
                            colorPicker.selectedColor = editor.solidColor
                            colorPicker.open()
                        }
                    }
                }

                Text {
                    text: editor.solidColor.toUpperCase()
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.sizeSmall
                    Layout.fillWidth: true
                }
            }
        }

        // ── Gradient Mode Controls ──
        ColumnLayout {
            visible: editor.styleMode === "gradient"
            Layout.fillWidth: true
            spacing: Theme.gapTight

            // Gradient Preview Bar (click empty to add stop)
            Rectangle {
                id: barBox
                Layout.fillWidth: true
                height: 22
                color: Theme.sunken
                border.width: 1
                border.color: Theme.hairline
                clip: true

                Canvas {
                    id: gradientCanvas
                    anchors.fill: parent
                    onPaint: {
                        let ctx = getContext("2d")
                        let g = ctx.createLinearGradient(0, 0, width, 0)
                        for (let i = 0; i < editor.stops.length; ++i) {
                            let p = Math.min(Math.max(editor.stops[i].position, 0.0), 1.0)
                            g.addColorStop(p, editor.stops[i].color)
                        }
                        ctx.fillStyle = g
                        ctx.fillRect(0, 0, width, height)
                    }
                    onWidthChanged: requestPaint()
                }

                TapHandler {
                    onTapped: function(event) {
                        if (editor.stops.length >= 8) return
                        let pos = Math.round((event.position.x / barBox.width) * 1000) / 1000
                        pos = Math.min(Math.max(pos, 0.0), 1.0)
                        // Interpolate color at clicked position
                        let newCol = "#ffffff"
                        let st = editor.stops.slice()
                        for (let i = 0; i < st.length - 1; ++i) {
                            if (pos >= st[i].position && pos <= st[i + 1].position) {
                                newCol = st[i].color
                                break
                            }
                        }
                        st.push({ position: pos, color: newCol })
                        st.sort((a, b) => a.position - b.position)
                        editor.stops = st
                        for (let i = 0; i < st.length; ++i) {
                            if (Math.abs(st[i].position - pos) < 1e-4) {
                                editor.selectedStop = i
                                break
                            }
                        }
                        editor.pushToViewport()
                    }
                }
            }

            // Draggable Stop Handles Track
            Item {
                id: handleTrack
                Layout.fillWidth: true
                height: 26

                Repeater {
                    model: editor.stops

                    Item {
                        id: handleItem
                        required property int index
                        required property var modelData
                        width: 16
                        height: 24
                        x: Math.round(modelData.position * (handleTrack.width - width))
                        y: 0

                        Rectangle {
                            anchors.fill: parent
                            color: handleItem.modelData.color
                            border.width: editor.selectedStop === handleItem.index ? 2 : 1
                            border.color: editor.selectedStop === handleItem.index ? Theme.accent : Theme.border
                        }

                        MouseArea {
                            anchors.fill: parent
                            drag.target: parent
                            drag.axis: Drag.XAndYAxis
                            drag.minimumX: 0
                            drag.maximumX: handleTrack.width - handleItem.width
                            onPressed: {
                                editor.selectedStop = handleItem.index
                            }
                            onPositionChanged: {
                                if (drag.active) {
                                    let newPos = handleItem.x / (handleTrack.width - handleItem.width)
                                    newPos = Math.round(newPos * 1000) / 1000
                                    let st = editor.stops.slice()
                                    st[handleItem.index].position = Math.min(Math.max(newPos, 0.0), 1.0)
                                    editor.stops = st
                                    editor.pushToViewport()
                                }
                            }
                            onReleased: {
                                // If dragged off the bar vertically (outside [-20, 45]), delete stop if > 2
                                if ((handleItem.y > 35 || handleItem.y < -20) && editor.stops.length > 2) {
                                    let st = editor.stops.slice()
                                    st.splice(handleItem.index, 1)
                                    st.sort((a, b) => a.position - b.position)
                                    editor.stops = st
                                    editor.selectedStop = Math.max(0, handleItem.index - 1)
                                    editor.pushToViewport()
                                } else {
                                    handleItem.y = 0
                                    let st = editor.stops.slice()
                                    st.sort((a, b) => a.position - b.position)
                                    editor.stops = st
                                    editor.pushToViewport()
                                }
                            }
                        }
                    }
                }
            }

            // Stop Inspector Row
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap

                Text {
                    text: "Stop " + (editor.selectedStop + 1)
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeSmall
                }

                Rectangle {
                    width: 28
                    height: 20
                    color: (editor.stops[editor.selectedStop] ? editor.stops[editor.selectedStop].color : "#fff")
                    border.width: 1
                    border.color: Theme.border

                    TapHandler {
                        onTapped: {
                            colorPicker.target = "stop"
                            colorPicker.selectedColor = (editor.stops[editor.selectedStop] ? editor.stops[editor.selectedStop].color : "#ffffff")
                            colorPicker.open()
                        }
                    }
                }

                Text {
                    text: "Pos: " + (editor.stops[editor.selectedStop] ? editor.stops[editor.selectedStop].position.toFixed(2) : "0.00")
                    color: Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.sizeSmall
                    Layout.fillWidth: true
                }

                FlatButton {
                    small: true
                    label: "Del"
                    enabledLook: editor.stops.length > 2
                    onClicked: {
                        if (editor.stops.length > 2) {
                            let st = editor.stops.slice()
                            st.splice(editor.selectedStop, 1)
                            st.sort((a, b) => a.position - b.position)
                            editor.stops = st
                            editor.selectedStop = Math.max(0, editor.selectedStop - 1)
                            editor.pushToViewport()
                        }
                    }
                }
            }
        }

        // ── Mapping Selector Row ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap

            Text {
                text: "Mapping"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }

            RowLayout {
                spacing: Theme.gapTight
                Repeater {
                    model: editor.currentMappings

                    FlatButton {
                        small: true
                        required property var modelData
                        label: modelData.label.split(" ")[0]
                        active: editor.mappingKey === modelData.key
                        onClicked: {
                            editor.mappingKey = modelData.key
                            editor.pushToViewport()
                        }
                    }
                }
            }
        }

        // ── Glow Color Row ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap

            Text {
                text: "Glow"
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }

            FlatButton {
                small: true
                label: "Match Line"
                active: editor.glowColor === "match"
                onClicked: {
                    editor.glowColor = "match"
                    editor.pushToViewport()
                }
            }

            Rectangle {
                width: 24
                height: 20
                color: editor.glowColor === "match" ? (editor.styleMode === "solid" ? editor.solidColor : (editor.stops[0] ? editor.stops[0].color : "#fff")) : editor.glowColor
                border.width: editor.glowColor !== "match" ? 2 : 1
                border.color: editor.glowColor !== "match" ? Theme.accent : Theme.border

                TapHandler {
                    onTapped: {
                        colorPicker.target = "glow"
                        colorPicker.selectedColor = editor.glowColor === "match" ? "#ff00ffff" : editor.glowColor
                        colorPicker.open()
                    }
                }
            }

            Text {
                text: editor.glowColor === "match" ? "Auto" : "Custom"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
                Layout.fillWidth: true
            }
        }

        // ── Presets Section ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapTight

            Text {
                text: "Presets"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
                Layout.preferredWidth: 48
            }

            FlatButton {
                small: true
                label: "Mono"
                onClicked: {
                    editor.styleMode = "gradient"
                    editor.stops = [
                        { position: 0.0, color: "#ffffffff" },
                        { position: 1.0, color: "#ffffffff" }
                    ]
                    editor.pushToViewport()
                }
            }

            FlatButton {
                small: true
                label: "Sunset"
                onClicked: {
                    editor.styleMode = "gradient"
                    editor.stops = [
                        { position: 0.0, color: "#ff1a0066" },
                        { position: 0.35, color: "#ffff2266" },
                        { position: 0.75, color: "#ffffaa00" },
                        { position: 1.0, color: "#ffffffcc" }
                    ]
                    editor.pushToViewport()
                }
            }

            FlatButton {
                small: true
                label: "Ice"
                onClicked: {
                    editor.styleMode = "gradient"
                    editor.stops = [
                        { position: 0.0, color: "#ff004488" },
                        { position: 0.5, color: "#ff00ccff" },
                        { position: 1.0, color: "#ffffffff" }
                    ]
                    editor.pushToViewport()
                }
            }

            FlatButton {
                small: true
                label: "Toxic"
                onClicked: {
                    editor.styleMode = "gradient"
                    editor.stops = [
                        { position: 0.0, color: "#ff002200" },
                        { position: 0.5, color: "#ff00ff44" },
                        { position: 1.0, color: "#ffccff66" }
                    ]
                    editor.pushToViewport()
                }
            }

            FlatButton {
                small: true
                label: "Heat"
                onClicked: {
                    editor.styleMode = "gradient"
                    editor.stops = [
                        { position: 0.0, color: "#ff0a001a" },
                        { position: 0.25, color: "#ff660066" },
                        { position: 0.5, color: "#ffff2200" },
                        { position: 0.75, color: "#ffffcc00" },
                        { position: 1.0, color: "#ffffffff" }
                    ]
                    editor.pushToViewport()
                }
            }
        }

        // ── Save / Load User Presets Row ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gapTight

            FlatButton {
                small: true
                label: "Save Preset..."
                onClicked: savePresetDialog.open()
            }

            FlatButton {
                small: true
                label: "Load Preset..."
                onClicked: loadPresetDialog.open()
            }
        }
    }
}
