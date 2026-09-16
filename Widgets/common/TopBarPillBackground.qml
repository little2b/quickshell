import QtQuick
import Qt5Compat.GraphicalEffects
import qs.Common
import qs.Services

Item {
    id: root

    property color fillColor: BlurService.backgroundColor(Appearance.colors.colLayer0)
    property real cornerRadius: height / 2
    property real shadowPadding: Sizes.barShadowBuffer
    property bool shadowCached: true
    property bool shadowEnabled: true
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

    Rectangle {
        id: shadowSource

        anchors.fill: parent
        color: root.fillColor
        radius: root.cornerRadius
        visible: false
    }

    DropShadow {
        anchors.fill: shadowSource
        source: shadowSource
        visible: root.shadowEnabled
        radius: 16
        samples: 32
        transparentBorder: true
        color: Appearance.applyAlpha(Appearance.colors.colShadow, 0.4)
        horizontalOffset: root.contextualEdge === "left" ? 3 : root.contextualEdge === "right" ? -3 : 0
        verticalOffset: root.contextualEdge === "top" ? 3 : root.contextualEdge === "bottom" ? -3 : 0
        cached: root.shadowCached
    }

    Rectangle {
        anchors.fill: parent
        color: root.fillColor
        radius: root.cornerRadius
        antialiasing: true
        clip: true
    }
}
