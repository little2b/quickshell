pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import Clavis.Niri

Singleton {
    id: root

    // Layer-shell panels can take keyboard focus without changing the
    // selected application in a workspace. Resolve that stable selection
    // instead of treating activeToplevel === null as an unmaximized desktop.
    readonly property var toplevels: ToplevelManager.toplevels.values
    property int selectionRevision: 0
    property var hoveredSurfaces: ({})
    // Mutate this queue in place: only flushHoverChanges publishes reactive
    // state, after window visibility/hover signal delivery has unwound.
    property var _pendingHoverChanges: ({})

    Connections {
        target: Niri
        function onWindowsChanged() {
            root.selectionRevision += 1;
        }
        function onWorkspacesChanged() {
            root.selectionRevision += 1;
        }
        function onOutputsChanged() {
            root.selectionRevision += 1;
        }
    }

    function coversScreen(screen) {
        const revision = root.selectionRevision;
        if (!screen || Niri.inOverview)
            return false;
        const screenName = screen.name;
        if (!screenName)
            return false;
        const workspace = Niri.activeWorkspaceForOutput(screenName);
        if (!workspace || !workspace.activeWindowId)
            return false;
        const selected = Niri.windowById(workspace.activeWindowId);
        if (!selected || !selected.id)
            return false;
        // Output objects may be destroyed while window handles survive a resume
        // or monitor reconnect. Ignore missing outputs until the list is refreshed.
        const candidates = root.toplevels.filter(window => window && window.appId === selected.appId
                                                           && window.title === selected.title
                                                           && window.screens.some(output => output
                                                                                            && output.name
                                                                                            === screenName));
        // Prefer the active handle when indistinguishable titles exist. During
        // a panel focus grab, only hide if all matching handles agree.
        const active = ToplevelManager.activeToplevel;
        let window = candidates.includes(active) ? active : candidates.length === 1 ? candidates[0] : null;
        if (!window)
            return candidates.length > 0 && candidates.every(candidate => candidate.maximized &&
                                                                          !candidate.fullscreen);
        while (window) {
            if (window.maximized && !window.fullscreen && window.screens.some(output => output && output.name
                                                                                        === screenName))
                return true;
            window = window.parent;
        }
        return false;
    }

    function revealed(screen) {
        if (!screen)
            return false;
        return Object.keys(root.hoveredSurfaces).some(key => key.startsWith(screen.name + "/"));
    }

    function setHovered(screen, owner, hovered) {
        if (!screen)
            return;
        const key = screen.name + "/" + owner;
        root._pendingHoverChanges[key] = !!hovered;
        Qt.callLater(root.flushHoverChanges);
    }

    function flushHoverChanges() {
        const keys = Object.keys(root._pendingHoverChanges);
        if (keys.length === 0)
            return;
        const next = Object.assign({}, root.hoveredSurfaces);
        let changed = false;
        for (const key of keys) {
            const hovered = root._pendingHoverChanges[key];
            delete root._pendingHoverChanges[key];
            if (!!next[key] === hovered)
                continue;
            changed = true;
            if (hovered)
                next[key] = true;
            else
                delete next[key];
        }
        // Mapping a bar can queue another hover update here. It will be
        // published on a later turn, never inside its own visibility binding.
        if (changed)
            root.hoveredSurfaces = next;
    }
}
