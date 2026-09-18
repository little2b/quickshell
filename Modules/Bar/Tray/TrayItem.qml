import QtQuick
import Clavis.Niri
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Services
import qs.Common
import qs.Widgets.common
import "../../../Services/TrayActivation.js" as TrayActivation

MouseArea {
    id: root

    required property var modelData
    property var screen: null
    property string edge: "top"
    property var barVisualItem: null
    property bool pinned: true
    property int activationPid: 0
    property string activationProcessName: ""
    property bool activationPending: false
    property bool dragActive: false
    property point lastDragGlobalPosition: Qt.point(0, 0)

    signal menuOpened(var qsWindow)
    signal menuClosed
    signal dragStarted(string itemId, bool pinned, var iconSource, real globalX, real globalY)
    signal dragMoved(real globalX, real globalY)
    signal dragFinished(real globalX, real globalY, bool canceled)

    implicitWidth: 20
    implicitHeight: 20
    hoverEnabled: true
    cursorShape: root.dragActive ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    pressAndHoldInterval: 260
    preventStealing: true
    opacity: root.dragActive ? 0.32 : 1
    scale: root.dragActive ? 0.82 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.expressiveFastEffects.duration
            easing.type: Appearance.animation.expressiveFastEffects.type
            easing.bezierCurve: Appearance.animation.expressiveFastEffects.bezierCurve
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: Appearance.animation.expressiveFastEffects.duration
            easing.type: Appearance.animation.expressiveFastEffects.type
            easing.bezierCurve: Appearance.animation.expressiveFastEffects.bezierCurve
        }
    }

    function updateDragPosition(event) {
        const globalPosition = root.mapToGlobal(event.x, event.y);
        root.lastDragGlobalPosition = globalPosition;
        return globalPosition;
    }

    function closeMenu() {
        if (menu.active && menu.item && typeof menu.item.close === "function")
            menu.item.close();
    }

    function closeOtherMenus() {
        if (!root.parent)
            return;

        const siblings = root.parent.children;
        for (let i = 0; i < siblings.length; i += 1) {
            const sibling = siblings[i];
            if (sibling === root)
                continue;
            if (typeof sibling.closeMenu === "function")
                sibling.closeMenu();
        }
    }

    function focusApplicationWindow() {
        const windows = Niri.searchWindows("");
        const target = TrayActivation.resolveOwner({
                                                       pid: root.activationPid,
                                                       processName: root.activationProcessName
                                                   }, ApplicationService.applications, windows)
              || TrayActivation.resolve(root.modelData, ApplicationService.applications, windows);
        return target ? Niri.focusWindow(target.id) : false;
    }

    function activateItem() {
        focusRetry.stop();
        if (ownerLookup.running)
            return;
        root.activationPid = 0;
        root.activationProcessName = "";
        root.activationPending = false;
        // Tray Activate alone cannot reliably focus windows on Niri, and some
        // applications toggle visibility instead of raising an existing window.
        if (root.focusApplicationWindow())
            return;
        focusRetry.initialWindowId = Niri.focusedWindow.id || 0;
        root.activationPending = true;
        ownerLookup.command = ["python3", Paths.systemScriptsDir + "/tray-owner.py", JSON.stringify({
                                                                                                        id: root.modelData.id
                                                                                                            || "",
                                                                                                        title: root.modelData.title
                                                                                                               || "",
                                                                                                        tooltipTitle:
                                                                                                        root.modelData.tooltipTitle
                                                                                                        || ""
                                                                                                    })];
        ownerLookup.running = true;
    }

    function finishActivation(pid, processName) {
        if (!root.activationPending)
            return;
        root.activationPending = false;
        const currentId = Niri.focusedWindow.id || 0;
        if (currentId && currentId !== focusRetry.initialWindowId)
            return;
        root.activationPid = pid;
        root.activationProcessName = processName || "";
        if (root.focusApplicationWindow())
            return;
        root.modelData.activate();
        focusRetry.attempts = 0;
        focusRetry.start();
    }

    Process {
        id: ownerLookup
        stdout: StdioCollector {
            onStreamFinished: {
                let pid = 0;
                let processName = "";
                try {
                    const owner = JSON.parse(text);
                    pid = Number(owner.pid) || 0;
                    processName = String(owner.processName || "");
                } catch (error) {}
                root.finishActivation(pid, processName);
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.finishActivation(0, "");
        }
    }

    Timer {
        id: focusRetry
        property int attempts: 0
        property var initialWindowId: 0
        interval: 100
        repeat: true
        onTriggered: {
            attempts += 1;
            const currentId = Niri.focusedWindow.id || 0;
            // Stop waiting if the user or application already switched focus.
            if ((currentId && currentId !== initialWindowId) || root.focusApplicationWindow() || attempts
                    >= 20)
                stop();
        }
    }

    onPressAndHold: event => {
        if (event.button !== Qt.LeftButton)
            return;

        root.activationPending = false;
        focusRetry.stop();
        root.closeOtherMenus();
        root.closeMenu();
        root.dragActive = true;
        const globalPosition = root.updateDragPosition(event);
        root.dragStarted(root.modelData.id || "", root.pinned, root.modelData.icon || "", globalPosition.x,
                         globalPosition.y);
        event.accepted = true;
    }

    onPositionChanged: event => {
        if (!root.dragActive)
            return;

        const globalPosition = root.updateDragPosition(event);
        root.dragMoved(globalPosition.x, globalPosition.y);
        event.accepted = true;
    }

    onReleased: event => {
        if (!root.dragActive)
            return;

        const globalPosition = root.updateDragPosition(event);
        root.dragActive = false;
        root.dragFinished(globalPosition.x, globalPosition.y, false);
        event.accepted = true;
    }

    onCanceled: {
        if (!root.dragActive)
            return;

        root.dragActive = false;
        root.dragFinished(root.lastDragGlobalPosition.x, root.lastDragGlobalPosition.y, true);
    }

    onClicked: event => {
        if (event.button === Qt.LeftButton && !root.modelData.onlyMenu) {
            root.closeOtherMenus();
            root.closeMenu();
            root.activateItem();
        } else if (event.button === Qt.RightButton || root.modelData.onlyMenu) {
            root.activationPending = false;
            focusRetry.stop();
            if (root.modelData.hasMenu || root.modelData.menu) {
                if (menu.active && menu.item && typeof menu.item.close === "function") {
                    menu.item.close();
                } else {
                    root.closeOtherMenus();
                    menu.open();
                }
            }
        }
        event.accepted = true;
    }

    Loader {
        id: menu

        active: false

        function open() {
            menu.active = true;
        }

        sourceComponent: TrayMenu {
            Component.onCompleted: this.open()

            trayItemMenuHandle: root.modelData.menu
            trayItemId: root.modelData.id || ""
            anchorItem: root
            screen: root.screen
            edge: root.edge
            barVisualItem: root.barVisualItem

            onMenuOpened: window => root.menuOpened(window)
            onMenuClosed: {
                root.menuClosed();
                menu.active = false;
            }
        }
    }

    IconImage {
        id: trayIcon

        source: root.modelData.icon || ""
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        asynchronous: true
        mipmap: true
    }

    PopupToolTip {
        extraVisibleCondition: root.containsMouse && !root.dragActive
        text: TrayService.getTooltipForItem(root.modelData)
    }
}
