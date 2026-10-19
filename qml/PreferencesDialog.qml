import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

// Appearance settings. Presets plus an accent, not a colour well per surface -
// a dozen independent pickers is how a UI ends up unreadable, and the tones in
// a preset are chosen to hold their contrast against each other.
// "Custom surfaces" is there for people who want it anyway.
AppDialog {
    id: dlg
    title: "Preferences"
    width: Math.min(620, Overlay.overlay ? Overlay.overlay.width - Theme.groupGap * 2 : 620)
    standardButtons: Dialog.Close

    required property var viewport
    property var effectIds: []
    property bool advanced: false
    property bool pickingChannel: false
    property string pickingKey: ""

    function saveColor(channel, key, value) {
        if (channel) {
            Theme.setChannelColor(key, value)
            prefs.channelColorsJson = JSON.stringify(Theme.channelColorOverrides)
        } else {
            Theme.setEffectColor(key, value)
            prefs.effectColorsJson = JSON.stringify(Theme.effectColorOverrides)
        }
    }

    ColorDialog {
        id: colorPicker
        title: "Choose color"
        onAccepted: dlg.saveColor(dlg.pickingChannel, dlg.pickingKey,
                                  selectedColor.toString())
    }

    // Persisted across runs. Written on change, read at startup.
    Settings {
        id: prefs
        category: "appearance"
        property string preset: "system"
        property string accent: "#E8442E"
        property real   scale: 1.0
        // "" means the Windows UI face; anything else is a family the user
        // picked out of the fonts installed on this machine.
        property string uiFont: ""
        property string effectColorsJson: "{}"
        property string channelColorsJson: "{}"
    }

    Component.onCompleted: {
        Theme.applyPreset(prefs.preset)
        Theme.applyScale(prefs.scale)
        Theme.accent = prefs.accent
        if (prefs.uiFont !== "") Theme.fontUI = prefs.uiFont
        try { Theme.effectColorOverrides = JSON.parse(prefs.effectColorsJson) || ({}) }
        catch (e) { Theme.effectColorOverrides = ({}) }
        try { Theme.channelColorOverrides = JSON.parse(prefs.channelColorsJson) || ({}) }
        catch (e) { Theme.channelColorOverrides = ({}) }
    }

    readonly property var accents: [
        "#E8442E", "#F5A524", "#4ADE80", "#38BDF8",
        "#A78BFA", "#F472B6", "#E5E5E5"
    ]

    contentItem: ScrollView {
        id: formScroll
        objectName: "preferencesScroll"
        clip: true
        implicitHeight: form.implicitHeight
        contentWidth: availableWidth
        contentHeight: form.implicitHeight
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AlwaysOn

        ColumnLayout {
        id: form
        width: formScroll.availableWidth - Theme.groupGap
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
                    model: [{ k: "system",   n: "System" },
                            { k: "dark",     n: "Dark" },
                            { k: "darker",   n: "Darker" },
                            { k: "contrast", n: "High contrast" },
                            { k: "light",    n: "Light" }]
                    delegate: FlatButton {
                        required property var modelData
                        label: modelData.n
                        objectName: "theme-" + modelData.k
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
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: "Accent " + modelData
                        border.width: activeFocus ? Theme.focusWidth : (Theme.accent === modelData ? 2 : 1)
                        border.color: activeFocus ? Theme.focusRing : Theme.accent === modelData ? Theme.text
                                                                 : Theme.hairline
                        function choose() {
                            Theme.accent = modelData
                            prefs.accent = modelData
                        }
                        Keys.onSpacePressed: choose()
                        Keys.onReturnPressed: choose()
                        TapHandler {
                            onTapped: parent.choose()
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
                text: "Node and audio colors"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }
            Repeater {
                model: [
                    { label: "Effect node", keys: dlg.effectIds, channel: false },
                    { label: "Audio parameter", keys: dlg.viewport.channelNames.map(c => c.name), channel: true }
                ]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.gap

                    Text {
                        text: modelData.label
                        color: Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        Layout.preferredWidth: 105
                    }
                    ComboBox {
                        id: colorTarget
                        Layout.fillWidth: true
                        model: modelData.keys
                        contentItem: Text {
                            leftPadding: 8
                            text: Theme.nice(colorTarget.currentText)
                            color: Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeSmall
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: Theme.raised
                            border.width: 1
                            border.color: Theme.border
                        }
                    }
                    Rectangle {
                        width: 36
                        height: 24
                        color: modelData.channel
                               ? Theme.channelColor(colorTarget.currentText)
                               : Theme.effectColor(colorTarget.currentText)
                        border.width: 1
                        border.color: Theme.textDim
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                dlg.pickingChannel = modelData.channel
                                dlg.pickingKey = colorTarget.currentText
                                colorPicker.selectedColor = parent.color
                                colorPicker.open()
                            }
                        }
                        ToolTipArea { text: "Choose color" }
                    }
                    FlatButton {
                        plain: true
                        small: true
                        label: "Reset"
                        onClicked: dlg.saveColor(modelData.channel,
                                                 colorTarget.currentText, "")
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
                    defaultLabel: "Segoe UI Variable (default)"
                    selected: prefs.uiFont
                    onPicked: function (family) {
                        prefs.uiFont = family
                        Theme.fontUI = family === ""
                            ? "Segoe UI Variable" : family
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
}
