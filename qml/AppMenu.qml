import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

// Top menu. Everything that is not a per-second action lives here rather than
// on a permanent panel - a new user should be able to find "open", "export" and
// "settings" without being shown where they are.
MenuBar {
    id: bar
    required property var viewport
    // Panels the shell can show/hide, owned by Main so the layout can react.
    property bool showColor: false
    property bool showQueue: false

    signal requestExit()

    // The Basic style ships light grey; restate it in the app's own palette so
    // the menu does not look bolted on. The bar sits on the page colour rather
    // than the panel colour so it reads as chrome, not as another region.
    spacing: 6
    background: Rectangle {
        color: "transparent"
    }

    delegate: MenuBarItem {
        id: mbi
        padding: 0
        contentItem: Text {
            text: mbi.text
            color: mbi.highlighted ? "#FFFFFF" : "#E2E2E2"
            font.family: Theme.fontUI
            font.pixelSize: 13
            font.weight: Font.Normal
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            implicitWidth: mbi.contentItem.implicitWidth + 20
            implicitHeight: 30
            radius: 4
            color: mbi.highlighted ? "#222222" : "transparent"
        }
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
    PreferencesDialog { id: prefsDialog; viewport: bar.viewport }

    StyledMenu {
        title: "File"
        MenuItem { text: "New project";      onTriggered: bar.viewport.newProject() }
        MenuItem { text: "Open…";            onTriggered: openDialog.open() }
        MenuItem { text: "Save";             onTriggered: bar.saveProject() }
        MenuItem { text: "Save as…";         onTriggered: saveDialog.open() }
        MenuItem { text: "Save preset…";     onTriggered: presetDialog.open() }
        MenuItem { text: "Import video or image…"; onTriggered: mediaDialog.open() }
        MenuItem { text: "Import audio…";    onTriggered: audioDialog.open() }
        MenuItem { text: "Add text layer";   onTriggered: {
            bar.viewport.addTextClip("Text", 1, 5.0)
            bar.viewport.selectClip(bar.viewport.clips.length - 1)
        } }
        MenuItem { text: "Export video…";    onTriggered: exportDialog.open() }
        MenuItem { text: "Render queue";     onTriggered: bar.showQueue = !bar.showQueue }
        MenuItem { text: "Exit";             onTriggered: bar.requestExit() }
    }

    StyledMenu {
        title: "Edit"
        MenuItem {
            text: bar.viewport.canUndo ? "Undo " + bar.viewport.undoLabel : "Undo"
            enabled: bar.viewport.canUndo
            onTriggered: bar.viewport.undo()
        }
        MenuItem {
            text: bar.viewport.canRedo ? "Redo " + bar.viewport.redoLabel : "Redo"
            enabled: bar.viewport.canRedo
            onTriggered: bar.viewport.redo()
        }
        MenuItem { text: "Reset effect settings"; onTriggered: bar.viewport.resetParams() }
        MenuItem { text: "Reset colour";          onTriggered: bar.viewport.resetGrade() }
        MenuItem { text: "Preferences…";          onTriggered: prefsDialog.open() }
    }

    StyledMenu {
        title: "View"
        MenuItem {
            text: (bar.viewport.mode === 0 ? "• " : "   ") + "React mode"
            onTriggered: bar.viewport.mode = 0
        }
        MenuItem {
            text: (bar.viewport.mode === 1 ? "• " : "   ") + "Live mode"
            onTriggered: bar.viewport.mode = 1
        }
        MenuItem {
            text: (bar.showColor ? "• " : "   ") + "Colour grade"
            onTriggered: bar.showColor = !bar.showColor
        }
        MenuItem {
            text: (bar.showQueue ? "• " : "   ") + "Render queue"
            onTriggered: bar.showQueue = !bar.showQueue
        }
        MenuItem { text: "Detect beats";  onTriggered: bar.viewport.detectMarkers() }
        MenuItem {
            text: (bar.viewport.snapToMarkers ? "• " : "   ") + "Snap to beats"
            onTriggered: bar.viewport.snapToMarkers = !bar.viewport.snapToMarkers
        }
        StyledMenu {
            title: "Aspect ratio"
            MenuItem {
                text: (bar.viewport.projectAspect === 0 ? "• " : "   ") + "16:9 (Widescreen)"
                onTriggered: bar.viewport.projectAspect = 0
            }
            MenuItem {
                text: (bar.viewport.projectAspect === 1 ? "• " : "   ") + "1:1 (Square)"
                onTriggered: bar.viewport.projectAspect = 1
            }
            MenuItem {
                text: (bar.viewport.projectAspect === 2 ? "• " : "   ") + "4:3 (Classic)"
                onTriggered: bar.viewport.projectAspect = 2
            }
            MenuItem {
                text: (bar.viewport.projectAspect === 3 ? "• " : "   ") + "9:16 (Vertical)"
                onTriggered: bar.viewport.projectAspect = 3
            }
            MenuItem {
                text: (bar.viewport.projectAspect === 4 ? "• " : "   ") + "21:9 (Ultrawide)"
                onTriggered: bar.viewport.projectAspect = 4
            }
        }
    }

    StyledMenu {
        title: "Help"
        MenuItem { text: "Keyboard shortcuts"; onTriggered: helpDialog.open() }
        MenuItem { text: "About RIFT";         onTriggered: aboutDialog.open() }
    }

    ShortcutSheet { id: helpDialog }
    AboutDialog   { id: aboutDialog }
}
