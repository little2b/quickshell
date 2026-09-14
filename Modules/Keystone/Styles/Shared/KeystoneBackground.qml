import QtQuick
import QtQuick.Shapes

// Render the animated surface as geometry instead of repainting a large bitmap.
Shape {
    id: surface

    property color surfaceColor: "black"
    property real topLeftRadius: 0
    property real topRightRadius: 0
    property real bottomRightRadius: 0
    property real bottomLeftRadius: 0
    property bool cutoutVisible: false
    property real cutoutX: 0
    property real cutoutY: 0
    property real cutoutWidth: 0
    property real cutoutHeight: 0
    property real cutoutRadius: 0

    preferredRendererType: Shape.CurveRenderer
    clip: true

    ShapePath {
        strokeWidth: -1
        fillColor: surface.surfaceColor
        fillRule: ShapePath.OddEvenFill

        PathRectangle {
            width: surface.width
            height: surface.height
            topLeftRadius: surface.topLeftRadius
            topRightRadius: surface.topRightRadius
            bottomRightRadius: surface.bottomRightRadius
            bottomLeftRadius: surface.bottomLeftRadius
        }
        PathRectangle {
            x: surface.cutoutX
            y: surface.cutoutY
            width: surface.cutoutVisible ? surface.cutoutWidth : 0
            height: surface.cutoutVisible ? surface.cutoutHeight : 0
            radius: surface.cutoutRadius
        }
    }
}
