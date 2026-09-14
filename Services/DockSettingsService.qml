pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var settings: ({pinned: [], ignoredApps: []})
    property var confirmed: ({pinned: [], ignoredApps: []})
    property var pending: ({})
    property var failedPatch: ({})
    property bool ready: false
    property string error: ""
    property bool refreshPending: false
    readonly property bool busy: operation.running || saveDelay.running
    readonly property string executable: Quickshell.env("HOME") + "/.local/bin/qs"

    function refresh() {
        if (operation.running || Object.keys(pending).length) {
            refreshPending = true;
            return;
        }
        refreshPending = false;
        operation.kind = "read";
        operation.command = [executable, "ipc", "-c", "nyx-dock", "call", "dock", "getSettings"];
        operation.running = true;
    }
    function setOptions(patch) {
        if (!ready) return;
        error = "";
        failedPatch = ({});
        pending = Object.assign({}, pending, patch);
        settings = Object.assign({}, settings, patch);
        saveDelay.restart();
    }
    function flush() {
        if (operation.running || !Object.keys(pending).length) return;
        operation.patch = pending;
        pending = ({});
        operation.kind = "write";
        operation.command = [executable, "ipc", "-c", "nyx-dock", "call", "dock", "configure",
                             JSON.stringify(operation.patch)];
        operation.running = true;
    }
    function retry() {
        if (Object.keys(failedPatch).length) {
            const patch = failedPatch;
            failedPatch = ({});
            setOptions(patch);
        } else refresh();
    }
    function startDock() {
        if (operation.running) return;
        operation.kind = "start";
        operation.command = ["systemctl", "--user", "start", "nyx-dock.service"];
        operation.running = true;
    }
    function pin(id) {
        if (settings.pinned.indexOf(id) === -1)
            setOptions({pinned: settings.pinned.concat([id])});
    }
    function unpin(id) { setOptions({pinned: settings.pinned.filter(value => value !== id)}); }
    function movePin(index, offset) {
        const next = settings.pinned.slice();
        const target = index + offset;
        if (target < 0 || target >= next.length) return;
        const item = next.splice(index, 1)[0];
        next.splice(target, 0, item);
        setOptions({pinned: next});
    }
    function resetAppearance() {
        setOptions({enabled: true, output: "", hideMode: "smart", showRunning: true,
            iconSize: 44, spacing: 8, bottomMargin: 10, backgroundOpacity: 93,
            cornerRadius: 20, hideDelay: 650, hoverZoom: true, showTooltips: true,
            showIndicators: true});
    }

    Component.onCompleted: refresh()
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
              + "/quickshell/nyx-dock/settings.json"
        preload: true
        watchChanges: true
        onFileChanged: refreshDelay.restart()
    }
    Timer { id: saveDelay; interval: 180; onTriggered: root.flush() }
    Timer { id: refreshDelay; interval: 180; onTriggered: root.refresh() }
    Process {
        id: operation
        property string kind: "read"
        property var patch: ({})
        stdout: StdioCollector { id: reply }
        stderr: StdioCollector { id: diagnostics }
        onExited: code => {
            try {
                if (code !== 0) throw new Error(diagnostics.text.trim() || qsTr("Dock 暂时无法连接"));
                if (kind === "start") {
                    refreshDelay.restart();
                    return;
                }
                const result = JSON.parse(reply.text.trim());
                if (kind === "write" && !result.ok) throw new Error(result.error);
                const config = kind === "write" ? result.settings : result;
                if (!config || !Array.isArray(config.pinned)) throw new Error(qsTr("无法读取 Dock 设置"));
                root.confirmed = config;
                root.settings = Object.assign({}, config, root.pending);
                root.ready = true;
                root.error = "";
            } catch (e) {
                root.error = qsTr("设置未能保存或读取：%1").arg(String(e));
                if (kind === "write") root.failedPatch = patch;
                root.settings = Object.assign({}, root.confirmed, root.pending);
            }
            if (Object.keys(root.pending).length) saveDelay.restart();
            else if (root.refreshPending) refreshDelay.restart();
        }
    }
}
