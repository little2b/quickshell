pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property int type: Easing.BezierSpline
    readonly property int expandingDuration: 260
    readonly property int shrinkingDuration: 200
    readonly property int radiusDuration: 200
    readonly property int hoverDuration: 180
    readonly property var expandingBezier: [0.16, 0.68, 0.36, 1, 1, 1]
    readonly property var shrinkingBezier: [0.16, 0.68, 0.36, 1, 1, 1]
    readonly property var hoverBezier: [0.2, 0, 0, 1, 1, 1]
    readonly property var radiusBezier: shrinkingBezier
    readonly property int hoverWidthDelta: 20
    readonly property int hoverHeightDelta: 8
    readonly property int hoverRadiusDelta: 3
    readonly property int audioRecordingWidth: 320
    readonly property int audioRecordingHeight: 56
    readonly property int verticalAudioRecordingWidth: 56
    readonly property int verticalAudioRecordingHeight: 320
    readonly property int audioExpandDuration: 300
    readonly property int audioContentEnterDuration: 180
    readonly property int audioContentExitDuration: 120
    readonly property int audioCollapseDuration: 240
}
