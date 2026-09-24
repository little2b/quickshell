import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Components
import qs.Services
import qs.Widgets.common

TopBarPill {
    id: root

    property bool trayOverflowOpen: false
    property bool vertical: false
    property string edge: "top"
    property var barVisualItem: null
    property var activeMenu: null
    property var screen: null
    property real overflowX: 10
    property real overflowY: 10
    property real overflowEdgeMargin: Sizes.barPopupScreenMargin
    property real overflowPopupGap: Sizes.barPopupGap
    property real overflowSurfacePadding: 10
    property real overflowAnchorX: 10
    property real overflowAnchorY: 10
    property real overflowAnchorWidth: 0
    property real overflowAnchorHeight: 0
    property bool overflowAnchorReady: false
    property bool trayDragActive: false
    property string trayDragItemId: ""
    property bool trayDragFromPinned: false
    property var trayDragIconSource: ""
    property real trayDragGlobalX: 0
    property real trayDragGlobalY: 0
    readonly property var pinnedItems: TrayService.pinnedItems
    readonly property var unpinnedItems: TrayService.unpinnedItems
    readonly property bool dragOverOverflowButton: root.trayDragActive && root.trayDragFromPinned
                                                   && root.containsGlobalPoint(trayOverflowButton,
                                                                               root.trayDragGlobalX,
                                                                               root.trayDragGlobalY, 6)
    readonly property bool dragOverPinnedArea: root.trayDragActive && !root.trayDragFromPinned
                                               && root.containsGlobalPoint(root, root.trayDragGlobalX,
                                                                           root.trayDragGlobalY, 6)

    implicitHeight: vertical ? content.implicitHeight + 16 : Sizes.barPillThickness
    implicitWidth: vertical ? Sizes.barVisualThickness : content.implicitWidth + 24

    onUnpinnedItemsChanged: {
        if (root.unpinnedItems.length === 0) {
            root.trayOverflowOpen = false;
            root.overflowAnchorReady = false;
        } else if (root.trayOverflowOpen) {
            Qt.callLater(root.updateOverflowPosition);
        }
    }

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    function containsGlobalPoint(item, globalX, globalY, padding) {
        if (!item || !item.visible || item.width <= 0 || item.height <= 0)
            return false;

        const topLeft = item.mapToGlobal(0, 0);
        const inset = padding || 0;
        return globalX >= topLeft.x - inset && globalX <= topLeft.x + item.width + inset && globalY
                >= topLeft.y - inset && globalY <= topLeft.y + item.height + inset;
    }

    function beginTrayItemDrag(itemId, pinned, iconSource, globalX, globalY) {
        if (!itemId || itemId.length === 0)
            return;

        root.closeActiveMenu();
        root.trayDragItemId = itemId;
        root.trayDragFromPinned = pinned;
        root.trayDragIconSource = iconSource || "";
        root.trayDragActive = true;
        root.updateTrayItemDrag(globalX, globalY);
    }

    function updateTrayItemDrag(globalX, globalY) {
        if (!root.trayDragActive)
            return;

        root.trayDragGlobalX = globalX;
        root.trayDragGlobalY = globalY;
    }

    function finishTrayItemDrag(globalX, globalY, canceled) {
        if (!root.trayDragActive)
            return;

        root.updateTrayItemDrag(globalX, globalY);
        const itemId = root.trayDragItemId;
        const hideItem = !canceled && root.trayDragFromPinned && root.dragOverOverflowButton;
        const showItem = !canceled && !root.trayDragFromPinned && root.dragOverPinnedArea;

        root.trayDragActive = false;
        root.trayDragItemId = "";
        root.trayDragIconSource = "";

        if (hideItem) {
            TrayService.setHidden(itemId, true);
            Qt.callLater(() => {
                if (root.unpinnedItems.length === 0)
                    return;
                root.captureOverflowAnchor();
                root.updateOverflowPosition();
                root.trayOverflowOpen = true;
            });
        } else if (showItem) {
            TrayService.setHidden(itemId, false);
        }
    }

    function captureOverflowAnchor() {
        if (!trayOverflowButton.visible || trayOverflowButton.width <= 0 || trayOverflowButton.height <= 0) {
            root.overflowAnchorReady = false;
            return;
        }

        const globalPos = trayOverflowButton.mapToGlobal(0, 0);
        const screenX = root.screen ? (root.screen.x || 0) : 0;
        const screenY = root.screen ? (root.screen.y || 0) : 0;

        root.overflowAnchorX = globalPos.x - screenX;
        root.overflowAnchorY = globalPos.y - screenY;
        root.overflowAnchorWidth = trayOverflowButton.width || 0;
        root.overflowAnchorHeight = trayOverflowButton.height || 0;
        root.overflowAnchorReady = true;
    }

    function barVisualBounds() {
        if (!root.barVisualItem)
            return null;

        const globalPos = root.barVisualItem.mapToGlobal(0, 0);
        const screenX = root.screen ? (root.screen.x || 0) : 0;
        const screenY = root.screen ? (root.screen.y || 0) : 0;
        return {
            "x": globalPos.x - screenX,
            "y": globalPos.y - screenY,
            "width": root.barVisualItem.width || 0,
            "height": root.barVisualItem.height || 0
        };
    }

    function updateOverflowPosition() {
        const surfaceWidth = Math.max(1, overflowSurface.implicitWidth);
        const surfaceHeight = Math.max(1, overflowSurface.implicitHeight);
        const screenWidth = root.screen ? (root.screen.width || 0) : 0;
        const screenHeight = root.screen ? (root.screen.height || 0) : 0;
        const availableWidth = Math.max(surfaceWidth + root.overflowEdgeMargin * 2, overflowPopup.width,
                                        screenWidth);
        const availableHeight = Math.max(surfaceHeight + root.overflowEdgeMargin * 2, overflowPopup.height,
                                         screenHeight);
        const anchorX = root.overflowAnchorReady ? root.overflowAnchorX : root.overflowEdgeMargin;
        const anchorY = root.overflowAnchorReady ? root.overflowAnchorY : root.overflowEdgeMargin;
        const anchorWidth = root.overflowAnchorReady ? root.overflowAnchorWidth : 0;
        const anchorHeight = root.overflowAnchorReady ? root.overflowAnchorHeight : 0;
        const barBounds = root.barVisualBounds();

        const rightX = barBounds ? barBounds.x + barBounds.width + root.overflowPopupGap - root.overflowSurfacePadding :
                                   anchorX + anchorWidth + root.overflowPopupGap;
        const leftX = barBounds ? barBounds.x - surfaceWidth - root.overflowPopupGap
                                  + root.overflowSurfacePadding : anchorX - surfaceWidth
                                  - root.overflowPopupGap;
        const maxX = availableWidth - surfaceWidth - root.overflowEdgeMargin;
        root.overflowX = root.edge === "left" ? root.clamp(rightX, root.overflowEdgeMargin, maxX) : root.edge === "right"
                                                ? root.clamp(leftX, root.overflowEdgeMargin, maxX) :
                                                  root.clamp(anchorX + anchorWidth / 2 - surfaceWidth / 2,
                                                             root.overflowEdgeMargin, maxX);

        const belowY = barBounds ? barBounds.y + barBounds.height + root.overflowPopupGap - root.overflowSurfacePadding :
                                   anchorY + anchorHeight + root.overflowPopupGap;
        const aboveY = barBounds ? barBounds.y - surfaceHeight - root.overflowPopupGap
                                   + root.overflowSurfacePadding : anchorY - surfaceHeight
                                   - root.overflowPopupGap;
        const maxY = availableHeight - surfaceHeight - root.overflowEdgeMargin;
        root.overflowY = root.vertical ? root.clamp(anchorY + anchorHeight / 2 - surfaceHeight / 2,
                                                    root.overflowEdgeMargin, maxY) : root.edge === "bottom"
                                         ? root.clamp(aboveY, root.overflowEdgeMargin, maxY) : root.clamp(
                                               belowY, root.overflowEdgeMargin, maxY);
    }

    function setActiveMenu(window) {
        if (root.activeMenu && root.activeMenu !== window && typeof root.activeMenu.close === "function")
            root.activeMenu.close();
        root.activeMenu = window;
    }

    function releaseActiveMenu(window) {
        if (!window || root.activeMenu === window)
            root.activeMenu = null;
    }

    function closeActiveMenu() {
        if (root.activeMenu && typeof root.activeMenu.close === "function")
            root.activeMenu.close();
        root.activeMenu = null;
    }

    onTrayOverflowOpenChanged: {
        if (!root.trayOverflowOpen) {
            root.overflowAnchorReady = false;
            root.closeActiveMenu();
        }
    }
    onEdgeChanged: {
        if (root.trayOverflowOpen)
            Qt.callLater(root.updateOverflowPosition);
    }

    GridLayout {
        id: content

        anchors.centerIn: parent
        rowSpacing: 15
        columnSpacing: 15
        columns: root.vertical ? 1 : Math.max(1, root.pinnedItems.length + 1)

        RippleButton {
            id: trayOverflowButton

            visible: TrayService.visibleItems.length > 0
            toggled: root.trayOverflowOpen || root.dragOverOverflowButton
            implicitWidth: 24
            implicitHeight: 24
            buttonRadius: Appearance.rounding.full
            containerColor: root.dragOverOverflowButton ? Appearance.colors.colPrimaryContainer :
                                                          root.trayOverflowOpen
                                                          ? Appearance.colors.colSecondaryContainer :
                                                            "transparent"
            stateLayerColor: root.dragOverOverflowButton ? Appearance.colors.colPrimaryContainerHover :
                                                           root.trayOverflowOpen
                                                           ? Appearance.colors.colSecondaryContainerHover :
                                                             Appearance.colors.colSecondaryContainer
            pressedStateLayerColor: Appearance.colors.colSecondaryContainerActive
            rippleColor: Appearance.colors.colOnSecondaryContainer
            Layout.alignment: Qt.AlignVCenter
            scale: root.dragOverOverflowButton ? 1.16 : 1

            Behavior on scale {
                NumberAnimation {
                    duration: Appearance.animation.expressiveFastEffects.duration
                    easing.type: Appearance.animation.expressiveFastEffects.type
                    easing.bezierCurve: Appearance.animation.expressiveFastEffects.bezierCurve
                }
            }

            releaseAction: () => {
                if (root.trayOverflowOpen) {
                    root.trayOverflowOpen = false;
                    root.closeActiveMenu();
                    return;
                }

                if (root.unpinnedItems.length === 0)
                    return;

                root.closeActiveMenu();
                root.captureOverflowAnchor();
                root.updateOverflowPosition();
                root.trayOverflowOpen = true;
            }

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "expand_more"
                iconSize: 19
                color: root.trayOverflowOpen || root.dragOverOverflowButton
                       || trayOverflowButton.pointerHovered ? Appearance.colors.colOnSecondaryContainer :
                                                              Appearance.colors.colOnLayer0
                rotation: (root.edge === "left" ? -90 : root.edge === "right" ? 90 : 0) + (
                              root.trayOverflowOpen ? 180 : 0)

                Behavior on rotation {
                    NumberAnimation {
                        duration: Appearance.animation.expressiveEffects.duration
                        easing.type: Appearance.animation.expressiveEffects.type
                        easing.bezierCurve: Appearance.animation.expressiveEffects.bezierCurve
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.expressiveEffects.duration
                        easing.type: Appearance.animation.expressiveEffects.type
                        easing.bezierCurve: Appearance.animation.expressiveEffects.bezierCurve
                    }
                }
            }
        }

        Repeater {
            model: root.pinnedItems

            delegate: TrayItem {
                screen: root.screen
                edge: root.edge
                barVisualItem: root.barVisualItem
                pinned: true
                Layout.alignment: Qt.AlignVCenter
                onMenuOpened: window => root.setActiveMenu(window)
                onMenuClosed: root.releaseActiveMenu(null)
                onDragStarted: (itemId, pinned, iconSource, globalX, globalY) => root.beginTrayItemDrag(itemId,
                                                                                                        pinned, iconSource,
                                                                                                        globalX, globalY)
                onDragMoved: (globalX, globalY) => root.updateTrayItemDrag(globalX, globalY)
                onDragFinished: (globalX, globalY, canceled) => root.finishTrayItemDrag(globalX, globalY,
                                                                                        canceled)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        z: 90
        visible: root.dragOverPinnedArea
        color: "transparent"
        radius: Appearance.rounding.full
        border.width: 2
        border.color: Appearance.colors.colPrimary
    }

    Item {
        readonly property point localPosition: root.mapFromGlobal(Qt.point(root.trayDragGlobalX,
                                                                           root.trayDragGlobalY))

        visible: root.trayDragActive && root.trayDragFromPinned
        x: localPosition.x - width / 2
        y: localPosition.y - height / 2
        width: 30
        height: 30
        z: 100
        scale: 1.08

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }

        IconImage {
            anchors.centerIn: parent
            width: 20
            height: 20
            source: root.trayDragIconSource
            asynchronous: true
            mipmap: true
        }
    }

    PanelWindow {
        id: overflowPopup

        visible: root.trayOverflowOpen && root.unpinnedItems.length > 0
        screen: root.screen
        color: "transparent"
        exclusiveZone: -1

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "clavis-shell-tray-overflow"
        WlrLayershell.keyboardFocus: overflowPopup.visible ? WlrKeyboardFocus.Exclusive :
                                                             WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        mask: Region {
            item: overflowInputRegion
        }

        onVisibleChanged: {
            if (visible)
                Qt.callLater(() => {
                    root.updateOverflowPosition();
                    overflowKeyScope.forceActiveFocus();
                });
        }

        Item {
            id: overflowInputRegion
            anchors.fill: parent
        }

        MouseArea {
            anchors.fill: parent
            enabled: overflowPopup.visible
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            z: -1

            onClicked: event => {
                const outsideMenu = event.x < overflowSurface.x || event.x > overflowSurface.x
                      + overflowSurface.width || event.y < overflowSurface.y || event.y > overflowSurface.y
                      + overflowSurface.height;
                if (outsideMenu) {
                    root.trayOverflowOpen = false;
                    root.closeActiveMenu();
                }
            }
        }

        FocusScope {
            id: overflowKeyScope

            anchors.fill: parent
            focus: overflowPopup.visible

            Keys.onEscapePressed: event => {
                root.trayOverflowOpen = false;
                root.closeActiveMenu();
                event.accepted = true;
            }

            Item {
                id: overflowSurface

                x: root.overflowX
                y: root.overflowY
                implicitWidth: popupBackground.implicitWidth + root.overflowSurfacePadding * 2
                implicitHeight: popupBackground.implicitHeight + root.overflowSurfacePadding * 2
                width: implicitWidth
                height: implicitHeight

                onImplicitWidthChanged: Qt.callLater(root.updateOverflowPosition)
                onImplicitHeightChanged: Qt.callLater(root.updateOverflowPosition)

                StyledRectangularShadow {
                    target: popupBackground
                    opacity: popupBackground.opacity
                }

                Rectangle {
                    id: popupBackground

                    readonly property real popupPadding: 4

                    x: root.overflowSurfacePadding
                    y: root.overflowSurfacePadding
                    implicitWidth: overflowLayout.implicitWidth + popupPadding * 2
                    implicitHeight: overflowLayout.implicitHeight + popupPadding * 2
                    color: BlurService.backgroundColor(Appearance.colors.colLayer0)
                    radius: 18
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    clip: true
                    opacity: overflowPopup.visible ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            alwaysRunToEnd: true
                            duration: Appearance.animation.expressiveEffects.duration
                            easing.type: Appearance.animation.expressiveEffects.type
                            easing.bezierCurve: Appearance.animation.expressiveEffects.bezierCurve
                        }
                    }
                    Behavior on implicitWidth {
                        NumberAnimation {
                            alwaysRunToEnd: true
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                    Behavior on implicitHeight {
                        NumberAnimation {
                            alwaysRunToEnd: true
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }

                    GridLayout {
                        id: overflowLayout

                        anchors.centerIn: parent
                        columns: Math.max(1, Math.ceil(Math.sqrt(root.unpinnedItems.length)))
                        columnSpacing: 10
                        rowSpacing: 10

                        Repeater {
                            model: root.unpinnedItems

                            delegate: TrayItem {
                                screen: root.screen
                                edge: root.edge
                                pinned: false
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                                onMenuOpened: window => root.setActiveMenu(window)
                                onMenuClosed: root.releaseActiveMenu(null)
                                onDragStarted: (itemId, pinned, iconSource, globalX, globalY)
                                               => root.beginTrayItemDrag(itemId, pinned, iconSource, globalX,
                                                                         globalY)
                                onDragMoved: (globalX, globalY) => root.updateTrayItemDrag(globalX, globalY)
                                onDragFinished: (globalX, globalY, canceled) => root.finishTrayItemDrag(
                                                                                    globalX, globalY,
                                                                                    canceled)
                            }
                        }
                    }
                }
            }

            Item {
                visible: root.trayDragActive && !root.trayDragFromPinned
                x: root.trayDragGlobalX - (root.screen ? root.screen.x || 0 : 0) - width / 2
                y: root.trayDragGlobalY - (root.screen ? root.screen.y || 0 : 0) - height / 2
                width: 30
                height: 30
                z: 100
                scale: 1.08

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                }

                IconImage {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    source: root.trayDragIconSource
                    asynchronous: true
                    mipmap: true
                }
            }
        }

        CompositorBlurRegion {
            targetWindow: overflowPopup
            backgroundItem: popupBackground
        }
    }
}
