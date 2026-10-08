import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs

// Render queue. Each job carries its own snapshot of the session, so you can
// queue a render, keep editing, and queue another - the first still renders
// what it was when you added it. Collapsed until there is something in it.
Rectangle {
    id: panel
    required property var viewport
    // Opens itself the first time a job appears: a queue you cannot see is a
    // queue you forget you started. Still collapsible by hand afterwards.
    property bool expanded: false
    property bool autoOpened: false
    onQueueLenChanged: if (queueLen > 0 && !autoOpened) {
        expanded = true
        autoOpened = true
    }
    readonly property int queueLen: viewport.queue.length

    // Output settings for the NEXT job added. Deliberately per-job rather than
    // global: queueing several sizes of the same look is the main reason to
    // have a queue at all.
    property int  nextQuality: 0
    property var  sizes: [[1920, 1080], [1280, 720], [3840, 2160], [1080, 1080]]
    property int  sizeIdx: 0

    readonly property int pending: {
        let n = 0
        for (let i = 0; i < viewport.queue.length; ++i)
            if (viewport.queue[i].stateName === "PENDING") n += 1
        return n
    }

    color: Theme.panel
    // Only what is on screen. A closed panel is its header and nothing else.
    implicitHeight: hdr.height
                    + (expanded ? col.implicitHeight + Theme.padding * 2 : 0)
    // A closed panel used to draw its content past its own bottom edge.
    clip: true

    FileDialog {
        id: queueDialog
        title: "Queue render"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "mp4"
        nameFilters: ["MP4 (*.mp4)", "QuickTime (*.mov)"]
        onAccepted: panel.viewport.enqueueExport(
            selectedFile, panel.nextQuality,
            panel.sizes[panel.sizeIdx][0], panel.sizes[panel.sizeIdx][1], 60)
    }

    SectionHeader {
        id: hdr
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        title: "Render queue"
        hint: panel.viewport.queue.length === 0 ? ""
            : panel.viewport.queueRunning
              ? "running, " + panel.pending + " left"
              : panel.viewport.queue.length + " waiting"
        marked: panel.viewport.queueRunning
        expanded: panel.expanded
        onToggled: panel.expanded = !panel.expanded
    }

    ColumnLayout {
        id: col
        visible: panel.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: hdr.bottom
        anchors.margins: Theme.padding
        spacing: Theme.gap

        // ── settings for the next job ──
        RowLayout {
            visible: panel.expanded
            Layout.fillWidth: true
            spacing: Theme.gapTight
            FlatButton {
                label: ["High", "YouTube", "Archive", "Preview"][panel.nextQuality]
                implicitWidth: 66
                onClicked: panel.nextQuality = (panel.nextQuality + 1) % 4
            }
            FlatButton {
                label: panel.sizes[panel.sizeIdx][0] + "x"
                       + panel.sizes[panel.sizeIdx][1]
                implicitWidth: 76
                onClicked: panel.sizeIdx = (panel.sizeIdx + 1) % panel.sizes.length
            }
            Item { Layout.fillWidth: true }
            FlatButton {
                label: "+ ADD"
                onClicked: queueDialog.open()
            }
        }

        RowLayout {
            visible: panel.expanded && panel.viewport.queue.length > 0
            Layout.fillWidth: true
            spacing: Theme.gapTight
            FlatButton {
                label: panel.viewport.queueRunning ? "Stop" : "Render"
                active: panel.viewport.queueRunning
                onClicked: panel.viewport.queueRunning
                           ? panel.viewport.stopQueue()
                           : panel.viewport.startQueue()
            }
            FlatButton {
                // Abandons the render in progress; STOP only stops the queue
                // moving on to the next job.
                visible: panel.viewport.exporting
                label: "Cancel"
                onClicked: panel.viewport.cancelExport()
            }
            Item { Layout.fillWidth: true }
            FlatButton {
                label: "Clear"
                onClicked: panel.viewport.clearQueue()
            }
        }

        // ── jobs ──
        Repeater {
            model: panel.expanded ? panel.viewport.queue : []
            delegate: Rectangle {
                required property int index
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 36
                color: Theme.raised
                border.width: 1
                border.color: modelData.stateName === "RUNNING"
                              ? Theme.accent : Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padding
                    anchors.rightMargin: Theme.padding
                    spacing: Theme.gapTight

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: modelData.name
                            color: Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeSmall
                            font.weight: Font.Medium
                            elide: Text.ElideMiddle
                            Layout.maximumWidth: 150
                        }
                        Text {
                            text: modelData.width + "x" + modelData.height
                                  + "  " + modelData.fps + "fps"
                            color: Theme.textMuted
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeTiny
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: modelData.stateName === "RUNNING"
                              ? modelData.percent + "%" : modelData.stateName
                        color: modelData.stateName === "FAILED" ? Theme.danger
                             : modelData.stateName === "DONE"   ? Theme.ok
                             : modelData.stateName === "RUNNING"? Theme.accent
                             : Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeTiny
                        font.weight: Font.Medium
                        font.letterSpacing: Theme.microSpacing
                    }
                    FlatButton {
                        visible: modelData.stateName !== "RUNNING"
                        label: "✕"
                        implicitWidth: 20
                        implicitHeight: 20
                        onClicked: panel.viewport.removeJob(index)
                    }
                }

                // 6px tall progress bar at the bottom of the job row
                Rectangle {
                    visible: modelData.stateName === "RUNNING"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 4
                    color: Theme.border

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * (modelData.percent / 100)
                        color: Theme.accent
                    }
                }
            }
        }
    }
}
