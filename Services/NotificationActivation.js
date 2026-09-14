.pragma library

function normalize(value) {
    return String(value || "").trim().replace(/\.desktop$/i, "").toLowerCase();
}

// Match application metadata exactly; notification text is never a command.
function resolve(notification, applications, windows) {
    if (!notification || notification.localKind)
        return null;
    const desktopId = normalize(notification.desktopEntry);
    const appName = normalize(notification.appName);
    let matches = applications.filter(app => desktopId && normalize(app.id) === desktopId);
    if (matches.length === 0 && !desktopId) {
        matches = applications.filter(app => appName &&
            (normalize(app.name) === appName || normalize(app.id) === appName));
    }
    const application = matches.length === 1 ? matches[0] : null;
    const ids = [desktopId, application ? normalize(application.id) : "",
                 application ? normalize(application.startupClass) : ""].filter(Boolean);
    let candidates = windows.filter(window => ids.indexOf(normalize(window.appId)) !== -1);
    if (candidates.length === 0 && !desktopId && appName) {
        const named = windows.filter(window => normalize(window.appName) === appName ||
            normalize(window.appId) === appName);
        // Do not guess between unrelated applications with the same display name.
        const distinctIds = Array.from(new Set(named.map(window => normalize(window.appId))));
        if (distinctIds.length === 1 && distinctIds[0])
            candidates = named;
    }
    const window = candidates.find(candidate => candidate.isUrgent)
        || candidates.find(candidate => candidate.isFocused) || candidates[0];
    return window || application ? { window: window || null, application: application } : null;
}
