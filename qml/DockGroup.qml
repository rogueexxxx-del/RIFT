import QtQuick
import QtQuick.Controls

Rectangle {
    id: group
    objectName: "dock-" + groupId
    required property var workspace
    required property string groupId
    readonly property var info: workspace ? workspace.groupInfo(groupId) : null
    readonly property var tabs: info ? info.tabs : []
    property alias bodyItem: body
    radius: 0
    color: Theme.bg
    border.width: workspace && workspace.dragPanel !== "" && workspace.dropGroup === groupId ? 1 : 0
    border.color: workspace && workspace.dragPanel !== "" && workspace.dropGroup === groupId
        ? Theme.accent : Theme.hairline
    clip: true

    function revealTab(tab) {
        if (!tab) return
        const edge = Math.max(0, tab.x + tab.width - tabScroll.width)
        tabScroll.contentX = Math.max(0, Math.min(tabScroll.contentX, tab.x))
        if (tab.x + tab.width > tabScroll.contentX + tabScroll.width)
            tabScroll.contentX = edge
    }
    function activateTab(index) {
        index = Math.max(0, Math.min(tabs.length - 1, index))
        workspace.showPanel(tabs[index])
        const tab = tabRepeater.itemAt(index)
        if (tab) { tab.forceActiveFocus(); revealTab(tab) }
    }
    function revealActiveTab() {
        for (let i = 0; i < tabRepeater.count; ++i) {
            const tab = tabRepeater.itemAt(i)
            if (tab && tab.selected) revealTab(tab)
        }
    }
    function openPanelMenu(panelId, anchor) {
        panelMenu.panelId = panelId
        panelMenu.popup(anchor, Qt.point(0, anchor.height))
    }

    component HeaderButton: ToolButton {
        id: headerButton
        property url iconSource: ""
        width: visible ? 32 : 0
        height: 32
        focusPolicy: Qt.StrongFocus
        contentItem: Item {
            Text {
                anchors.fill: parent
                visible: String(headerButton.iconSource) === ""
                text: headerButton.text
                color: headerButton.enabled ? Theme.text : Theme.textDisabled
                font.family: Theme.fontUI
                font.pixelSize: Theme.size
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            AssetIcon {
                anchors.centerIn: parent
                width: 16; height: 16
                source: headerButton.iconSource
                color: headerButton.enabled ? Theme.text : Theme.textDisabled
                visible: String(source) !== ""
            }
        }
        background: Rectangle {
            radius: Theme.radius
            color: parent.down ? Theme.raised : parent.hovered ? Theme.hover : "transparent"
            border.width: parent.visualFocus ? Theme.focusWidth : 0
            border.color: Theme.focusRing
        }
    }

    Rectangle {
        id: header
        readonly property real naturalTabsWidth: group.tabs.reduce(function(sum, id) {
            return sum + Math.max(54, tabMetrics.advanceWidth(group.workspace.panelTitle(id)) + 24)
        }, 0)
        readonly property bool overflow: naturalTabsWidth > width - actionButton.width - menuButton.width
        anchors.left: parent.left
        anchors.right: parent.right
        height: 32
        color: Theme.panel
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.hairline
        }
        FontMetrics {
            id: tabMetrics
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
        }

        HeaderButton {
            id: previousTabs
            objectName: "previousDockTabs"
            anchors.left: menuButton.right
            visible: header.overflow
            enabled: tabScroll.contentX > 0
            text: "‹"
            Accessible.name: "Previous panel tabs"
            onClicked: tabScroll.contentX = Math.max(0, tabScroll.contentX - tabScroll.width)
        }
        HeaderButton {
            id: nextTabs
            objectName: "nextDockTabs"
            anchors.right: actionButton.left
            visible: header.overflow
            enabled: tabScroll.contentX < tabScroll.contentWidth - tabScroll.width - 1
            text: "›"
            Accessible.name: "Next panel tabs"
            onClicked: tabScroll.contentX = Math.min(tabScroll.contentWidth - tabScroll.width,
                tabScroll.contentX + tabScroll.width)
        }

        Flickable {
            id: tabScroll
            objectName: "dockTabs"
            anchors.left: previousTabs.right
            anchors.right: nextTabs.left
            height: parent.height
            contentWidth: tabRow.width
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            onWidthChanged: Qt.callLater(group.revealActiveTab)
            WheelHandler {
                target: null
                onWheel: (event) => {
                    const delta = event.pixelDelta.x || event.pixelDelta.y
                        || (event.angleDelta.x || event.angleDelta.y) / 2
                    tabScroll.contentX = Math.max(0, Math.min(tabScroll.contentWidth - tabScroll.width,
                        tabScroll.contentX - delta))
                    event.accepted = true
                }
            }

            Row {
                id: tabRow
                height: header.height
                Repeater {
                    id: tabRepeater
                    model: group.tabs.length
                    delegate: Rectangle {
                        id: tab
                        required property int index
                        readonly property string modelData: group.tabs[index] || ""
                        objectName: "tab-" + modelData
                        readonly property bool selected: group.info && group.info.active === modelData
                        width: Math.max(32, Math.min(tabScroll.width, Math.max(54, label.implicitWidth + 24)))
                        height: header.height
                        color: "transparent"
                        radius: 0
                        activeFocusOnTab: true
                        border.width: 0
                        border.color: Theme.focusRing
                        onSelectedChanged: if (selected) Qt.callLater(group.revealActiveTab)
                        onActiveFocusChanged: if (activeFocus) group.revealTab(tab)
                        Keys.onLeftPressed: group.activateTab(index - 1)
                        Keys.onRightPressed: group.activateTab(index + 1)
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Home) group.activateTab(0)
                            else if (event.key === Qt.Key_End) group.activateTab(group.tabs.length - 1)
                            else if (event.key === Qt.Key_Menu
                                     || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)))
                                group.openPanelMenu(modelData, tab)
                            else return
                            event.accepted = true
                        }
                        Keys.onReturnPressed: group.workspace.showPanel(modelData)
                        Keys.onSpacePressed: group.workspace.showPanel(modelData)
                        Accessible.role: Accessible.PageTab
                        Accessible.selected: selected
                        Accessible.name: group.workspace.panelTitle(modelData)
                        Accessible.onPressAction: group.workspace.showPanel(modelData)
                        Text {
                            id: label
                            anchors.centerIn: parent
                            width: parent.width - 24
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: group.workspace.panelTitle(tab.modelData)
                            color: tab.selected || tabHover.hovered ? Theme.text : Theme.textMuted
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeSmall
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 24
                            height: tab.activeFocus ? Theme.focusWidth : 1
                            color: tab.activeFocus ? Theme.focusRing : tab.selected ? Theme.accent : "transparent"
                        }
                        HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: group.workspace.showPanel(tab.modelData) }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: group.openPanelMenu(tab.modelData, tab)
                        }
                        DragHandler {
                            enabled: tab.modelData !== "preview"
                            target: null
                            onCanceled: group.workspace.cancelDrag()
                            onActiveChanged: {
                                if (active) group.workspace.startDrag(tab.modelData)
                                else if (group.workspace.dragPanel === tab.modelData)
                                    group.workspace.finishDrag()
                            }
                            onTranslationChanged: if (active) {
                                const point = tab.mapToGlobal(centroid.position.x, centroid.position.y)
                                group.workspace.updateDrag(point.x, point.y)
                            }
                        }
                        ToolTipArea {
                            text: group.workspace.panelTitle(tab.modelData) + "\n"
                                + (tab.modelData === "preview" ? "Preview stays in the main window"
                                : "Drag to a panel center to group, an edge to split, or outside to float")
                        }
                    }
                }
            }
        }

        HeaderButton {
            id: actionButton
            readonly property bool available: group.info && (group.info.active === "effects" || group.info.active === "presets")
            anchors.right: parent.right
            visible: available
            text: "+"
            onClicked: group.workspace.panelActionRequested(group.info.active)
            ToolTipArea { text: group.info && group.info.active === "effects" ? "Add effect" : "Save preset" }
            Accessible.role: Accessible.Button
            Accessible.name: group.info && group.info.active === "effects" ? "Add effect" : "Save preset"
            Accessible.onPressAction: group.workspace.panelActionRequested(group.info.active)
        }
        HeaderButton {
            id: menuButton
            objectName: "dockOptions"
            anchors.left: parent.left
            text: "☰"
            iconSource: Theme.asset("icons inspo/icons8-hamburger-menu.svg")
            onClicked: group.openPanelMenu(group.info ? group.info.active : "", menuButton)
            Accessible.role: Accessible.Button
            Accessible.name: "Panel options"
            Accessible.onPressAction: {
                group.openPanelMenu(group.info ? group.info.active : "", menuButton)
            }
        }
    }

    Item {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 0
        clip: true
    }

    StyledMenu {
        id: panelMenu
        objectName: "dockPanelMenu"
        property string panelId: ""
        StyledMenuItem {
            objectName: "hideDockPanel"
            text: "Hide panel"
            enabled: !!group.workspace && panelMenu.panelId !== ""
            onTriggered: group.workspace.hidePanel(panelMenu.panelId)
        }
        StyledMenuItem {
            text: "Float panel"
            enabled: !!group.workspace && panelMenu.panelId !== "preview" && !group.workspace.isFloating(group.groupId)
            onTriggered: {
                const point = group.mapToGlobal(24, 40)
                group.workspace.floatPanel(panelMenu.panelId, point.x, point.y)
            }
        }
        StyledMenuItem {
            text: "Return to workspace"
            enabled: !!group.workspace && group.workspace.isFloating(group.groupId)
            onTriggered: group.workspace.returnGroup(group.groupId)
        }
        StyledMenuItem { text: "Reset workspace"; onTriggered: group.workspace.resetLayout() }
    }
}
