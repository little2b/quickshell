pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root

    function refreshItems() {
        contentRevision++;
    }

    required property var entries
    required property int columns
    required property int pageSize
    required property real tileHeight
    required property real iconSize
    property int page: 0
    property int selected: -1
    property bool animate: false
    property string draggedKey: ""
    property string dropKey: ""
    property bool mergeReady: false
    property bool insertAfter: false
    property real position: 0
    property bool swiping: false
    property real swipeOrigin: 0
    property real swipeDistance: 0
    property int contentRevision: 0
    readonly property int pageCount: Math.max(1, Math.ceil(entries.length / pageSize))
    readonly property bool moving: slide.running || swiping
    readonly property bool ready: {
        const revision = contentRevision;
        const current = pages.itemAt(page) as LaunchpadPage;
        return current ? current.displayReady : entries.length === 0;
    }

    readonly property bool cached: {
        const revision = contentRevision;
        const current = pages.itemAt(page) as LaunchpadPage;
        return current ? current.snapshot !== null : entries.length === 0;
    }

    signal activated(var entry)
    signal pageRequested(int index)
    signal settled

    clip: true
    onPageChanged: Qt.callLater(root.goToPage)
    onReadyChanged: {
        if (ready)
            Qt.callLater(root.goToPage);
    }
    onEntriesChanged: {
        swiping = false;
        Qt.callLater(root.finishTransition);
    }
    onPageSizeChanged: Qt.callLater(root.finishTransition)
    onAnimateChanged: {
        if (!animate)
            finishTransition();
    }

    function goToPage() {
        if (swiping || !ready)
            return;
        slide.stop();
        if (!animate || Math.abs(position - page) < 0.001) {
            position = page;
            settled();
            return;
        }
        slide.from = position;
        slide.to = page;
        slide.duration = Math.max(160, Math.min(340, 300 * Math.abs(position - page)));
        slide.start();
    }
    function finishTransition() {
        slide.stop();
        swiping = false;
        position = page;
        settled();
    }
    function beginSwipe() {
        if (swiping || pageCount < 2)
            return;
        slide.stop();
        swipeOrigin = position;
        swipeDistance = 0;
        swiping = true;
    }
    function swipeBy(distance) {
        if (!swiping)
            return;
        swipeDistance += distance;
        const next = swipeOrigin + swipeDistance / Math.max(1, width);
        position = next < 0 ? next * 0.18 : next > pageCount - 1 ? pageCount - 1 + (next - pageCount + 1)
                                                                   * 0.18 : next;
    }
    function endSwipe() {
        if (!swiping)
            return;
        swiping = false;
        const origin = Math.round(swipeOrigin);
        const next = Math.max(0, Math.min(pageCount - 1, Math.abs(swipeDistance) > width * 0.16 ? origin + (
                                                                                                      swipeDistance
                                                                                                      > 0 ? 1 :
                                                                                                            -1) : origin));
        if (next !== page)
            pageRequested(next);
        else
            goToPage();
    }
    function tileAt(owner, point) {
        if (moving)
            return null;
        const local = mapFromItem(owner, point.x, point.y);
        if (local.x < 0 || local.x > width || local.y < 0 || local.y > height)
            return null;
        const current = pages.itemAt(page) as LaunchpadPage;
        return current ? current.tileAt(owner, point) : null;
    }

    NumberAnimation {
        id: slide
        target: root
        property: "position"
        easing.type: Easing.OutCubic
        onFinished: root.settled()
    }
    Item {
        id: strip
        width: root.width * root.pageCount
        height: root.height
        x: -root.position * root.width
        Repeater {
            id: pages
            model: root.pageCount
            onItemAdded: Qt.callLater(root.refreshItems)
            onItemRemoved: Qt.callLater(root.refreshItems)
            LaunchpadPage {
                required property int index
                width: root.width
                height: root.height
                x: index * width
                entries: root.entries.slice(index * root.pageSize, (index + 1) * root.pageSize)
                firstIndex: index * root.pageSize
                columns: root.columns
                tileHeight: root.tileHeight
                iconSize: root.iconSize
                selected: root.selected
                draggedKey: root.draggedKey
                dropKey: root.dropKey
                mergeReady: root.mergeReady
                insertAfter: root.insertAfter
                onActivated: entry => root.activated(entry)
            }
        }
    }
}
