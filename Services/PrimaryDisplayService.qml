pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root
    property bool started: false
    property bool ready: false
    property var preferences: ({primary: null, autoMove: true})
    property var outputs: []
    property string selectedName: ""
    property string activePrimary: ""
    property string fallback: ""
    property string error: ""
    property string message: ""
    readonly property bool busy: operation.running

    function initialize() { root.started = true; }

    function receive(text, explicitOperation) {
        try {
            const result = JSON.parse(text);
            if (!result.ok)
                throw new Error(result.error || qsTr("无法更新主显示器设置。"));
            root.preferences = result.preferences;
            root.outputs = result.outputs;
            root.selectedName = result.selectedName;
            root.activePrimary = result.activePrimary;
            root.fallback = result.fallback;
            root.ready = true;
            root.error = "";
            if (explicitOperation)
                root.message = result.moved > 0 ? qsTr("已保存，并将 %1 个工作区移至主显示器。").arg(result.moved)
                                               : qsTr("主显示器设置已生效。");
        } catch (exception) {
            root.error = String(exception.message || exception);
        }
    }

    function invoke(request) {
        if (root.busy) return;
        root.error = "";
        root.message = "";
        operation.command = ["/usr/bin/python3", "-I", Paths.systemScriptsDir + "/primary_display.py", JSON.stringify(request)];
        operation.running = true;
    }
    function setPrimary(name) { root.invoke({operation: "configure", primary: name}); }
    function setAutoMove(value) { root.invoke({operation: "configure", autoMove: value}); }
    function moveNow() { root.invoke({operation: "move"}); }

    Timer {
        id: restart
        interval: 3000
        onTriggered: if (root.started) watcher.running = true
    }
    Process {
        id: watcher
        command: ["/usr/bin/python3", "-I", Paths.systemScriptsDir + "/primary_display.py", "watch"]
        stdinEnabled: true
        running: root.started
        stdout: SplitParser { onRead: data => root.receive(data, false) }
        stderr: SplitParser { onRead: data => console.warn("Primary display:", data) }
        onExited: {
            root.ready = false;
            if (root.started) restart.restart();
        }
    }
    Process {
        id: operation
        stdout: StdioCollector { id: response }
        stderr: StdioCollector { id: diagnostics }
        onExited: code => {
            if (response.text.trim()) root.receive(response.text, true);
            else root.error = diagnostics.text.trim() || qsTr("主显示器设置失败（%1）。").arg(code);
        }
    }
}
