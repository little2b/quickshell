import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services

PanelWindow {
    id: root

    required property string edge
    readonly property bool horizontal: edge === "top" || edge === "bottom"
    property var hoveredScreen: null

    // A separate, unblurred input strip lets the visual bar unmap completely.
    // Keep this outside clavis-shell-* so shell effect rules cannot reach it.
    color: "transparent"
    implicitWidth: 1
    implicitHeight: 1
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "clavis-bar-edge-trigger"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors.left: root.horizontal || root.edge === "left"
    anchors.right: root.horizontal || root.edge === "right"
    anchors.top: !root.horizontal || root.edge === "top"
    anchors.bottom: !root.horizontal || root.edge === "bottom"

    function clearHover() {
        leaveDelay.stop();
        if (root.hoveredScreen)
            MaximizedWindowService.setHovered(root.hoveredScreen, "bar-edge", false);
        root.hoveredScreen = null;
    }

    onVisibleChanged: if (!visible)
                          clearHover()
    onScreenChanged: clearHover()
    Component.onDestruction: clearHover()

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                leaveDelay.stop();
                root.hoveredScreen = root.screen;
                MaximizedWindowService.setHovered(root.screen, "bar-edge", true);
            } else {
                leaveDelay.restart();
            }
        }
    }

    Timer {
        id: leaveDelay
        interval: 500
        onTriggered: root.clearHover()
    }
}
