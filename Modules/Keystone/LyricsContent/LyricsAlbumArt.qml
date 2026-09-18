import QtQuick
import QtQuick.Effects
import QtQuick.Window
import qs.Common
import qs.Components

Item {
    id: root

    required property string sourceUrl

    implicitWidth: 26
    implicitHeight: 26

    Image {
        anchors.fill: parent
        source: root.sourceUrl
        sourceSize: Qt.size(Math.max(1, Math.ceil(width * Screen.devicePixelRatio)), Math.max(1, Math.ceil(
                                                                                                  height * Screen.devicePixelRatio)))
        asynchronous: true
        retainWhileLoading: true
        visible: source !== ""
        fillMode: Image.PreserveAspectCrop
        layer.enabled: true

        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: roundedMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }

    Rectangle {
        id: roundedMask

        anchors.fill: parent
        radius: 5
        color: "black"
        visible: false
        layer.enabled: true
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.sourceUrl === ""
        text: "music_note"
        iconSize: 14
        color: Appearance.applyAlpha(Appearance.colors.colOnLayer0, 0.5)
    }
}
