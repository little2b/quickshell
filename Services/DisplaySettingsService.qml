pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root

    readonly property bool supported: (Quickshell.env("NIRI_SOCKET") || "") !== ""
    property var outputs: []
    property string error: ""
    property string message: ""
    property bool previewing: false
    property bool confirming: false
    property int secondsRemaining: 0
    property double deadline: 0
    property string operationKind: ""
    property bool receivedResult: false
    readonly property bool busy: operation.running

    function refresh() {
        if (!root.supported || root.busy)
            return;
        root.invoke({
                        operation: "status"
                    });
    }

    function invoke(request) {
        root.operationKind = request.operation;
        root.receivedResult = false;
        operation.writing = request.operation !== "status";
        operation.command = ["python3", Paths.systemScriptsDir + "/display_settings.py", JSON.stringify(
                                 request)];
        operation.running = true;
    }

    function apply(name, mode, scale, transform) {
        if (!root.supported || root.busy)
            return;
        root.error = "";
        root.message = "";
        root.invoke({
                        operation: "preview",
                        name: name,
                        mode: mode,
                        scale: scale,
                        transform: transform
                    });
    }

    function applyLayout(positions) {
        if (!root.supported || root.busy)
            return;
        root.error = "";
        root.message = "";
        root.invoke({
                        operation: "layout-preview",
                        positions: positions
                    });
    }

    function confirm() {
        if (!root.previewing || root.confirming)
            return;
        root.confirming = true;
        operation.write("confirm\n");
    }

    function revert() {
        if (!root.previewing || root.confirming)
            return;
        root.confirming = true;
        operation.write("revert\n");
    }

    function receive(data) {
        try {
            const response = JSON.parse(data);
            if (response.schemaVersion !== 1)
                throw new Error(qsTr("Invalid display response"));
            if (response.event === "preview") {
                root.previewing = true;
                root.confirming = false;
                root.secondsRemaining = response.seconds;
                root.deadline = Date.now() + response.seconds * 1000;
                return;
            }
            root.receivedResult = true;
            if (response.event === "status") {
                root.outputs = response.outputs;
            } else if (response.event === "saved") {
                root.message = qsTr("Display settings saved");
            } else if (response.event === "reverted") {
                root.message = qsTr("Previous display settings restored");
            } else if (response.event === "error") {
                root.error = qsTr("Unable to change display settings: %1").arg(response.error);
            } else {
                throw new Error(qsTr("Invalid display response"));
            }
        } catch (e) {
            root.error = String(e);
        }
    }

    Timer {
        interval: 200
        running: root.previewing
        repeat: true
        onTriggered: root.secondsRemaining = Math.max(0, Math.ceil((root.deadline - Date.now()) / 1000))
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            root.refresh();
        }
    }

    Process {
        id: operation
        property bool writing: false
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.receive(data)
        }
        stderr: StdioCollector {
            id: diagnostics
        }
        onExited: code => {
            root.previewing = false;
            root.confirming = false;
            if (!root.receivedResult)
                root.error = qsTr("Unable to read display settings: %1").arg(diagnostics.text.trim() || String(
                                                                                 code));
            if (writing)
                Qt.callLater(root.refresh);
        }
    }
}
