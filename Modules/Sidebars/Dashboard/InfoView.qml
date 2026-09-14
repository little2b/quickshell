import QtQuick
import QtQuick.Layouts
import qs.Services
import qs.Widgets.common
import "./notifications"
import "./infoTools"

StyledFlickable {
    id: root

    property string screenName: ""
    property bool foreground: false
    readonly property bool isForeground: root.foreground

    contentWidth: width
    contentHeight: Math.max(height, contentLayout.implicitHeight)

    onIsForegroundChanged: {
        SystemIdentityService.setUptimeConsumer("left-sidebar-info:" + root.screenName, root.isForeground);
        if (isForeground) {
            NotificationManager.hideAllPopups();
            NotificationManager.markAllRead();
            Time.refreshNow();
        }
    }
    Component.onCompleted: SystemIdentityService.setUptimeConsumer("left-sidebar-info:" + root.screenName,
                                                                   root.isForeground)
    Component.onDestruction: SystemIdentityService.setUptimeConsumer("left-sidebar-info:" + root.screenName,
                                                                     false)

    ColumnLayout {
        id: contentLayout

        width: root.width
        height: root.contentHeight
        spacing: 12

        ProfileHeaderCard {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            screenName: root.screenName
        }

        NotificationList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: implicitHeight
        }

        InfoToolDrawer {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            active: root.isForeground
        }
    }
}
