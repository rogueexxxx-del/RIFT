import QtQuick
import QtQuick.Controls
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
    minimumWidth: 1180; minimumHeight: 700
    // The project name belongs in the window title, where Windows shows it in
    // the task bar and Alt-Tab. Repeating it inside the app was spending a row
    // of the UI on something the OS already displays.
    title: viewport.projectName + " - RIFT"
    color: Theme.bg

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
    property string initialChain: ""      // --chain ascii,glitch,blur
    property string initialSave: ""       // --save PATH: write project, quit
    property string initialSavePreset: "" // --savepreset NAME: write look, quit
    property string initialOpen: ""       // --open PATH: load project
    property string initialOsc: ""        // --osc PORT: listen for OSC
    property var    initialMaps: []       // --map KEY=PARAM (repeatable)
    property var    initialNodeBlends: [] // --nodeblend IDX|MODE|MIX
    property string initialQueue: ""      // --queue PATH: batch render, then quit
    property var    initialTexts: []      // --text TEXT[|LANE|SECONDS|SIZE]

    // Which side each dock sits on. Persisted, so an arrangement someone
    // sets up survives a restart.
    //
    // ONE flag, with both sides derived from it - not two independent strings.
    // The swap used to assign effectsSide and then settingsSide, and QML
    // bindings re-evaluate on the FIRST assignment: in between the two, both
    // docks read "right", both resolved to GridLayout column 2, and two items
    // claiming one cell makes the layout place the second somewhere else
    // entirely. That is why a shifted dock would not stay put. Deriving both
    // from a single property means they can never disagree, even momentarily.
    property bool docksSwapped: false
    property int rightDockTab: 0
    readonly property string effectsSide:  docksSwapped ? "right" : "left"
    readonly property string settingsSide: docksSwapped ? "left"  : "right"
    Settings {
        category: "layout"
        property alias docksSwapped: root.docksSwapped
    }
    function swapDocks() { docksSwapped = !docksSwapped }
    // Effects offered by the picker and the chain's "+" menu. Every id needs a
    // matching <id>.frag.qsb and <id>.manifest.json in shaderDir.
    readonly property var effectIds: ["ascii", "halftone", "dither", "glitch",
                                      "pixel_sort", "blur", "oscilloscope",
                                      "datamosh", "cyanotype", "risograph",
                                      "thermal", "terminal", "electron_scan",
                                      "kaleido", "mirror_tile", "flow_warp",
                                      "voronoi_shatter", "dot_field",
                                      "tunnel", "lens", "bloom",
                                      "feedback", "slit_scan", "post_fx"]

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
        onActivated: viewport.undo()
    }
    Shortcut {
        sequences: [StandardKey.Redo, "Ctrl+Y"]
        onActivated: viewport.redo()
    }
    Shortcut { sequences: [StandardKey.Save]; onActivated: appMenu.saveProject() }
    Shortcut { sequence: "Space";   onActivated: viewport.playing ? viewport.pause()
                                                                  : viewport.play() }
    Shortcut { sequence: "1";       onActivated: viewport.mode = 0 }
    Shortcut { sequence: "2";       onActivated: viewport.mode = 1 }
    // These two were documented in Help before they existed. The shortcut sheet
    // draws from the same list the app binds, so it cannot drift again.
    Shortcut { sequences: [StandardKey.Open]; onActivated: appMenu.openProject() }
    Shortcut { sequence: "Ctrl+E";  onActivated: appMenu.exportVideo() }
    Shortcut { sequence: "Ctrl+N";  onActivated: viewport.newProject() }

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
            viewport.startExport(norm.startsWith("file:") ? norm : ("file:///" + norm), 0)
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
        anchors.fill: parent
        spacing: 0

        // ── Top Header Bar (matches Figma 3_37.png) ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 46
            color: "#000000"

            // Left: Embedded Menu Bar (File, Edit, View, Help)
            AppMenu {
                id: appMenu
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                viewport: viewport
                onRequestExit: Qt.quit()
            }

            // Center: RIFT Monogram Logo (just the logo, not full text)
            Image {
                id: monogramLogo
                anchors.centerIn: parent
                source: Theme.monogram
                height: 32
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            // Right side: Mode Switcher [ REACT.svg | LIVE.svg ]
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                // REACT Button (Custom SVG icon from assets/figma icons)
                Item {
                    id: reactBtn
                    width: 36
                    height: 28
                    opacity: viewport.mode === 0 ? 1.0 : (reactHover.hovered ? 0.6 : 0.35)

                    Image {
                        anchors.fill: parent
                        source: Theme.asset("figma icons/REACT.svg")
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    HoverHandler { id: reactHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: viewport.mode = 0 }
                    ToolTipArea { text: "React Mode: Edit timeline, patch audio, export" }
                }

                // LIVE Button (Custom SVG icon from assets/figma icons)
                Item {
                    id: liveBtn
                    width: 28
                    height: 28
                    opacity: viewport.mode === 1 ? 1.0 : (liveHover.hovered ? 0.6 : 0.35)

                    Image {
                        anchors.fill: parent
                        source: Theme.asset("figma icons/LIVE.svg")
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    HoverHandler { id: liveHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: viewport.mode = 1 }
                    ToolTipArea { text: "Live Mode: Perform with MIDI controller / OSC" }
                }
            }
        }

        // ── centre row ──
        // GridLayout, not RowLayout: a dock names the column it sits in, so
        // swapping sides is a property change instead of reparenting.
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 3
            columnSpacing: 0
            rowSpacing: 0

            // Left dock: the effect chain and the audio meters. Named and
            // collapsible so the picture can take the whole window.
            Dock {
                id: leftDock
                title: nodeRail.currentTab === 0 ? "Effect Chain" : "Presets"
                tabs: ["Effect Chain", "Presets"]
                currentTab: nodeRail.currentTab
                onTabClicked: (idx) => nodeRail.currentTab = idx
                side: root.effectsSide
                handleEdge: side === "left" ? "right" : "left"
                actionText: "+"
                onActionTriggered: {
                    if (nodeRail.currentTab === 0) nodeRail.openAdd()
                    else nodeRail.openSavePreset()
                }
                onTitleClicked: {
                    nodeRail.currentTab = (nodeRail.currentTab === 0 ? 1 : 0)
                }
                Layout.row: 0
                Layout.column: side === "left" ? 0 : 2
                expandedWidth: 260
                minWidth: 210

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    NodeRail {
                        id: nodeRail
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        viewport: viewport
                        effectIds: root.effectIds
                        onNodeSelected: (idx) => root.rightDockTab = 0
                    }
                }
            }

            ColumnLayout {
                Layout.row: 0
                Layout.column: 1
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 200
                spacing: 0
                Item {
                    id: viewportContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // Dark letterbox/pillarbox background behind framed render
                    Rectangle {
                        anchors.fill: parent
                        color: "#050507"
                    }

                    RiftViewport {
                        id: viewport
                        anchors.fill: parent
                        shaderDir: root.shaderDir
                    }

                    // Viewport HUD and interactive transform overlay
                    ViewportOverlay {
                        anchors.fill: parent
                        viewport: viewport
                    }
                }
                TransportBar {
                    Layout.fillWidth: true
                    viewport: viewport
                    onImportRequested: appMenu.importMedia()
                }
            }

            // Right dock: Tab switcher between Parameters, Clip, Color, and Queue
            Dock {
                id: rightDock
                title: root.rightDockTab === 0 ? "Parameters" : (root.rightDockTab === 1 ? "Clip" : (root.rightDockTab === 2 ? "Color" : "Queue"))
                tabs: ["Params", "Clip", "Color", "Queue"]
                currentTab: root.rightDockTab
                onTabClicked: (idx) => root.rightDockTab = idx
                side: root.settingsSide
                handleEdge: side === "left" ? "right" : "left"
                actionText: ""
                onTitleClicked: {
                    root.rightDockTab = (root.rightDockTab + 1) % 4
                }
                Layout.row: 0
                Layout.column: side === "left" ? 0 : 2
                expandedWidth: 330
                minWidth: 280
                maxWidth: 560

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    ParamPanel {
                        id: paramPanel
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: (viewport.mode === 1) || (viewport.mode === 0 && root.rightDockTab === 0)
                        viewport: viewport
                        onChannelPicked: (ch) => channelMeters.highlight = ch
                    }

                    ClipInspector {
                        id: clipInspector
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: viewport.mode === 0 && root.rightDockTab === 1
                        viewport: viewport
                    }

                    // Live first: this is the panel you reach for on stage.
                    ControlPanel {
                        Layout.fillWidth: true
                        visible: viewport.mode === 1
                        viewport: viewport
                    }
                    // Audio source second in Live
                    AudioInputPanel {
                        Layout.fillWidth: true
                        visible: viewport.mode === 1
                        viewport: viewport
                    }

                    ColorPanel {
                        id: colorPanel
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: viewport.mode === 0 && root.rightDockTab === 2
                        viewport: viewport
                        onChannelPicked: (ch) => channelMeters.highlight = ch
                    }

                    QueuePanel {
                        id: queuePanel
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: viewport.mode === 0 && root.rightDockTab === 3
                        viewport: viewport
                    }
                }
            }
        }

        // ── timeline & channel meters (matches Figma 7_123.png) ──
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            Layout.maximumHeight: 250
            Layout.fillHeight: false
            visible: viewport.mode === 0
            spacing: 0

            TimelinePanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                viewport: viewport
            }

            ChannelMeters {
                id: channelMeters
                Layout.preferredWidth: rightDock.width
                Layout.fillHeight: true
                viewport: viewport
            }
        }

        // Live only: your controller, and the transport/input strip under it.
        RowLayout {
            Layout.fillWidth: true
            visible: viewport.mode === 1
            Layout.preferredHeight: controllerView.implicitHeight
            Layout.maximumHeight: controllerView.implicitHeight
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


