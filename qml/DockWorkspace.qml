import QtQuick
import QtQuick.Window
import QtCore
import "DockLayout.js" as DockLayout

Item {
    id: workspace
    property var panels: ({})
    property bool live: false
    property bool persistLayout: true
    property var floatingFocusItem: null
    property var state: DockLayout.defaultState(live)
    property bool adaptiveRows: true
    readonly property var placement: DockLayout.placements(state, width, height, adaptiveRows)
    property alias parkingItem: parking
    property alias layoutLocation: settings.location
    signal panelActionRequested(string panelId)
    property string dragPanel: ""
    property real dragX: 0
    property real dragY: 0
    property string dropGroup: ""
    property string dropZone: ""
    property rect dropRect: Qt.rect(0, 0, 0, 0)
    property bool ready: false
    property int nextId: 1
    property var holders: ({})
    readonly property var titles: ({ effects: "Effect Chain", presets: "Presets", preview: "Preview",
        params: "Parameters", clip: "Clip", color: "Color", queue: "Queue", timeline: "Timeline",
        levels: "Levels", controls: "Controls", audio: "Audio Input" })

    Settings {
        id: settings
        category: "workspace"
        property string reactLayout: ""
        property string liveLayout: ""
    }
    Item { id: parking; visible: false }
    ListModel { id: groupModel }
    ListModel { id: splitModel }
    Timer {
        id: saveDelay
        interval: 250
        onTriggered: {
            if (!workspace.persistLayout || !workspace.ready) return
            const json = JSON.stringify(workspace.state)
            if (workspace.live) settings.liveLayout = json
            else settings.reactLayout = json
        }
    }

    function panelTitle(id) { return titles[id] || id }
    function groupInfo(id) { return DockLayout.find(state, id) }
    function isFloating(id) { return state.floating.some(function(g) { return g.id === id }) }
    function isPanelActive(id) {
        const g = DockLayout.owner(state, id)
        return !!g && g.active === id
    }
    function newId() {
        let id
        do { id = "group-" + nextId++ } while (DockLayout.find(state, id))
        return id
    }
    function parkPanels() {
        for (const id of Object.keys(panels)) {
            const panel = panels[id]
            if (panel) { panel.parent = parking; panel.visible = false }
        }
    }
    function attachPanels() {
        for (const id of Object.keys(panels)) {
            const panel = panels[id]
            if (!panel) continue
            const owner = DockLayout.owner(state, id)
            const holder = owner ? holders[owner.id] : null
            if (holder) {
                panel.parent = holder.bodyItem
                panel.visible = owner.active === id
            } else {
                panel.parent = parking
                panel.visible = false
            }
        }
    }
    function apply(next) {
        if (!DockLayout.valid(next, live)) return false
        parkPanels()
        state = next
        const ids = DockLayout.allGroups(state).map(function(g) { return g.id })
        for (let i = groupModel.count - 1; i >= 0; --i) {
            if (ids.indexOf(groupModel.get(i).gid) < 0) groupModel.remove(i)
        }
        for (const id of ids) {
            let found = false
            for (let i = 0; i < groupModel.count; ++i)
                if (groupModel.get(i).gid === id) { found = true; break }
            if (!found) groupModel.append({ gid: id })
        }
        const splits = placement.handles.map(function(h) { return h.id })
        for (let i = splitModel.count - 1; i >= 0; --i)
            if (splits.indexOf(splitModel.get(i).sid) < 0) splitModel.remove(i)
        for (const id of splits) {
            let found = false
            for (let i = 0; i < splitModel.count; ++i)
                if (splitModel.get(i).sid === id) { found = true; break }
            if (!found) splitModel.append({ sid: id })
        }
        Qt.callLater(attachPanels)
        if (ready) saveDelay.restart()
        return true
    }
    function restoreLayout() {
        saveDelay.stop()
        cancelDrag()
        adaptiveRows = true
        let restored = null
        if (persistLayout) {
            try { restored = JSON.parse(live ? settings.liveLayout : settings.reactLayout) }
            catch (error) { restored = null }
        }
        if (DockLayout.valid(restored, live)) {
            for (const g of restored.floating) {
                const visible = Qt.application.screens.some(function(screen) {
                    return g.x + g.width > screen.virtualX + 80 && g.x < screen.virtualX + screen.width - 80
                        && g.y + g.height > screen.virtualY + 40 && g.y < screen.virtualY + screen.height - 40
                })
                if (!visible) {
                    const point = mapToGlobal(20, 40)
                    g.x = point.x; g.y = point.y
                }
            }
        }
        apply(DockLayout.valid(restored, live) ? restored : DockLayout.defaultState(live))
        ready = true
    }
    function resetLayout() { cancelDrag(); adaptiveRows = true; apply(DockLayout.defaultState(live)) }
    function isPanelVisible(id) { return !!DockLayout.owner(state, id) }
    function showPanel(id) { return apply(DockLayout.show(state, id, live, newId())) }
    function hidePanel(id) { return apply(DockLayout.hide(state, id)) }
    function togglePanel(id) { return isPanelVisible(id) ? hidePanel(id) : showPanel(id) }
    function floatPanel(id, gx, gy) {
        if (!id || id === "preview") return
        apply(DockLayout.move(state, id, "", "float", newId(),
            { x: Math.round(gx), y: Math.round(gy), width: id === "timeline" ? 1000 : 380,
              height: id === "timeline" ? 360 : 520 }))
    }
    function returnGroup(id) {
        const floating = groupInfo(id)
        if (!floating || !isFloating(id)) return
        let next = state
        for (const panel of floating.tabs.slice()) {
            next = DockLayout.show(DockLayout.hide(next, panel), panel, live, newId())
        }
        apply(next)
    }
    function rememberGeometry(id, x, y, w, h) {
        const g = groupInfo(id)
        if (!g || !isFloating(id) || !ready || w < 180 || h < 100) return
        if (g.x === x && g.y === y && g.width === w && g.height === h) return
        const next = DockLayout.copy(state)
        const changed = DockLayout.find(next, id)
        changed.x = x; changed.y = y; changed.width = w; changed.height = h
        state = next
        saveDelay.restart()
    }
    function resizeSplit(id, position, origin, extent) {
        if (extent <= 0) return
        if (id === "rows") adaptiveRows = false
        const next = DockLayout.copy(state)
        DockLayout.setRatio(next.root, id, (position - origin) / extent)
        state = next
        saveDelay.restart()
    }
    function startDrag(panel) {
        dragPanel = panel
        dropGroup = ""
        dropZone = ""
    }
    function updateDrag(gx, gy) {
        const point = mapFromGlobal(gx, gy)
        dragX = point.x; dragY = point.y
        dropGroup = ""; dropZone = ""
        for (let i = state.floating.length - 1; i >= 0; --i) {
            const g = state.floating[i]
            if (gx >= g.x && gx <= g.x + g.width && gy >= g.y && gy <= g.y + g.height) {
                dropGroup = g.id; dropZone = "center"; return
            }
        }
        for (const g of DockLayout.groups(state.root)) {
            const r = placement.groups[g.id]
            if (!r || point.x < r.x || point.x > r.x + r.width
                || point.y < r.y || point.y > r.y + r.height) continue
            dropGroup = g.id
            const x = (point.x - r.x) / r.width, y = (point.y - r.y) / r.height
            const edge = Math.min(x, 1 - x, y, 1 - y)
            dropZone = edge > 0.22 ? "center" : edge === x ? "left"
                : edge === 1 - x ? "right" : edge === y ? "top" : "bottom"
            dropRect = Qt.rect(r.x, r.y, r.width, r.height)
            if (dropZone === "left" || dropZone === "right") {
                dropRect = Qt.rect(r.x + (dropZone === "right" ? r.width / 2 : 0),
                    r.y, r.width / 2, r.height)
            } else if (dropZone === "top" || dropZone === "bottom") {
                dropRect = Qt.rect(r.x, r.y + (dropZone === "bottom" ? r.height / 2 : 0),
                    r.width, r.height / 2)
            }
            break
        }

    }
    function finishDrag() {
        if (!dragPanel) return
        const panel = dragPanel, target = dropGroup, zone = dropZone
        const point = mapToGlobal(dragX, dragY)
        cancelDrag()
        if (target) apply(DockLayout.move(state, panel, target, zone, newId(), null))
        else if (dragX < 0 || dragY < 0 || dragX > width || dragY > height)
            floatPanel(panel, point.x - 60, point.y - 15)
    }
    function cancelDrag() { dragPanel = ""; dropGroup = ""; dropZone = "" }

    onLiveChanged: if (ready) {
        if (persistLayout) {
            if (live) settings.reactLayout = JSON.stringify(state)
            else settings.liveLayout = JSON.stringify(state)
        }
        restoreLayout()
    }
    onPanelsChanged: if (ready) Qt.callLater(attachPanels)
    Component.onCompleted: Qt.callLater(restoreLayout)
    Component.onDestruction: parkPanels()

    Repeater {
        model: groupModel
        delegate: Item {
            id: holder
            required property string gid
            readonly property var manager: workspace
            readonly property var info: workspace.groupInfo(gid)
            readonly property bool floating: workspace.isFloating(gid)
            readonly property var rect: workspace.placement.groups[gid]
            parent: floating ? floatWindow.contentItem : workspace
            x: floating ? 0 : rect ? rect.x : 0
            y: floating ? 0 : rect ? rect.y : 0
            width: floating ? floatWindow.width : rect ? rect.width : 0
            height: floating ? floatWindow.height : rect ? rect.height : 0
            visible: !!info
            Window {
                id: floatWindow
                transientParent: workspace.Window.window
                title: "RIFT | " + (holder.info ? workspace.panelTitle(holder.info.active) : "Panel")
                visible: holder.floating
                minimumWidth: 180
                minimumHeight: 100
                width: holder.floating && holder.info ? holder.info.width : 380
                height: holder.floating && holder.info ? holder.info.height : 520
                x: holder.floating && holder.info ? holder.info.x : 0
                y: holder.floating && holder.info ? holder.info.y : 0
                color: Theme.bg
                onActiveChanged: if (active) workspace.floatingFocusItem = activeFocusItem
                onActiveFocusItemChanged: if (active) workspace.floatingFocusItem = activeFocusItem
                onClosing: (close) => { close.accepted = false; workspace.returnGroup(holder.gid) }
                onXChanged: if (visible) geometryDelay.restart()
                onYChanged: if (visible) geometryDelay.restart()
                onWidthChanged: if (visible) geometryDelay.restart()
                onHeightChanged: if (visible) geometryDelay.restart()
                Timer {
                    id: geometryDelay
                    interval: 200
                    onTriggered: workspace.rememberGeometry(holder.gid, floatWindow.x,
                        floatWindow.y, floatWindow.width, floatWindow.height)
                }
            }
            DockGroup {
                id: dockGroup
                anchors.fill: parent
                workspace: holder.manager
                groupId: holder.gid
            }
            Component.onCompleted: {
                workspace.holders[gid] = dockGroup
                Qt.callLater(workspace.attachPanels)
            }
            Component.onDestruction: { delete workspace.holders[gid] }
        }
    }

    Repeater {
        model: splitModel
        delegate: Rectangle {
            id: divider
            required property string sid
            readonly property var modelData: workspace.placement.handles.find(function(h) {
                return h.id === divider.sid
            }) || { id: "", axis: "horizontal", origin: 0, extent: 0, x: 0, y: 0, width: 0, height: 0 }
            objectName: "split-" + sid
            x: modelData.x; y: modelData.y
            width: modelData.width; height: modelData.height
            color: "transparent"
            Rectangle {
                anchors.centerIn: parent
                width: divider.modelData.axis === "horizontal" ? 1 : parent.width
                height: divider.modelData.axis === "horizontal" ? parent.height : 1
                color: resizeHover.hovered || resizeDrag.active ? Theme.borderHover : Theme.hairline
            }
            HoverHandler {
                id: resizeHover
                cursorShape: divider.modelData.axis === "horizontal" ? Qt.SplitHCursor : Qt.SplitVCursor
            }
            DragHandler {
                id: resizeDrag
                target: null
                property real origin: 0
                property real extent: 1
                onActiveChanged: if (active) {
                    origin = divider.modelData.origin
                    extent = divider.modelData.extent
                }
                onTranslationChanged: if (active) {
                    const point = workspace.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y)
                    workspace.resizeSplit(divider.modelData.id,
                        divider.modelData.axis === "horizontal" ? point.x : point.y, origin, extent)
                }
            }
        }
    }

    Rectangle {
        visible: workspace.dragPanel !== "" && workspace.dropGroup !== ""
            && !workspace.isFloating(workspace.dropGroup)
        x: workspace.dropRect.x; y: workspace.dropRect.y
        width: workspace.dropRect.width; height: workspace.dropRect.height
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
        border.width: 1
        border.color: Theme.accent
        z: 100
        Text {
            anchors.centerIn: parent
            text: workspace.dropZone === "center" ? "Group as tab" : "Split " + workspace.dropZone
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: Theme.size
        }
    }
    Rectangle {
        visible: workspace.dragPanel !== ""
        x: workspace.dragX + 12; y: workspace.dragY + 12
        width: dragLabel.implicitWidth + 20; height: 28
        color: Theme.raised
        border.width: 1; border.color: Theme.borderHover
        z: 101
        Text {
            id: dragLabel
            anchors.centerIn: parent
            text: workspace.panelTitle(workspace.dragPanel)
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeSmall
        }
    }
    Shortcut {
        sequence: "Escape"
        enabled: workspace.dragPanel !== ""
        context: Qt.ApplicationShortcut
        onActivated: workspace.cancelDrag()
    }
}
