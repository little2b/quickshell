pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Components
import qs.Services
import qs.Widgets.common
import "../../Common/functions/LaunchpadLayout.js" as Layout

PanelWindow {
    id: root
    screen: LaunchpadService.targetScreen || Quickshell.screens[0] || null
    implicitWidth: screen ? screen.width : 1280
    implicitHeight: screen ? screen.height : 720
    visible: false
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    WlrLayershell.namespace: "clavis-shell-launchpad"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: LaunchpadService.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    readonly property real viewWidth: screen ? screen.width : 1280
    readonly property real viewHeight: screen ? screen.height : 720
    property real openProgress: 0
    property string phase: "hidden"
    property bool initialized: false
    property bool warmed: false
    property bool awaitingFrame: false
    property int openingFrames: 0
    property int preloadRevision: 0
    readonly property bool iconsPreloaded: {
        const revision = preloadRevision;
        if (iconPreload.count !== LaunchpadService.applications.length)
            return false;
        for (let index = 0; index < iconPreload.count; ++index) {
            const icon = iconPreload.itemAt(index) as ThemeIcon;
            if (!icon || (icon.status !== Image.Ready && icon.status !== Image.Error))
                return false;
        }
        return true;
    }
    function refreshPreload() {
        preloadRevision++;
    }
    readonly property bool prepared: pager.ready && backdrop.ready
    property bool pagingGesture: false
    property bool gestureCancelled: false
    property real lastPointerX: 0
    property real wheelDistance: 0

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
    readonly property int columns: Math.max(1, Math.min(7, Math.floor(gridArea.width / 142)))
    readonly property int rows: Math.max(1, Math.min(5, Math.floor(gridArea.height / 144)))
    readonly property int pageSize: columns * rows
    readonly property int pageCount: Math.max(1, Math.ceil(entries.length / pageSize))
    readonly property real tileHeight: Math.min(154, gridArea.height / rows)
    readonly property real iconSize: Math.min(80, Math.max(48, tileHeight - 65))

    Component.onCompleted: {
        initialized = true;
        Qt.callLater(root.syncVisibility);
        Qt.callLater(root.prewarm);
    }
    onPreparedChanged: {
        Qt.callLater(root.tryReveal);
        Qt.callLater(root.prewarm);
    }

    // A transparent surface warms the native window and its DPR-sized icons
    // once. It takes neither pointer nor keyboard input while doing so.
    mask: Region {
        width: LaunchpadService.visible ? root.viewWidth : 0
        height: LaunchpadService.visible ? root.viewHeight : 0
    }
    function prewarm() {
        if (!initialized || warmed || phase !== "hidden" || LaunchpadService.visible || !prepared)
            return;
        warmed = true;
        phase = "warming";
        openingFrames = 0;
        awaitingFrame = true;
        visible = true;
    }

    function animateOpen(target) {
        opening.stop();
        opening.from = openProgress;
        opening.to = target;
        opening.duration = Math.max(1, (target > openProgress ? 300 : 200) * Math.abs(target - openProgress));
        opening.start();
    }
    function syncVisibility() {
        if (!initialized)
            return;
        if (LaunchpadService.visible) {
            if (phase === "warming") {
                phase = "opening";
                search.forceActiveFocus();
            } else if (phase === "closing") {
                phase = "opening";
                animateOpen(1);
                search.forceActiveFocus();
            } else if (phase === "hidden") {
                phase = "preparing";
                tryReveal();
            }
        } else {
            awaitingFrame = false;
            cancelDrag();
            pagingGesture = false;
            swipeEnd.stop();
            pager.finishTransition();
            contextMenu.close();
            if (visible) {
                phase = "closing";
                animateOpen(0);
            } else {
                phase = "hidden";
            }
        }
    }
    function tryReveal() {
        if (phase !== "preparing" || !LaunchpadService.visible || !prepared)
            return;
        awaitingFrame = true;
        openingFrames = 0;
        phase = "opening";
        visible = true;
        Qt.callLater(() => search.forceActiveFocus());
    }
    Connections {
        target: LaunchpadService
        function onVisibleChanged() {
            root.syncVisibility();
        }
    }
    FrameAnimation {
        running: root.awaitingFrame
        onTriggered: {
            if (++root.openingFrames < 2 || !root.prepared)
                return;
            if (root.phase === "warming") {
                if (!pager.cached || !root.iconsPreloaded)
                    return;
                root.awaitingFrame = false;
                root.visible = false;
                root.phase = "hidden";
                return;
            }
            root.awaitingFrame = false;
            if (LaunchpadService.visible && root.phase === "opening")
                root.animateOpen(1);
        }
    }
    NumberAnimation {
        id: opening
        target: root
        property: "openProgress"
        easing.type: Easing.OutCubic
        onFinished: {
            if (LaunchpadService.visible) {
                root.phase = "open";
            } else {
                root.visible = false;
                root.phase = "hidden";
                root.query = "";
                root.folderId = "";
                root.selected = -1;
            }
        }
    }

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
        if (dragging) {
            cancelDrag();
            gestureCancelled = true;
        } else if (folderId) {
            folderId = "";
            search.forceActiveFocus();
        } else if (query)
            query = "";
        else
            LaunchpadService.close();
    }
    function changePage(delta) {
        dropKey = "";
        mergeReady = false;
        mergeDelay.stop();
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
        return pager.tileAt(content, point);
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
        if (pager.moving) {
            pager.finishTransition();
            updateDrop();
        }
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
        onTriggered: root.changePage(root.pointerPoint.x < root.viewWidth / 2 ? -1 : 1)
    }
    Timer {
        id: swipeEnd
        interval: 150
        onTriggered: pager.endSwipe()
    }

    Item {
        id: content
        width: root.viewWidth
        height: root.viewHeight
        focus: true
        enabled: LaunchpadService.visible
        // Render the first, nearly transparent frame before starting the
        // entrance animation, so texture uploads do not consume its duration.
        // Warm the native window without drawing a translucent veil over the
        // desktop. Page snapshots render offscreen even during this warm-up.
        opacity: root.phase === "warming" ? 0 : Math.max(0.001, root.openProgress)

        // Keep full-size icons for folder contents too, not just the small
        // folder previews, so entering a group reuses the same pixmaps.
        Repeater {
            id: iconPreload
            model: LaunchpadService.applications
            onItemAdded: Qt.callLater(root.refreshPreload)
            onItemRemoved: Qt.callLater(root.refreshPreload)
            ThemeIcon {
                required property var modelData
                visible: false
                iconSource: LaunchpadService.icon(String(modelData.id))
                sourceSize: Qt.size(160, 160)
                fillMode: Image.PreserveAspectFit
                cacheThemeIcons: true
                asynchronous: true
                retainWhileLoading: true
            }
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

        LaunchpadBackdrop {
            id: backdrop
            anchors.fill: parent
            screenName: root.screen ? root.screen.name : ""
            viewportSize: Qt.size(root.screen ? root.screen.width : 1280, root.screen ? root.screen.height :
                                                                                        720)
            scale: 1.035 - 0.035 * root.openProgress
        }

        Rectangle {
            visible: !!root.folderId
            x: gridArea.x - 24
            y: gridArea.y - 24
            width: gridArea.width + 48
            height: gridArea.height + 48
            scale: gridArea.scale
            radius: 32
            color: "#65202839"
            border.width: 1
            border.color: "#28ffffff"
        }

        Item {
            id: gridArea
            x: (root.viewWidth - width) / 2
            y: 148
            width: Math.max(160, Math.min(root.folderId ? 920 : 1220, root.viewWidth - 96))
            height: Math.max(100, root.viewHeight - 280)
            scale: 0.94 + 0.06 * root.openProgress
            LaunchpadPager {
                id: pager
                anchors.fill: parent
                entries: root.entries
                columns: root.columns
                pageSize: root.pageSize
                tileHeight: root.tileHeight
                iconSize: root.iconSize
                page: root.page
                selected: root.selected
                animate: root.visible && root.openProgress > 0
                draggedKey: Layout.key(root.draggedEntry)
                dropKey: root.dropKey
                mergeReady: root.mergeReady
                insertAfter: root.insertAfter
                onActivated: entry => root.activate(entry)
                onPageRequested: index => root.changePage(index - root.page)
                onSettled: {
                    if (root.dragging)
                        root.updateDrop();
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
            preventStealing: root.dragging || root.pagingGesture
            cursorShape: root.dragging ? Qt.ClosedHandCursor : root.selected >= 0 ? Qt.PointingHandCursor :
                                                                                    Qt.ArrowCursor
            onPressed: mouse => {
                root.gestureCancelled = pager.moving && !pager.swiping;
                root.pagingGesture = false;
                root.lastPointerX = mouse.x;
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
                if (pressed && !root.pressedKey && !root.gestureCancelled && !root.pagingGesture && Math.abs(
                            mouse.x - root.pressPoint.x) > 16 && Math.abs(mouse.x - root.pressPoint.x)
                        > Math.abs(mouse.y - root.pressPoint.y) * 1.2) {
                    root.pagingGesture = true;
                    pager.beginSwipe();
                }
                if (root.pagingGesture)
                    pager.swipeBy(root.lastPointerX - mouse.x);
                root.lastPointerX = mouse.x;
                if (pressed && (pressedButtons & Qt.LeftButton) && root.pressedKey && !root.searching &&
                        !root.dragging && !root.gestureCancelled && Math.hypot(mouse.x - root.pressPoint.x,
                                                                               mouse.y - root.pressPoint.y)
                        > 8) {
                    const source = Layout.locate(LaunchpadService.entries, root.pressedKey);
                    if (source)
                        root.draggedEntry = Layout.clone([source.entry])[0];
                }
                if (root.dragging)
                    root.updateDrop();
            }
            onReleased: mouse => {
                if (root.gestureCancelled) {
                    root.gestureCancelled = false;
                    root.pressedKey = "";
                    return;
                }
                if (root.pagingGesture) {
                    root.pagingGesture = false;
                    pager.endSwipe();
                    return;
                }
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
            onCanceled: {
                root.cancelDrag();
                root.pagingGesture = false;
                pager.endSwipe();
            }
            onWheel: wheel => {
                if (root.dragging) {
                    wheel.accepted = true;
                    return;
                }
                if (wheel.phase === Qt.ScrollEnd && pager.swiping) {
                    swipeEnd.stop();
                    pager.endSwipe();
                } else if (Math.abs(wheel.pixelDelta.x) > 0) {
                    pager.beginSwipe();
                    pager.swipeBy(-wheel.pixelDelta.x);
                    swipeEnd.restart();
                } else if (!pager.swiping) {
                    const delta = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)
                          ? wheel.angleDelta.x : wheel.angleDelta.y;
                    if (Date.now() - root.lastWheelTime > 180)
                        root.wheelDistance = 0;
                    root.wheelDistance += delta;
                    root.lastWheelTime = Date.now();
                    if (Math.abs(root.wheelDistance) >= 90) {
                        root.changePage(root.wheelDistance < 0 ? 1 : -1);
                        root.wheelDistance = 0;
                    }
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
            y: root.viewHeight - 104
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
            y: root.viewHeight - 54
            width: root.viewWidth - 64
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
            width: gridArea.width / root.columns
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
