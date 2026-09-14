import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    required property var locker
    property bool enabled: true
    property int pendingSerial: -1
    property bool ready: false
    signal lockConfirmed(int serial)

    function confirmLock() {
        if (root.pendingSerial < 0 || !root.locker.secure)
            return;
        const serial = root.pendingSerial;
        root.pendingSerial = -1;
        if (bridge.running)
            bridge.write(JSON.stringify({secured: serial}) + "\n");
        root.lockConfirmed(serial);
    }

    function receive(event) {
        if (event.event === "ready") {
            root.ready = true;
        } else if (event.event === "prepare") {
            root.pendingSerial = event.serial;
            root.locker.open();
            root.confirmLock();
        } else if (event.event === "resume") {
            root.pendingSerial = -1;
            // Also retry locking if the pre-sleep request failed or timed out.
            if (!root.locker.secure)
                root.locker.open();
        }
    }

    Connections {
        target: root.locker
        function onSecured() { root.confirmLock(); }
    }

    Timer {
        id: retry
        interval: 3000
        onTriggered: if (root.enabled) bridge.running = true
    }

    Process {
        id: bridge
        command: ["/usr/bin/python3", "-I", Quickshell.shellDir + "/scripts/system/sleep_lock_bridge.py"]
        running: root.enabled
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try { root.receive(JSON.parse(data)); }
                catch (error) { console.warn("Sleep lock bridge:", error); }
            }
        }
        stderr: SplitParser {
            onRead: data => console.warn("Sleep lock bridge:", data)
        }
        onExited: code => {
            root.ready = false;
            if (root.enabled) {
                console.warn("Sleep lock bridge stopped:", code, "— restarting");
                retry.restart();
            }
        }
    }
}
