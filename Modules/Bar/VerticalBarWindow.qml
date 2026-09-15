import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets.common

PanelWindow {
    id: root

    readonly property bool autoHidden: MaximizedWindowService.coversScreen(root.screen)
    readonly property bool showContents: !autoHidden || MaximizedWindowService.revealed(root.screen)

    property real revealProgress: root.showContents ? 1 : 0

    Behavior on revealProgress {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                hideDelay.stop();
                MaximizedWindowService.setHovered(root.screen, "bar", true);
            } else {
                hideDelay.restart();
            }
        }
    }

    Timer {
        id: hideDelay
        interval: 500
        onTriggered: MaximizedWindowService.setHovered(root.screen, "bar", false)
    }

    Component.onDestruction: MaximizedWindowService.setHovered(root.screen, "bar", false)

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
        opacity: root.revealProgress

        x: axis.isLeft ? root.outerEdgeMargin : Sizes.barShadowBuffer
        y: 0
        width: root.visualThickness
        height: parent.height

        VerticalBarContent {
            id: content

            anchors.fill: parent
            screen: root.screen
            axis: axis
        }
    }

    Item {
        id: edgeTrigger
        x: axis.isLeft ? 0 : parent.width - 1
        y: 0
        width: 1
        height: parent.height
    }

    CompositorBlurRegion {
        // Compositor blur does not inherit the QML opacity animation.
        // Enable only after content fades in; clear as soon as exit starts.
        blurEnabled: root.showContents && root.revealProgress >= 1
        inset: 1
        pillShapes: true
        targetWindow: root
        backgroundItem: content.backgroundItems.length > 0 ? content.backgroundItems[0] : null
        additionalBackgroundItems: content.backgroundItems.slice(1)
        radius: 18
    }

    mask: Region {
        Region {
            item: root.autoHidden ? (root.showContents ? visualBand : edgeTrigger) : null
        }

        Region {
            item: root.autoHidden ? null : content.leadingInputRegionItem
        }

        Region {
            item: root.autoHidden ? null : content.trailingInputRegionItem
        }
    }
}
