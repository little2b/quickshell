import QtQuick
import QtQuick.Controls

Flickable {
    id: root

    clip: true
    // Keep text and thin outlines on pixel boundaries while scrolling.
    pixelAligned: true
    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    // Let Qt keep one continuous scroll timeline, including touchpad momentum.
    // The custom controller remains opt-in for callers that need accelerated steps.
    property bool smoothWheelScrolling: false
    // Compatibility for callers that explicitly request accelerated scrolling.
    property alias fasterTouchpadScroll: root.smoothWheelScrolling
    property bool showVerticalScrollBar: true

    ScrollBar.vertical: StyledScrollBar {
        policy: root.showVerticalScrollBar ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
    }

    WheelScrollController {
        flickable: root
        enabled: root.smoothWheelScrolling && root.interactive
        orientation: root.flickableDirection === Flickable.HorizontalFlick || (root.flickableDirection
                                                                               !== Flickable.VerticalFlick
                                                                               && root.contentWidth
                                                                               > root.width
                                                                               && root.contentHeight
                                                                               <= root.height)
                     ? Qt.Horizontal : Qt.Vertical
    }
}
