pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Components
import qs.Services
import qs.Widgets.common
import "../../Common/functions/LaunchpadLayout.js" as Layout

PanelWindow {
    id: root
    screen: LaunchpadService.targetScreen
    visible: true
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    WlrLayershell.namespace: "clavis-shell-launchpad"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    property string folderId: ""
    property string query: ""
    property int page: 0
    property int selected: -1
    property string pressedKey: ""
    property point pressPoint
    property point pointerPoint
    property var draggedEntry: null
    property string dropKey: ""
    property bool mergeCandidate: false
    property bool mergeReady: false
    property bool insertAfter: false
    property bool leftFolderByDrag: false
    property string contextKey: ""
    property double lastWheelTime: 0
    readonly property bool searching: query.trim().length > 0
    readonly property bool dragging: draggedEntry !== null
    readonly property var folder: Layout.folder(LaunchpadService.entries, folderId)
    readonly property var entries: searching ? LaunchpadService.search(query) : Layout.contents(
                                                   LaunchpadService.entries, folderId)
    readonly property int columns: Math.max(1, Math.min(7, Math.floor(appGrid.width / 142)))
    readonly property int rows: Math.max(1, Math.min(5, Math.floor(gridArea.height / 144)))
    readonly property int pageSize: columns * rows
    readonly property int pageCount: Math.max(1, Math.ceil(entries.length / pageSize))
    readonly property var pageEntries: entries.slice(page * pageSize, (page + 1) * pageSize)
    readonly property real tileHeight: Math.min(154, gridArea.height / rows)
    readonly property real iconSize: Math.min(80, Math.max(48, tileHeight - 65))

    onQueryChanged: {
        page = 0;
        selected = entries.length ? 0 : -1;
    }
    onFolderIdChanged: {
        page = 0;
        selected = -1;
    }
    onPageCountChanged: Qt.callLater(root.clampPage)
    onPageSizeChanged: Qt.callLater(root.clampPage)
    onFolderChanged: {
        if (folderId && !folder)
            folderId = "";
    }

    function clampPage() {
        page = Math.max(0, Math.min(page, pageCount - 1));
    }
    function activate(entry) {
        if (!entry)
            return;
        if (entry.kind === "folder") {
            folderId = entry.id;
            query = "";
            content.forceActiveFocus();
        } else
            LaunchpadService.launch(entry.id);
    }
    function back() {
        if (dragging)
            cancelDrag();
        else if (folderId) {
            folderId = "";
            search.forceActiveFocus();
        } else if (query)
            query = "";
        else
            LaunchpadService.close();
    }
    function changePage(delta) {
        page = Math.max(0, Math.min(pageCount - 1, page + delta));
        selected = Math.min(entries.length - 1, page * pageSize);
        if (dragging)
            updateDrop();
    }
    function navigate(offset) {
        selected = Math.max(0, Math.min(entries.length - 1, selected < 0 ? 0 : selected + offset));
        page = Math.floor(Math.max(0, selected) / pageSize);
        content.forceActiveFocus();
    }
    function tileAt(point) {
        for (let i = 0; i < tiles.count; ++i) {
            const tile = tiles.itemAt(i);
            const local = tile.mapFromItem(content, point.x, point.y);
            if (local.x >= 0 && local.x < tile.width && local.y >= 0 && local.y < tile.height)
                return {
                    tile: tile,
                    index: page * pageSize + i,
                    point: local
                };
        }
        return null;
    }
    function overBack() {
        const point = backButton.mapFromItem(content, pointerPoint.x, pointerPoint.y);
        return folderId !== "" && point.x >= -16 && point.x <= backButton.width + 16 && point.y >= -16
                && point.y <= backButton.height + 16;
    }
    function updateDrop() {
        const hit = tileAt(pointerPoint);
        const nextKey = hit && hit.tile.entryKey !== Layout.key(draggedEntry) ? hit.tile.entryKey : "";
        const grouping = !!nextKey && !folderId && draggedEntry.kind === "app" && hit.point.y < iconSize + 26 && Math.abs(hit.point.x
                                                                                                                          - hit.tile.width
                                                                                                                          / 2) < iconSize
              * 0.55;
        if (nextKey !== dropKey || grouping !== mergeCandidate) {
            mergeDelay.stop();
            mergeReady = false;
            dropKey = nextKey;
            mergeCandidate = grouping;
            if (grouping)
                mergeDelay.start();
        }
        insertAfter = !!hit && hit.point.x > hit.tile.width / 2;
        if (overBack()) {
            if (!folderExit.running)
                folderExit.start();
        } else
            folderExit.stop();
    }
    function cancelDrag() {
        draggedEntry = null;
        pressedKey = "";
        dropKey = "";
        mergeCandidate = false;
        mergeReady = false;
        leftFolderByDrag = false;
        mergeDelay.stop();
        folderExit.stop();
    }
    function finishDrag() {
        const source = Layout.key(draggedEntry);
        if (overBack() || (leftFolderByDrag && pointerPoint.y < gridArea.y))
            LaunchpadService.move(source, "", LaunchpadService.entries.length);
        else if (dropKey && mergeReady)
            LaunchpadService.merge(source, dropKey);
        else {
            const hit = tileAt(pointerPoint);
            const local = gridArea.mapFromItem(content, pointerPoint.x, pointerPoint.y);
            if (local.x >= 0 && local.x <= gridArea.width && local.y >= 0 && local.y <= gridArea.height) {
                const slot = hit ? hit.index + (insertAfter ? 1 : 0) : Math.min(entries.length, (page + 1)
                                                                                * pageSize);
                LaunchpadService.move(source, folderId, slot);
            }
        }
        cancelDrag();
    }

    Timer {
        id: mergeDelay
        interval: 450
        onTriggered: root.mergeReady = root.mergeCandidate
    }
    Timer {
        id: folderExit
        interval: 550
        onTriggered: {
            root.leftFolderByDrag = true;
            root.folderId = "";
            root.updateDrop();
        }
    }
    Timer {
        interval: 700
        repeat: true
        running: root.dragging && (root.pointerPoint.x < gridArea.x + 22 || root.pointerPoint.x > gridArea.x
                                   + gridArea.width - 22)
        onTriggered: root.changePage(root.pointerPoint.x < root.width / 2 ? -1 : 1)
    }

    Item {
        id: content
        anchors.fill: parent
        focus: true
        opacity: 0
        Component.onCompleted: {
            reveal.start();
            search.forceActiveFocus();
        }
        NumberAnimation {
            id: reveal
            target: content
            property: "opacity"
            to: 1
            duration: 180
            easing.type: Easing.OutCubic
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                root.back();
            else if (event.key === Qt.Key_Right)
                root.navigate(1);
            else if (event.key === Qt.Key_Left)
                root.navigate(-1);
            else if (event.key === Qt.Key_Down)
                root.navigate(root.columns);
            else if (event.key === Qt.Key_Up)
                root.navigate(-root.columns);
            else if (event.key === Qt.Key_PageDown)
                root.changePage(1);
            else if (event.key === Qt.Key_PageUp)
                root.changePage(-1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                root.activate(root.entries[root.selected]);
            else if (event.text.length && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier
                                                               | Qt.MetaModifier))) {
                root.folderId = "";
                root.query += event.text;
                search.forceActiveFocus();
            } else
                return;
            event.accepted = true;
        }

        Rectangle {
            anchors.fill: parent
            color: "#202938"
        }
        Image {
            id: wallpaper
            anchors.fill: parent
            visible: false
            readonly property string path: WallpaperService.overviewWallpaperForScreen(root.screen
                                                                                       ? root.screen.name :
                                                                                         "")
            source: WallpaperService.isImagePath(path) ? "file://" + path : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        MultiEffect {
            anchors.fill: parent
            source: wallpaper
            blurEnabled: true
            blurMax: 64
            blur: 1
            saturation: -0.15
        }
        Rectangle {
            anchors.fill: parent
            color: "#730c1220"
        }

        Rectangle {
            visible: !!root.folderId
            x: gridArea.x - 24
            y: gridArea.y - 24
            width: gridArea.width + 48
            height: gridArea.height + 48
            radius: 32
            color: "#65202839"
            border.width: 1
            border.color: "#28ffffff"
        }

        Item {
            id: gridArea
            x: (root.width - width) / 2
            y: 148
            width: Math.max(160, Math.min(root.folderId ? 920 : 1220, root.width - 96))
            height: Math.max(100, root.height - 280)
            Grid {
                id: appGrid
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                columns: root.columns
                Repeater {
                    id: tiles
                    model: root.pageEntries
                    LaunchpadTile {
                        id: tile
                        required property var modelData
                        required property int index
                        entry: modelData
                        width: appGrid.width / root.columns
                        height: root.tileHeight
                        iconSize: root.iconSize
                        highlighted: root.selected === root.page * root.pageSize + index && !root.dragging
                        grouping: root.dropKey === entryKey && root.mergeReady
                        opacity: root.dragging && entryKey === Layout.key(root.draggedEntry) ? 0.3 : 1
                        onActivated: root.activate(entry)
                        Rectangle {
                            x: root.insertAfter ? parent.width - 2 : 0
                            y: 8
                            width: 3
                            height: root.iconSize + 18
                            radius: 2
                            color: "#eeffffff"
                            visible: root.dragging && root.dropKey === tile.entryKey && !root.mergeReady
                        }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: root.entries.length === 0
                text: root.searching ? qsTr("No matching applications") : qsTr("No applications found")
                color: "#ddffffff"
                font.family: Fonts.ui
                font.pixelSize: 18
            }
        }

        // One stable pointer owner survives page changes and leaving folders,
        // so the drag never loses its grab when a tile delegate is replaced.
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: root.dragging
            cursorShape: root.dragging ? Qt.ClosedHandCursor : root.selected >= 0 ? Qt.PointingHandCursor :
                                                                                    Qt.ArrowCursor
            onPressed: mouse => {
                root.pointerPoint = Qt.point(mouse.x, mouse.y);
                root.pressPoint = root.pointerPoint;
                const hit = root.tileAt(root.pointerPoint);
                root.pressedKey = hit ? hit.tile.entryKey : "";
                content.forceActiveFocus();
            }
            onPositionChanged: mouse => {
                root.pointerPoint = Qt.point(mouse.x, mouse.y);
                const hit = root.tileAt(root.pointerPoint);
                if (!pressed)
                    root.selected = hit ? hit.index : -1;
                if (pressed && (pressedButtons & Qt.LeftButton) && root.pressedKey && !root.searching &&
                        !root.dragging && Math.hypot(mouse.x - root.pressPoint.x, mouse.y
                                                     - root.pressPoint.y) > 8) {
                    const source = Layout.locate(LaunchpadService.entries, root.pressedKey);
                    if (source)
                        root.draggedEntry = Layout.clone([source.entry])[0];
                }
                if (root.dragging)
                    root.updateDrop();
            }
            onReleased: mouse => {
                if (root.dragging) {
                    root.finishDrag();
                    return;
                }
                const hit = root.tileAt(Qt.point(mouse.x, mouse.y));
                if (mouse.button === Qt.RightButton && hit) {
                    root.contextKey = hit.tile.entryKey;
                    contextMenu.popup(mouse.x, mouse.y);
                } else if (hit && root.pressedKey === hit.tile.entryKey)
                    root.activate(hit.tile.entry);
                else if (!root.pressedKey)
                    root.back();
                root.pressedKey = "";
            }
            onCanceled: root.cancelDrag()
            onWheel: wheel => {
                if (root.dragging || Date.now() - root.lastWheelTime < 250) {
                    wheel.accepted = true;
                    return;
                }
                const delta = wheel.angleDelta.y || wheel.angleDelta.x;
                if (Math.abs(delta) >= 30) {
                    root.changePage(delta < 0 ? 1 : -1);
                    root.lastWheelTime = Date.now();
                }
                wheel.accepted = true;
            }
        }

        Item {
            id: header
            x: gridArea.x
            y: 52
            width: gridArea.width
            height: 52
            IconButton {
                id: backButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: !!root.folderId
                iconName: "arrow_back"
                iconColor: "white"
                accessibleName: qsTr("All Apps")
                normalContainerColor: root.dragging && root.overBack() ? "#55ffffff" : "#18ffffff"
                onClicked: {
                    root.folderId = "";
                    search.forceActiveFocus();
                }
            }
            TextField {
                id: folderName
                visible: !!root.folderId
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 128)
                height: 48
                text: root.folder ? root.folder.name : ""
                maximumLength: 80
                horizontalAlignment: TextInput.AlignHCenter
                font.family: Fonts.ui
                font.pixelSize: 25
                font.weight: Font.Medium
                color: "white"
                selectByMouse: true
                Accessible.name: qsTr("Folder name")
                background: Rectangle {
                    radius: 12
                    color: folderName.activeFocus ? "#25ffffff" : "transparent"
                }
                onEditingFinished: {
                    if (root.folder && text.trim() !== root.folder.name)
                        LaunchpadService.rename(root.folderId, text);
                    text = Qt.binding(() => root.folder ? root.folder.name : "");
                }
                onAccepted: content.forceActiveFocus()
            }
            TextField {
                id: search
                visible: !root.folderId
                anchors.centerIn: parent
                width: Math.min(360, parent.width - 100)
                height: 46
                text: root.query
                onTextEdited: root.query = text
                placeholderText: qsTr("Search applications")
                color: "white"
                placeholderTextColor: "#bbffffff"
                selectionColor: "#668aafff"
                font.family: Fonts.ui
                font.pixelSize: 16
                leftPadding: 42
                rightPadding: 38
                selectByMouse: true
                Accessible.name: placeholderText
                background: Rectangle {
                    radius: 14
                    color: "#25ffffff"
                    border.width: 1
                    border.color: search.activeFocus ? "#77ffffff" : "#35ffffff"
                }
                MaterialSymbol {
                    x: 13
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    color: "#ddffffff"
                    iconSize: 22
                }
                IconButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    controlSize: 34
                    iconSize: 18
                    iconName: "close"
                    iconColor: "white"
                    visible: root.query.length > 0
                    accessibleName: qsTr("Clear search")
                    onClicked: {
                        root.query = "";
                        search.forceActiveFocus();
                    }
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape)
                        root.back();
                    else if (event.key === Qt.Key_Down)
                        root.navigate(0);
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        root.activate(root.entries[Math.max(0, root.selected)]);
                    else
                        return;
                    event.accepted = true;
                }
            }
            IconButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconName: "close"
                iconColor: "white"
                normalContainerColor: "#18ffffff"
                accessibleName: qsTr("Close")
                onClicked: LaunchpadService.close()
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height - 104
            spacing: 12
            IconButton {
                iconName: "chevron_left"
                iconColor: "white"
                controlSize: 32
                enabled: root.page > 0
                opacity: enabled ? 1 : 0.25
                accessibleName: qsTr("Previous page")
                onClicked: root.changePage(-1)
            }
            Repeater {
                model: root.pageCount
                Item {
                    required property int index
                    width: 18
                    height: 32
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.index === root.page ? 9 : 7
                        height: width
                        radius: width / 2
                        color: parent.index === root.page ? "white" : "#66ffffff"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Page %1").arg(parent.index + 1)
                        onClicked: root.changePage(parent.index - root.page)
                        Accessible.onPressAction: root.changePage(parent.index - root.page)
                    }
                }
            }
            IconButton {
                iconName: "chevron_right"
                iconColor: "white"
                controlSize: 32
                enabled: root.page < root.pageCount - 1
                opacity: enabled ? 1 : 0.25
                accessibleName: qsTr("Next page")
                onClicked: root.changePage(1)
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height - 54
            width: root.width - 64
            horizontalAlignment: Text.AlignHCenter
            text: LaunchpadService.error || (root.searching ? qsTr("Clear search to arrange applications") :
                                                              root.folderId ? qsTr(
                                                                                  "Drag an app to the back arrow to move it out of this folder") :
                                                                              qsTr("Drag to rearrange. Hold over another app to create a folder."))
            color: LaunchpadService.error ? "#ffb4ab" : "#aaffffff"
            font.family: Fonts.ui
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }
        LaunchpadTile {
            visible: root.dragging
            entry: root.draggedEntry || {
                       kind: "app",
                       id: ""
                   }
            x: root.pointerPoint.x - width / 2
            y: root.pointerPoint.y - root.iconSize / 2 - 12
            width: appGrid.width / root.columns
            height: root.tileHeight
            iconSize: root.iconSize
            ghost: true
        }
        Menu {
            id: contextMenu
            readonly property var location: Layout.locate(LaunchpadService.entries, root.contextKey)
            MenuItem {
                text: qsTr("Open")
                onTriggered: {
                    if (contextMenu.location)
                        root.activate(contextMenu.location.entry);
                }
            }
            MenuItem {
                text: qsTr("Move out of folder")
                visible: !!contextMenu.location && !!contextMenu.location.parent
                height: visible ? implicitHeight : 0
                onTriggered: LaunchpadService.move(root.contextKey, "", LaunchpadService.entries.length)
            }
            MenuItem {
                text: qsTr("Rename folder")
                visible: !!contextMenu.location && contextMenu.location.entry.kind === "folder"
                height: visible ? implicitHeight : 0
                onTriggered: {
                    root.folderId = contextMenu.location.entry.id;
                    folderName.forceActiveFocus();
                    folderName.selectAll();
                }
            }
            MenuItem {
                text: qsTr("Ungroup")
                visible: !!contextMenu.location && contextMenu.location.entry.kind === "folder"
                height: visible ? implicitHeight : 0
                onTriggered: LaunchpadService.dissolve(contextMenu.location.entry.id)
            }
        }
    }
}
