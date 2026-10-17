pragma Singleton

import QtQuick
import Quickshell
import Clavis.Niri
import qs.Services
import "DockBadges.js" as DockBadges

Singleton {
    id: root

    property int windowRevision: 0
    readonly property var windows: {
        const revision = root.windowRevision;
        return Niri.connected ? Niri.searchWindows("") : [];
    }
    readonly property var counts: DockBadges.counts(NotificationManager.list,
                                                    ApplicationService.launcherApplications, root.windows)

    function countFor(key) {
        return root.counts[key] || 0;
    }

    function acknowledgeFocused() {
        const notifications = DockBadges.focusedNotifications(NotificationManager.list,
                                                              ApplicationService.launcherApplications,
                                                              root.windows);
        if (notifications.length === 0)
            return;
        notifications.forEach(notification => notification.dockUnread = false);
        NotificationManager.saveNotifications();
    }

    Component.onCompleted: root.acknowledgeFocused()
    onWindowsChanged: root.acknowledgeFocused()

    Connections {
        target: Niri
        function onWindowsChanged() {
            root.windowRevision++;
        }
        function onConnectedChanged() {
            root.windowRevision++;
        }
    }
    Connections {
        target: NotificationManager
        function onListChanged() {
            root.acknowledgeFocused();
        }
    }
    Connections {
        target: ApplicationService
        function onLauncherApplicationsChanged() {
            root.acknowledgeFocused();
        }
    }
}
