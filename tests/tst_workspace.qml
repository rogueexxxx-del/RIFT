import QtQuick
import QtQuick.Window
import QtTest
import "../qml"
import "../qml/DockLayout.js" as DockLayout

Item {
    id: root
    width: 1440
    height: 800
    DockWorkspace {
        id: workspace
        anchors.fill: parent
        persistLayout: false
        layoutLocation: Qt.resolvedUrl("workspace.ini")
    }
    Component { id: panelComponent; Item { property int preservedValue: 42; anchors.fill: parent } }
    TestCase {
        name: "Workspace"
        when: windowShown
        property var originalPanels: ({})
        property int originalBodySize: Theme.size
        property int originalSmallSize: Theme.sizeSmall
        function initTestCase() {
            originalBodySize = Theme.size
            originalSmallSize = Theme.sizeSmall
            const panels = {}
            for (const id of DockLayout.panelIds)
                panels[id] = panelComponent.createObject(workspace.parkingItem, {objectName: "panel-" + id})
            originalPanels = panels
            workspace.panels = panels
            tryCompare(workspace, "ready", true)
            wait(30)
        }
        function cleanup() {
            Theme.size = originalBodySize
            Theme.sizeSmall = originalSmallSize
            root.width = 1440
            root.height = 800
            workspace.persistLayout = false
            workspace.live = false
            workspace.resetLayout()
            wait(30)
        }
        function test_initialLayout() {
            verify(DockLayout.valid(workspace.state, false))
            for (const id of DockLayout.panelIds) {
                const owner = DockLayout.owner(workspace.state, id)
                verify(workspace.holders[owner.id] !== undefined, "group exists for " + id)
                compare(originalPanels[id].parent, workspace.holders[owner.id].bodyItem)
                compare(originalPanels[id].visible, owner.active === id)
            }
            compare(originalPanels.preview.width > 0, true)
        }
        function test_adaptiveTimeline_data() {
            return [{tag: "150 percent", width: 1280, height: 600},
                {tag: "200 percent", width: 960, height: 440}]
        }
        function test_adaptiveTimeline(data) {
            root.width = data.width; root.height = data.height
            wait(30)
            verify(originalPanels.timeline.height >= 220, "video and audio fit below the dock header")
            workspace.resizeSplit("rows", data.height * 0.60, 0, data.height - 6)
            const ratio = workspace.state.root.ratio
            root.height += 100
            wait(30)
            fuzzyCompare(workspace.placement.groups.timeline.height, (root.height - 6) * (1 - ratio), 0.01)
        }
        function test_inspectorOverflowAndKeyboard_data() {
            return [{tag: "normal text", small: 12, body: 14},
                {tag: "large text", small: 18, body: 20}]
        }
        function test_inspectorOverflowAndKeyboard(data) {
            Theme.sizeSmall = data.small
            Theme.size = data.body
            root.width = 960
            wait(30)
            const group = workspace.holders.settings
            const next = findChild(group, "nextDockTabs")
            const previous = findChild(group, "previousDockTabs")
            const scroll = findChild(group, "dockTabs")
            verify(next.visible && previous.visible, "overflow navigation is visible")
            verify(next.width >= 32 && next.height >= 32)
            mouseClick(next, 16, 16)
            verify(scroll.contentX > 0)
            const first = findChild(group, "tab-params")
            first.forceActiveFocus()
            keyClick(Qt.Key_End)
            compare(group.info.active, "audio")
            const last = findChild(group, "tab-audio")
            verify(last.activeFocus)
            verify(last.x >= scroll.contentX && last.x + last.width <= scroll.contentX + scroll.width + 1)
            keyClick(Qt.Key_Home)
            compare(group.info.active, "params")
            const menuButton = findChild(group, "dockOptions")
            menuButton.forceActiveFocus()
            keyClick(Qt.Key_Space)
            const menu = findChild(group, "dockPanelMenu")
            tryCompare(menu, "visible", true)
            compare(menu.panelId, "params")
            menu.close()
        }
        function test_toggleInactiveTabPreservesObject() {
            const panel = originalPanels.clip
            verify(workspace.isPanelVisible("clip"))
            verify(!workspace.isPanelActive("clip"))
            verify(workspace.togglePanel("clip"))
            wait(30)
            verify(!workspace.isPanelVisible("clip"))
            compare(panel.parent, workspace.parkingItem)
            verify(!panel.visible)
            verify(workspace.togglePanel("clip"))
            wait(30)
            verify(workspace.isPanelVisible("clip"))
            verify(workspace.isPanelActive("clip"))
            compare(originalPanels.clip, panel)
            compare(panel.preservedValue, 42)
        }
        function test_hideAllAndRestore() {
            const preview = originalPanels.preview
            const window = preview.Window.window
            for (const id of DockLayout.panelIds) verify(workspace.hidePanel(id))
            wait(30)
            compare(workspace.state.root, null)
            compare(workspace.state.floating.length, 0)
            verify(DockLayout.valid(workspace.state, false))
            for (const id of DockLayout.panelIds) {
                compare(originalPanels[id].parent, workspace.parkingItem)
                verify(workspace.showPanel(id))
                wait(10)
                verify(workspace.isPanelVisible(id))
                compare(originalPanels[id].preservedValue, 42)
            }
            compare(originalPanels.preview, preview)
            compare(preview.Window.window, window)
        }
        function test_tabContextMenuHidesInactiveTab() {
            const group = workspace.holders.effects
            const tab = findChild(group, "tab-presets")
            group.revealTab(tab)
            mouseClick(tab, tab.width / 2, tab.height / 2, Qt.RightButton)
            const menu = findChild(group, "dockPanelMenu")
            tryCompare(menu, "visible", true)
            compare(menu.panelId, "presets")
            const hide = findChild(group, "hideDockPanel")
            mouseClick(hide, hide.width / 2, hide.height / 2)
            tryVerify(function() { return !workspace.isPanelVisible("presets") })
            compare(originalPanels.presets.parent, workspace.parkingItem)
        }
        function test_floatReturnWithoutPreview() {
            workspace.floatPanel("queue", 100, 100)
            wait(30)
            const floating = DockLayout.owner(workspace.state, "queue").id
            for (const id of DockLayout.panelIds)
                if (id !== "queue") workspace.hidePanel(id)
            wait(30)
            workspace.returnGroup(floating)
            wait(30)
            verify(DockLayout.valid(workspace.state, false))
            compare(workspace.state.floating.length, 0)
            verify(workspace.isPanelVisible("queue"))
            compare(originalPanels.queue.parent, workspace.holders.settings.bodyItem)
        }
        function test_centerGroupsOnlyDraggedPanel() {
            const preview = originalPanels.preview
            verify(workspace.apply(DockLayout.move(workspace.state, "queue", "effects", "center", "test-center", null)))
            wait(30)
            compare(DockLayout.owner(workspace.state, "queue").id, "effects")
            compare(DockLayout.owner(workspace.state, "params").id, "settings")
            compare(originalPanels.queue.parent, workspace.holders.effects.bodyItem)
            compare(originalPanels.queue.visible, true)
            compare(originalPanels.effects.visible, false)
            compare(originalPanels.preview, preview)
            compare(originalPanels.queue.preservedValue, 42)
        }
        function test_split_data() {
            return [{tag:"left"}, {tag:"right"}, {tag:"top"}, {tag:"bottom"}]
        }
        function test_split(data) {
            const id = "split-" + data.tag
            verify(workspace.apply(DockLayout.move(workspace.state, "queue", "program", data.tag, id, null)))
            wait(30)
            compare(DockLayout.owner(workspace.state, "queue").id, id)
            verify(workspace.holders[id] !== undefined)
            compare(originalPanels.queue.parent, workspace.holders[id].bodyItem)
            const rect = workspace.placement.groups[id]
            verify(rect.width > 0 && rect.height > 0)
            workspace.showPanel("params")
            wait(30)
            compare(originalPanels.queue.preservedValue, 42)
        }
        function test_floatAndReturn() {
            workspace.floatPanel("queue", 100, 100)
            wait(50)
            const id = DockLayout.owner(workspace.state, "queue").id
            verify(workspace.isFloating(id))
            compare(workspace.state.floating[0].tabs.length, 1)
            compare(originalPanels.queue.parent, workspace.holders[id].bodyItem)
            workspace.returnGroup(id)
            wait(50)
            compare(workspace.state.floating.length, 0)
            compare(DockLayout.owner(workspace.state, "queue").id, "settings")
            compare(originalPanels.queue.parent, workspace.holders.settings.bodyItem)
        }
        function test_dragTabCreatesGroup() {
            const next = findChild(workspace.holders.effects, "nextDockTabs")
            if (next.visible && next.enabled) mouseClick(next, 16, 16)
            const tab = findChild(workspace.holders.effects, "tab-presets")
            verify(tab !== null)
            const start = tab.mapToItem(workspace, tab.width / 2, tab.height / 2)
            const target = workspace.placement.groups.program
            mouseDrag(tab, tab.width / 2, tab.height / 2,
                target.x + target.width / 2 - start.x,
                target.y + target.height / 2 - start.y, Qt.LeftButton, Qt.NoModifier, 30)
            wait(50)
            compare(DockLayout.owner(workspace.state, "presets").id, "program")
            compare(originalPanels.presets.parent, workspace.holders.program.bodyItem)
        }
        function test_resizeDoesNotDestroyHandle() {
            const handle = findChild(workspace, "split-main")
            verify(handle !== null)
            const before = workspace.placement.groups.effects.width
            mouseDrag(handle, handle.width / 2, handle.height / 2, 90, 0, Qt.LeftButton, Qt.NoModifier, 30)
            wait(30)
            compare(findChild(workspace, "split-main"), handle)
            verify(workspace.placement.groups.effects.width > before + 40)
        }
        function test_switchModesPreservesPanelObjects() {
            workspace.live = true
            wait(30)
            verify(DockLayout.valid(workspace.state, true))
            compare(originalPanels.timeline.parent, workspace.parkingItem)
            workspace.live = false
            wait(30)
            verify(DockLayout.valid(workspace.state, false))
            compare(originalPanels.timeline.parent, workspace.holders.timeline.bodyItem)
            compare(originalPanels.timeline.preservedValue, 42)
        }
        function test_badStateRejected() {
            const before = JSON.stringify(workspace.state)
            verify(!workspace.apply({version:1,root:{id:"bad",tabs:["unknown"],active:"unknown"},floating:[]}))
            compare(JSON.stringify(workspace.state), before)
        }
        function test_hiddenStateRoundTrip() {
            workspace.persistLayout = true
            workspace.hidePanel("clip")
            workspace.hidePanel("timeline")
            const saved = JSON.stringify(workspace.state)
            wait(350)
            workspace.resetLayout()
            workspace.restoreLayout()
            wait(30)
            compare(JSON.stringify(workspace.state), saved)
            verify(!workspace.isPanelVisible("clip"))
            verify(!workspace.isPanelVisible("timeline"))
            compare(originalPanels.clip.parent, workspace.parkingItem)
        }
        function test_persistedStateRoundTrip() {
            workspace.persistLayout = true
            verify(workspace.apply(DockLayout.move(workspace.state, "queue", "effects", "center", "persist-test", null)))
            const saved = JSON.stringify(workspace.state)
            wait(350)
            workspace.resetLayout()
            workspace.restoreLayout()
            wait(30)
            compare(JSON.stringify(workspace.state), saved)
        }
        function test_customRatioRestoresWithoutMigration() {
            workspace.persistLayout = true
            workspace.resizeSplit("rows", (root.height - 6) * 0.66, 0, root.height - 6)
            wait(350)
            workspace.restoreLayout()
            fuzzyCompare(workspace.state.root.ratio, 0.66, 0.0001)
            fuzzyCompare(workspace.placement.groups.timeline.height, (root.height - 6) * 0.34, 0.01)
        }
    }
}
