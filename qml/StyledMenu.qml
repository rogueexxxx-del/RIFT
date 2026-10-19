import QtQuick
import QtQuick.Controls

// A Menu in the app's own palette.
//
// The Basic style draws menus as a light panel with a hard 1px frame, which is
// the white border showing through on a dark UI. Restyling has to cover the
// popup background AND the item delegate - the item paints its own background,
// so theming only the menu leaves white rows inside a dark box.
Menu {
    id: menu

    // Popup.Item keeps the menu inside the scene graph instead of spawning a
    // native window, so it inherits the window's theme and cannot be clipped.
    popupType: Popup.Item
    padding: Theme.gapTight
    spacing: 0
    font.family: Theme.fontUI
    font.pixelSize: Math.max(12, Theme.size)
    implicitWidth: {
        let widest = 136
        for (let i = 0; i < count; ++i) {
            const row = itemAt(i)
            if (row && typeof row.text === "string") widest = Math.max(widest, row.implicitWidth)
        }
        return widest + leftPadding + rightPadding
    }
    margins: Theme.gap
    height: Math.min(implicitHeight, Overlay.overlay ? Overlay.overlay.height - Theme.groupGap : implicitHeight)

    background: Rectangle {
        color: Theme.flyout
        radius: Theme.panelRadius
        border.width: 1
        border.color: Theme.popupBorder
    }

    delegate: StyledMenuItem {}
}
