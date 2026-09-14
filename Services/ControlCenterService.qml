pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import Clavis.Niri

Singleton {
    id: root

    property var controlCenterLoader: null
    property var controlCenterWindow: null

    property bool _openRequested: false
    property string _pendingPage: ""
    property bool _activationPending: false

    readonly property bool loaded: controlCenterWindow !== null
    readonly property bool visible: loaded && controlCenterWindow.visible

    function registerLoader(loader) {
        root.controlCenterLoader = loader;
        if (loader && loader.item)
            root.registerWindow(loader.item);
    }

    function registerWindow(window) {
        if (!window)
            return;

        root.controlCenterWindow = window;
        if (root._openRequested)
            root.presentWindow(window);
    }

    function presentWindow(window) {
        if (!window)
            return;

        const page = root._pendingPage;
        root._pendingPage = "";
        if (page !== "" && window.openPage)
            window.openPage(page);

        if (window.showWindow)
            window.showWindow();
        else
            window.visible = true;

        root._activationPending = true;
        if (!root.activateWindow()) {
            activationRetry.attempts = 0;
            activationRetry.restart();
        }
    }

    function niriWindow() {
        if (!root.controlCenterWindow || !Niri.connected)
            return null;
        const title = root.controlCenterWindow.title;
        return Niri.searchWindows(title).find(window => window.title === title && window.pid
                                                        === Quickshell.processId) || null;
    }

    function toplevel() {
        if (!root.controlCenterWindow)
            return null;
        return ToplevelManager.toplevels.values.find(window => window.title
                                                               === root.controlCenterWindow.title) || null;
    }

    function isFocused() {
        const nativeWindow = root.niriWindow();
        if (nativeWindow)
            return nativeWindow.isFocused;
        const target = root.toplevel();
        return target ? target.activated : false;
    }

    function activateWindow() {
        if (!root._activationPending || !root.visible || !root._openRequested)
            return false;
        const nativeWindow = root.niriWindow();
        if (nativeWindow && Niri.focusWindow(nativeWindow.id)) {
            root._activationPending = false;
            activationRetry.stop();
            return true;
        }
        const target = root.toplevel();
        if (target) {
            target.activate();
            root._activationPending = false;
            activationRetry.stop();
            return true;
        }
        return false;
    }

    function open(pageId) {
        root._openRequested = true;
        if (pageId !== undefined && pageId !== null && String(pageId) !== "") {
            root._pendingPage = String(pageId);
        }

        if (!root.controlCenterLoader)
            return false;

        root.controlCenterLoader.active = true;
        if (root.controlCenterLoader.item) {
            if (root.controlCenterWindow !== root.controlCenterLoader.item)
                root.registerWindow(root.controlCenterLoader.item);
            else
                root.presentWindow(root.controlCenterWindow);
        }
        return true;
    }

    function openOrFocus() {
        return root.open();
    }

    function close() {
        root._openRequested = false;
        root._pendingPage = "";
        root._activationPending = false;
        activationRetry.stop();

        const window = root.controlCenterWindow || (root.controlCenterLoader ? root.controlCenterLoader.item :
                                                                               null);
        if (window) {
            if (window.hideWindow)
                window.hideWindow();
            else
                window.visible = false;
            return true;
        }

        if (root.controlCenterLoader)
            root.controlCenterLoader.active = false;
        return false;
    }

    function toggle(pageId) {
        if ((root.visible && root.isFocused()) || (!root.visible && root._openRequested)) {
            root.close();
            return false;
        }
        return root.open(pageId);
    }

    function windowClosed(window) {
        if (root.controlCenterWindow && root.controlCenterWindow !== window) {
            return;
        }

        root.controlCenterWindow = null;
        root._openRequested = false;
        root._pendingPage = "";
        root._activationPending = false;
        activationRetry.stop();
        if (root.controlCenterLoader)
            root.controlCenterLoader.active = false;
    }

    Connections {
        target: Niri
        function onWindowsChanged() {
            if (root._activationPending)
                root.activateWindow();
        }
    }

    // A newly created window is not in the compositor's window list yet.
    // Retry only for this open request, never after a close or indefinitely.
    Timer {
        id: activationRetry
        property int attempts: 0
        interval: 50
        repeat: true
        onTriggered: {
            if (!root.activateWindow() && ++attempts >= 40) {
                root._activationPending = false;
                stop();
            }
        }
    }
}
