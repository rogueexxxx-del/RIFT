import QtQuick
import QtQuick.Layouts

// The header of one collapsible section in a dock.
//
// Every panel used to draw its own, as a shouted "> COLOR" that was clickable
// only on the letters themselves. Made shared so the whole dock reads as one
// stack of sections you open and close, and so the hit target is the whole row
// rather than a word.
Rectangle {
    id: hdr
    property string title: ""
    // Shown on the right when collapsed - what the section is doing while you
    // cannot see it. Empty means nothing to say.
    property string hint: ""
    property bool   expanded: false
    // Marks a section that is active even though it is closed, so the state is
    // not hidden by collapsing it.
    property bool   marked: false
    default property alias trailing: extra.data

    signal toggled()

    Layout.fillWidth: true
    implicitHeight: Theme.header
    color: hover.hovered ? Theme.hover : "transparent"

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.hairline
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padding
        anchors.rightMargin: Theme.padding
        spacing: Theme.gapTight

        // Drawn rather than a glyph so it can rotate
        Text {
            text: "›"
            color: hdr.marked ? Theme.accent : Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
            rotation: hdr.expanded ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Theme.fast } }
        }
        Text {
            text: hdr.title.toUpperCase()
            color: hdr.marked ? Theme.accent : Theme.text
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeTiny
            font.weight: Font.Medium
            font.letterSpacing: Theme.microSpacing
        }
        Text {
            visible: !hdr.expanded && hdr.hint !== ""
            text: hdr.hint
            color: hdr.marked ? Theme.accent : Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeTiny
        }
        Item { Layout.fillWidth: true }
        // Buttons that belong to the section, kept on its header so an open
        // section does not need a second row for them.
        RowLayout {
            id: extra
            spacing: Theme.gap
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: hdr.toggled() }
}
