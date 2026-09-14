pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Window
import qs.Common
import qs.Components

FocusScope {
    id: root

    property var options: []
    property var values: []
    property string zone: ""
    property var dragCoordinator: null
    property int highlightedIndex: 0
    property bool expanded: false
    property real fieldHeight: 40
    property real itemHeight: 40
    property real menuItemSpacing: 4
    property int maxVisibleItems: 6
    readonly property Item popupParentItem: root.Window.window ? root.Window.window.contentItem : null
    readonly property real menuPadding: 6
    readonly property real menuGap: 6
    readonly property var availableOptions: options.filter(option => {
        return values.indexOf(optionValue(option)) === -1;
    })
    readonly property real listTargetHeight: Math.max(itemHeight, Math.min(optionFlow.implicitHeight,
                                                                           maxVisibleItems * itemHeight))
                                             + menuPadding * 2
    readonly property bool dragActive: dragCoordinator && dragCoordinator.dragActive

    signal toggled(string componentId)
    signal removed(string componentId)

    function optionValue(option) {
        return option && typeof option === "object" ? String(option.value || "") : String(option || "");
    }

    function optionLabel(option) {
        return option && typeof option === "object" ? String(option.label || option.value || "") : String(
                                                          option || "");
    }

    function optionIcon(option) {
        return option && typeof option === "object" ? String(option.icon || "widgets") : "widgets";
    }

    function labelFor(componentId) {
        for (let index = 0; index < root.options.length; index += 1) {
            if (root.optionValue(root.options[index]) === componentId)
                return root.optionLabel(root.options[index]);
        }
        return componentId;
    }

    function iconFor(componentId) {
        for (let index = 0; index < root.options.length; index += 1) {
            if (root.optionValue(root.options[index]) === componentId)
                return root.optionIcon(root.options[index]);
        }
        return "widgets";
    }

    function entryIndex(entryKey) {
        for (let index = 0; index < chipModel.count; index += 1) {
            if (chipModel.get(index).entryKey === entryKey)
                return index;
        }
        return -1;
    }

    function synchronizeEntries(entries) {
        const desiredKeys = entries.map(entry => {
            return entry.entryKey;
        });
        for (let index = chipModel.count - 1; index >= 0; index -= 1) {
            if (desiredKeys.indexOf(chipModel.get(index).entryKey) === -1)
                chipModel.remove(index);
        }
        for (let index = 0; index < entries.length; index += 1) {
            const entry = entries[index];
            const currentIndex = root.entryIndex(entry.entryKey);
            if (currentIndex < 0) {
                chipModel.insert(index, entry);
            } else {
                if (currentIndex !== index)
                    chipModel.move(currentIndex, index, 1);

                chipModel.setProperty(index, "componentId", entry.componentId);
                chipModel.setProperty(index, "placeholder", entry.placeholder);
            }
        }
    }

    function synchronizeValues() {
        if (root.dragActive)
            return;

        const entries = [];
        const source = Array.isArray(root.values) ? root.values : [];
        for (let index = 0; index < source.length; index += 1) {
            entries.push({
                             "entryKey": source[index],
                             "componentId": source[index],
                             "placeholder": false
                         });
        }
        root.synchronizeEntries(entries);
    }

    function showDropPreview(componentId, sourceZone, targetZone, targetIndex) {
        const source = Array.isArray(root.values) ? root.values : [];
        const entries = [];
        for (let index = 0; index < source.length; index += 1) {
            const value = source[index];
            const isDraggedComponent = value === componentId;
            const movingWithinThisZone = root.zone === sourceZone && root.zone === targetZone;
            if (isDraggedComponent && movingWithinThisZone)
                continue;

            if (isDraggedComponent && root.zone !== sourceZone)
                continue;

            entries.push({
                             "entryKey": value,
                             "componentId": value,
                             "placeholder": false
                         });
        }
        if (root.zone === targetZone) {
            const insertionIndex = Math.max(0, Math.min(entries.length, targetIndex));
            entries.splice(insertionIndex, 0, {
                               "entryKey": componentId,
                               "componentId": componentId,
                               "placeholder": true
                           });
        }
        root.synchronizeEntries(entries);
    }

    function clearDropPreview() {
        root.synchronizeValues();
    }

    function insertionIndexAt(coordinatorItem, sceneX, sceneY) {
        const local = chipFlow.mapFromItem(coordinatorItem, sceneX, sceneY);
        let insertionIndex = 0;
        for (let index = 0; index < chipModel.count; index += 1) {
            const delegateItem = chipRepeater.itemAt(index);
            if (!delegateItem || delegateItem.placeholder || delegateItem.isDragged)
                continue;
            if (local.y < delegateItem.y || (local.y <= delegateItem.y + delegateItem.height && local.x
                                             < delegateItem.x + delegateItem.width / 2))
                return insertionIndex;
            insertionIndex += 1;
        }
        return insertionIndex;
    }

    function containsScenePoint(coordinatorItem, sceneX, sceneY) {
        const local = root.mapFromItem(coordinatorItem, sceneX, sceneY);
        return local.x >= 0 && local.x <= root.width && local.y >= 0 && local.y <= root.height;
    }

    function updatePopupGeometry() {
        if (!root.popupParentItem)
            return false;

        const origin = root.mapToItem(root.popupParentItem, 0, 0);
        const margin = 12;
        optionsPopup.width = Math.min(root.width, root.popupParentItem.width - margin * 2);
        optionsPopup.x = Math.max(margin, Math.min(origin.x, root.popupParentItem.width - optionsPopup.width
                                                   - margin));
        const belowY = origin.y + root.height + root.menuGap;
        const belowSpace = Math.max(0, root.popupParentItem.height - margin - belowY);
        const aboveSpace = Math.max(0, origin.y - root.menuGap - margin);
        const useBelow = belowSpace >= root.listTargetHeight || belowSpace >= aboveSpace;
        optionsPopup.height = Math.min(root.listTargetHeight, useBelow ? belowSpace : aboveSpace);
        optionsPopup.y = useBelow ? belowY : origin.y - root.menuGap - optionsPopup.height;
        return true;
    }

    function openMenu() {
        if (!root.expanded && root.updatePopupGeometry()) {
            root.highlightedIndex = 0;
            root.expanded = true;
        }
    }

    function closeMenu() {
        root.expanded = false;
    }

    function toggleMenu() {
        if (root.expanded)
            root.closeMenu();
        else
            root.openMenu();
    }

    function moveHighlight(delta) {
        if (root.availableOptions.length === 0)
            return;

        root.highlightedIndex = (root.highlightedIndex + delta + root.availableOptions.length)
                % root.availableOptions.length;
        const item = optionRepeater.itemAt(root.highlightedIndex);
        if (item) {
            if (item.y < optionPool.contentY)
                optionPool.contentY = item.y;
            else if (item.y + item.height > optionPool.contentY + optionPool.height)
                optionPool.contentY = item.y + item.height - optionPool.height;
        }
    }

    function toggleHighlighted() {
        if (root.highlightedIndex < 0 || root.highlightedIndex >= root.availableOptions.length)
            return;

        root.toggled(root.optionValue(root.availableOptions[root.highlightedIndex]));
    }

    function handleKey(event) {
        if (!root.expanded) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space
                    || event.key === Qt.Key_Down) {
                root.openMenu();
                event.accepted = true;
            }
            return;
        }
        if (event.key === Qt.Key_Escape)
            root.closeMenu();
        else if (event.key === Qt.Key_Down)
            root.moveHighlight(1);
        else if (event.key === Qt.Key_Up)
            root.moveHighlight(-1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            root.toggleHighlighted();
        else
            return;
        event.accepted = true;
    }

    implicitWidth: 360
    implicitHeight: Math.max(fieldHeight, chipFlow.implicitHeight + 12)
    activeFocusOnTab: true
    onValuesChanged: synchronizeValues()
    onListTargetHeightChanged: {
        if (root.expanded)
            Qt.callLater(root.updatePopupGeometry);
    }
    onWidthChanged: {
        if (root.expanded)
            Qt.callLater(root.updatePopupGeometry);
    }
    onHeightChanged: {
        if (root.expanded)
            Qt.callLater(root.updatePopupGeometry);
    }
    Component.onCompleted: synchronizeValues()
    Keys.onPressed: event => {
        return root.handleKey(event);
    }
    onExpandedChanged: {
        if (expanded) {
            updatePopupGeometry();
            optionsPopup.open();
            Qt.callLater(root.updatePopupGeometry);
        } else if (optionsPopup.visible) {
            optionsPopup.close();
        }
    }

    Rectangle {
        id: fieldFrame

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.height
        clip: true
        color: root.expanded || fieldTap.pressed ? Appearance.colors.colLayer2Active : fieldHover.hovered
                                                   ? Appearance.colors.colLayer2Hover :
                                                     Appearance.colors.colLayer2

        Item {
            id: chipViewport

            clip: true

            anchors {
                left: parent.left
                right: menuButton.left
                top: parent.top
                bottom: parent.bottom
                leftMargin: 8
                rightMargin: 8
            }

            Flow {
                id: chipFlow
                width: parent.width
                anchors.top: parent.top
                anchors.topMargin: 6
                spacing: 6

                Repeater {
                    id: chipRepeater
                    model: chipModel

                    delegate: Item {
                        id: chipDelegate

                        required property string entryKey
                        required property string componentId
                        required property bool placeholder
                        readonly property bool ownsActiveDrag: root.dragActive && root.dragCoordinator
                                                               && root.dragCoordinator.componentId
                                                               === chipDelegate.componentId
                                                               && root.dragCoordinator.sourceZone
                                                               === root.zone
                        readonly property bool isDragged: root.dragActive && root.dragCoordinator.componentId
                                                          === componentId && !placeholder
                        readonly property real naturalWidth: Math.min(chipFlow.width, Math.max(88, chipLabel.implicitWidth
                                                                                               + 70))

                        width: placeholder && root.dragCoordinator ? Math.min(chipFlow.width,
                                                                              root.dragCoordinator.dragWidth) :
                                                                     isDragged ? 0 : naturalWidth
                        height: isDragged ? 0 : 30
                        opacity: isDragged ? 0 : 1

                        Rectangle {
                            id: chipSurface

                            width: chipDelegate.placeholder ? parent.width : chipDelegate.naturalWidth
                            height: 30
                            anchors.centerIn: parent
                            radius: Appearance.rounding.small
                            color: chipDelegate.placeholder ? Appearance.colors.colLayer2Active :
                                                              chipHover.hovered
                                                              ? Appearance.colors.colPrimaryContainerHover :
                                                                Appearance.colors.colPrimaryContainer
                            opacity: chipDelegate.placeholder ? 0.45 : 1

                            MaterialSymbol {
                                id: chipIcon

                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.iconFor(chipDelegate.componentId)
                                iconSize: 17
                                fill: 1
                                color: Appearance.colors.colOnPrimaryContainer
                                visible: !chipDelegate.placeholder
                            }

                            Text {
                                id: chipLabel

                                text: root.labelFor(chipDelegate.componentId)
                                color: Appearance.colors.colOnPrimaryContainer
                                font.family: Fonts.ui
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                visible: !chipDelegate.placeholder
                                elide: Text.ElideRight

                                anchors {
                                    left: chipIcon.right
                                    right: closeButton.left
                                    leftMargin: 6
                                    rightMargin: 4
                                    verticalCenter: parent.verticalCenter
                                }
                            }

                            Item {
                                id: closeButton

                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                height: 30
                                visible: !chipDelegate.placeholder

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 17
                                    color: Appearance.colors.colOnPrimaryContainer
                                }

                                MouseArea {
                                    id: closeMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        mouse.accepted = true;
                                        root.removed(chipDelegate.componentId);
                                    }
                                }
                            }

                            HoverHandler {
                                id: chipHover
                            }

                            MouseArea {
                                enabled: !chipDelegate.placeholder
                                cursorShape: dragHandler.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                onClicked: mouse => {
                                    return mouse.accepted = true;
                                }

                                anchors {
                                    left: parent.left
                                    right: closeButton.left
                                    top: parent.top
                                    bottom: parent.bottom
                                }
                            }

                            DragHandler {
                                id: dragHandler

                                enabled: root.dragCoordinator !== null && (!chipDelegate.placeholder
                                                                           || chipDelegate.ownsActiveDrag) && (
                                             !closeMouse.containsMouse || chipDelegate.ownsActiveDrag)
                                target: null
                                dragThreshold: 8
                                onActiveChanged: {
                                    if (active)
                                        root.dragCoordinator.beginDrag(root, chipDelegate.componentId,
                                                                       root.labelFor(chipDelegate.componentId),
                                                                       root.iconFor(chipDelegate.componentId),
                                                                       chipDelegate.naturalWidth,
                                                                       centroid.scenePosition);
                                    else if (root.dragCoordinator && root.dragCoordinator.dragActive
                                             && root.dragCoordinator.componentId === chipDelegate.componentId)
                                        root.dragCoordinator.finishDrag();
                                }
                                onTranslationChanged: {
                                    if (active)
                                        root.dragCoordinator.updateDrag(centroid.scenePosition);
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: chipModel.count === 0
            text: qsTr("No components selected")
            color: Appearance.colors.colSubtext
            font.family: Fonts.ui
            font.pixelSize: 14

            anchors {
                left: parent.left
                right: menuButton.left
                leftMargin: 14
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
        }

        Item {
            id: menuButton
            anchors.right: parent.right
            anchors.top: parent.top
            width: 40
            height: root.fieldHeight

            MaterialSymbol {
                anchors.centerIn: parent
                text: "expand_more"
                iconSize: 20
                color: Appearance.colors.colOnLayer2
                rotation: root.expanded ? 180 : 0
            }

            TapHandler {
                id: fieldTap
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: {
                    root.forceActiveFocus();
                    root.toggleMenu();
                }
            }
        }

        HoverHandler {
            id: fieldHover
        }

        Rectangle {
            height: root.expanded ? 2 : 1
            color: root.expanded ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: Appearance.animation.expressiveFastEffects.duration
                easing.type: Appearance.animation.expressiveFastEffects.type
                easing.bezierCurve: Appearance.animation.expressiveFastEffects.bezierCurve
            }
        }
    }

    ListModel {
        id: chipModel
    }

    Popup {
        id: optionsPopup

        parent: root.popupParentItem
        padding: 0
        modal: false
        dim: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: root.expanded = false

        background: Item {}

        contentItem: Rectangle {
            id: optionPoolCard

            clip: true
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh

            Flickable {
                id: optionPool

                anchors.fill: parent
                anchors.margins: root.menuPadding
                contentWidth: width
                contentHeight: optionFlow.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ScrollBar.vertical: StyledScrollBar {}

                Flow {
                    id: optionFlow

                    width: optionPool.width
                    spacing: root.menuItemSpacing

                    Repeater {
                        id: optionRepeater
                        model: root.availableOptions

                        delegate: Rectangle {
                            id: optionChip

                            required property var modelData
                            required property int index
                            readonly property string componentId: root.optionValue(modelData)
                            readonly property bool highlighted: index === root.highlightedIndex

                            width: Math.min(optionFlow.width, Math.max(88, optionLabel.implicitWidth + 52))
                            height: 30
                            radius: Appearance.rounding.small
                            color: optionTap.pressed ? Appearance.colors.colPrimaryContainerActive :
                                                       optionHover.hovered || highlighted
                                                       ? Appearance.colors.colPrimaryContainerHover :
                                                         Appearance.colors.colPrimaryContainer

                            MaterialSymbol {
                                id: optionIcon

                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.optionIcon(optionChip.modelData)
                                iconSize: 17
                                fill: 1
                                color: Appearance.colors.colOnPrimaryContainer
                            }

                            Text {
                                id: optionLabel

                                anchors.left: optionIcon.right
                                anchors.leftMargin: 6
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.optionLabel(optionChip.modelData)
                                color: Appearance.colors.colOnPrimaryContainer
                                font.family: Fonts.ui
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            HoverHandler {
                                id: optionHover

                                onHoveredChanged: {
                                    if (hovered)
                                        root.highlightedIndex = optionChip.index;
                                }
                            }

                            TapHandler {
                                id: optionTap

                                onTapped: root.toggled(optionChip.componentId)
                            }
                        }
                    }

                    Text {
                        visible: root.availableOptions.length === 0
                        width: optionFlow.width
                        height: root.itemHeight
                        text: qsTr("All widgets are in use")
                        color: Appearance.colors.colSubtext
                        font.family: Fonts.ui
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: Appearance.animation.standardDecel.duration
                easing.type: Appearance.animation.standardDecel.type
                easing.bezierCurve: Appearance.animation.standardDecel.bezierCurve
            }
        }
    }
}
