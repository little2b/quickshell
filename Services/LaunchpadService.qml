pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Clavis.Niri
import qs.Common
import qs.Services
import "../Common/functions/LaunchpadLayout.js" as Layout

Singleton {
    id: root

    property bool visible: false
    property bool chromeHold: false
    property var targetScreen: null
    property var savedEntries: []
    property bool ready: false
    property bool writable: false
    property bool storeReady: false
    property string error: ""
    property bool backendReady: false
    property bool externalEnabled: false
    property bool externalAvailable: false
    property var externalQueue: []
    onExternalEnabledChanged: {
        externalWatch.running = backendReady && externalEnabled;
        if (!externalEnabled) {
            visible = false;
            chromeHold = false;
            externalAvailable = false;
        }
    }
    onBackendReadyChanged: externalWatch.running = backendReady && externalEnabled
    readonly property string filePath: Paths.configHome + "/launchpad.json"
    readonly property var applications: ApplicationService.launcherApplications.filter(application =>
    !application.dragOnly && application.id !== ApplicationService.launchpadApplication.id)
    readonly property var entries: Layout.reconcile(savedEntries, applications.map(application => String(
                                                                                                      application.id)))

    function open(outputName) {
        if (externalEnabled)
            return requestExternal("show", outputName);
        const name = outputName || Niri.currentOutput;
        targetScreen = Quickshell.screens.find(screen => screen.name === name) || Quickshell.screens[0]
                || null;
        if (!targetScreen) {
            chromeHold = false;
            visible = false;
            return false;
        }
        // Freeze top-edge surfaces before the overlay requests focus. Their
        // native mapping and exclusive zone must not change under the fade.
        chromeHold = true;
        visible = true;
        return true;
    }
    function close() {
        if (externalEnabled) {
            requestExternal("hide", "");
            return;
        }
        if (!visible)
            chromeHold = false;
        visible = false;
    }
    function finishClose() {
        if (!visible)
            chromeHold = false;
    }
    function toggle(outputName) {
        if (externalEnabled)
            return requestExternal("toggle", outputName);
        if (visible)
            close();
        else
            open(outputName);
        return true;
    }
    function requestExternal(action, outputName) {
        if (action !== "hide")
            chromeHold = true;
        externalQueue.push([Paths.binHome + "/clavis-launchpad", "--" + action, "--output", outputName
                            || Niri.currentOutput || ""]);
        pumpExternal();
        return true;
    }
    function pumpExternal() {
        if (!externalControl.running && externalQueue.length)
            externalControl.exec(externalQueue.shift());
    }
    function consumeExternal(data) {
        if (!externalEnabled)
            return;
        try {
            const state = JSON.parse(data);
            if (state.schemaVersion !== 1)
                return;
            externalAvailable = state.phase !== "unavailable";
            visible = state.visible === true;
            chromeHold = visible;
        } catch (exception) {
            console.warn("LaunchpadService: invalid external state:", exception);
        }
    }

    FileView {
        id: backendFile
        path: Paths.configHome + "/launchpad-backend.json"
        watchChanges: true
        onFileChanged: backendFile.reload()
        onLoaded: {
            try {
                root.externalEnabled = JSON.parse(backendFile.text()).external === true;
            } catch (exception) {
                root.externalEnabled = false;
            }
            root.backendReady = true;
        }
        onLoadFailed: {
            root.externalEnabled = false;
            root.backendReady = true;
        }
    }
    Process {
        id: externalControl
        stdout: SplitParser {
            onRead: data => root.consumeExternal(data)
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.error = qsTr("This application could not be opened.");
                root.visible = false;
                root.chromeHold = false;
            }
            Qt.callLater(root.pumpExternal);
        }
    }
    Process {
        id: externalWatch
        command: [Paths.binHome + "/clavis-launchpad", "--watch"]
        running: root.backendReady && root.externalEnabled
        stdout: SplitParser {
            onRead: data => root.consumeExternal(data)
        }
        onExited: {
            root.externalAvailable = false;
            if (root.externalEnabled) {
                root.visible = false;
                root.chromeHold = false;
                watchRestart.restart();
            }
        }
    }
    Timer {
        id: watchRestart
        interval: 2000
        onTriggered: {
            if (root.externalEnabled)
                externalWatch.running = true;
        }
    }
    function launch(id) {
        const success = SpotlightAppUsage.launch(id);
        if (success)
            close();
        else
            error = qsTr("This application could not be opened.");
        return success;
    }
    function commit(next) {
        if (!ready || next === null)
            return false;
        savedEntries = next;
        if (writable)
            layoutFile.setText(JSON.stringify({
                                                  schemaVersion: 1,
                                                  entries: next
                                              }, null, 2));
        return true;
    }
    function move(key, folderId, index) {
        return commit(Layout.move(entries, key, folderId, index));
    }
    function merge(source, target) {
        return commit(Layout.merge(entries, source, target, "group-" + Date.now() + "-" + Math.random(
                                       ).toString(36).slice(2, 8), qsTr("Folder")));
    }
    function rename(id, name) {
        return commit(Layout.rename(entries, id, name));
    }
    function dissolve(id) {
        return commit(Layout.dissolve(entries, id));
    }
    function title(entry) {
        if (!entry)
            return "";
        if (entry.kind === "folder")
            return entry.name;
        const application = ApplicationService.findById(entry.id);
        return application ? String(application.name || application.id) : entry.id;
    }
    function icon(id) {
        const application = ApplicationService.findById(id);
        return ApplicationService.iconSource(application ? application.icon : "");
    }
    function search(query) {
        const terms = query.toLocaleLowerCase().trim().split(/\s+/);
        return applications.filter(application => {
            const text = [application.name, application.genericName, application.id].concat(Array.from(
                                                                                                application.keywords
                                                                                                || [])).join(
                      " ").toLocaleLowerCase();
            return terms.every(term => text.includes(term));
        }).map(application => Layout.app(String(application.id)));
    }
    function finishLoad(entries, canWrite) {
        if (ready)
            return;
        savedEntries = entries || [];
        writable = canWrite;
        ready = true;
        if (!canWrite)
            error = qsTr("The saved layout could not be read. Changes apply to this session only.");
    }

    Process {
        command: ["mkdir", "-p", Paths.configHome]
        running: true
        onExited: exitCode => {
            if (exitCode === 0)
                root.storeReady = true;
            else
                root.finishLoad(null, false);
        }
    }
    FileView {
        id: layoutFile
        path: root.storeReady ? root.filePath : ""
        atomicWrites: true
        blockWrites: true
        watchChanges: true
        onFileChanged: layoutFile.reload()
        onLoaded: {
            const entries = Layout.decode(layoutFile.text());
            if (root.ready) {
                root.savedEntries = entries || [];
                root.writable = entries !== null;
            } else {
                root.finishLoad(entries, entries !== null);
            }
        }
        onLoadFailed: error => {
            if (root.storeReady)
                root.finishLoad(null, error === FileViewError.FileNotFound);
        }
        onSaveFailed: error => {
            root.writable = false;
            root.error = qsTr("The layout could not be saved. Changes apply to this session only.");
            console.warn("LaunchpadService: cannot save layout:", error);
        }
    }
}
