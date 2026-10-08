import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

// Appearance settings. Presets plus an accent, not a colour well per surface -
// a dozen independent pickers is how a UI ends up unreadable, and the tones in
// a preset are chosen to hold their contrast against each other.
// "Custom surfaces" is there for people who want it anyway.
AppDialog {
    id: dlg
    title: "Preferences"
    width: 480
    standardButtons: Dialog.Close

    required property var viewport
    property bool advanced: false

    // Persisted across runs. Written on change, read at startup.
    Settings {
        id: prefs
        category: "appearance"
        property string preset: "dark"
        property string accent: "#E8442E"
        property real   scale: 1.0
        // "" means the bundled Geist stack; anything else is a family the user
        // picked out of the fonts installed on this machine.
        property string uiFont: ""
    }

    Component.onCompleted: {
        Theme.applyPreset(prefs.preset)
        Theme.applyScale(prefs.scale)
        Theme.accent = prefs.accent
        if (prefs.uiFont !== "") Theme.fontUI = prefs.uiFont
    }

    readonly property var accents: [
        "#E8442E", "#F5A524", "#4ADE80", "#38BDF8",
        "#A78BFA", "#F472B6", "#E5E5E5"
    ]

    contentItem: ColumnLayout {
        spacing: Theme.groupGap

        // ── theme ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            Text {
                text: "Theme"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap
                Repeater {
                    model: [{ k: "dark",     n: "Dark" },
                            { k: "darker",   n: "Darker" },
                            { k: "contrast", n: "High contrast" },
                            { k: "light",    n: "Light" }]
                    delegate: FlatButton {
                        required property var modelData
                        label: modelData.n
                        active: Theme.preset === modelData.k
                        onClicked: {
                            Theme.applyPreset(modelData.k)
                            prefs.preset = modelData.k
                        }
                    }
                }
            }
        }

        // ── accent ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            Text {
                text: "Accent"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap
                Repeater {
                    model: dlg.accents
                    delegate: Rectangle {
                        required property string modelData
                        width: 34; height: 26
                        radius: Theme.radius
                        color: modelData
                        border.width: Theme.accent === modelData ? 2 : 1
                        border.color: Theme.accent === modelData ? Theme.text
                                                                 : Theme.hairline
                        TapHandler {
                            onTapped: {
                                Theme.accent = parent.modelData
                                prefs.accent = parent.modelData
                            }
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }

        // ── text size ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            Text {
                text: "Text size"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap
                Repeater {
                    model: [{ s: 0.9,  n: "Small" },
                            { s: 1.0,  n: "Default" },
                            { s: 1.15, n: "Large" },
                            { s: 1.3,  n: "Largest" }]
                    delegate: FlatButton {
                        required property var modelData
                        label: modelData.n
                        active: Math.abs(Theme.textScale - modelData.s) < 0.01
                        onClicked: {
                            Theme.applyScale(modelData.s)
                            prefs.scale = modelData.s
                        }
                    }
                }
            }
        }

        // ── interface font ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            Text {
                text: "Interface font"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap

                FontPicker {
                    id: fontPick
                    Layout.fillWidth: true
                    fonts: dlg.viewport.systemFonts()
                    defaultLabel: "Geist (bundled)"
                    selected: prefs.uiFont
                    onPicked: function (family) {
                        prefs.uiFont = family
                        Theme.fontUI = family === ""
                            ? "Geist, Segoe UI, sans-serif" : family
                    }
                }

                FlatButton {
                    label: "Restart app"
                    onClicked: dlg.viewport.restartApp()
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "The font changes straight away. Restart if you want every "
                    + "panel remeasured against it - save your project first."
                color: Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeTiny
            }
        }

        // ── per-area colours ──
        FlatButton {
            label: dlg.advanced ? "Hide custom surfaces" : "Custom surfaces…"
            onClicked: dlg.advanced = !dlg.advanced
        }
        GridLayout {
            visible: dlg.advanced
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Theme.gap
            rowSpacing: 6

            Repeater {
                model: [{ n: "Page background", p: "bg" },
                        { n: "Panels",          p: "panel" },
                        { n: "Controls",        p: "raised" },
                        { n: "Text",            p: "text" },
                        { n: "Dimmed text",     p: "textDim" },
                        { n: "Seams",           p: "hairline" }]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.gap
                    Text {
                        text: modelData.n
                        color: Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        Layout.preferredWidth: 110
                    }
                    Rectangle {
                        implicitWidth: 60
                        implicitHeight: 22
                        radius: Theme.radius
                        color: Theme[modelData.p]
                        border.width: 1
                        border.color: Theme.hairline
                    }
                    // Typed rather than a colour wheel: a hex field is exact,
                    // and these are values people copy from a palette.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 22
                        color: Theme.sunken
                        border.color: hexIn.activeFocus ? Theme.accent : Theme.hairline
                        TextInput {
                            id: hexIn
                            anchors.fill: parent
                            anchors.margins: 4
                            text: String(Theme[modelData.p])
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.sizeSmall
                            selectByMouse: true
                            onEditingFinished: {
                                if (/^#[0-9a-fA-F]{6}$/.test(text))
                                    Theme[modelData.p] = text
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Custom surface colours apply now but are not saved with the "
                + "preset - pick a preset again to get back to a known-good set."
            color: Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeTiny
            visible: dlg.advanced
        }
    }
}
