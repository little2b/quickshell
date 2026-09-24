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
    property var targetScreen: null
    property var savedEntries: []
    property bool ready: false
    property bool writable: false
    property bool storeReady: false
    property string error: ""
    readonly property string filePath: Paths.configHome + "/launchpad.json"
    readonly property var applications: ApplicationService.launcherApplications.filter(application =>
    !application.dragOnly && application.id !== ApplicationService.launchpadApplication.id)
    readonly property var entries: Layout.reconcile(savedEntries, applications.map(application => String(
                                                                                                      application.id)))

    function open(outputName) {
        const name = outputName || Niri.currentOutput;
        targetScreen = Quickshell.screens.find(screen => screen.name === name) || Quickshell.screens[0]
                || null;
        visible = !!targetScreen;
        return visible;
    }
    function close() {
        visible = false;
    }
    function toggle(outputName) {
        if (visible)
            close();
        else
            open(outputName);
        return true;
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
        watchChanges: false
        onLoaded: {
            const entries = Layout.decode(layoutFile.text());
            root.finishLoad(entries, entries !== null);
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
