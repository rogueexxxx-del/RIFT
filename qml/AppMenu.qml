import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

// Top menu. Everything that is not a per-second action lives here rather than
// on a permanent panel - a new user should be able to find "open", "export" and
// "settings" without being shown where they are.
MenuBar {
    id: bar
    required property var viewport
    property var effectIds: []
    property var panelManager: null
    // Panels the shell can show/hide, owned by Main so the layout can react.
    property bool showColor: false
    property bool showQueue: false

    signal requestExit()
    signal requestPanel(string panelId)
    signal resetWorkspaceRequested()

    // The Basic style ships light grey; restate it in the app's own palette so
    // the menu does not look bolted on. The bar sits on the page colour rather
    // than the panel colour so it reads as chrome, not as another region.
    spacing: Theme.gapTight
    background: Rectangle {
        color: "transparent"
    }

    delegate: MenuBarItem {
        id: mbi
        padding: 0
        contentItem: Text {
            text: mbi.text
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            implicitWidth: mbi.contentItem.implicitWidth + Theme.padding * 2
            implicitHeight: Theme.control
            radius: Theme.radius
            color: mbi.highlighted ? Theme.hover : "transparent"
            border.width: mbi.visualFocus ? Theme.focusWidth : 0
            border.color: Theme.focusRing
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    // Named entry points so keyboard shortcuts and menu items trigger exactly
    // the same thing.
    function openProject() { openDialog.open() }
    function exportVideo() { exportDialog.open() }
    // Save straight back to the file we came from; only ask for a path when
    // there isn't one yet.
    function saveProject() {
        if (viewport.projectPath === "") saveDialog.open()
        else viewport.saveProject("file:///" + viewport.projectPath, true)
    }

    FileDialog {
        id: openDialog
        title: "Open project"
        nameFilters: ["RIFT project (*.rt)", "Legacy (*.rift *.riftproj)",
                      "All files (*)"]
        onAccepted: bar.viewport.loadProject(selectedFile)
    }
    FileDialog {
        id: saveDialog
        title: "Save project"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "rt"
        nameFilters: ["RIFT project (*.rt)"]
        onAccepted: bar.viewport.saveProject(selectedFile, true)
    }
    FileDialog {
        id: presetDialog
        title: "Save preset - look only, no clips"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "rt"
        nameFilters: ["RIFT preset (*.rt)"]
        onAccepted: bar.viewport.saveProject(selectedFile, false)
    }
    // Reachable from the transport bar too: Live mode has no timeline, so
    // there is no other way to load footage while it is on screen.
    function importMedia() { mediaDialog.open() }

    FileDialog {
        id: mediaDialog
        title: "Import video or image"
        nameFilters: ["Video/Image (*.mp4 *.mov *.mkv *.avi *.webm *.png *.jpg *.jpeg)",
                      "All files (*)"]
        onAccepted: bar.viewport.addClip(selectedFile)
    }
    FileDialog {
        id: audioDialog
        title: "Import audio"
        nameFilters: ["Audio (*.wav *.mp3 *.flac *.ogg *.m4a)", "All files (*)"]
        onAccepted: bar.viewport.loadAudio(selectedFile)
    }
    ExportDialog {
        id: exportDialog
        viewport: bar.viewport
    }
    ExportProgressDialog {
        id: exportProgress
        viewport: bar.viewport
    }
    PreferencesDialog { id: prefsDialog; viewport: bar.viewport; effectIds: bar.effectIds }

    StyledMenu {
        title: "File"
        StyledMenuItem { text: "New project"; shortcutText: "Ctrl+N"; onTriggered: bar.viewport.newProject() }
        StyledMenuItem { text: "Open…"; shortcutText: "Ctrl+O"; onTriggered: openDialog.open() }
        StyledMenuSeparator {}
        StyledMenuItem { text: "Save"; shortcutText: "Ctrl+S"; onTriggered: bar.saveProject() }
        StyledMenuItem { text: "Save as…";         onTriggered: saveDialog.open() }
        StyledMenuItem { text: "Save preset…";     onTriggered: presetDialog.open() }
        StyledMenuSeparator {}
        StyledMenuItem { text: "Import video or image…"; onTriggered: mediaDialog.open() }
        StyledMenuItem { text: "Import audio…";    onTriggered: audioDialog.open() }
        StyledMenuItem { text: "Add text layer";   onTriggered: {
            bar.viewport.addTextClip("Text", 1, 5.0)
            bar.viewport.selectClip(bar.viewport.clips.length - 1)
        } }
        StyledMenuSeparator {}
        StyledMenuItem { text: "Export video…"; shortcutText: "Ctrl+E"; onTriggered: exportDialog.open() }
        StyledMenuItem { text: "Render queue";     onTriggered: bar.requestPanel("queue") }
        StyledMenuSeparator {}
        StyledMenuItem { text: "Exit";             onTriggered: bar.requestExit() }
    }

    StyledMenu {
        title: "Edit"
        StyledMenuItem {
            text: bar.viewport.canUndo ? "Undo " + bar.viewport.undoLabel : "Undo"
            shortcutText: "Ctrl+Z"
            enabled: bar.viewport.canUndo
            onTriggered: bar.viewport.undo()
        }
        StyledMenuItem {
            text: bar.viewport.canRedo ? "Redo " + bar.viewport.redoLabel : "Redo"
            shortcutText: "Ctrl+Y"
            enabled: bar.viewport.canRedo
            onTriggered: bar.viewport.redo()
        }
        StyledMenuSeparator {}
        StyledMenuItem { text: "Detect beats"; onTriggered: bar.viewport.detectMarkers() }
        StyledMenuItem {
            text: "Snap to beats"
            checkable: true
            checked: bar.viewport.snapToMarkers
            onTriggered: bar.viewport.snapToMarkers = !bar.viewport.snapToMarkers
        }
        StyledMenuSeparator {}
        StyledMenuItem { text: "Reset effect settings"; onTriggered: bar.viewport.resetParams() }
        StyledMenuItem { text: "Reset colour";          onTriggered: bar.viewport.resetGrade() }
        StyledMenuSeparator {}
        StyledMenuItem { text: "Preferences…";          onTriggered: prefsDialog.open() }
    }

    StyledMenu {
        title: "View"
        StyledMenuItem {
            text: "React mode"
            shortcutText: "1"
            checkable: true
            checked: bar.viewport.mode === 0
            onTriggered: bar.viewport.mode = 0
        }
        StyledMenuItem {
            text: "Live mode"
            shortcutText: "2"
            checkable: true
            checked: bar.viewport.mode === 1
            onTriggered: bar.viewport.mode = 1
        }
        StyledMenuSeparator {}
        StyledMenuItem {
            text: "Colour grade"
            checkable: true
            checked: bar.panelManager ? bar.panelManager.isPanelVisible("color") : bar.showColor
            onTriggered: bar.requestPanel("color")
        }
        StyledMenuItem {
            text: "Render queue"
            checkable: true
            checked: bar.panelManager ? bar.panelManager.isPanelVisible("queue") : bar.showQueue
            onTriggered: bar.requestPanel("queue")
        }
        StyledMenuItem {
            text: "Effect chain"
            checkable: true
            checked: bar.panelManager ? bar.panelManager.isPanelVisible("effects") : false
            onTriggered: bar.requestPanel("effects")
        }
        StyledMenuItem {
            text: "Presets"
            checkable: true
            checked: bar.panelManager ? bar.panelManager.isPanelVisible("presets") : false
            onTriggered: bar.requestPanel("presets")
        }
        StyledMenuItem {
            text: "Parameters"
            checkable: true
            checked: bar.panelManager ? bar.panelManager.isPanelVisible("params") : false
            onTriggered: bar.requestPanel("params")
        }
        StyledMenuItem {
            text: "Clip inspector"
            checkable: true
            checked: bar.panelManager ? bar.panelManager.isPanelVisible("clip") : false
            onTriggered: bar.requestPanel("clip")
        }
        StyledMenuItem {
            text: "Audio input"
            checkable: true
            checked: bar.panelManager ? bar.panelManager.isPanelVisible("audio") : false
            onTriggered: bar.requestPanel("audio")
        }
        StyledMenuItem {
            text: "Preview"
            checkable: true
            checked: bar.panelManager ? bar.panelManager.isPanelVisible("preview") : false
            onTriggered: bar.requestPanel("preview")
        }
        StyledMenuItem {
            text: "Timeline"
            checkable: true
            checked: bar.panelManager ? bar.panelManager.isPanelVisible("timeline") : false
            enabled: !bar.panelManager || !bar.panelManager.live
            onTriggered: bar.requestPanel("timeline")
        }
        StyledMenuItem {
            text: "Levels"
            checkable: true
            checked: bar.panelManager ? bar.panelManager.isPanelVisible("levels") : false
            enabled: !bar.panelManager || !bar.panelManager.live
            onTriggered: bar.requestPanel("levels")
        }
        StyledMenuItem {
            text: "Controller settings"
            checkable: true
            checked: bar.panelManager ? bar.panelManager.isPanelVisible("controls") : false
            onTriggered: bar.requestPanel("controls")
        }
        StyledMenuSeparator {}
        StyledMenuItem { text: "Reset workspace"; onTriggered: bar.resetWorkspaceRequested() }
        StyledMenuSeparator {}
        StyledMenu {
            title: "Aspect ratio"
            StyledMenuItem {
                text: "16:9 (Widescreen)"
            checkable: true
            checked: bar.viewport.projectAspect === 0
                onTriggered: bar.viewport.projectAspect = 0
            }
            StyledMenuItem {
                text: "1:1 (Square)"
            checkable: true
            checked: bar.viewport.projectAspect === 1
                onTriggered: bar.viewport.projectAspect = 1
            }
            StyledMenuItem {
                text: "4:3 (Classic)"
            checkable: true
            checked: bar.viewport.projectAspect === 2
                onTriggered: bar.viewport.projectAspect = 2
            }
            StyledMenuItem {
                text: "9:16 (Vertical)"
            checkable: true
            checked: bar.viewport.projectAspect === 3
                onTriggered: bar.viewport.projectAspect = 3
            }
            StyledMenuItem {
                text: "21:9 (Ultrawide)"
            checkable: true
            checked: bar.viewport.projectAspect === 4
                onTriggered: bar.viewport.projectAspect = 4
            }
        }
    }

    StyledMenu {
        title: "Help"
        StyledMenuItem { text: "Keyboard shortcuts"; onTriggered: helpDialog.open() }
        StyledMenuItem { text: "About RIFT";         onTriggered: aboutDialog.open() }
    }

    ShortcutSheet { id: helpDialog }
    AboutDialog   { id: aboutDialog }
}
