import QtQuick

// Static tiled grain is confined to a panel's bounds, beneath its controls.
Rectangle {
    id: card
    property bool selected: false
    property bool interactive: false
    signal clicked()
    radius: Theme.panelRadius
    color: card.enabled && hover.hovered && interactive ? Theme.hover : Theme.panel
    border.width: Theme.line
    border.color: activeFocus ? Theme.accent : selected ? Theme.selection : Theme.border
    activeFocusOnTab: interactive
    opacity: enabled ? 1 : Theme.disabledOpacity
    Keys.onSpacePressed: if (interactive) clicked()
    Keys.onReturnPressed: if (interactive) clicked()
    Image {
        anchors.fill: parent
        anchors.margins: Theme.panelRadius
        source: Theme.asset("grain.png")
        fillMode: Image.Tile
        opacity: Theme.grainOpacity
        visible: Theme.grain > 0 && source.toString() !== ""
        enabled: false
    }
    HoverHandler { id: hover; enabled: card.interactive }
    TapHandler { enabled: card.interactive; onTapped: { card.forceActiveFocus(); card.clicked() } }
}
