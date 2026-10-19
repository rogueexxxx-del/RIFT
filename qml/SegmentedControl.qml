import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Control {
    id: control
    property var options: []
    property int currentIndex: 0
    signal selected(int index)
    implicitHeight: Theme.control
    implicitWidth: row.implicitWidth + Theme.gapTight * 2
    padding: Theme.gapTight
    background: Rectangle {
        color: Theme.sunken
        radius: Theme.radius
        border.width: Theme.line
        border.color: Theme.border
    }
    contentItem: RowLayout {
        id: row
        spacing: Theme.gapTight
        Repeater {
            model: control.options
            FlatButton {
                required property int index
                required property string modelData
                label: modelData
                small: true
                active: control.currentIndex === index
                Layout.fillWidth: true
                implicitHeight: Theme.control - Theme.gapTight * 2
                onClicked: control.selected(index)
                Keys.onRightPressed: control.selected((index + 1) % control.options.length)
                Keys.onLeftPressed: control.selected((index + control.options.length - 1) % control.options.length)
            }
        }
    }
}
