import QtQuick
import QtQuick.Layouts

// A picture of the controller in front of you, with MAP on top - the Ableton
// idea: see your hardware, click the knob you mean, then click the setting.
//
// Layouts are matched by device name. An unknown controller falls back to a
// generic 8-knob / 8-pad grid, which is what most small controllers are, so
// mapping still works without a profile.
Rectangle {
    id: view
    required property var viewport

    property bool mapping: false

    color: Theme.panel

    // Default CCs/notes as the units ship. A controller re-programmed in its
    // vendor editor still maps fine - MAP learns whatever actually arrives, the
    // diagram is only a picture.
    readonly property var profiles: [
        {
            match: "minilab",
            name:  "Arturia MiniLab mk II",
            // Two rows of eight; knob 1 and 9 are the clickable encoders.
            knobs: [ { cc: 112, label: "1" }, { cc: 74, label: "2" },
                     { cc: 71,  label: "3" }, { cc: 76, label: "4" },
                     { cc: 77,  label: "5" }, { cc: 93, label: "6" },
                     { cc: 73,  label: "7" }, { cc: 75, label: "8" },
                     { cc: 114, label: "9" }, { cc: 18, label: "10" },
                     { cc: 19,  label: "11" }, { cc: 16, label: "12" },
                     { cc: 17,  label: "13" }, { cc: 91, label: "14" },
                     { cc: 79,  label: "15" }, { cc: 72, label: "16" } ],
            pads:  [ 36, 37, 38, 39, 40, 41, 42, 43 ],
            keys:  25,
            firstKey: 48
        },
        {
            match: "",
            name:  "Generic controller",
            knobs: [ { cc: 1, label: "1" }, { cc: 2, label: "2" },
                     { cc: 3, label: "3" }, { cc: 4, label: "4" },
                     { cc: 5, label: "5" }, { cc: 6, label: "6" },
                     { cc: 7, label: "7" }, { cc: 8, label: "8" } ],
            pads:  [ 36, 37, 38, 39, 40, 41, 42, 43 ],
            keys:  0,
            firstKey: 48
        }
    ]

    readonly property var profile: {
        const n = (viewport.midiName || "").toLowerCase()
        for (let i = 0; i < profiles.length; ++i)
            if (profiles[i].match !== "" && n.indexOf(profiles[i].match) >= 0)
                return profiles[i]
        return profiles[profiles.length - 1]
    }

    // key -> parameter label, for every mapping regardless of selected node.
    readonly property var bound: {
        const m = {}
        const all = viewport.allControls
        for (let i = 0; i < all.length; ++i) m[all[i].key] = all[i].label
        return m
    }

    implicitHeight: col.implicitHeight + Theme.padding * 2

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.padding
        spacing: Theme.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap

            FlatButton {
                label: view.mapping ? "Mapping - click a control" : "Map"
                active: view.mapping
                implicitWidth: view.mapping ? 190 : 70
                onClicked: {
                    view.mapping = !view.mapping
                    if (!view.mapping) view.viewport.armControl("")
                }
                ToolTipArea {
                    text: "Click MAP, then a knob or pad here, then the setting it should drive"
                }
            }
            // First run is one click: find the controller and open it.
            FlatButton {
                visible: !view.viewport.midiOpen
                label: "Connect controller"
                implicitWidth: 168
                onClicked: view.viewport.connectController()
            }
            Text {
                text: view.viewport.midiOpen
                      ? view.profile.name
                      : "plug in a MIDI controller, then connect"
                color: view.viewport.midiOpen ? Theme.text : Theme.textMuted
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
            }
            Item { Layout.fillWidth: true }
            Text {
                text: view.viewport.lastControl
                color: Theme.accent
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeSmall
                elide: Text.ElideLeft
                Layout.maximumWidth: 220
            }
        }

        // ── knobs ──
        Grid {
            Layout.fillWidth: true
            columns: 8
            spacing: Theme.gapTight
            Repeater {
                model: view.profile.knobs
                delegate: Rectangle {
                    required property var modelData
                    readonly property string key: "cc:" + modelData.cc
                    readonly property string boundTo: view.bound[key] || ""
                    readonly property bool armed: view.viewport.armedControl === key

                    // Lit for a moment each time this control sends something.
                    // Without it there is no way to tell the controller is
                    // connected except by watching a panel across the window.
                    property bool hot: false
                    Connections {
                        target: view.viewport
                        function onControlChanged() {
                            // lastControl is "<key> <value>" ("cc:74 0.53"), so
                            // comparing it to the key never matched and this
                            // never lit. Prefix plus the space: cc:1 must not
                            // also light for cc:10.
                            if (view.viewport.lastControl.indexOf(key + " ") === 0) {
                                hot = true
                                cool.restart()
                            }
                        }
                    }
                    Timer { id: cool; interval: 350; onTriggered: hot = false }

                    width: 62; height: 44
                    color: armed ? Theme.accent
                         : hot   ? Theme.accentSoft : "transparent"
                    border.width: hot ? 2 : 1
                    border.color: armed ? Theme.accent
                                : hot   ? Theme.accent
                                : (boundTo !== "" ? Theme.accent : Theme.hairline)
                    Behavior on border.width { NumberAnimation { duration: 90 } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 1
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "cc " + modelData.cc
                            color: parent.parent.armed ? Theme.bg : Theme.textMuted
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeTiny
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: parent.parent.boundTo !== "" ? parent.parent.boundTo
                                                               : ("knob " + modelData.label)
                            color: parent.parent.armed ? Theme.bg
                                 : (parent.parent.boundTo !== "" ? Theme.accent
                                                                 : Theme.textMuted)
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeSmall
                            width: 56
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    TapHandler {
                        onTapped: if (view.mapping) view.viewport.armControl(parent.key)
                    }
                }
            }
        }

        // ── pads ──
        Grid {
            Layout.fillWidth: true
            columns: 8
            spacing: Theme.gapTight
            Repeater {
                model: view.profile.pads
                delegate: Rectangle {
                    required property int modelData
                    required property int index
                    readonly property string key: "note:" + modelData
                    readonly property string boundTo: view.bound[key] || ""
                    readonly property bool armed: view.viewport.armedControl === key

                    property bool hot: false
                    Connections {
                        target: view.viewport
                        function onControlChanged() {
                            // lastControl is "<key> <value>" ("cc:74 0.53"), so
                            // comparing it to the key never matched and this
                            // never lit. Prefix plus the space: cc:1 must not
                            // also light for cc:10.
                            if (view.viewport.lastControl.indexOf(key + " ") === 0) {
                                hot = true
                                padCool.restart()
                            }
                        }
                    }
                    Timer { id: padCool; interval: 350; onTriggered: hot = false }

                    width: 62; height: 30
                    color: armed ? Theme.accent
                         : hot   ? Theme.accentSoft : "transparent"
                    border.width: 1
                    border.color: armed ? Theme.accent
                                        : (boundTo !== "" ? Theme.accent : Theme.hairline)
                    Text {
                        anchors.centerIn: parent
                        text: parent.boundTo !== "" ? parent.boundTo : ("pad " + (index + 1))
                        color: parent.armed ? Theme.bg
                             : (parent.boundTo !== "" ? Theme.accent : Theme.textMuted)
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        width: 56
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                    TapHandler {
                        onTapped: if (view.mapping) view.viewport.armControl(parent.key)
                    }
                }
            }
        }

        // ── keyboard ──
        // Orientation: it makes the diagram read as YOUR device. Keys are
        // mappable too - a pad and a key are both just notes.
        Item {
            Layout.fillWidth: true
            visible: view.profile.keys > 0
            implicitHeight: 54

            readonly property int keyW: 24
            readonly property var whiteNotes: {
                const out = []
                const pat = [0, 2, 4, 5, 7, 9, 11]
                for (let i = 0; i < view.profile.keys; ++i) {
                    const n = view.profile.firstKey + i
                    if (pat.indexOf(n % 12) >= 0) out.push(n)
                }
                return out
            }
            // Each black key sits on the seam after a given white key, so its x
            // comes from counting whites - not from a running offset, which is
            // what made them pile up.
            readonly property var blackNotes: {
                const out = []
                const pat = [1, 3, 6, 8, 10]
                let whites = 0
                for (let i = 0; i < view.profile.keys; ++i) {
                    const n = view.profile.firstKey + i
                    if (pat.indexOf(n % 12) >= 0) out.push({ note: n, after: whites })
                    else whites += 1
                }
                return out
            }

            Repeater {
                model: parent.whiteNotes
                delegate: Rectangle {
                    required property int modelData
                    required property int index
                    readonly property string key: "note:" + modelData
                    readonly property bool armed: view.viewport.armedControl === key
                    readonly property bool mapped: view.bound[key] !== undefined

                    x: index * parent.keyW
                    width: parent.keyW - 2
                    height: 54
                    color: armed ? Theme.accent : (mapped ? "#4A4A4A" : "#E6E6E6")
                    border.width: 1
                    border.color: Theme.hairline
                    TapHandler {
                        onTapped: if (view.mapping) view.viewport.armControl(parent.key)
                    }
                }
            }
            Repeater {
                model: parent.blackNotes
                delegate: Rectangle {
                    required property var modelData
                    readonly property string key: "note:" + modelData.note
                    readonly property bool armed: view.viewport.armedControl === key
                    readonly property bool mapped: view.bound[key] !== undefined

                    x: modelData.after * parent.keyW - 7
                    z: 1
                    width: 14
                    height: 34
                    color: armed ? Theme.accent : (mapped ? "#8A8A8A" : "#111111")
                    border.width: 1
                    border.color: Theme.hairline
                    TapHandler {
                        onTapped: if (view.mapping) view.viewport.armControl(parent.key)
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: view.mapping
            text: view.viewport.armedControl !== ""
                  ? "Now click MAP next to the setting this should control."
                  : "Click the knob or pad you want to use. Or just move it - that works too."
            color: Theme.accent
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
        }
    }
}
