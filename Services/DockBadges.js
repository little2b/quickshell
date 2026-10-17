.pragma library
.import "NotificationActivation.js" as NotificationActivation
.import "../Common/functions/DockModel.js" as DockModel

function keyForNotification(notification, applications, windows) {
    const target = NotificationActivation.resolve(notification, applications, windows);
    if (!target) return "";
    const application = target.application || (target.window
        ? DockModel.applicationForWindow(target.window, applications) : null);
    return application ? "app:" + DockModel.desktopId(application.id)
        : target.window ? DockModel.windowKey(target.window, null) : "";
}

function counts(notifications, applications, windows) {
    const result = Object.create(null);
    for (const notification of notifications) {
        if (!notification.dockUnread || notification.isTransient || notification.localKind) continue;
        const key = keyForNotification(notification, applications, windows);
        if (key) result[key] = (result[key] || 0) + 1;
    }
    return result;
}

function focusedNotifications(notifications, applications, windows) {
    const focused = windows.find(window => window.isFocused);
    if (!focused) return [];
    const key = DockModel.windowKey(focused, DockModel.applicationForWindow(focused, applications));
    return notifications.filter(notification => notification.dockUnread
        && keyForNotification(notification, applications, windows) === key);
}

function unreadForArrival(replaced, transient) {
    // Updates retain their acknowledgement state, and replace the previous
    // snapshot rather than counting as a second notification.
    return !transient && (replaced.length === 0 || replaced.some(notification => notification.dockUnread));
}

function label(count) {
    return count > 99 ? "99+" : count > 0 ? String(count) : "";
}
