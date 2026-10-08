import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// Pick what you are rendering before picking where to put it. Resolution used
// to be pinned to 1080p in code, so 4K existed in the engine but nothing in the
// UI could ask for it.
AppDialog {
    id: dlg
    required property var viewport

    title: "Export video"
    width: 380
    standardButtons: Dialog.Cancel

    // Defaults to the shape the project was started in, so an export does not
    // silently reframe work that was composed for something else.
    property int ratioIdx: dlg.viewport ? dlg.viewport.projectAspect : 0
    property int sizeIdx: 0
    property int qualIdx: 0
    // 30, not 60. Sixty doubles both the render time and the file size, and
    // almost nothing here is delivered at 60.
    property int fpsIdx: 1
    property bool includeWatermark: true

    // Aspect first, then a height within it. Picking "4K" and "1:1" separately
    // is how people actually think about a delivery, and it beats a flat list
    // that has to enumerate every combination.
    readonly property var ratios: [
        { label: "16:9",  w: 16, h: 9  },
        { label: "1:1",   w: 1,  h: 1  },
        { label: "4:3",   w: 4,  h: 3  },
        { label: "9:16",  w: 9,  h: 16 },
        { label: "21:9",  w: 21, h: 9  }
    ]
    // Named by the SHORT side so the name means the same in every aspect.
    readonly property var heights: [
        { label: "720",  v: 720  },
        { label: "1080", v: 1080 },
        { label: "1440", v: 1440 },
        { label: "2160 (4K)", v: 2160 }
    ]

    readonly property int outH: heights[sizeIdx].v
    readonly property int outW: {
        const r = ratios[ratioIdx]
        // Even numbers only - the encoders mask the low bit anyway, and an odd
        // width silently changes the aspect.
        return Math.round(outH * r.w / r.h / 2) * 2
    }
    // Order matches rift_export_quality.
    readonly property var quals: [
        { label: "High - best H.264",        hint: "for delivery and upload" },
        { label: "YouTube - smaller file",   hint: "good enough for streaming" },
        { label: "Archive - ProRes 422 10-bit", hint: "huge, for further editing" },
        { label: "Preview - fast and rough", hint: "to check timing" }
    ]
    readonly property var fpsList: [24, 30, 60]

    FileDialog {
        id: fileDialog
        title: "Export video"
        fileMode: FileDialog.SaveFile
        defaultSuffix: dlg.qualIdx === 2 ? "mov" : "mp4"
        nameFilters: dlg.qualIdx === 2 ? ["QuickTime (*.mov)"]
                                       : ["MP4 (*.mp4)", "QuickTime (*.mov)"]
        onAccepted: {
            dlg.viewport.startExport(selectedFile, dlg.qualIdx,
                                     dlg.outW, dlg.outH,
                                     dlg.fpsList[dlg.fpsIdx],
                                     !dlg.includeWatermark)
            dlg.close()
        }
    }

    contentItem: ColumnLayout {
        spacing: Theme.gap

        Text {
            text: "Aspect ratio"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            Repeater {
                model: dlg.ratios
                delegate: FlatButton {
                    required property int index
                    required property var modelData
                    label: modelData.label
                    active: dlg.ratioIdx === index
                    onClicked: dlg.ratioIdx = index
                }
            }
        }

        Text {
            text: "Size"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            Repeater {
                model: dlg.heights
                delegate: FlatButton {
                    required property int index
                    required property var modelData
                    label: modelData.label
                    active: dlg.sizeIdx === index
                    onClicked: dlg.sizeIdx = index
                }
            }
        }

        // What you will actually get, so the two choices above are unambiguous.
        Text {
            text: dlg.outW + " x " + dlg.outH + "  ·  "
                  + dlg.fpsList[dlg.fpsIdx] + " fps"
            color: Theme.accent
            font.family: Theme.fontMono
            font.pixelSize: Theme.size
        }

        Text {
            text: "Quality"
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
        }
        Repeater {
            model: dlg.quals
            delegate: FlatButton {
                required property int index
                required property var modelData
                Layout.fillWidth: true
                label: modelData.label
                active: dlg.qualIdx === index
                onClicked: dlg.qualIdx = index
                ToolTipArea { text: modelData.hint }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            Text {
                text: "Frame rate"
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }
            Repeater {
                model: dlg.fpsList
                delegate: FlatButton {
                    required property int index
                    required property int modelData
                    label: modelData + " fps"
                    implicitWidth: 66
                    active: dlg.fpsIdx === index
                    onClicked: dlg.fpsIdx = index
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            Text {
                text: "Watermark"
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }
            Item { Layout.fillWidth: true }
            FlatButton {
                label: dlg.includeWatermark ? "Watermark: Included" : "Watermark: None"
                active: !dlg.includeWatermark
                tip: dlg.includeWatermark ? "Click to remove watermark from render" : "Watermark disabled for this export"
                onClicked: dlg.includeWatermark = !dlg.includeWatermark
            }
        }

        FlatButton {
            Layout.fillWidth: true
            label: "Choose file and export"
            active: true
            onClicked: fileDialog.open()
        }
    }
}
