import QtQuick
import QtQuick.Controls
import QtQuick.Controls.FluentWinUI3 as Fluent
import QtCore
import QtQuick.Layouts
import Rift

// P4 shell. Layout mirrors the prototype's RIFTWindow (core/main_window.py):
//   top bar / [left panel | viewport + transport | params] / chain rack / status
ApplicationWindow {
    id: root
    visible: true
    visibility: Window.Maximized
    width: 1440; height: 830
    minimumWidth: 800; minimumHeight: 480
    // The project name belongs in the window title, where Windows shows it in
    // the task bar and Alt-Tab. Repeating it inside the app was spending a row
    // of the UI on something the OS already displays.
    title: viewport.projectName + " - RIFT"
    color: Theme.bg
    font.family: Theme.fontUI
    font.pixelSize: Theme.size
    palette.window: Theme.bg
    palette.windowText: Theme.text
    palette.base: Theme.sunken
    palette.alternateBase: Theme.panel
    palette.text: Theme.text
    palette.button: Theme.raised
    palette.buttonText: Theme.text
    palette.highlight: Theme.accent
    palette.highlightedText: Theme.onAccent
    palette.toolTipBase: Theme.raised
    palette.toolTipText: Theme.text
    palette.placeholderText: Theme.textMuted
    readonly property var keyboardFocus: active ? activeFocusItem : workspace.floatingFocusItem
    readonly property bool textInputFocused: keyboardFocus instanceof TextInput
        || keyboardFocus instanceof TextEdit

    required property string shaderDir
    property url assetsUrl: typeof assetsUrl !== "undefined" ? assetsUrl : ""
    // Optional preload from the command line (--media / --audio). Empty unless
    // given; lets the app open straight into a file without the dialogs.
    property string initialMedia: ""
    property string initialAudio: ""
    property string initialAnalysis: ""
    property bool   initialPlay: false
    property bool   initialLive: false     // --live: start on mic/loopback
    // "index=value" pairs from --param, for scripted/headless checks so the
    // param path can be exercised without driving the mouse.
    property var    initialParams: []
    property var    initialClips: []      // --clip PATH (repeatable), appended
    property var    initialBlends: []     // --blend IDX|MODE|OPACITY
    property var    initialKeys: []       // --key PARAM|TIME|VALUE|INTERP
    property var    initialGrade: []      // --grade INDEX=VALUE
    property string initialExport: ""     // --export PATH: render and quit
    property int initialExportWidth: 1920
    property int initialExportHeight: 1080
    property string initialChain: ""      // --chain ascii,glitch,blur
    property string initialSave: ""       // --save PATH: write project, quit
    property string initialSavePreset: "" // --savepreset NAME: write look, quit
    property string initialOpen: ""       // --open PATH: load project
    property string initialOsc: ""        // --osc PORT: listen for OSC
    property var    initialMaps: []       // --map KEY=PARAM (repeatable)
    property var    initialNodeBlends: [] // --nodeblend IDX|MODE|MIX
    property string initialQueue: ""      // --queue PATH: batch render, then quit
    property var    initialTexts: []      // --text TEXT[|LANE|SECONDS|SIZE]

    // Workspace layout is separate from project data and never owns engine state.
    // Effects offered by the picker and the chain's "+" menu. Every id needs a
    // matching <id>.frag.qsb and <id>.manifest.json in shaderDir.
    readonly property var effectIds: ["ascii", "halftone", "dither", "glitch",
                                      "pixel_sort", "oscilloscope", "datamosh",
                                      "risograph", "electron_scan", "kaleido", "flow_warp",
                                      "voronoi_shatter", "fracture", "noise_field", "dot_field", "contour",
                                      "tunnel", "lens", "prism_split", "shockwave", "bloom",
                                      "feedback", "halation_grain", "slit_scan", "post_fx"]

    Component.onCompleted: {
        if (typeof assetsUrl !== "undefined" && assetsUrl) {
            Theme.assetsUrl = assetsUrl
        }
        if (initialMedia !== "") viewport.loadMedia("file:///" + initialMedia)
        // --clip PATH  or  --clip PATH|LANE  (lane defaults to 0)
        for (let ci = 0; ci < initialClips.length; ++ci) {
            const spec = String(initialClips[ci])
            const bar = spec.lastIndexOf("|")
            const p = bar > 1 ? spec.substring(0, bar) : spec
            const ln = bar > 1 ? parseInt(spec.substring(bar + 1)) : 0
            viewport.addClip("file:///" + p, isNaN(ln) ? 0 : ln)
        }
        // --text TEXT[|LANE|SECONDS|SIZE]. After --clip so text lands on a lane
        // above the footage by default.
        for (let ti = 0; ti < initialTexts.length; ++ti) {
            const t = String(initialTexts[ti]).split("|")
            const lane = t.length > 1 ? parseInt(t[1]) : 1
            const secs = t.length > 2 ? parseFloat(t[2]) : 5.0
            viewport.addTextClip(t[0], isNaN(lane) ? 1 : lane,
                                 isNaN(secs) ? 5.0 : secs)
            if (t.length > 3) {
                const idx = viewport.clips.length - 1
                const st = viewport.clipText(idx)
                viewport.setClipTextStyle(idx, parseFloat(t[3]), st.x, st.y,
                                          st.r, st.g, st.b, st.bold,
                                          st.letterSpacing, st.wrapWidth)
            }
        }
        if (initialAudio !== "")
            viewport.loadAudio("file:///" + initialAudio,
                               initialAnalysis !== "" ? "file:///" + initialAnalysis : "")
        if (initialPlay) viewport.play()
        if (initialLive) viewport.liveInput = true
        // --grade INDEX=VALUE (order: lift gamma gain contrast sat temp tint exp)
        for (let gi = 0; gi < initialGrade.length; ++gi) {
            const kv = String(initialGrade[gi]).split("=")
            if (kv.length === 2)
                viewport.setGradeParam(parseInt(kv[0]), parseFloat(kv[1]))
        }
        // --key PARAM|TIME|VALUE|INTERP  (interp 0 linear, 1 ease, 2 step)
        for (let ki = 0; ki < initialKeys.length; ++ki) {
            const k = String(initialKeys[ki]).split("|")
            if (k.length >= 3)
                viewport.addKeyAt(parseInt(k[0]), parseFloat(k[1]),
                                  parseFloat(k[2]),
                                  k.length > 3 ? parseInt(k[3]) : 0)
        }
        // --blend IDX|MODE|OPACITY  (0 normal, 1 add, 2 multiply, 3 screen)
        for (let bi = 0; bi < initialBlends.length; ++bi) {
            const f = String(initialBlends[bi]).split("|")
            if (f.length >= 3)
                viewport.setClipBlend(parseInt(f[0]), parseInt(f[1]), parseFloat(f[2]))
        }
        console.log("[Main] initialChain =", initialChain)
        if (initialChain !== "") {
            const ids = initialChain.split(",").filter(s => s !== "")
            console.log("[Main] parsed chain ids =", JSON.stringify(ids))
            for (let i = 0; i < ids.length; ++i) {
                if (i === 0) viewport.effect = ids[0]      // replace node 0
                else viewport.addNode(ids[i])
            }
            viewport.selectedNode = 0
        }
        console.log("[Main] after chain setup, count =", viewport.chain.length)
        // AFTER --chain: switching a node's effect reloads its manifest, which
        // resets every parameter to the shader defaults. Applied before the
        // chain was built, --param was silently discarded for any effect that
        // was not already selected.
        for (let i = 0; i < initialParams.length; ++i) {
            const kv = String(initialParams[i]).split("=")
            if (kv.length === 2) viewport.setParam(parseInt(kv[0]), parseFloat(kv[1]))
        }
        // --nodeblend IDX|MODE|MIX  (mode: 0 norm 1 add 2 mult 3 scrn
        // 4 diff 5 over 6 sub). After --chain, so the nodes exist.
        for (let ni = 0; ni < initialNodeBlends.length; ++ni) {
            const nb = String(initialNodeBlends[ni]).split("|")
            if (nb.length >= 3)
                viewport.setNodeBlend(parseInt(nb[0]), parseInt(nb[1]),
                                      parseFloat(nb[2]))
        }
        // --map KEY=PARAM binds without learn mode; --osc PORT opens the
        // listener. Together they let a script drive the app over UDP with no
        // controller hardware attached.
        for (let mi = 0; mi < initialMaps.length; ++mi) {
            const m = String(initialMaps[mi])
            const eq = m.lastIndexOf("=")
            if (eq > 0) viewport.mapControl(m.substring(0, eq),
                                            parseInt(m.substring(eq + 1)))
        }
        if (initialOsc !== "") viewport.startOsc(parseInt(initialOsc))
        if (initialOpen !== "") viewport.loadProject("file:///" + initialOpen)
        if (initialSave !== "") saveKick.start()
        if (initialSavePreset !== "") presetKick.start()
        console.log("[Main] initialExport =", JSON.stringify(initialExport))
        if (initialExport !== "") exportKick.start()
        if (initialQueue !== "") queueKick.start()

        // Straight into the new-project dialog on a plain launch. Skipped
        // whenever the command line already said what to open - a scripted or
        // headless run must not stop on a dialog nobody can click.
        if (initialMedia === "" && initialAudio === "" && initialOpen === ""
            && initialClips.length === 0 && initialExport === ""
            && initialQueue === "" && initialSave === ""
            && initialSavePreset === "" && initialChain === "")
            newProjectDialog.open()
    }

    NewProjectDialog {
        id: newProjectDialog
        viewport: viewport
        onOpenExisting: appMenu.openProject()
    }


    // Window-level, so undo works wherever focus happens to be. Ctrl+Y as well
    // as Ctrl+Shift+Z: both are in common use and neither collides here.
    Shortcut {
        sequences: [StandardKey.Undo]
        context: Qt.ApplicationShortcut
        enabled: !root.textInputFocused
        onActivated: viewport.undo()
    }
    Shortcut {
        sequences: [StandardKey.Redo, "Ctrl+Y"]
        context: Qt.ApplicationShortcut
        enabled: !root.textInputFocused
        onActivated: viewport.redo()
    }
    Shortcut { sequences: [StandardKey.Save]; context: Qt.ApplicationShortcut; onActivated: appMenu.saveProject() }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; enabled: !root.textInputFocused; onActivated: viewport.playing ? viewport.pause()
                                                                  : viewport.play() }
    Shortcut { sequence: "1"; context: Qt.ApplicationShortcut; enabled: !root.textInputFocused; onActivated: viewport.mode = 0 }
    Shortcut { sequence: "2"; context: Qt.ApplicationShortcut; enabled: !root.textInputFocused; onActivated: viewport.mode = 1 }
    // These two were documented in Help before they existed. The shortcut sheet
    // draws from the same list the app binds, so it cannot drift again.
    Shortcut { sequences: [StandardKey.Open]; context: Qt.ApplicationShortcut; onActivated: appMenu.openProject() }
    Shortcut { sequence: "Ctrl+E"; context: Qt.ApplicationShortcut; onActivated: appMenu.exportVideo() }
    Shortcut { sequence: "Ctrl+N"; context: Qt.ApplicationShortcut; onActivated: viewport.newProject() }

    // Batch render. Same settle delay as --export: the engine has to exist and
    // the clips have to be in place before a job snapshots them.
    Timer {
        id: queueKick
        interval: 700
        onTriggered: {
            const ok = viewport.loadQueue("file:///" + root.initialQueue)
            console.log("[Main] loadQueue:", ok, viewport.lastError,
                        "jobs", viewport.queue.length)
            if (!ok) { Qt.quit(); return }
            viewport.startQueue()
            queueWatch.start()
        }
    }
    // Quit when the batch drains. --queue is a headless mode, so the process
    // must end on its own or the muxer never writes its trailer.
    Timer {
        id: queueWatch
        interval: 400
        repeat: true
        onTriggered: {
            if (viewport.queueRunning || viewport.exporting) return
            let done = 0, failed = 0
            for (let i = 0; i < viewport.queue.length; ++i) {
                const s = viewport.queue[i].stateName
                if (s === "DONE") done += 1
                else if (s === "FAILED") failed += 1
            }
            console.log("[Main] queue finished:", done, "done,", failed, "failed")
            stop()
            Qt.quit()
        }
    }

    // Batch save: let the engine settle so manifests and clips are in place.
    Timer {
        id: saveKick
        interval: 900
        onTriggered: {
            const ok = viewport.saveProject("file:///" + root.initialSave, true)
            console.log("[Main] saveProject:", ok, viewport.lastError)
            Qt.quit()
        }
    }

    // --savepreset NAME. Same settle delay as --save: the chain has to exist
    // before there is a look to capture out of it.
    Timer {
        id: presetKick
        interval: 900
        onTriggered: {
            const ok = viewport.savePresetNamed(root.initialSavePreset)
            console.log("[Main] savePresetNamed:", ok, viewport.lastError)
            Qt.quit()
        }
    }

    // Give the viewport a frame to build its engine before exporting, so the
    // chain and sources are in place.
    Timer {
        id: exportKick
        interval: 700
        onTriggered: {
            console.log("[Main] startExport ->", root.initialExport)
            const norm = root.initialExport.replace(/\\/g, "/")
            viewport.startExport(norm.startsWith("file:") ? norm : ("file:///" + norm), 0,
                                 root.initialExportWidth, root.initialExportHeight, 60)
        }
    }

    // Batch mode: --export renders and quits, so the run terminates on its own
    // and the muxer gets to write its trailer. Killing it early leaves a file
    // with no moov atom.
    Connections {
        target: viewport
        function onExportChanged() {
            if (root.initialExport === "") return
            console.log("[Main] export:", viewport.exportStatus)
            if (!viewport.exporting && viewport.exportStatus !== "" &&
                viewport.exportStatus !== "starting")
                Qt.quit()
        }
    }


    ColumnLayout {
        id: rootLayout
        anchors.fill: parent
        spacing: 0

        // ── Top Header Bar (matches Figma 3_37.png) ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            color: Theme.panel

            // Left: Embedded Menu Bar (File, Edit, View, Help)
            AppMenu {
                id: appMenu
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                viewport: viewport
                effectIds: root.effectIds
                panelManager: workspace
                onRequestExit: Qt.quit()
                onRequestPanel: (panelId) => workspace.togglePanel(panelId)
                onResetWorkspaceRequested: workspace.resetLayout()
                showColor: workspace.isPanelActive("color")
                showQueue: workspace.isPanelActive("queue")
            }

            // Center: RIFT Monogram Logo (just the logo, not full text)
            Image {
                id: monogramLogo
                visible: root.width >= 1008
                anchors.centerIn: parent
                source: Theme.monogram
                height: 32
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            // Bottom hairline seam
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.hairline
            }

            // Borderless mode controls share one icon and text baseline.
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                height: 40
                width: modeRow.implicitWidth + 8
                radius: Theme.radius
                color: "transparent"
                border.width: 0

                Row {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: Theme.gap

                    // REACT segment
                    Rectangle {
                        id: reactSegment
                        height: 32
                        width: reactContent.implicitWidth + 16
                        radius: Theme.radius
                        color: reactHover.hovered ? Theme.hover : "transparent"
                        activeFocusOnTab: true
                        border.width: activeFocus ? Theme.focusWidth : 0
                        border.color: Theme.focusRing
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: "React mode"
                        Accessible.checked: viewport.mode === 0
                        Accessible.onPressAction: viewport.mode = 0
                        Keys.onSpacePressed: viewport.mode = 0
                        Keys.onReturnPressed: viewport.mode = 0

                        Row {
                            id: reactContent
                            anchors.centerIn: parent
                            height: 18
                            spacing: Theme.gap

                            Canvas {
                                id: reactIcon
                                width: 18; height: 18
                                anchors.verticalCenter: parent.verticalCenter
                                property color ink: viewport.mode === 0 ? Theme.text : Theme.textMuted
                                onInkChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.reset()
                                    ctx.strokeStyle = ink
                                    ctx.lineWidth = 1.5
                                    ctx.lineCap = "round"
                                    ctx.beginPath()
                                    ctx.moveTo(2, 10)
                                    ctx.lineTo(5, 6)
                                    ctx.lineTo(8, 13)
                                    ctx.lineTo(12, 4)
                                    ctx.lineTo(16, 9)
                                    ctx.stroke()
                                }
                                Connections {
                                    target: viewport
                                    function onModeChanged() { reactIcon.requestPaint() }
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "React"
                                color: viewport.mode === 0 ? Theme.text : Theme.textMuted
                                font.family: Theme.fontUI
                                font.pixelSize: Theme.size
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.6
                            }
                        }

                        HoverHandler { id: reactHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: viewport.mode = 0 }
                        ToolTipArea { text: "React Mode: Timeline editing, audio modulation & export (1)" }
                    }

                    // LIVE segment
                    Rectangle {
                        id: liveSegment
                        height: 32
                        width: liveContent.implicitWidth + 16
                        radius: Theme.radius
                        color: liveHover.hovered ? Theme.hover : "transparent"
                        activeFocusOnTab: true
                        border.width: activeFocus ? Theme.focusWidth : 0
                        border.color: Theme.focusRing
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: "Live mode"
                        Accessible.checked: viewport.mode === 1
                        Accessible.onPressAction: viewport.mode = 1
                        Keys.onSpacePressed: viewport.mode = 1
                        Keys.onReturnPressed: viewport.mode = 1

                        Row {
                            id: liveContent
                            anchors.centerIn: parent
                            height: 18
                            spacing: Theme.gap

                            // Live beacon indicator
                            Rectangle {
                                width: 18; height: 18; radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                color: "transparent"

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 8; height: 8; radius: 4
                                    color: viewport.mode === 1 ? Theme.danger : Theme.textMuted
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Live"
                                color: viewport.mode === 1 ? Theme.text : Theme.textMuted
                                font.family: Theme.fontUI
                                font.pixelSize: Theme.size
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.6
                            }
                        }

                        HoverHandler { id: liveHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: viewport.mode = 1 }
                        ToolTipArea { text: "Live Mode: Real-time performance with MIDI controller / OSC (2)" }
                    }
                }
            }
        }

        DockWorkspace {
            id: workspace
            objectName: "workspace"
            Layout.fillWidth: true
            Layout.fillHeight: true
            live: viewport.mode === 1
            onPanelActionRequested: (panelId) => {
                if (panelId === "effects") nodeRail.openAdd()
                else if (panelId === "presets") presetRail.openSavePreset()
            }
            panels: ({ effects: nodeRail, presets: presetRail, preview: previewPanel,
                params: paramPanel, clip: clipInspector, color: colorPanel, queue: queuePanel,
                timeline: timelinePanel, levels: channelMeters, controls: controlPanel,
                audio: audioInputPanel })

            NodeRail {
                id: nodeRail
                parent: workspace.parkingItem
                anchors.fill: parent
                viewport: viewport
                effectIds: root.effectIds
                onNodeSelected: (idx) => workspace.showPanel("params")
            }
            NodeRail {
                id: presetRail
                parent: workspace.parkingItem
                anchors.fill: parent
                currentTab: 1
                viewport: viewport
                effectIds: root.effectIds
            }
            ColumnLayout {
                id: previewPanel
                parent: workspace.parkingItem
                anchors.fill: parent
                spacing: 0
                clip: true
                Item {
                    id: viewportContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // Preserve the composition aspect without a black editor surround.
                    Rectangle { anchors.fill: parent; color: Theme.panel }
                    RiftViewport {
                        id: viewport
                        readonly property real displayAspect: [16 / 9, 1, 4 / 3, 9 / 16, 21 / 9][projectAspect] || 16 / 9
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height * displayAspect)
                        height: Math.min(parent.height, parent.width / displayAspect)
                        shaderDir: root.shaderDir
                    }
                    // Viewport HUD and interactive transform overlay
                    ViewportOverlay { anchors.fill: viewport; viewport: viewport }
                    Column {
                        objectName: "emptyPreviewGuidance"
                        anchors.centerIn: parent
                        width: Math.max(0, Math.min(320, parent.width - 24))
                        spacing: Theme.gap
                        visible: viewport.mode === 0 && !viewport.hasMedia && viewport.clips.length === 0
                            && parent.height >= implicitHeight + 16
                        Text {
                            width: parent.width
                            text: "Start with media"
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            color: Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeTitle
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: "Add a video or image to start editing."
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            color: Theme.textDim
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.size
                        }
                        FlatButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            label: "Add clip"
                            onClicked: appMenu.importMedia()
                        }
                    }
                }
                TransportBar { Layout.fillWidth: true; viewport: viewport }
            }
            ParamPanel {
                id: paramPanel
                parent: workspace.parkingItem
                anchors.fill: parent
                viewport: viewport
                onChannelPicked: (ch) => channelMeters.highlight = ch
            }
            ClipInspector {
                id: clipInspector
                parent: workspace.parkingItem
                anchors.fill: parent
                viewport: viewport
            }
            ColorPanel {
                id: colorPanel
                parent: workspace.parkingItem
                anchors.fill: parent
                viewport: viewport
                onChannelPicked: (ch) => channelMeters.highlight = ch
            }
            QueuePanel {
                id: queuePanel
                parent: workspace.parkingItem
                anchors.fill: parent
                viewport: viewport
            }
            TimelinePanel {
                id: timelinePanel
                parent: workspace.parkingItem
                anchors.fill: parent
                viewport: viewport
                shortcutsSuspended: workspace.dragPanel !== ""
            }
            ChannelMeters {
                id: channelMeters
                parent: workspace.parkingItem
                anchors.fill: parent
                viewport: viewport
            }
            ControlPanel {
                id: controlPanel
                parent: workspace.parkingItem
                anchors.fill: parent
                viewport: viewport
            }
            AudioInputPanel {
                id: audioInputPanel
                parent: workspace.parkingItem
                anchors.fill: parent
                viewport: viewport
            }
        }

        // Live only: your controller, and the transport/input strip under it.
        RowLayout {
            id: liveControllerRow
            Layout.fillWidth: true
            visible: viewport.mode === 1
            Layout.minimumHeight: 120
            Layout.preferredHeight: Math.min(controllerView.implicitHeight, root.height * 0.34)
            Layout.maximumHeight: liveControllerRow.Layout.preferredHeight
            spacing: 0

            ControllerView {
                id: controllerView
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                Layout.fillHeight: true
                viewport: viewport
            }
            MappingList {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                Layout.fillHeight: true
                viewport: viewport
            }
        }
        LiveBar {
            Layout.fillWidth: true
            visible: viewport.mode === 1
            viewport: viewport
        }
    }

    // Vintage modern film grain overlay
    Image {
        anchors.fill: parent
        source: Theme.asset("grain.png")
        fillMode: Image.Tile
        opacity: 0.035
        z: 9999
        enabled: false
    }
}


