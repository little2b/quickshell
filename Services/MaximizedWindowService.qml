pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import Clavis.Niri
import "../Common/functions/BarWindowSelection.js" as BarWindowSelection

Singleton {
    id: root

    // Layer-shell panels can take keyboard focus without changing the
    // selected application in a workspace. Resolve that stable selection
    // instead of treating activeToplevel === null as an unmaximized desktop.
    readonly property var toplevels: ToplevelManager.toplevels.values
    property int selectionRevision: 0
    property var _tiledWindowIds: ({})
    property var hoveredSurfaces: ({})
    // Mutate this queue in place: only flushHoverChanges publishes reactive
    // state, after window visibility/hover signal delivery has unwound.
    property var _pendingHoverChanges: ({})

    Connections {
        target: Niri
        function onWindowsChanged() {
            root.syncSelections();
        }
        function onWorkspacesChanged() {
            root.syncSelections();
        }
        function onOutputsChanged() {
            root.syncSelections();
        }
    }

    Component.onCompleted: syncSelections()

    function syncSelections() {
        const next = {};
        for (const output of Niri.outputSnapshot()) {
            for (const workspace of Niri.workspacesForOutput(output.name)) {
                const background = BarWindowSelection.tiledBackground(Niri.windowsForWorkspace(workspace.id),
                                                                      workspace.activeWindowId,
                                                                      root._tiledWindowIds[workspace.id]);
                if (background)
                    next[workspace.id] = background.id;
            }
        }
        root._tiledWindowIds = next;
        root.selectionRevision += 1;
    }

    function coversScreen(screen) {
        return !Niri.inOverview && root.hasMaximizedWindow(screen);
    }

    // Overview changes panel visibility, not the selected window's sizing mode.
    // Panels can reveal themselves without restoring a maximized window's strut.
    function hasMaximizedWindow(screen) {
        const revision = root.selectionRevision;
        if (!screen)
            return false;
        const screenName = screen.name;
        if (!screenName)
            return false;
        const workspace = Niri.activeWorkspaceForOutput(screenName);
        if (!workspace || !workspace.activeWindowId)
            return false;
        const selected = Niri.windowById(workspace.activeWindowId);
        if (!selected || !selected.id || selected.isMinimized)
            return false;
        if (root.windowIsMaximized(selected, screenName))
            return true;
        // Independent floating tools (such as selection translation) have no
        // parent handle. Keep using the selected tiled window behind them.
        if (!selected.isFloating)
            return false;
        const background = Niri.windowById(root._tiledWindowIds[workspace.id] || 0);
        return !!background.id && background.workspaceId === workspace.id && !background.isFloating &&
                !background.isMinimized && root.windowIsMaximized(background, screenName);
    }

    function windowIsMaximized(selected, screenName) {
        // Output objects may be destroyed while window handles survive a resume
        // or monitor reconnect. Ignore missing outputs until the list is refreshed.
        const sameApp = root.toplevels.filter(window => window && window.appId === selected.appId
                                                        && window.screens.some(output => output
                                                                                         && output.name
                                                                                         === screenName));
        const candidates = sameApp.filter(window => window.title === selected.title);
        // Prefer the active handle when indistinguishable titles exist. During
        // a panel focus grab, only hide if all matching handles agree.
        const active = ToplevelManager.activeToplevel;
        // Niri and the foreign-toplevel protocol can report a browser tab's
        // new title on different frames. Only use a title-less match when the
        // selected application has exactly one window on this output.
        let window = candidates.includes(active) ? active : candidates.length === 1 ? candidates[0] :
                                                                                      candidates.length === 0
                                                                                      && sameApp.length === 1
                                                                                      ? sameApp[0] : null;
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
        // Top bars and their pinned lyrics stay hidden over maximized windows.
        if (!screen || PersonalizationConfig.barPosition === "top")
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
