import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets.common

PanelWindow {
    id: root

    required property var modelData

    readonly property bool detectedAutoHidden: MaximizedWindowService.coversScreen(root.modelData)
    property bool heldAutoHidden: detectedAutoHidden
    readonly property bool autoHidden: LaunchpadService.chromeHold ? heldAutoHidden : detectedAutoHidden
    readonly property bool showContents: !autoHidden || MaximizedWindowService.revealed(root.modelData)
    visible: root.showContents

    onDetectedAutoHiddenChanged: {
        if (!LaunchpadService.chromeHold)
            heldAutoHidden = detectedAutoHidden;
    }
    Connections {
        target: LaunchpadService
        function onChromeHoldChanged() {
            root.heldAutoHidden = root.detectedAutoHidden;
        }
    }

    property var edgeSensor: BarEdgeTrigger {
        screen: root.modelData
        edge: root.edge
        visible: root.autoHidden
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                hideDelay.stop();
                MaximizedWindowService.setHovered(root.modelData, "bar", true);
            } else {
                hideDelay.restart();
            }
        }
    }

    Timer {
        id: hideDelay
        interval: 500
        onTriggered: MaximizedWindowService.setHovered(root.modelData, "bar", false)
    }

    Component.onDestruction: MaximizedWindowService.setHovered(root.modelData, "bar", false)

    required property string edge
    readonly property real visualThickness: Sizes.barVisualThickness
    readonly property real outerEdgeMargin: PersonalizationConfig.barEdgeMargin
    // Shadow pixels need surface space, but must not reserve desktop space.
    readonly property real surfaceThickness: outerEdgeMargin + visualThickness + Sizes.barShadowBuffer
    readonly property real exclusiveThickness: outerEdgeMargin + visualThickness

    implicitWidth: surfaceThickness
    color: "transparent"
    exclusiveZone: root.autoHidden ? 0 : exclusiveThickness
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "clavis-shell-bar-vertical"
    WlrLayershell.exclusionMode: ExclusionMode.Normal

    BarAxis {
        id: axis

        edge: root.edge
    }

    anchors {
        top: true
        bottom: true
        left: axis.isLeft
        right: axis.isRight
    }

    Item {
        id: visualBand
        visible: root.showContents

        x: axis.isLeft ? root.outerEdgeMargin : Sizes.barShadowBuffer
        y: 0
        width: root.visualThickness
        height: parent.height

        VerticalBarContent {
            id: content

            anchors.fill: parent
            screen: root.modelData
            axis: axis
        }
    }

    CompositorBlurRegion {
        // Reattaching a rounded native blur region after auto-hide produces
        // visibly polygonal edges on fractional/high-DPI compositor surfaces.
        blurEnabled: root.showContents && !root.autoHidden
        inset: 1
        pillShapes: true
        targetWindow: root
        backgroundItem: content.backgroundItems.length > 0 ? content.backgroundItems[0] : null
        additionalBackgroundItems: content.backgroundItems.slice(1)
        radius: 18
    }

    mask: Region {
        Region {
            item: root.autoHidden ? visualBand : null
        }

        Region {
            item: root.autoHidden ? null : content.leadingInputRegionItem
        }

        Region {
            item: root.autoHidden ? null : content.trailingInputRegionItem
        }
    }
}
