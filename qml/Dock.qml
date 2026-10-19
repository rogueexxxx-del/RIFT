import QtQuick
import QtQuick.Layouts
import QtQuick.Window

// A named, collapsible, resizable side panel.
//
// Every region of the app is one of these so it can be titled, folded away and
// dragged wider - the old fixed 232/280 px columns could not be reclaimed when
// you wanted the picture bigger, and nothing told you what a region was called.
Item {
    id: dock
    property string title: ""
    property bool   collapsed: false
    property bool   floating: false
    // Which edge the resize handle lives on: "left" for a right-hand dock.
    property string handleEdge: "right"
    property int    expandedWidth: 260
    property int    minWidth: 200
    property int    maxWidth: 520
    default property alias content: body.data
    property alias bodyItem: body

    property string side: handleEdge === "right" ? "left" : "right"
    property string actionText: "+"
    property var tabs: []
    property bool tabsDetachable: false
    property int currentTab: 0
    signal tabClicked(int index)
    signal actionTriggered()
    signal titleClicked()
    signal moveRequested()
    signal floatRequested()
    signal tabFloatRequested(int index)
    signal dragMoved(real dx, real dy, real screenX, real screenY)
    signal dragFinished(real dx, real dy, real screenX, real screenY)

    readonly property int barWidth: 26

    Layout.fillHeight: true
    Layout.fillWidth: false
    Layout.preferredWidth: collapsed ? barWidth : expandedWidth
    Layout.minimumWidth: collapsed ? barWidth : minWidth
    Layout.maximumWidth: collapsed ? barWidth : maxWidth

    Behavior on Layout.preferredWidth {
        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }

    // ── collapsed: a vertical title strip you click to bring it back ──
    Rectangle {
        anchors.fill: parent
        visible: dock.collapsed
        color: "#080808"

        Text {
            anchors.centerIn: parent
            rotation: -90
            text: dock.title
            color: Theme.textMuted
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
        }
        TapHandler { onTapped: dock.collapsed = false }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        ToolTipArea { text: "Show " + dock.title }
    }

    // ── expanded ──
    Rectangle {
        anchors.fill: parent
        visible: !dock.collapsed
        color: "#000000"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Title bar: matches Figma 7_126 / 7_127 (◀   Title   +)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                color: "#000000"

                DragHandler {
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: true
                    property real lastX: 0
                    property real lastY: 0
                    property real totalX: 0
                    property real totalY: 0
                    property real lastScreenX: 0
                    property real lastScreenY: 0
                    onTranslationChanged: if (active) {
                        totalX = translation.x
                        totalY = translation.y
                        const win = dock.Window.window
                        if (win) {
                            lastScreenX = win.x + centroid.scenePosition.x
                            lastScreenY = win.y + centroid.scenePosition.y
                            dock.dragMoved(translation.x - lastX, translation.y - lastY,
                                           lastScreenX, lastScreenY)
                        }
                        lastX = translation.x
                        lastY = translation.y
                    }
                    onActiveChanged: {
                        if (active) { lastX = 0; lastY = 0; totalX = 0; totalY = 0 }
                        else dock.dragFinished(totalX, totalY, lastScreenX, lastScreenY)
                    }
                }

                // Left: ◀ / ▶ collapse button
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: dock.side === "left" ? "◀" : "▶"
                    color: hideHover.hovered ? "#FFFFFF" : "#888888"
                    font.family: Theme.fontUI
                    font.pixelSize: 11

                    HoverHandler { id: hideHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: dock.collapsed = true }
                    ToolTipArea { text: "Collapse " + dock.title }
                }

                // Center: Segmented tabs when provided, otherwise single title
                Row {
                    visible: dock.tabs && dock.tabs.length > 0
                    anchors.centerIn: parent
                    spacing: 12

                    Repeater {
                        model: dock.tabs
                        delegate: Text {
                            required property int index
                            required property string modelData
                            text: modelData
                            color: dock.currentTab === index ? "#FFFFFF" : (tabHov.hovered ? "#CCCCCC" : "#777777")
                            font.family: Theme.fontUI
                            font.pixelSize: 12
                            font.weight: dock.currentTab === index ? Font.Medium : Font.Normal

                            HoverHandler { id: tabHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    dock.currentTab = index
                                    dock.tabClicked(index)
                                }
                            }
                            DragHandler {
                                enabled: dock.tabsDetachable
                                target: null
                                property real lastY: 0
                                onTranslationChanged: if (active) lastY = translation.y
                                onActiveChanged: {
                                    if (!active && Math.abs(lastY) > 40)
                                        dock.tabFloatRequested(index)
                                    if (!active) lastY = 0
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: !dock.tabs || dock.tabs.length === 0
                    anchors.centerIn: parent
                    text: dock.title
                    color: titleHover.hovered ? Theme.accent : "#FFFFFF"
                    font.family: Theme.fontUI
                    font.pixelSize: 13
                    font.weight: Font.Normal

                    HoverHandler { id: titleHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: dock.titleClicked() }
                }

                // Right: Action button (+)
                Text {
                    visible: dock.actionText !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: dock.actionText
                    color: actHover.hovered ? "#FFFFFF" : "#888888"
                    font.family: Theme.fontUI
                    font.pixelSize: 14
                    font.weight: Font.Normal

                    HoverHandler { id: actHover; cursorShape: Qt.PointingHandCursor; enabled: dock.actionText !== "" }
                    TapHandler { onTapped: dock.actionTriggered(); enabled: dock.actionText !== "" }
                    ToolTipArea { text: "Add"; enabled: dock.actionText !== "" }
                }

            }

            Item {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
            }
        }
    }

    // ── resize handle ──
    Rectangle {
        width: 1
        height: parent.height
        visible: !dock.collapsed
        anchors.right: dock.handleEdge === "right" ? parent.right : undefined
        anchors.left:  dock.handleEdge === "left"  ? parent.left  : undefined
        color: grab.active || hoverH.hovered ? Theme.accent : "transparent"
        z: 10

        // Expanded interactive hit zone
        Item {
            anchors.centerIn: parent
            width: 8
            height: parent.height

            HoverHandler { id: hoverH; cursorShape: Qt.SizeHorCursor }
            DragHandler {
                id: grab
                target: null
                yAxis.enabled: false
                property real startWidth: 260
                onActiveChanged: if (active) startWidth = dock.expandedWidth
                onTranslationChanged: {
                    const d = dock.handleEdge === "right" ? translation.x : -translation.x
                    dock.expandedWidth = Math.max(dock.minWidth,
                                         Math.min(dock.maxWidth, startWidth + d))
                }
            }
        }
    }
}
