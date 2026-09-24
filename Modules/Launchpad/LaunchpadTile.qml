pragma ComponentBehavior: Bound
import QtQuick
import qs.Common
import qs.Components
import qs.Services
import "../../Common/functions/LaunchpadLayout.js" as Layout

Item {
    id: root
    required property var entry
    property real iconSize: 76
    property bool highlighted: false
    property bool grouping: false
    property bool ghost: false
    readonly property string entryKey: Layout.key(entry)
    readonly property string title: LaunchpadService.title(entry)
    readonly property real iconTop: 12
    signal activated

    Accessible.name: title
    Accessible.role: entry.kind === "folder" ? Accessible.Button : Accessible.ListItem
    Accessible.onPressAction: root.activated()

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.iconTop - 9
        width: root.iconSize + 20
        height: width
        radius: width * 0.24
        color: root.grouping ? "#55ffffff" : "#22ffffff"
        border.color: root.grouping ? "#bbffffff" : "transparent"
        border.width: 2
        visible: root.highlighted || root.grouping
    }
    Item {
        id: artwork
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.iconTop
        width: root.iconSize
        height: width
        scale: root.grouping ? 0.9 : root.ghost ? 1.08 : 1
        Behavior on scale {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
        ThemeIcon {
            anchors.fill: parent
            visible: root.entry.kind === "app"
            iconSource: visible ? LaunchpadService.icon(root.entry.id) : ""
            sourceSize: Qt.size(160, 160)
            asynchronous: true
            fillMode: Image.PreserveAspectFit
        }
        Rectangle {
            anchors.fill: parent
            visible: root.entry.kind === "folder"
            radius: width * 0.23
            color: "#65d7dce5"
            border.width: 1
            border.color: "#70ffffff"
            Grid {
                anchors.centerIn: parent
                columns: 3
                spacing: root.iconSize * 0.055
                Repeater {
                    model: root.entry.kind === "folder" ? root.entry.children.slice(0, 9) : []
                    ThemeIcon {
                        required property string modelData
                        width: root.iconSize * 0.23
                        height: width
                        sourceSize: Qt.size(64, 64)
                        iconSource: LaunchpadService.icon(modelData)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }
            }
        }
    }
    Text {
        anchors.top: artwork.bottom
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 12
        text: root.title
        color: "white"
        style: Text.Outline
        styleColor: "#40000000"
        font.family: Fonts.ui
        font.pixelSize: 14
        font.weight: Font.Medium
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        maximumLineCount: 2
        wrapMode: Text.Wrap
        elide: Text.ElideRight
    }
}
