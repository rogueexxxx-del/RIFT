import QtQuick
import QtQuick.Layouts

// A named, collapsible, resizable side panel.
//
// Every region of the app is one of these so it can be titled, folded away and
// dragged wider - the old fixed 232/280 px columns could not be reclaimed when
// you wanted the picture bigger, and nothing told you what a region was called.
Item {
    id: dock
    property string title: ""
    property bool   collapsed: false
    // Which edge the resize handle lives on: "left" for a right-hand dock.
    property string handleEdge: "right"
    property int    expandedWidth: 260
    property int    minWidth: 200
    property int    maxWidth: 520
    default property alias content: body.data

    property string side: handleEdge === "right" ? "left" : "right"
    property string actionText: "+"
    property var tabs: []
    property int currentTab: 0
    signal tabClicked(int index)
    signal actionTriggered()
    signal titleClicked()
    signal moveRequested()

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
        width: 4
        height: parent.height
        visible: !dock.collapsed
        anchors.right: dock.handleEdge === "right" ? parent.right : undefined
        anchors.left:  dock.handleEdge === "left"  ? parent.left  : undefined
        color: grab.active || hoverH.hovered ? Theme.accent : "transparent"
        opacity: grab.active ? 1.0 : 0.6

        HoverHandler { id: hoverH; cursorShape: Qt.SizeHorCursor }
        DragHandler {
            id: grab
            target: null
            yAxis.enabled: false
            onTranslationChanged: {
                // Dragging the handle on the LEFT edge of a right-hand dock
                // grows it in the opposite direction to the cursor.
                const d = dock.handleEdge === "right" ? translation.x : -translation.x
                dock.expandedWidth = Math.max(dock.minWidth,
                                     Math.min(dock.maxWidth, dock.expandedWidth + d))
            }
        }
    }
}
