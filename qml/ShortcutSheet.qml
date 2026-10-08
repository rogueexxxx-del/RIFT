import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Shortcuts drawn on a keyboard rather than listed as text. A list tells you a
// binding exists; a picture tells you where your hand goes, which is the thing
// you are actually trying to learn.
//
// The binding table is the single source: keys light up because they appear
// here, so the sheet cannot claim a shortcut the app does not have.
AppDialog {
    id: sheet
    title: "Keyboard shortcuts"
    standardButtons: Dialog.Close

    readonly property int unit: 40
    readonly property int gap: 3

    // key id -> { mod, label }. `mod` groups by modifier so the legend can
    // colour them; "" means press it on its own.
    readonly property var bind: ({
        "Space": { mod: "",      label: "play / pause" },
        "1":     { mod: "",      label: "React" },
        "2":     { mod: "",      label: "Live" },
        "N":     { mod: "ctrl",  label: "new" },
        "O":     { mod: "ctrl",  label: "open" },
        "S":     { mod: "ctrl",  label: "save" },
        "E":     { mod: "ctrl",  label: "export" },
        "Z":     { mod: "ctrl",  label: "undo" },
        "Y":     { mod: "ctrl",  label: "redo" }
    })

    function colourFor(id) {
        const b = bind[id]
        if (!b) return "#222222"
        return b.mod === "ctrl" ? Theme.accent : Theme.ok
    }
    function textFor(id) {
        const b = bind[id]
        if (!b) return "#D4D4D4"
        return "#000000"
    }

    // Each row: a list of { id, w } where w is width in key units.
    readonly property var rows: [
        [ { id: "Esc", w: 1.4 }, { id: "F1" }, { id: "F2" }, { id: "F3" },
          { id: "F4" }, { id: "F5" }, { id: "F6" }, { id: "F7" }, { id: "F8" },
          { id: "F9" }, { id: "F10" }, { id: "F11" }, { id: "F12" } ],
        [ { id: "`" }, { id: "1" }, { id: "2" }, { id: "3" }, { id: "4" },
          { id: "5" }, { id: "6" }, { id: "7" }, { id: "8" }, { id: "9" },
          { id: "0" }, { id: "-" }, { id: "=" }, { id: "Back", w: 1.8 } ],
        [ { id: "Tab", w: 1.5 }, { id: "Q" }, { id: "W" }, { id: "E" },
          { id: "R" }, { id: "T" }, { id: "Y" }, { id: "U" }, { id: "I" },
          { id: "O" }, { id: "P" }, { id: "[" }, { id: "]" }, { id: "\\", w: 1.3 } ],
        [ { id: "Caps", w: 1.8 }, { id: "A" }, { id: "S" }, { id: "D" },
          { id: "F" }, { id: "G" }, { id: "H" }, { id: "J" }, { id: "K" },
          { id: "L" }, { id: ";" }, { id: "'" }, { id: "Enter", w: 2.0 } ],
        [ { id: "Shift", w: 2.3 }, { id: "Z" }, { id: "X" }, { id: "C" },
          { id: "V" }, { id: "B" }, { id: "N" }, { id: "M" }, { id: "," },
          { id: "." }, { id: "/" }, { id: "Shift ", w: 2.5 } ],
        [ { id: "Ctrl", w: 1.5 }, { id: "Alt", w: 1.3 }, { id: "Space", w: 8 },
          { id: "Alt ", w: 1.3 }, { id: "Ctrl ", w: 1.5 } ]
    ]

    contentItem: ColumnLayout {
        spacing: Theme.groupGap

        // ── legend ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.groupGap
            Repeater {
                model: [{ c: Theme.ok,     n: "press on its own" },
                        { c: Theme.accent, n: "hold Ctrl" }]
                delegate: RowLayout {
                    required property var modelData
                    spacing: Theme.gapTight
                    Rectangle {
                        width: 14; height: 14
                        radius: Theme.radius
                        color: modelData.c
                    }
                    Text {
                        text: modelData.n
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        // ── keyboard ──
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: sheet.gap

            Repeater {
                model: sheet.rows
                delegate: Row {
                    required property var modelData
                    spacing: sheet.gap

                    Repeater {
                        model: parent.modelData
                        delegate: Rectangle {
                            id: keyRect
                            required property var modelData
                            readonly property string id: modelData.id
                            readonly property var b: sheet.bind[id]

                            width: sheet.unit * (modelData.w !== undefined
                                                 ? modelData.w : 1)
                            height: sheet.unit
                            radius: 4
                            color: sheet.colourFor(id)
                            border.width: 1
                            border.color: b ? Qt.rgba(0,0,0,0.3) : "#333333"

                            // Top subtle bevel
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.12)
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: parent.b ? 4 : 0
                                anchors.verticalCenter: parent.b ? undefined
                                                                 : parent.verticalCenter
                                text: parent.id.trim()
                                color: sheet.textFor(parent.id)
                                font.family: Theme.fontUI
                                font.pixelSize: parent.id.trim().length > 2
                                                ? Theme.sizeTiny : Theme.sizeSmall
                                font.weight: parent.b ? Font.Bold : Font.DemiBold
                            }
                            // The action, on the key itself.
                            Text {
                                visible: parent.b !== undefined
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                width: parent.width - 4
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: parent.b ? parent.b.label : ""
                                color: "#000000"
                                font.family: Theme.fontUI
                                font.pixelSize: Theme.sizeTiny
                                font.weight: Font.Bold
                            }
                        }
                    }
                }
            }
        }

        // ── things that are not single keys ──
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Theme.groupGap
            rowSpacing: 6

            Repeater {
                model: [
                    { k: "Ctrl + Shift + Z", n: "Redo" },
                    { k: "Drag a clip",      n: "Move it in time" },
                    { k: "Drag a clip edge", n: "Trim it" },
                    { k: "Drag up / down",   n: "Change its lane" },
                    { k: "Ctrl + wheel",     n: "Zoom the timeline" },
                    { k: "Wheel",            n: "Scroll the timeline" }
                ]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.gap
                    Text {
                        text: modelData.k
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.sizeSmall
                        Layout.preferredWidth: 128
                    }
                    Text {
                        text: modelData.n
                        color: Theme.textDim
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
