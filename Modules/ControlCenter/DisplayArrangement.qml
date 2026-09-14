pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets.common
import "DisplayLayout.js" as Geometry

ColumnLayout {
    id: root

    property bool busy: false
    property var outputs: []
    property string selectedName: ""
    property var positions: ({})
    property bool dragging: false
    property var dragBounds: ({
                                  x: 0,
                                  y: 0,
                                  width: 1,
                                  height: 1
                              })
    readonly property var screens: Geometry.rectangles(root.outputs, root.positions)
    readonly property var bounds: root.dragging ? root.dragBounds : Geometry.bounds(root.screens)
    readonly property var selected: root.screens.find(screen => screen.name === root.selectedName) || null
    readonly property bool overlap: Geometry.hasOverlap(root.screens)
    readonly property bool dirty: root.outputs.some(output => {
        const p = root.positions[output.name];
        return p && (p.x !== output.logical.x || p.y !== output.logical.y);
    })
    readonly property bool inputValid: xField.acceptableInput && yField.acceptableInput

    signal screenSelected(string name)
    signal applyRequested(var positions)

    spacing: Metrics.spacingM

    function reset() {
        root.dragging = false;
        const next = {};
        root.outputs.forEach(output => next[output.name] = {
            x: output.logical.x,
            y: output.logical.y
        });
        root.positions = next;
    }

    function move(name, x, y) {
        if (!Number.isFinite(x) || !Number.isFinite(y))
            return;
        const next = Object.assign({}, root.positions);
        next[name] = {
            x: Math.max(-100000, Math.min(100000, Math.round(x))),
            y: Math.max(-100000, Math.min(100000, Math.round(y)))
        };
        root.positions = next;
    }

    onOutputsChanged: root.reset()
    Component.onCompleted: root.reset()

    Rectangle {
        id: canvas
        Layout.fillWidth: true
        Layout.preferredHeight: 220
        radius: Metrics.cornerM
        color: Appearance.colors.colLayer1
        clip: true
        readonly property real factor: Math.min((width - 64) / Math.max(1, root.bounds.width), (height - 64)
                                                / Math.max(1, root.bounds.height))
        readonly property real offsetX: (width - root.bounds.width * factor) / 2 - root.bounds.x * factor
        readonly property real offsetY: (height - root.bounds.height * factor) / 2 - root.bounds.y * factor

        Repeater {
            model: root.outputs
            Rectangle {
                id: screenRect
                required property var modelData
                readonly property var geometry: root.screens.find(screen => screen.name === modelData.name)
                                                || modelData.logical
                readonly property bool selected: modelData.name === root.selectedName
                x: canvas.offsetX + geometry.x * canvas.factor
                y: canvas.offsetY + geometry.y * canvas.factor
                width: geometry.width * canvas.factor
                height: geometry.height * canvas.factor
                radius: Metrics.cornerS
                color: selected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                border.width: selected ? 2 : 1
                border.color: selected ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                z: selected ? 1 : 0

                Text {
                    anchors.centerIn: parent
                    width: Math.max(0, parent.width - 12)
                    text: screenRect.modelData.name
                    color: screenRect.selected ? Appearance.colors.colOnPrimaryContainer :
                                                 Appearance.colors.colOnSurface
                    font.family: Fonts.ui
                    font.pixelSize: Typography.bodyMedium.pixelSize
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    preventStealing: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property point startPoint
                    property real startX: 0
                    property real startY: 0
                    property real factor: 1
                    property string movingName: ""
                    onPressed: mouse => {
                        root.screenSelected(screenRect.modelData.name);
                        movingName = screenRect.modelData.name;
                        startPoint = mapToItem(canvas, mouse.x, mouse.y);
                        startX = screenRect.geometry.x;
                        startY = screenRect.geometry.y;
                        factor = canvas.factor;
                        root.dragBounds = Geometry.bounds(root.screens);
                        root.dragging = true;
                    }
                    onPositionChanged: mouse => {
                        if (!pressed)
                            return;
                        const p = mapToItem(canvas, mouse.x, mouse.y);
                        root.move(movingName, startX + (p.x - startPoint.x) / factor, startY + (p.y
                                                                                                - startPoint.y)
                                  / factor);
                    }
                    onReleased: {
                        const moving = root.screens.find(screen => screen.name === movingName);
                        if (moving) {
                            const p = Geometry.snap(moving, root.screens, 12 / factor);
                            root.move(movingName, p.x, p.y);
                        }
                        root.dragging = false;
                    }
                    onCanceled: root.dragging = false
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.spacingM
        MaterialTextField {
            id: xField
            Layout.fillWidth: true
            labelText: qsTr("Horizontal position (X)")
            text: String(root.selected ? root.selected.x : 0)
            validator: IntValidator {
                bottom: -100000
                top: 100000
            }
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            onTextEdited: {
                if (acceptableInput && root.selected)
                    root.move(root.selectedName, Number.fromLocaleString(Qt.locale(), text), root.selected.y);
            }
        }
        MaterialTextField {
            id: yField
            Layout.fillWidth: true
            labelText: qsTr("Vertical position (Y)")
            text: String(root.selected ? root.selected.y : 0)
            validator: IntValidator {
                bottom: -100000
                top: 100000
            }
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            onTextEdited: {
                if (acceptableInput && root.selected)
                    root.move(root.selectedName, root.selected.x, Number.fromLocaleString(Qt.locale(), text));
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        ActionButton {
            text: qsTr("Horizontal")
            onClicked: root.positions = Geometry.arrange(root.screens, false)
        }
        ActionButton {
            text: qsTr("Vertical")
            onClicked: root.positions = Geometry.arrange(root.screens, true)
        }
        Item {
            Layout.fillWidth: true
        }
        ActionButton {
            text: qsTr("Reset")
            enabled: root.dirty
            onClicked: root.reset()
        }
    }

    InlineStatusBanner {
        Layout.fillWidth: true
        visible: root.overlap
        tone: "warning"
        message: qsTr("Displays overlap. Move them apart before applying.")
    }
    ActionButton {
        Layout.alignment: Qt.AlignRight
        text: qsTr("Apply layout")
        filled: true
        enabled: root.dirty && !root.overlap && root.inputValid && !root.dragging
        onClicked: root.applyRequested(root.positions)
        InlineBusyIndicator {
            anchors.right: parent.left
            anchors.rightMargin: Metrics.spacingS
            anchors.verticalCenter: parent.verticalCenter
            busy: root.busy
        }
    }
}
