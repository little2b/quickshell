pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import qs.Services

Item {
    id: root

    function refreshItems() {
        tileRevision++;
    }
    required property var entries
    required property int firstIndex
    required property int columns
    required property real tileHeight
    required property real iconSize
    property int selected: -1
    property string draggedKey: ""
    property string dropKey: ""
    property bool mergeReady: false
    property bool insertAfter: false
    property int tileRevision: 0
    property var snapshot: null
    property int snapshotRevision: 0
    property bool capturing: false
    property string language: Qt.uiLanguage
    readonly property bool displayReady: ready || snapshot !== null

    function invalidateSnapshot() {
        snapshotRevision++;
        snapshot = null;
        capturing = false;
        Qt.callLater(root.captureSnapshot);
    }
    function captureSnapshot() {
        if (capturing || snapshot || !ready || draggedKey || !root.Window.window ||
                !root.Window.window.visible)
            return;
        const revision = snapshotRevision;
        capturing = true;
        const ratio = Math.min(Screen.devicePixelRatio, 2048 / Math.max(1, width));
        if (!grid.grabToImage(result => {
            if (!root || revision !== root.snapshotRevision)
                return;
            root.capturing = false;
            if (root.ready)
                root.snapshot = result;
        }, Qt.size(Math.max(1, Math.round(width * ratio)), Math.max(1, Math.round(grid.height * ratio)))))
            capturing = false;
    }
    onEntriesChanged: invalidateSnapshot()
    onWidthChanged: invalidateSnapshot()
    onHeightChanged: invalidateSnapshot()
    onLanguageChanged: invalidateSnapshot()
    onReadyChanged: {
        if (ready)
            Qt.callLater(root.captureSnapshot);
    }
    onDraggedKeyChanged: {
        if (!draggedKey)
            Qt.callLater(root.captureSnapshot);
    }
    Connections {
        target: root.Window.window
        function onVisibleChanged() {
            if (!root.Window.window.visible && root.capturing)
                root.invalidateSnapshot();
            else
                Qt.callLater(root.captureSnapshot);
        }
    }
    Connections {
        target: ThemeService
        function onIconThemeRevisionChanged() {
            root.invalidateSnapshot();
        }
    }

    readonly property bool ready: {
        const revision = tileRevision;
        if (tiles.count !== entries.length)
            return false;
        for (let i = 0; i < tiles.count; ++i) {
            const tile = tiles.itemAt(i) as LaunchpadTile;
            if (!tile || !tile.ready)
                return false;
        }
        return true;
    }
    signal activated(var entry)

    // Keep every page instantiated and reveal new icons together.
    opacity: displayReady ? 1 : 0

    function tileAt(owner, point) {
        for (let i = 0; i < tiles.count; ++i) {
            const tile = tiles.itemAt(i) as LaunchpadTile;
            if (!tile)
                continue;
            const local = tile.mapFromItem(owner, point.x, point.y);
            if (local.x >= 0 && local.x < tile.width && local.y >= 0 && local.y < tile.height)
                return {
                    tile: tile,
                    index: firstIndex + i,
                    point: local
                };
        }
        return null;
    }

    Image {
        anchors.centerIn: parent
        width: root.width
        height: grid.height
        source: root.snapshot ? root.snapshot.url : ""
        visible: !root.ready && !!root.snapshot
        fillMode: Image.Stretch
    }
    Grid {
        id: grid
        opacity: root.ready ? 1 : 0
        anchors.centerIn: parent
        width: parent.width
        columns: root.columns
        Repeater {
            id: tiles
            model: root.entries
            onItemAdded: Qt.callLater(root.refreshItems)
            onItemRemoved: Qt.callLater(root.refreshItems)
            LaunchpadTile {
                id: tile
                required property var modelData
                required property int index
                entry: modelData
                width: root.width / root.columns
                height: root.tileHeight
                iconSize: root.iconSize
                highlighted: !root.capturing && root.selected === root.firstIndex + index && !root.draggedKey
                grouping: root.dropKey === entryKey && root.mergeReady
                opacity: entryKey === root.draggedKey ? 0.3 : 1
                onActivated: root.activated(entry)
                Rectangle {
                    x: root.insertAfter ? parent.width - 2 : 0
                    y: 8
                    width: 3
                    height: root.iconSize + 18
                    radius: 2
                    color: "#eeffffff"
                    visible: root.draggedKey !== "" && root.dropKey === tile.entryKey && !root.mergeReady
                }
            }
        }
    }
}
