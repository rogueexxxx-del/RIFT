import QtQuick
import QtQuick.Controls

// Font chooser, used for both the interface font and text layers.
//
// Each name is drawn in its own face. A list of family names set in one font
// is unusable for picking a font - the name is not the information you need.
ComboBox {
    id: pick
    // Families installed on this machine, plus the ones the app ships.
    property var fonts: []
    // Shown first and reported as "" - "whatever the app picked" is a real
    // choice and should not force the user to guess which family that was.
    property string defaultLabel: "Default"
    // The family in use, "" for default.
    property string selected: ""

    signal picked(string family)

    implicitHeight: Theme.control
    model: [defaultLabel].concat(fonts)
    currentIndex: {
        if (selected === "") return 0
        const i = model.indexOf(selected)
        return i < 0 ? 0 : i
    }
    onActivated: pick.picked(currentIndex === 0 ? "" : String(currentText))

    // A family name is only a valid font.family if it is actually installed;
    // index 0 is a label, not a font, so it falls back to the UI face.
    function faceFor(i, name) {
        return i === 0 ? Theme.fontUI : name
    }

    contentItem: Text {
        leftPadding: 10
        rightPadding: 10
        text: pick.displayText
        color: Theme.text
        font.family: pick.faceFor(pick.currentIndex, pick.displayText)
        font.pixelSize: Theme.size
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        color: Theme.raised
        radius: Theme.radius
        border.width: 1
        border.color: pick.activeFocus ? Theme.accent : Theme.hairline
    }

    indicator: Text {
        x: pick.width - width - 10
        y: (pick.height - height) / 2
        text: "▾"
        color: Theme.textMuted
        font.pixelSize: Theme.sizeSmall
    }

    popup: Popup {
        y: pick.height
        width: pick.width
        // Machines have hundreds of fonts; the list scrolls rather than
        // growing taller than the screen.
        implicitHeight: Math.min(contentItem.implicitHeight, 340)
        padding: 1
        background: Rectangle {
            color: Theme.raised
            radius: Theme.radius
            border.width: 1
            border.color: Theme.hairline
        }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: pick.delegateModel
            currentIndex: pick.highlightedIndex
            ScrollBar.vertical: ScrollBar {}
        }
    }

    delegate: ItemDelegate {
        id: item
        required property string modelData
        required property int index
        width: pick.width
        height: 30

        background: Rectangle {
            color: item.hovered ? Theme.accent : "transparent"
        }
        contentItem: Text {
            leftPadding: 10
            text: item.modelData
            color: item.hovered ? Theme.bg : Theme.text
            font.family: pick.faceFor(item.index, item.modelData)
            font.pixelSize: Theme.size
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
}
