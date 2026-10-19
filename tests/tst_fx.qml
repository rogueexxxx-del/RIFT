import QtQuick
import QtQuick.Controls
import QtTest
import "../qml"

Item {
    width: 360
    height: 640
    ChainBlock { id: sample; label: "Film grain"; effectId: "film_grain"; width: 280 }
    Component { id: coloredBlock; ChainBlock { label: "Ascii"; effectId: "ascii"; width: 280; z: 1000 } }
    SignalSpy { id: activation; target: sample; signalName: "activated" }
    QtObject {
        id: viewport
        property int editedClip: 0
        property int selectedNode: 0
        property string effect: ""
        property var clips: [{}]
        property var chain: [{label: "ASCII", effect: "ascii", selected: true},
                             {label: "Film grain", effect: "film_grain", mix: 0.5}]
        property var presetList: []
        property string added: ""
        property int removed: -1
        property int moved: -1
        property int moveDelta: 0
        property string saved: ""
        function blendNames() { return ["Normal"] }
        function selectClip(index) { editedClip = index }
        function addNode(id) { added = id }
        function removeNode(index) { removed = index }
        function moveNode(index, delta) { moved = index; moveDelta = delta }
        function savePresetNamed(name) { saved = name }
    }
    NodeRail { id: rail; anchors.fill: parent; viewport: viewport; effectIds: ["ascii", "film_grain", "prism_split"] }
    TestCase {
        name: "FxRail"
        when: windowShown
        function init() { failOnWarning(/.*/) }
        function test_compactChainAndReorderPitch() {
            const first = findChild(rail, "chain-holder-0")
            const second = findChild(rail, "chain-holder-1")
            verify(first !== null, "Chain rows must expose their real layout pitch")
            verify(first.height <= 72)
            first.dy = second.y - first.y
            compare(first.shift, 1)
            first.dy = -(second.y - first.y)
            compare(first.shift, -1)
            first.dy = 0
        }
        function test_searchableRows() {
            rail.openAdd()
            const search = findChild(rail, "effect-search")
            verify(search !== null)
            search.text = "FiLm GrAiN"
            const hits = findChild(rail, "effect-results")
            compare(hits.snapMode, ListView.SnapToItem)
            fuzzyCompare((hits.height + hits.spacing) % (64 + hits.spacing), 0, 0.01)
            tryCompare(hits, "count", 1)
            verify(hits.currentItem.height <= 64)
            compare(hits.currentItem.width, hits.width)
            keyClick(Qt.Key_Return)
            compare(viewport.added, "film_grain")
        }
        function test_compactBlock() {
            verify(sample.implicitHeight <= 64, "Effect rows must not be square tiles")
            verify(Qt.colorEqual(sample.nodeColor, Theme.effectColor("film_grain")))
        }
        function test_integratedPreviewPattern() {
            const preview = findChild(sample, "effect-preview")
            const pattern = findChild(sample, "effect-pattern")
            const mask = findChild(sample, "effect-text-mask")
            const text = findChild(sample, "effect-text")
            compare(preview.fillMode, Image.PreserveAspectCrop)
            compare(preview.smooth, false)
            compare(preview.visible, false)
            verify(preview.opacity > 0 && preview.opacity <= 0.35)
            compare(findChild(sample, "effect-thumbnail"), null)
            compare(pattern.width, sample.width - sample.border.width * 2)
            compare(pattern.height, sample.height - sample.border.width * 2)
            compare(preview.width, pattern.width)
            compare(preview.height, pattern.height)
            compare(mask.gradient.orientation, Gradient.Horizontal)
            compare(mask.gradient.stops[1].position, 0.72)
            verify(Qt.colorEqual(mask.gradient.stops[1].color, sample.color))
            verify(text.x + text.width <= sample.width * 0.72)
            verify(Qt.colorEqual(text.children[0].color, Theme.text))
            sample.active = true
            verify(Qt.colorEqual(mask.gradient.stops[1].color, sample.color))
            sample.active = false
            verify(findChild(sample, "effect-preview-popup") !== null)
        }
        function test_effectDescription() {
            sample.effectId = "ascii"
            verify(Qt.colorEqual(sample.nodeColor, Theme.effectColor("ascii")))
            const description = findChild(sample, "effect-description")
            compare(description.text, "Rebuilds the image using characters and symbols.")
            compare(description.wrapMode, Text.WordWrap)
            compare(findChild(sample, "effect-expanded-preview"), null)
            sample.effectId = "film_grain"
        }
        function test_coloredPatternPixels() {
            const block = createTemporaryObject(coloredBlock, sample.parent)
            const image = findChild(block, "effect-preview")
            const ink = findChild(block, "effect-colored-pattern")
            image.source = Qt.resolvedUrl("../assets/ascii.png")
            tryCompare(image, "status", Image.Ready)
            tryVerify(() => ink.paintRevision > 0)
            wait(50)
            const pixels = ink.getContext("2d").getImageData(0, 0, ink.width, ink.height).data
            let colored = 0, clear = 0, opaqueInk = 0
            for (let i = 0; i < pixels.length; i += 4) {
                if (pixels[i + 3] === 0) { clear++; continue }
                colored++
                // Near-transparent pixels lose RGB precision during unpremultiplication.
                if (pixels[i + 3] >= 64) {
                    opaqueInk++
                    verify(Math.abs(pixels[i] - Math.round(block.nodeColor.r * 255)) <= 4)
                    verify(Math.abs(pixels[i + 1] - Math.round(block.nodeColor.g * 255)) <= 4)
                    verify(Math.abs(pixels[i + 2] - Math.round(block.nodeColor.b * 255)) <= 4)
                }
            }
            verify(colored > 0 && clear > 0 && opaqueInk > 0,
                "Colored=" + colored + " clear=" + clear + " length=" + pixels.length)
            verify(colored < pixels.length / 4 * 0.6, "Background must not become a solid colored card")
        }
        function test_sourceHasNoPattern() {
            sample.isSource = true
            compare(findChild(sample, "effect-preview").visible, false)
            compare(String(findChild(sample, "effect-preview").source), "")
            sample.isSource = false
        }
        function test_keyboardActivation() {
            activation.clear()
            sample.forceActiveFocus()
            keyClick(Qt.Key_Return)
            keyClick(Qt.Key_Space)
            compare(activation.count, 2)
        }
    }
}
