import QtQuick
import QtQuick.Layouts

// Faint horizontal seam. Regions are separated mainly by surface value now, so
// this only needs to hint at the boundary rather than draw a box.
Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    color: Theme.hairline
}
