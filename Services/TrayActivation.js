.pragma library

function normalize(value) {
    return String(value || "").trim().replace(/\.desktop$/i, "").toLowerCase();
}

function resolveOwner(owner, applications, windows) {
    if (!owner)
        return null;
    const owned = owner.pid > 0 ? windows.filter(window => window.pid === owner.pid) : [];
    if (owned.length)
        return owned.find(window => window.isFocused) || owned.find(window => window.isUrgent) || owned[0];
    // XWayland satellite windows can expose the bridge's PID, not the app's.
    // Use the tray's verified D-Bus owner executable as exact app metadata;
    // never infer an application from a generic chrome_status_icon_* ID.
    return owner.processName ? resolve({id: owner.processName}, applications, windows) : null;
}

function resolve(item, applications, windows) {
    if (!item || item.onlyMenu)
        return null;
    // Electron and Ayatana tray IDs can differ from their window app IDs.
    // Only exact application metadata matches are used, never window contents.
    const labels = [item.id, item.title, item.tooltipTitle].map(normalize).filter(Boolean);
    for (const label of labels) {
        const entries = applications.filter(app =>
            [app.id, app.name, app.startupClass].map(normalize).indexOf(label) !== -1);
        const ids = [label];
        for (const app of entries)
            ids.push(normalize(app.id), normalize(app.startupClass));
        const candidates = windows.filter(window => {
            const appId = normalize(window.appId);
            return appId && (ids.indexOf(appId) !== -1 || normalize(window.appName) === label);
        });
        const appIds = Array.from(new Set(candidates.map(window => normalize(window.appId))));
        // A shared display name must not select an unrelated application.
        if (appIds.length > 1)
            return null;
        if (candidates.length > 0) {
            const names = labels.concat(entries.map(app => normalize(app.name)));
            return candidates.find(window => names.indexOf(normalize(window.title)) !== -1)
                || candidates.find(window => window.isFocused)
                || candidates.find(window => window.isUrgent) || candidates[0];
        }
    }
    return null;
}
