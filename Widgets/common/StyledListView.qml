import QtQuick
import QtQuick.Controls

ListView {
    id: root

    spacing: 0
    clip: true
    // Keep text and thin outlines on pixel boundaries while scrolling.
    pixelAligned: true
    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    property real removeOvershoot: 20
    property bool popin: true
    property bool animateAppearance: true
    property bool animateMovement: false
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
        orientation: root.orientation
    }

    Component {
        id: elementMoveAnimation

        ElementMoveAnimation {}
    }

    add: Transition {
        animations: root.animateAppearance ? [elementMoveAnimation.createObject(this, {
                                                                                    properties: root.popin
                                                                                                ? "opacity,scale" :
                                                                                                  "opacity",
                                                                                    from: 0,
                                                                                    to: 1
                                                                                }),] : []
    }

    addDisplaced: Transition {
        animations: root.animateAppearance ? [elementMoveAnimation.createObject(this, {
                                                                                    property: "y"
                                                                                }), elementMoveAnimation.createObject(
                                                  this, {
                                                      properties: root.popin ? "opacity,scale" : "opacity",
                                                      to: 1
                                                  }),] : []
    }

    displaced: Transition {
        animations: root.animateMovement ? [elementMoveAnimation.createObject(this, {
                                                                                  property: "y"
                                                                              }), elementMoveAnimation.createObject(
                                                this, {
                                                    properties: "opacity,scale",
                                                    to: 1
                                                }),] : []
    }

    move: Transition {
        animations: root.animateMovement ? [elementMoveAnimation.createObject(this, {
                                                                                  property: "y"
                                                                              }), elementMoveAnimation.createObject(
                                                this, {
                                                    properties: "opacity,scale",
                                                    to: 1
                                                }),] : []
    }

    moveDisplaced: Transition {
        animations: root.animateMovement ? [elementMoveAnimation.createObject(this, {
                                                                                  property: "y"
                                                                              }), elementMoveAnimation.createObject(
                                                this, {
                                                    properties: "opacity,scale",
                                                    to: 1
                                                }),] : []
    }

    remove: Transition {
        animations: root.animateAppearance ? [elementMoveAnimation.createObject(this, {
                                                                                    property: "x",
                                                                                    to: root.width
                                                                                        + root.removeOvershoot
                                                                                }), elementMoveAnimation.createObject(
                                                  this, {
                                                      property: "opacity",
                                                      to: 0
                                                  }),] : []
    }

    removeDisplaced: Transition {
        animations: root.animateAppearance ? [elementMoveAnimation.createObject(this, {
                                                                                    property: "y"
                                                                                }), elementMoveAnimation.createObject(
                                                  this, {
                                                      properties: "opacity,scale",
                                                      to: 1
                                                  }),] : []
    }
}
