import QtQuick
import QtTest
import "../qml"

Item {
    id: root
    width: 960
    height: 720
    property var backend: viewport

    QtObject {
        id: viewport
        property bool liveInput: false
        property real liveLevel: 0.4
        property int liveDevice: 0
        property var devices: [{name: "Speakers (playing)", loopback: true}, {name: "Microphone", loopback: false}]
        property bool midiOpen: false
        property string midiName: "MiniLab"
        property bool oscOpen: false
        property string lastControl: ""
        property int learning: -1
        property string armedControl: ""
        property var allControls: []
        property var params: []
        property var channelNames: [{name: "Bass"}]
        property var channelLevels: [0.2, 0.3, 0.4, 0.5]
        property var grade: []
        property var gradeKeyedNow: []
        property var gradeKeyInterpNow: []
        property var keyedNow: []
        property var keyInterpNow: []
        property var controlMap: []
        property var controlValues: []
        property var markers: []
        property int selectedNode: -1
        property var chain: []
        property string effect: ""
        property int editedClip: 0
        property int activeClipIndex: 0
        property var clips: [{name: "Clip", isText: false, blend: 0, opacity: 0.7, posX: 0, posY: 0, scale: 1}]
        property bool linkAllVisualizers: false
        property var lastBlend: []
        property var lastParam: []
        signal controlChanged()
        signal visualizerColorStyleChanged(int index)
        function liveDevices() { return devices }
        function midiDevices() { return [] }
        function armControl(key) { armedControl = key }
        function connectController() { midiOpen = true }
        function blendNames() { return ["NRM", "ADD", "SCR", "MUL", "DIFF"] }
        function setClipBlend(index, mode, opacity) { lastBlend = [index, mode, opacity] }
        function setNodeBlend(index, mode, mix) { lastBlend = [index, mode, mix] }
        function setParam(index, value) { lastParam = [index, value] }
        function visualizerColorStyle(index) { return {} }
        function systemFonts() { return ["Consolas"] }
        function clipText(index) { return {text: "", font: "", size: 0.18, x: 0.5, y: 0.5, r: 1, g: 1, b: 1, bold: false, letterSpacing: 0, wrapWidth: 0} }
    }

    Component { id: audioComponent; AudioInputPanel { viewport: root.backend; width: 300 } }
    Component { id: liveComponent; LiveBar { viewport: root.backend; width: 300 } }
    Component { id: controllerComponent; ControllerView { viewport: root.backend; width: 300; height: 320 } }
    Component { id: controlComponent; ControlPanel { viewport: root.backend; width: 300; expanded: true } }
    Component { id: inspectorComponent; ClipInspector { viewport: root.backend; width: 300 } }
    Component { id: paramComponent; ParamPanel { viewport: root.backend; width: 300; height: 320 } }
    Component { id: sliderComponent; ParamSlider { width: 240; label: "Opacity"; from: 0; to: 1; stepSize: 0.1; value: 0.5 } }
    Component { id: headerComponent; SectionHeader { width: 300; title: "Audio input" } }
    Component { id: colorComponent; ColorPanel { viewport: root.backend; width: 300 } }
    Component { id: patchComponent; PatchRow { viewport: root.backend; width: 300; paramIndex: 0; channel: 9; depth: 0; depthMax: 1 } }
    Component { id: meterComponent; ChannelMeters { viewport: root.backend; width: 240; height: 120 } }

    TestCase {
        name: "FluentLive"
        when: windowShown
        function init() {
            failOnWarning(/.*/)
            viewport.liveInput = false
            viewport.midiOpen = false
            viewport.armedControl = ""
            viewport.devices = [{name: "Speakers (playing)", loopback: true}, {name: "Microphone", loopback: false}]
            viewport.params = []
            viewport.chain = []
            viewport.selectedNode = -1
            viewport.lastBlend = []
            viewport.lastParam = []
            viewport.grade = []
        }
        function make(component) {
            const item = createTemporaryObject(component, root)
            verify(item !== null)
            return item
        }
        function test_deviceLabelsAndSelection() {
            const panel = make(audioComponent)
            const picker = findChild(panel, "audioCaptureDevice")
            compare(picker.model[0], "Output (loopback): Speakers")
            compare(picker.model[1], "Input: Microphone")
            compare(viewport.liveDevice, 0)
            picker.currentIndex = 1
            picker.activated(1)
            compare(viewport.liveDevice, 1)
            compare(panel.deviceLabel({name: "Interface (PLAYING)", loopback: true}), "Output (loopback): Interface")
            viewport.liveDevice = 0
        }
        function test_emptyDeviceGuidance() {
            viewport.devices = []
            const picker = findChild(make(audioComponent), "audioCaptureDevice")
            compare(picker.count, 0)
            compare(picker.displayText, "No audio devices found")
            verify(!viewport.liveInput)
        }
        function test_independentListeningAndGlow() {
            const bar = make(liveComponent)
            const button = findChild(bar, "audioListeningButton")
            const glow = findChild(bar, "audioListeningGlow")
            compare(button.label, "Audio: stopped")
            verify(!glow.visible)
            viewport.midiOpen = true
            compare(button.label, "Audio: stopped")
            button.clicked()
            verify(viewport.liveInput)
            verify(viewport.midiOpen)
            compare(button.label, "Audio: listening")
            compare(glow.visible, Theme.glowAllowed)
            wait(30)
            const originalAccent = String(Theme.accent)
            Theme.accent = "#64B5F6"
            wait(30)
            Theme.accent = originalAccent
            wait(30)
            viewport.liveInput = false
            verify(!glow.visible)
        }
        function test_contrastDisablesGlow() {
            const original = Theme.preset
            Theme.applyPreset("contrast")
            viewport.liveInput = true
            const glow = findChild(make(liveComponent), "audioListeningGlow")
            verify(!glow.visible)
            Theme.applyPreset(original)
        }
        function test_semanticColorContrast() {
            const slider = make(sliderComponent)
            slider.patched = true
            slider.tint = "#161616"
            const link = findChild(slider, "parameterAudioLink")
            compare(link.linkTextColor, Theme.foregroundFor(slider.tint))
            slider.tint = "#fff000"
            compare(link.linkTextColor, Theme.foregroundFor(slider.tint))
        }
        function test_compactChannelLink() {
            const slider = make(sliderComponent)
            slider.width = 320
            slider.patched = true
            slider.channelName = "Drums"
            slider.tint = "#307D07"
            const name = findChild(slider, "parameterChannelName")
            const link = findChild(slider, "parameterAudioLink")
            wait(20)
            fuzzyCompare(link.x - name.x - name.width, Theme.gapTight, 0.1)
            fuzzyCompare(name.width, name.implicitWidth, 0.1)
            verify(name.color.g > name.color.r && name.color.g > name.color.b)
            verify(Theme.contrastRatio(name.color, Theme.panel) >= 4.5)
        }
        function test_liveWraps() {
            const bar = make(liveComponent)
            wait(30)
            verify(bar.implicitHeight > Theme.control + Theme.padding * 2)
            bar.width = 900
            wait(30)
            verify(bar.implicitHeight < 100)
        }
        function test_sliderKeyboardAndClamp() {
            const slider = make(sliderComponent)
            slider.forceActiveFocus()
            keyClick(Qt.Key_Right)
            fuzzyCompare(slider.shown, 0.6, 0.001)
            keyClick(Qt.Key_End)
            compare(slider.shown, 1)
            keyClick(Qt.Key_Right)
            compare(slider.shown, 1)
            keyClick(Qt.Key_Home)
            compare(slider.shown, 0)
            compare(slider.snap(-4), 0)
            compare(slider.snap(4), 1)
        }
        function test_compactSliderResponsiveHeader() {
            const slider = make(sliderComponent)
            const name = findChild(slider, "parameterName")
            const readouts = findChild(slider, "parameterReadouts")
            const link = findChild(slider, "parameterAudioLink")
            const track = findChild(slider, "parameterTrack")
            slider.width = 320
            wait(20)
            verify(!slider.stackedHeader)
            verify(slider.implicitHeight <= 60)
            verify(name.x + name.width <= readouts.x)
            verify(link.height >= 32)
            slider.width = 180
            slider.label = "Long parameter caption"
            slider.patched = true
            slider.channelName = "Bass"
            wait(20)
            verify(slider.stackedHeader)
            verify(slider.implicitHeight < 84)
            verify(name.y + name.height <= readouts.y)
            verify(readouts.x >= 0)
            verify(readouts.x + readouts.width <= slider.width)
            verify(track.y >= readouts.y + readouts.height + 6)
            compare(slider.shown, 0.5)
            verify(link.height >= 32)
        }
        function test_tighterParameterListKeepsFields() {
            viewport.chain = [{blend: 2, mix: 0.35}]
            viewport.selectedNode = 0
            viewport.params = [{name: "opacity", label: "Opacity", min: 0, max: 1, step: 0.01, value: 0.65, discrete: false, channel: -1, depth: 0, depthMax: 1}]
            const panel = make(paramComponent)
            const list = findChild(panel, "effectParameters")
            wait(20)
            compare(list.count, 1)
            verify(list.spacing <= 6)
            verify(findChild(panel, "effectBlendSelector") !== null)
            compare(viewport.lastParam.length, 0)
        }
        function test_headerKeyboard() {
            const header = make(headerComponent)
            const spy = signalSpy.createObject(root, {target: header, signalName: "toggled"})
            header.forceActiveFocus()
            keyClick(Qt.Key_Space)
            keyClick(Qt.Key_Return)
            compare(spy.count, 2)
            spy.destroy()
        }
        function test_controllerWrapScrollAndMapping() {
            const controller = make(controllerComponent)
            controller.mapping = true
            const knobs = findChild(controller, "controllerKnobs")
            const scroll = findChild(controller, "controllerScroll")
            wait(30)
            verify(knobs.columns < 8)
            verify(scroll.contentHeight > scroll.height)
            const knob = findChild(controller, "controller-cc:112")
            verify(knob !== null)
            verify(knob.width >= 32)
            knob.forceActiveFocus()
            keyClick(Qt.Key_Return)
            compare(viewport.armedControl, "cc:112")
            const lastKnob = findChild(controller, "controller-cc:72")
            lastKnob.forceActiveFocus()
            verify(scroll.contentItem.contentY > 0)
            keyClick(Qt.Key_Escape)
            verify(!controller.mapping)
            compare(viewport.armedControl, "")
            controller.width = 900
            wait(30)
            compare(knobs.columns, 8)
        }
        function test_clipBlendFullNamesPreservesIndexAndOpacity() {
            const picker = findChild(make(inspectorComponent), "clipBlendSelector")
            compare(picker.model[0], "Normal")
            compare(picker.model[2], "Screen")
            compare(picker.model[3], "Multiply")
            picker.currentIndex = 3
            picker.activated(3)
            compare(viewport.lastBlend, [0, 3, 0.7])
        }
        function test_effectBlendPreservesMix() {
            viewport.chain = [{blend: 2, mix: 0.35}]
            viewport.selectedNode = 0
            const picker = findChild(make(paramComponent), "effectBlendSelector")
            compare(picker.currentIndex, 2)
            compare(picker.model[4], "Difference")
            picker.currentIndex = 4
            picker.activated(4)
            compare(viewport.lastBlend, [0, 4, 0.35])
        }
        function test_remainingPanelsLoadAndUnavailablePatch() {
            make(controlComponent)
            make(colorComponent)
            make(patchComponent)
            make(meterComponent)
            make(paramComponent)
            wait(20)
        }
        function test_populatedParametersKeepValues() {
            const parameter = {name: "opacity", label: "Opacity", min: 0, max: 1, step: 0.01, value: 0.65, default: 1, discrete: false, channel: 0, depth: 0.5, depthMax: 1, keyCount: 2}
            viewport.params = [parameter]
            viewport.grade = [parameter]
            const panel = make(paramComponent)
            panel.openRow = 0
            const grade = make(colorComponent)
            grade.openRow = 0
            wait(30)
            compare(viewport.params[0].value, 0.65)
            compare(viewport.grade[0].depth, 0.5)
            compare(viewport.lastParam.length, 0)
        }
    }
    Component { id: signalSpy; SignalSpy {} }
}
