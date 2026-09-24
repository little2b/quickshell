pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs.Services

Item {
    id: root

    required property var targetWindow
    required property Item backgroundItem
    property var additionalBackgroundItems: []
    property var additionalRegions: []
    property var subtractedBackgroundItems: []
    property var postSubtractionBackgroundItems: []
    // Applies only to regions added after subtraction.
    property Item postSubtractionClipItem: null
    property bool blurEnabled: true
    property bool compositorEnabled: BlurService.enabled
    property real radius: 0
    // Optional inset keeps integer protocol regions inside antialiased outlines.
    property real inset: 0
    property bool pillShapes: false
    property Item clipItem: null

    property bool surfaceReady: false
    property bool publishPending: false
    property bool destroying: false
    property var _publishedRegion: null
    property var _publishedWindow: null
    property string _publishedSignature: ""
    property var _regionObjects: []
    property var _subtractionRegionObjects: []
    property var _postSubtractionRegionObjects: []

    readonly property int visibleBackgroundCount: {
        let count = 0;
        const items = root.allBackgroundItems().concat(root.allPostSubtractionBackgroundItems());
        for (let index = 0; index < items.length; ++index) {
            const item = items[index];
            if (root.needsBlur(item))
                ++count;
        }
        return count;
    }
    readonly property bool shouldSubmit: root.compositorEnabled && root.blurEnabled && root.surfaceReady
                                         && root.targetWindow && root.targetWindow.visible
                                         && root.visibleBackgroundCount > 0
    readonly property var submittedRegion: root.shouldSubmit ? combinedRegion : null
    readonly property alias region: combinedRegion
    readonly property alias regionObjects: root._regionObjects
    readonly property alias subtractionRegionObjects: root._subtractionRegionObjects
    readonly property alias postSubtractionRegionObjects: root._postSubtractionRegionObjects

    visible: false

    function needsBlur(item) {
        if (!item || !item.visible || item.width <= 0 || item.height <= 0)
            return false;
        let opacity = 1;
        for (let ancestor = item; ancestor; ancestor = ancestor.parent) {
            if (!ancestor.visible || ancestor.opacity <= 0)
                return false;
            opacity *= ancestor.opacity;
        }
        // Only explicitly described fills are safe to cull. A color property
        // alone does not describe gradients, masks or geometry-only proxies.
        const fillOpacity = item.blurFillOpacity !== undefined ? item.blurFillOpacity : -1;
        return !(fillOpacity >= 1 && opacity >= 1);
    }

    function regionSnapshot(region) {
        let x = region.x, y = region.y, width = region.width, height = region.height;
        if (region.item) {
            // Match Quickshell Region's surface-local integer geometry.
            const origin = region.item.mapToItem(null, 0, 0);
            const extent = region.item.mapToItem(null, region.item.width, region.item.height);
            x = Math.trunc(origin.x);
            y = Math.trunc(origin.y);
            width = Math.ceil(extent.x - origin.x);
            height = Math.ceil(extent.y - origin.y);
        }
        const empty = width <= 0 || height <= 0;
        const children = [];
        for (let index = 0; index < region.regions.length; ++index) {
            const child = root.regionSnapshot(region.regions[index]);
            // Empty unions/subtractions do nothing. An empty intersection
            // must remain: it deliberately clips everything before it away.
            if (child.width > 0 || child.children.length > 0 || child.intersection === Intersection.Intersect)
                children.push(child);
        }
        return {
            x: empty ? 0 : x,
            y: empty ? 0 : y,
            width: empty ? 0 : width,
            height: empty ? 0 : height,
            shape: empty ? RegionShape.Rect : region.shape,
            intersection: region.intersection,
            topLeftRadius: empty ? 0 : region.topLeftRadius,
            topRightRadius: empty ? 0 : region.topRightRadius,
            bottomLeftRadius: empty ? 0 : region.bottomLeftRadius,
            bottomRightRadius: empty ? 0 : region.bottomRightRadius,
            children: children
        };
    }

    function updateSnapshot(snapshot, region, owner) {
        if (!region)
            region = snapshotRegionComponent.createObject(owner);
        region.x = snapshot.x;
        region.y = snapshot.y;
        region.width = snapshot.width;
        region.height = snapshot.height;
        region.shape = snapshot.shape;
        region.intersection = snapshot.intersection;
        // Quickshell's corner setters emit even when the value is unchanged.
        if (region.topLeftRadius !== snapshot.topLeftRadius)
            region.topLeftRadius = snapshot.topLeftRadius;
        if (region.topRightRadius !== snapshot.topRightRadius)
            region.topRightRadius = snapshot.topRightRadius;
        if (region.bottomLeftRadius !== snapshot.bottomLeftRadius)
            region.bottomLeftRadius = snapshot.bottomLeftRadius;
        if (region.bottomRightRadius !== snapshot.bottomRightRadius)
            region.bottomRightRadius = snapshot.bottomRightRadius;
        const previousCount = region.regions.length;
        const children = [];
        for (let index = 0; index < snapshot.children.length; ++index)
            children.push(root.updateSnapshot(snapshot.children[index], index < previousCount
                                              ? region.regions[index] : null, region));
        if (previousCount !== children.length) {
            const removed = [];
            for (let index = children.length; index < previousCount; ++index)
                removed.push(region.regions[index]);
            region.regions = children;
            for (const child of removed)
                child.destroy();
        }
        return region;
    }

    function invalidateSubmission() {
        root._publishedWindow = null;
        root._publishedSignature = "";
    }

    function releaseSnapshot() {
        if (root._publishedRegion) {
            root._publishedRegion.destroy();
            root._publishedRegion = null;
        }
    }

    function allBackgroundItems() {
        const items = [];
        if (root.backgroundItem)
            items.push(root.backgroundItem);
        const additional = root.additionalBackgroundItems || [];
        for (let index = 0; index < additional.length; ++index) {
            const item = additional[index];
            if (item && items.indexOf(item) < 0)
                items.push(item);
        }
        return items;
    }

    function combinedRegionCount() {
        return combinedRegion.regions.length;
    }

    function allSubtractedBackgroundItems() {
        const items = [];
        const subtracted = root.subtractedBackgroundItems || [];
        for (let index = 0; index < subtracted.length; ++index) {
            const item = subtracted[index];
            if (item && items.indexOf(item) < 0)
                items.push(item);
        }
        return items;
    }

    function allPostSubtractionBackgroundItems() {
        const items = [];
        const postSubtraction = root.postSubtractionBackgroundItems || [];
        for (let index = 0; index < postSubtraction.length; ++index) {
            const item = postSubtraction[index];
            if (item && items.indexOf(item) < 0)
                items.push(item);
        }
        return items;
    }

    function reconcileRegions(items, previous, component, postSubtraction) {
        const next = [];
        for (const item of items) {
            const region = previous.find(candidate => candidate.sourceItem === item) || component.createObject(combinedRegion,
                                                                                                               {
                                                                                                                   "sourceItem":
                                                                                                                   item
                                                                                                               });
            if (region && postSubtraction)
                region.clipItem = root.postSubtractionClipItem;
            if (region)
                next.push(region);
        }
        return next;
    }

    function sameRegions(left, right) {
        if (left.length !== right.length)
            return false;
        for (let index = 0; index < left.length; ++index) {
            if (left[index] !== right[index])
                return false;
        }
        return true;
    }

    function rebuildRegions() {
        const previous = root._regionObjects.concat(root._subtractionRegionObjects,
                                                    root._postSubtractionRegionObjects);
        const regions = root.reconcileRegions(root.allBackgroundItems(), root._regionObjects,
                                              itemRegionComponent, false);
        const subtractionRegions = root.reconcileRegions(root.allSubtractedBackgroundItems(),
                                                         root._subtractionRegionObjects,
                                                         subtractionRegionComponent, false);
        const postSubtractionRegions = root.reconcileRegions(root.allPostSubtractionBackgroundItems(),
                                                             root._postSubtractionRegionObjects,
                                                             postSubtractionRegionComponent, true);
        if (!root.sameRegions(root._regionObjects, regions))
            root._regionObjects = regions;
        if (!root.sameRegions(root._subtractionRegionObjects, subtractionRegions))
            root._subtractionRegionObjects = subtractionRegions;
        if (!root.sameRegions(root._postSubtractionRegionObjects, postSubtractionRegions))
            root._postSubtractionRegionObjects = postSubtractionRegions;

        // Region children are evaluated in order. Keep the operation chain
        // explicit: (base + additional) - subtraction + post-subtraction.
        const combinedRegions = regions.slice();
        for (const region of root.additionalRegions)
            combinedRegions.push(region);
        for (let index = 0; index < subtractionRegions.length; ++index)
            combinedRegions.push(subtractionRegions[index]);
        for (let index = 0; index < postSubtractionRegions.length; ++index)
            combinedRegions.push(postSubtractionRegions[index]);
        if (root.clipItem)
            combinedRegions.push(clipRegion);
        if (!root.sameRegions(combinedRegion.regions, combinedRegions))
            combinedRegion.regions = combinedRegions;
        for (const region of previous) {
            if (combinedRegions.indexOf(region) === -1)
                region.destroy();
        }
        root.publish();
    }

    function publish() {
        if (root.destroying || !root.targetWindow)
            return;
        if (!root.submittedRegion) {
            root.clear();
            return;
        }
        if (root.publishPending)
            return;
        root.publishPending = true;
        commitTimer.restart();
    }

    function requestFrame() {
        const item = root.targetWindow ? root.targetWindow.contentItem : null;
        const window = item ? item.Window.window : null;
        if (window && window.visible)
            window.update();
    }

    function commit() {
        root.publishPending = false;
        if (!root.targetWindow)
            return;
        if (!root.submittedRegion) {
            root.clear();
            return;
        }
        const snapshot = root.regionSnapshot(root.submittedRegion);
        const signature = JSON.stringify(snapshot);
        if (root._publishedWindow === root.targetWindow && root._publishedSignature === signature)
            return;
        // Only update the attached snapshot after this gate. The live tree
        // would let Quickshell submit geometry changes before deduplication.
        // Reuse its objects during animations; recreate after surface loss.
        const previous = root._publishedRegion;
        const next = root.updateSnapshot(snapshot, root._publishedSignature === "" ? null : previous, root);
        root.targetWindow.BackgroundEffect.blurRegion = next;
        if (previous && previous !== next)
            previous.destroy();
        root._publishedRegion = next;
        root._publishedWindow = root.targetWindow;
        root._publishedSignature = signature;
        // Protocol changes are double-buffered and need a surface commit,
        // even if transparent content has stopped producing scene damage.
        root.requestFrame();
    }

    function clear() {
        commitTimer.stop();
        root.publishPending = false;
        if (!root.targetWindow)
            return;
        if (root._publishedWindow === root.targetWindow && root._publishedSignature === "empty")
            return;
        // A new attachment may inherit the old native blur across hot reload
        // while its QML property already equals null. An explicit empty Region
        // forces a clear in that case too.
        root.targetWindow.BackgroundEffect.blurRegion = emptyRegion;
        root.releaseSnapshot();
        root._publishedWindow = root.targetWindow;
        root._publishedSignature = "empty";
        root.requestFrame();
    }

    onBackgroundItemChanged: rebuildRegions()
    onAdditionalBackgroundItemsChanged: rebuildRegions()
    onAdditionalRegionsChanged: rebuildRegions()
    onSubtractedBackgroundItemsChanged: rebuildRegions()
    onPostSubtractionBackgroundItemsChanged: rebuildRegions()
    onPostSubtractionClipItemChanged: rebuildRegions()
    onClipItemChanged: rebuildRegions()
    onSubmittedRegionChanged: publish()
    onTargetWindowChanged: {
        if (root._publishedWindow && root._publishedWindow !== root.targetWindow)
            root._publishedWindow.BackgroundEffect.blurRegion = null;
        root.invalidateSubmission();
        root.surfaceReady = !!root.targetWindow && root.targetWindow.visible;
        root.publish();
    }

    Component.onCompleted: {
        root.surfaceReady = !!root.targetWindow && root.targetWindow.visible;
        root.rebuildRegions();
    }

    Component.onDestruction: {
        root.destroying = true;
        commitTimer.stop();
        if (root.targetWindow)
            root.targetWindow.BackgroundEffect.blurRegion = null;
    }

    Timer {
        id: commitTimer

        interval: 0
        repeat: false
        onTriggered: {
            if (!root.destroying)
                root.commit();
        }
    }

    Connections {
        target: root.targetWindow
        enabled: root.targetWindow !== null
        ignoreUnknownSignals: true

        function onResourcesLost() {
            root.invalidateSubmission();
            root.surfaceReady = false;
            root.clear();
        }

        function onWindowConnected() {
            root.invalidateSubmission();
            root.surfaceReady = root.targetWindow.visible;
            root.publish();
        }

        function onVisibleChanged() {
            root.invalidateSubmission();
            root.surfaceReady = root.targetWindow.visible;
            if (root.surfaceReady)
                root.publish();
            else
                root.clear();
        }

        function onDevicePixelRatioChanged() {
            root.invalidateSubmission();
            root.publish();
        }
    }

    Connections {
        target: clipRegion

        function onChanged() {
            root.publish();
        }
    }

    TransformWatcher {
        id: clipTransformWatcher

        a: root.targetWindow ? root.targetWindow.contentItem : null
        b: root.clipItem
        onTransformChanged: root.publish()
    }

    Region {
        id: emptyRegion
        width: 0
        height: 0
    }

    Component {
        id: snapshotRegionComponent
        Region {}
    }

    Region {
        id: combinedRegion
    }

    Region {
        id: clipRegion

        item: root.clipItem && root.clipItem.visible && root.clipItem.width > 0 && root.clipItem.height > 0
              ? root.clipItem : null
        intersection: Intersection.Intersect
    }

    Component {
        id: itemRegionComponent

        Region {
            id: itemRegion

            required property Item sourceItem

            property Item insetItem: Item {
                parent: root.inset > 0 ? itemRegion.sourceItem : null
                x: root.inset
                y: root.inset
                width: itemRegion.sourceItem ? Math.max(0, itemRegion.sourceItem.width - 2 * root.inset) : 0
                height: itemRegion.sourceItem ? Math.max(0, itemRegion.sourceItem.height - 2 * root.inset) : 0
            }

            property TransformWatcher geometryWatcher: TransformWatcher {
                a: root.targetWindow ? root.targetWindow.contentItem : null
                b: root.inset > 0 ? itemRegion.insetItem : itemRegion.sourceItem
                onTransformChanged: root.publish()
            }

            onChanged: root.publish()

            item: root.needsBlur(sourceItem) ? (root.inset > 0 ? insetItem : sourceItem) : null
            radius: Math.max(0, Math.round((root.pillShapes && sourceItem ? Math.min(sourceItem.width,
                                                                                     sourceItem.height) / 2 :
                                                                            sourceItem && sourceItem.radius
                                                                            !== undefined ? sourceItem.radius :
                                                                                            root.radius)
                                           - root.inset))
            intersection: Intersection.Combine
        }
    }

    Component {
        id: subtractionRegionComponent

        Region {
            required property Item sourceItem

            property TransformWatcher geometryWatcher: TransformWatcher {
                a: root.targetWindow ? root.targetWindow.contentItem : null
                b: sourceItem
                onTransformChanged: root.publish()
            }

            onChanged: root.publish()

            item: sourceItem && sourceItem.visible && sourceItem.width > 0 && sourceItem.height > 0
                  ? sourceItem : null
            radius: sourceItem && sourceItem.radius !== undefined ? Math.max(0, Math.round(
                                                                                 sourceItem.radius)) :
                                                                    Math.max(0, Math.round(root.radius))
            intersection: Intersection.Subtract
        }
    }

    Component {
        id: postSubtractionRegionComponent

        // Keep each post-subtraction item as a stable Region group. Its
        // children express (post item ∩ post clip), while the group itself
        // is combined with the already-built base/subtraction chain.
        Region {
            required property Item sourceItem
            property Item clipItem: null

            property TransformWatcher sourceGeometryWatcher: TransformWatcher {
                a: root.targetWindow ? root.targetWindow.contentItem : null
                b: sourceItem
                onTransformChanged: root.publish()
            }

            property TransformWatcher clipGeometryWatcher: TransformWatcher {
                a: root.targetWindow ? root.targetWindow.contentItem : null
                b: clipItem
                onTransformChanged: root.publish()
            }

            onChanged: root.publish()

            Region {
                item: root.needsBlur(sourceItem) ? sourceItem : null
                radius: sourceItem && sourceItem.radius !== undefined ? Math.max(0, Math.round(
                                                                                     sourceItem.radius)) :
                                                                        Math.max(0, Math.round(root.radius))
                intersection: Intersection.Combine
            }

            Region {
                item: clipItem && clipItem.visible && clipItem.width > 0 && clipItem.height > 0 ? clipItem :
                                                                                                  null
                radius: clipItem && clipItem.radius !== undefined ? Math.max(0, Math.round(clipItem.radius)) :
                                                                    Math.max(0, Math.round(root.radius))
                intersection: clipItem ? Intersection.Intersect : Intersection.Combine
            }
        }
    }
}
