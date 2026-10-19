import QtQuick
import QtQuick.Layouts

Item {
    id: gallery
    property real amount: 0.42
    property int segment: 0
    property bool expanded: true
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.groupGap * 2
        spacing: Theme.groupGap
        RowLayout {
            Layout.fillWidth: true
            Text { text: "RIFT"; color: Theme.text; font.family: Theme.fontDisplay; font.pixelSize: Theme.sizeDisplay }
            ColumnLayout {
                spacing: Theme.gapTight
                Text { text: "Interface foundation"; color: Theme.text; font.family: Theme.fontUI; font.pixelSize: Theme.sizeTitle }
                Text { text: "Phase 1 / Component and palette review"; color: Theme.textMuted; font.family: Theme.fontUI; font.pixelSize: Theme.size }
            }
            Item { Layout.fillWidth: true }
            Text { text: "Geist + Geist Mono\n4 px grid / 1 px borders"; color: Theme.textDim; font.family: Theme.fontMono; font.pixelSize: Theme.sizeSmall }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Theme.line; color: Theme.border }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.groupGap
            AppCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.padding
                    spacing: Theme.groupGap
                    Text { text: "01  Actions and states"; color: Theme.text; font.family: Theme.fontUI; font.pixelSize: Theme.sizeTitle }
                    RowLayout {
                        spacing: Theme.gap
                        FlatButton { label: "Create"; primary: true }
                        FlatButton { label: "Cancel" }
                        FlatButton { label: "Disabled"; enabled: false }
                    }
                    RowLayout {
                        spacing: Theme.gap
                        FlatButton { label: "Selected"; active: true }
                        FlatButton { id: focusExample; label: "Keyboard focus"; Component.onCompleted: forceActiveFocus(Qt.TabFocusReason) }
                    }
                    SegmentedControl {
                        Layout.fillWidth: true
                        options: ["16:9", "1:1", "9:16"]
                        currentIndex: gallery.segment
                        onSelected: index => gallery.segment = index
                    }
                    AppToggle { text: "Enable effect"; checked: true }
                    AppToggle { text: "Keep original colors" }
                    AppToggle { text: "Unavailable"; enabled: false }
                    SectionHeader {
                        title: "Audio mapping"
                        expanded: gallery.expanded
                        onToggled: gallery.expanded = !gallery.expanded
                    }
                    Text {
                        visible: gallery.expanded
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Twirl-down sections keep related controls together. Tab to focus, Space to activate."
                        color: Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.size
                    }
                    Item { Layout.fillHeight: true }
                    Text { text: "Hover any button to inspect its state."; color: Theme.textMuted; font.family: Theme.fontUI; font.pixelSize: Theme.sizeTiny }
                }
            }
            AppCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.padding
                    spacing: Theme.groupGap
                    Text { text: "02  Parameters"; color: Theme.text; font.family: Theme.fontUI; font.pixelSize: Theme.sizeTitle }
                    ParamSlider {
                        id: scrubExample
                        Layout.fillWidth: true
                        label: "Amount"
                        value: gallery.amount
                        defaultValue: 0.42
                        onMoved: v => gallery.amount = v
                    }
                    ParamSlider {
                        Layout.fillWidth: true
                        label: "Displacement"
                        value: 0.68
                        defaultValue: 0.5
                        patched: true
                        channelName: "Bass"
                        availableChannels: ["Bass", "Drums", "Highs"]
                        onMoved: v => value = v
                        onLinkRequested: i => { patched = i >= 0; channelName = i >= 0 ? availableChannels[i] : "" }
                    }
                    ParamSlider {
                        Layout.fillWidth: true
                        label: "Decay"
                        value: 0.84
                        defaultValue: 0.84
                        patched: true
                        channelName: "Drums"
                        availableChannels: ["Bass", "Drums", "Highs"]
                        onMoved: v => value = v
                    }
                    ParamSlider { Layout.fillWidth: true; label: "Disabled"; value: 0.32; enabled: false }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Drag the value to scrub. Double click the value or track to reset. Arrow keys adjust the focused slider."
                        color: Theme.textMuted
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.size
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        spacing: Theme.gap
                        Repeater {
                            model: ["Drums", "Bass", "Mids", "Highs"]
                            Rectangle {
                                required property string modelData
                                Layout.fillWidth: true
                                height: Theme.swatchHeight
                                color: Theme.raised
                                radius: Theme.radius
                                border.width: Theme.line
                                border.color: Theme.channelColor(modelData)
                                Text { anchors.centerIn: parent; text: parent.modelData; color: Theme.channelColor(parent.modelData); font.family: Theme.fontUI; font.pixelSize: Theme.sizeTiny }
                            }
                        }
                    }
                }
            }
            AppCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.padding
                    spacing: Theme.groupGap
                    Text { text: "03  Surfaces and popovers"; color: Theme.text; font.family: Theme.fontUI; font.pixelSize: Theme.sizeTitle }
                    AppCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.sliderHeight + Theme.padding
                        selected: true
                        interactive: true
                        radius: Theme.radius
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.padding
                            Text { text: "01"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: Theme.sizeSmall }
                            Text { text: "Effect card"; color: Theme.text; font.family: Theme.fontUI; font.pixelSize: Theme.size }
                            Item { Layout.fillWidth: true }
                            Text { text: "Texture"; color: Theme.effectColor("ascii"); font.family: Theme.fontUI; font.pixelSize: Theme.sizeTiny }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledMenuItem { Layout.fillWidth: true; text: "New project"; shortcutText: "Ctrl+N" }
                        StyledMenuItem { Layout.fillWidth: true; text: "Snap to beats"; checkable: true; checked: true }
                        StyledMenuSeparator { Layout.fillWidth: true }
                        StyledMenuItem { Layout.fillWidth: true; text: "Unavailable action"; enabled: false }
                    }
                    FlatButton { label: "Open dialog"; onClicked: sampleDialog.open() }
                    FlatButton { label: "Hover for tooltip"; tip: "Readable tooltip. Neutral surface. No glow." }
                    Item { Layout.fillHeight: true }
                    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Static grain lives inside panels. The video preview stays clear."; color: Theme.textMuted; font.family: Theme.fontUI; font.pixelSize: Theme.size }
                }
            }
        }
        Text { text: "Effect labels / Proposed palette"; color: Theme.text; font.family: Theme.fontUI; font.pixelSize: Theme.sizeTitle }
        GridLayout {
            Layout.fillWidth: true
            columns: 9
            rowSpacing: Theme.gap
            columnSpacing: Theme.gap
            Repeater {
                model: Object.keys(Theme.effectColors)
                Rectangle {
                    required property string modelData
                    Layout.fillWidth: true
                    height: Theme.swatchHeight
                    color: Theme.raised
                    radius: Theme.radius
                    Rectangle { width: Theme.gapTight; height: parent.height; color: Theme.effectColor(parent.modelData); radius: Theme.radius }
                    Text { anchors.centerIn: parent; text: Theme.nice(parent.modelData); color: Theme.effectColor(parent.modelData); font.family: Theme.fontUI; font.pixelSize: Theme.sizeTiny }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap
            Repeater {
                model: ["bg", "panel", "raised", "hover", "text", "accent"]
                Rectangle {
                    required property string modelData
                    Layout.fillWidth: true
                    height: Theme.swatchHeight
                    color: Theme[modelData]
                    border.width: Theme.line
                    border.color: Theme.border
                    radius: Theme.radius
                    Text { anchors.centerIn: parent; text: parent.modelData + "  " + Theme[parent.modelData]; color: parent.modelData === "accent" || parent.modelData === "text" ? Theme.bg : Theme.textDim; font.family: Theme.fontMono; font.pixelSize: Theme.sizeSmall }
                }
            }
        }
    }
    AppDialog {
        id: sampleDialog
        title: "New composition"
        width: Theme.dialogWidth
        contentItem: ColumnLayout {
            spacing: Theme.groupGap
            Text { text: "Choose a frame shape."; color: Theme.text; font.family: Theme.fontUI; font.pixelSize: Theme.size }
            SegmentedControl { Layout.fillWidth: true; options: ["16:9", "1:1", "9:16"]; onSelected: i => currentIndex = i }
            RowLayout {
                Item { Layout.fillWidth: true }
                FlatButton { label: "Cancel"; onClicked: sampleDialog.close() }
                FlatButton { label: "Create"; primary: true; onClicked: sampleDialog.close() }
            }
        }
    }
}
