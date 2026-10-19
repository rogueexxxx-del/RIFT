import QtQuick
import QtTest
import "../qml"

Item {
    id: root
    width: 300; height: 100
    Component { id: asset; AssetIcon { color: "white" } }
    Component { id: tool; EditToolButton { x: 64; width: 32; height: 32 } }
    TestCase {
        name: "IconAssets"
        when: windowShown
        property string oldAssets
        function initTestCase() {
            oldAssets = String(Theme.assetsUrl)
            Theme.assetsUrl = Qt.resolvedUrl("../assets/")
        }
        function cleanupTestCase() { Theme.assetsUrl = oldAssets }
        function init() { failOnWarning(/.*/) }
        function test_suppliedIcons_data() {
            return [
                {tag: "cursor", file: "icons8-cursor.svg", kind: "select"},
                {tag: "type", file: "icons8-typography-48.png", kind: "text"},
                {tag: "space", file: "icons8-add-white-space-48.png", kind: "stretch_end"},
                {tag: "video", file: "icons8-video-48.png", kind: "add_clip"},
                {tag: "image", file: "icons8-add-image-48.png", kind: "add_image"},
                {tag: "audio", file: "icons8-add-song-48.png", kind: "add_audio"},
                {tag: "menu", file: "icons8-hamburger-menu.svg", kind: ""}
            ]
        }
        function test_suppliedIcons(data) {
            const icon = createTemporaryObject(asset, root, {source: Theme.asset("icons inspo/" + data.file)})
            verify(icon !== null)
            tryCompare(icon, "ready", true)
            const canvas = findChild(icon, "assetIconInk")
            tryCompare(canvas, "available", true)
            compare(icon.width, 18)
            compare(canvas.width, 48)
            verify(canvas.smooth && canvas.antialiasing && canvas.layer.mipmap)
            wait(30)
            const pixels = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data
            let colored = 0, clear = 0
            for (let i = 0; i < pixels.length; i += 4) {
                if (pixels[i + 3] === 0) clear++
                if (pixels[i + 3] >= 128) {
                    colored++
                    verify(pixels[i] >= 250 && pixels[i + 1] >= 250 && pixels[i + 2] >= 250)
                }
            }
            verify(colored > 0 && clear > 0, "Reference glyph must render as tinted ink, not a solid square")
            if (data.kind !== "") {
                const button = createTemporaryObject(tool, root, {kind: data.kind})
                compare(String(button.iconSource), String(icon.source))
                compare(button.width, 32)
                compare(findChild(button, "toolAssetIcon").width, 18)
                tryCompare(findChild(button, "toolAssetIcon"), "ready", true)
            }
        }
    }
}
