import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services

Item {
    id: root

    property color fillColor: BlurService.backgroundColor(Appearance.colors.colLayer0)
    property real cornerRadius: height / 2
    property real shadowPadding: Sizes.barShadowBuffer
    readonly property string contextualEdge: findContextEdge(root.parent)

    function findContextEdge(item) {
        let current = item;
        while (current !== null && current !== undefined) {
            if (current.popupEdge !== undefined)
                return current.popupEdge;
            current = current.parent;
        }
        return "top";
    }

    RectangularShadow {
        anchors.fill: parent
        radius: root.cornerRadius
        blur: 16
        spread: 0
        color: Appearance.applyAlpha(Appearance.colors.colShadow, 0.4)
        offset: Qt.vector2d(root.contextualEdge === "left" ? 3 : root.contextualEdge === "right" ? -3 : 0,
                            root.contextualEdge === "top" ? 3 : root.contextualEdge === "bottom" ? -3 : 0)
        cached: true
    }

    Rectangle {
        anchors.fill: parent
        color: root.fillColor
        radius: root.cornerRadius
        antialiasing: true
        // Cover the integer blur-region edge with a smooth, opaque outline.
        border.width: BlurService.enabled ? 1 : 0
        border.color: Appearance.applyAlpha(Appearance.colors.colLayer0Border, 1)
    }
}
