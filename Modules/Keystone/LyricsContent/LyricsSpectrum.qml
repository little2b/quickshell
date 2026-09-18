import QtQuick

Canvas {
    id: root

    required property bool active
    required property bool dataAvailable
    required property var values
    required property color barColor
    property bool vertical: false
    readonly property bool rendering: active && dataAvailable && visible
    readonly property bool animating: smoothing.running
    readonly property real settleThreshold: 0.05
    readonly property var ranges: [[0.55, 0.78, 1.5], [0.18, 0.33, 1.2], [0, 0.08, 1], [0.08, 0.18, 1], [0.33,
                                                                                                         0.55, 1.2],
        [0.78, 0.98, 1.5]]
    property var targetValues: [0, 0, 0, 0, 0, 0]
    property var smoothValues: [0, 0, 0, 0, 0, 0]

    function barLength(value) {
        return Math.max(3, Math.min(1, value / 100) * (root.vertical ? root.width : root.height));
    }

    function refreshTargets() {
        const targets = [0, 0, 0, 0, 0, 0];
        if (root.rendering && root.values && root.values.length >= 6) {
            for (let index = 0; index < root.ranges.length; ++index) {
                const range = root.ranges[index];
                const start = Math.floor(root.values.length * range[0]);
                const end = Math.min(root.values.length - 1, Math.floor(root.values.length * range[1]));
                let maximum = 0;
                for (let sample = start; sample <= end; ++sample)
                    maximum = Math.max(maximum, Number(root.values[sample]) || 0);
                targets[index] = Math.min(100, maximum * 100 * range[2]);
            }
        }
        root.targetValues = targets;
        if (!root.rendering) {
            smoothing.stop();
            const changed = root.smoothValues.some(value => value !== 0);
            if (changed) {
                root.smoothValues = targets;
                if (root.visible)
                    root.requestPaint();
            }
            return;
        }
        // Ignore differences smaller than 0.01 logical pixels at the usual
        // size. New samples restart smoothing after a static/silent interval.
        smoothing.running = targets.some((value, index) => Math.abs(value - root.smoothValues[index])
                                                           > root.settleThreshold);
    }

    function advance() {
        const next = root.smoothValues.slice();
        let moving = false;
        let paintChanged = false;
        for (let index = 0; index < next.length; ++index) {
            const target = root.targetValues[index];
            const difference = target - next[index];
            next[index] += (difference > 0 ? 0.85 : 0.08) * difference;
            if (Math.abs(target - next[index]) <= root.settleThreshold)
                next[index] = target;
            else
                moving = true;
            paintChanged = paintChanged || root.barLength(next[index]) !== root.barLength(
                        root.smoothValues[index]);
        }
        root.smoothValues = next;
        if (paintChanged)
            root.requestPaint();
        if (!moving)
            smoothing.stop();
    }

    onValuesChanged: refreshTargets()
    onRenderingChanged: refreshTargets()
    onBarColorChanged: if (visible)
                           requestPaint()
    onVerticalChanged: if (visible)
                           requestPaint()
    Component.onCompleted: refreshTargets()

    Timer {
        id: smoothing
        interval: 16
        repeat: true
        onTriggered: root.advance()
    }

    onPaint: {
        const context = getContext("2d");
        context.clearRect(0, 0, width, height);
        context.beginPath();
        context.lineCap = "round";
        context.lineWidth = 2.5;
        context.strokeStyle = String(root.barColor);
        for (let index = 0; index < 6; ++index) {
            const length = root.barLength(root.smoothValues[index]);
            const offset = 1.25 + index * 3.7;
            if (root.vertical) {
                context.moveTo(width / 2 - length / 2, offset);
                context.lineTo(width / 2 + length / 2, offset);
            } else {
                context.moveTo(offset, height / 2 - length / 2);
                context.lineTo(offset, height / 2 + length / 2);
            }
        }
        context.stroke();
    }
}
