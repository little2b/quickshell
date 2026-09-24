pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: root

    property bool ready: false
    property string profile: ""
    property var profiles: []
    property string readError: ""
    property string changeError: ""
    property string expectedProfile: ""
    property bool refreshPending: false
    readonly property bool busy: query.running || change.running
    readonly property string error: changeError || readError
    readonly property bool performanceLimited: PowerProfiles.degradationReason
                                               !== PerformanceDegradationReason.None

    function refresh() {
        if (root.busy) {
            root.refreshPending = true;
            return;
        }
        root.refreshPending = false;
        query.running = true;
    }

    function setProfile(value) {
        if (!root.ready || root.busy || root.profiles.indexOf(value) < 0 || value === root.profile)
            return;
        root.changeError = "";
        root.expectedProfile = value;
        change.command = ["powerprofilesctl", "set", value];
        change.running = true;
    }

    // Native D-Bus notifications keep external changes in sync without polling.
    Connections {
        target: PowerProfiles
        function onProfileChanged() {
            root.refresh();
        }
        function onHasPerformanceProfileChanged() {
            root.refresh();
        }
    }

    Process {
        id: query
        command: ["powerprofilesctl", "list"]
        stdout: StdioCollector {
            id: queryOutput
        }
        stderr: StdioCollector {
            id: queryError
        }
        onExited: code => {
            const available = [];
            let current = "";
            for (const line of queryOutput.text.split("\n")) {
                const match = line.match(/^\s*(\*)?\s*(power-saver|balanced|performance):\s*$/);
                if (!match)
                    continue;
                available.push(match[2]);
                if (match[1])
                    current = match[2];
            }
            root.ready = code === 0 && current !== "";
            if (root.ready) {
                root.profiles = available;
                root.profile = current;
                root.readError = "";
                if (root.expectedProfile && current !== root.expectedProfile)
                    root.changeError = qsTr("The system did not keep the requested power mode.");
            } else {
                root.profiles = [];
                root.profile = "";
                root.readError = queryError.text.trim() || qsTr(
                            "Power modes are unavailable. Check that power-profiles-daemon is installed and running.");
            }
            root.expectedProfile = "";
            if (root.refreshPending)
                Qt.callLater(root.refresh);
        }
    }

    Process {
        id: change
        stderr: StdioCollector {
            id: changeOutput
        }
        onExited: code => {
            if (code !== 0 && root.expectedProfile !== "") {
                root.expectedProfile = "";
                root.changeError = changeOutput.text.trim() || qsTr("Unable to change the power mode.");
            }
            Qt.callLater(root.refresh);
        }
    }

    Timer {
        interval: 15000
        running: root.busy
        onTriggered: {
            root.changeError = qsTr("The power mode request timed out.");
            root.expectedProfile = "";
            root.refreshPending = false;
            query.running = false;
            change.running = false;
        }
    }
}
