import QtQuick
import QtQuick.Shapes

// Supplied reference icons share an unboxed hit area with the remaining tools.
Rectangle {
    id: btn
    property string kind: "select"
    property string tip: ""
    property bool active: false
    signal clicked()

    implicitWidth: Theme.control
    implicitHeight: Theme.control
    radius: Theme.radius
    activeFocusOnTab: true
    color: "transparent"
    border.width: activeFocus ? Theme.focusWidth : 0
    border.color: Theme.focusRing
    opacity: enabled ? 1.0 : 0.3

    readonly property color fg: active || hover.hovered ? Theme.text : Theme.textDim
    readonly property var assetFiles: ({
        select: "icons8-cursor.svg",
        text: "icons8-typography-48.png",
        stretch_end: "icons8-add-white-space-48.png",
        fill: "icons8-add-white-space-48.png",
        add_clip: "icons8-video-48.png",
        add_image: "icons8-add-image-48.png",
        add_audio: "icons8-add-song-48.png"
    })
    readonly property url iconSource: assetFiles[kind] ? Theme.asset("icons inspo/" + assetFiles[kind]) : ""
    readonly property string iconPath: icons[kind === "cut" ? "razor" : kind === "fill" ? "stretch_end" : kind] || ""
    readonly property var icons: ({
        select: "M4 1V15.5L7.5 12L10.5 17L12 16L9 11H15Z",
        text: "M3 3H15V4.5H9.75V15H8.25V4.5H3Z",
        razor: "M6.1 6L16 15L15 16.2L5 7.2Z M5 10.8L15.2 1.8L16.2 3L6.1 12Z M1.5 5A3 3 0 1 1 7.5 5A3 3 0 1 1 1.5 5Z M3 5A1.5 1.5 0 1 1 6 5A1.5 1.5 0 1 1 3 5Z M1.5 13A3 3 0 1 1 7.5 13A3 3 0 1 1 1.5 13Z M3 13A1.5 1.5 0 1 1 6 13A1.5 1.5 0 1 1 3 13Z",
        stretch_end: "M2 3H3.5V15H2Z M14.5 3H16V15H14.5Z M7 5.5L3.5 9L7 12.5L8 11.5L6.25 9.75H11.75L10 11.5L11 12.5L14.5 9L11 5.5L10 6.5L11.75 8.25H6.25L8 6.5Z",
        copy: "M2 1H12V3H4V13H2Z M6 5H16V17H6Z",
        paste: "M6 1H12V4H6Z M3 3H5V6H13V3H15V17H3Z",
        add_clip: "M2 3H16V15H2Z M3.5 4.5H14.5V13.5H3.5Z M8.25 6H9.75V8.25H12V9.75H9.75V12H8.25V9.75H6V8.25H8.25Z",
        add_audio: "M1.5 7H3V11H1.5Z M5 3H6.5V15H5Z M8.5 5H10V13H8.5Z M13 6H14.5V8.25H17V9.75H14.5V12H13V9.75H10.5V8.25H13Z",
        remove: "M6 1H12V3H16V5H2V3H6Z M4 6H14L13 17H5Z M7 8V14H8V8Z M10 8V14H11V8Z",
        keyframe: "M9 3L15 9L9 15L3 9Z M9 5L13 9L9 13L5 9Z",
        mark_in: "M5 3H12V4.5H6.5V13.5H12V15H5Z",
        mark_out: "M6 3H13V15H6V13.5H11.5V4.5H6Z",
        go_in: "M2.5 3H4V15H2.5Z M11.5 4L5.5 9L11.5 14V9.75H16V8.25H11.5Z",
        go_out: "M14 3H15.5V15H14Z M6.5 4L12.5 9L6.5 14V9.75H2V8.25H6.5Z",
        clear_marks: "M2 3H5V4.5H3.5V13.5H5V15H2Z M13 3H16V15H13V13.5H14.5V4.5H13Z M6 6L9 9L12 6L13 7L10 10L13 13L12 14L9 11L6 14L5 13L8 10L5 7Z",
        window: "M5 2H16V13H14.5V3.5H5Z M2 5H13V16H2Z M3.5 6.5H11.5V14.5H3.5Z"
    })
    Accessible.role: Accessible.Button
    Accessible.name: tip
    Accessible.onPressAction: if (enabled) clicked()
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) clicked() }
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) clicked() }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: 14
        height: 2
        color: btn.fg
        visible: btn.active
    }

    Shape {
        visible: String(btn.iconSource) === ""
        anchors.centerIn: parent
        width: 18
        height: 18
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillColor: btn.fg
            fillRule: ShapePath.OddEvenFill
            PathSvg { path: btn.iconPath }
        }
    }

    AssetIcon {
        objectName: "toolAssetIcon"
        anchors.centerIn: parent
        width: 18; height: 18
        source: btn.iconSource
        color: btn.fg
        visible: String(source) !== ""
    }

    HoverHandler { id: hover; cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { onTapped: if (btn.enabled) { btn.forceActiveFocus(Qt.MouseFocusReason); btn.clicked() } }
    ToolTipArea { text: btn.tip }
}
