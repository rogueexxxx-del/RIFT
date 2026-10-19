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
    radius: Theme.radius
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: expanded ? "Expanded" : "Collapsed"
    Accessible.onPressAction: toggled()
    Keys.onSpacePressed: toggled()
    Keys.onReturnPressed: toggled()
    border.width: activeFocus ? Theme.focusWidth : 0
    border.color: Theme.focusRing

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
            text: hdr.title
            color: hdr.marked ? Theme.accentText : Theme.text
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
            font.weight: Font.Medium
        }
        Text {
            visible: !hdr.expanded && hdr.hint !== ""
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: hdr.hint
            color: hdr.marked ? Theme.accentText : Theme.textMuted
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
