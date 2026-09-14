pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets.common

StyledFlickable {
    id: root

    property bool presentationActive: false
    property string selectedName: ""
    property string selectedMode: ""
    property real selectedScale: 1
    property string selectedTransform: "normal"
    readonly property var display: DisplaySettingsService.outputs.find(output => output.name
                                                                                 === root.selectedName)
                                   || null
    readonly property var activeDisplays: DisplaySettingsService.outputs.filter(output => output.current_mode
                                                                                          !== null
                                                                                          && output.logical)
    readonly property string resolution: root.selectedMode.split("@")[0]
    readonly property var resolutionOptions: {
        const result = [];
        for (const mode of (root.display ? root.display.modes : [])) {
            const value = mode.width + "x" + mode.height;
            if (!result.some(option => option.value === value))
                result.push({
                                value: value,
                                label: mode.width + " × " + mode.height
                            });
        }
        return result;
    }
    readonly property var refreshOptions: {
        return (root.display ? root.display.modes : []).filter(mode => mode.width + "x" + mode.height
                                                                       === root.resolution).map(mode => ({
                                                                           value: root.modeValue(mode),
                                                                           label: qsTr("%1 Hz").arg(Number((
                                                                                                               mode.refresh_rate
                                                                                                               / 1000).toFixed(
                                                                                                               3)))
                                                                       }));
    }
        readonly property var scaleOptions: {
        const values = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 3, 3.5, 4];
        if (values.indexOf(root.selectedScale) === -1)
        values.push(root.selectedScale);
        return values.sort((a, b) => a - b).map(value => ({
        value: String(value),
        label: qsTr("%1%").arg(Math.round(value * 100))
    }));
    }

        clip: true
        contentWidth: width
        contentHeight: contentColumn.y + contentColumn.implicitHeight + Metrics.pageMargin

        function modeValue(mode) {
        return mode.width + "x" + mode.height + "@" + (mode.refresh_rate / 1000).toFixed(3);
    }

        function syncSelection() {
        if (!root.activeDisplays.some(output => output.name === root.selectedName))
        root.selectedName = root.activeDisplays.length ? root.activeDisplays[0].name : "";
        const output = root.display;
        if (!output || output.current_mode === null || !output.logical)
        return;
        root.selectedMode = root.modeValue(output.modes[output.current_mode]);
        root.selectedScale = output.logical.scale;
        const transforms = {
        Normal: "normal",
        "90": "90",
        "180": "180",
        "270": "270",
        Flipped: "flipped",
        Flipped90: "flipped-90",
        Flipped180: "flipped-180",
        Flipped270: "flipped-270"
    };
        root.selectedTransform = transforms[output.logical.transform] || "normal";
    }

        function selectResolution(value) {
        const choices = root.display.modes.filter(mode => mode.width + "x" + mode.height === value);
        const previousRate = root.selectedMode.split("@")[1];
        const matching = choices.find(mode => (mode.refresh_rate / 1000).toFixed(3) === previousRate);
        const best = matching || choices.reduce((a, b) => a.refresh_rate > b.refresh_rate ? a : b);
        root.selectedMode = root.modeValue(best);
    }

        function closeChildWindows() {
        DisplaySettingsService.revert();
    }

        Component.onCompleted: {
        root.syncSelection();
        DisplaySettingsService.refresh();
    }
        Component.onDestruction: DisplaySettingsService.revert()
        onPresentationActiveChanged: {
        if (root.presentationActive)
        DisplaySettingsService.refresh();
        else
        DisplaySettingsService.revert();
    }

        Connections {
        target: DisplaySettingsService
        function onOutputsChanged() {
        root.syncSelection();
    }
    }

        component DisplayField: SettingsRow {
        id: field
        property var options: []
        property string value: ""
        signal accepted(string value)
        Layout.fillWidth: true
        enabled: !DisplaySettingsService.busy
        trailing: SearchSelectMenuField {
        Layout.preferredWidth: Math.min(260, root.width * 0.46)
        Layout.preferredHeight: Metrics.controlHeightM
        options: field.options
        value: field.value
        closeOnAccept: true
        Accessible.name: field.title
        onAccepted: value => field.accepted(value)
    }
    }

        ColumnLayout {
        id: contentColumn
        width: Math.min(640, Math.max(0, root.width - Metrics.pageMargin * 2))
        x: Math.max(Metrics.pageMargin, (root.width - width) / 2)
        y: Metrics.pageMargin
        spacing: Metrics.spacingL

        // Confirmation is above the fields so it stays reachable after scaling.
        SettingsSection {
        Layout.fillWidth: true
        visible: DisplaySettingsService.previewing
        title: qsTr("Keep these display settings?")
        iconName: "timer"
        supportingText: qsTr("Restoring previous settings in %1 seconds").arg(
        DisplaySettingsService.secondsRemaining)
        RowLayout {
        Layout.fillWidth: true
        ActionButton {
        text: qsTr("Revert")
        enabled: !DisplaySettingsService.confirming
        onClicked: DisplaySettingsService.revert()
    }
        ActionButton {
        text: qsTr("Keep changes")
        enabled: !DisplaySettingsService.confirming && DisplaySettingsService.secondsRemaining > 0
        onClicked: DisplaySettingsService.confirm()
    }
    }
    }

        InlineStatusBanner {
        Layout.fillWidth: true
        visible: !DisplaySettingsService.supported
        message: qsTr("Display settings are unavailable in this session")
    }

        PrimaryDisplaySection {
        Layout.fillWidth: true
        visible: DisplaySettingsService.supported
    }

        SettingsSection {
        Layout.fillWidth: true
        visible: root.activeDisplays.length > 0 && DisplaySettingsService.supported
        flat: true
        title: qsTr("Arrangement")
        iconName: "dashboard"
        supportingText: qsTr("Drag displays to match their physical arrangement.")
        DisplayArrangement {
        Layout.fillWidth: true
        busy: DisplaySettingsService.busy && DisplaySettingsService.operationKind === "layout-preview" &&
        !DisplaySettingsService.previewing
        outputs: root.activeDisplays
        selectedName: root.selectedName
        enabled: !DisplaySettingsService.busy
        onScreenSelected: name => {
        root.selectedName = name;
        root.syncSelection();
    }
        onApplyRequested: positions => {
        root.contentY = 0;
        DisplaySettingsService.applyLayout(positions);
    }
    }
    }

        SettingsSection {
        Layout.fillWidth: true
        visible: root.activeDisplays.length > 0 && DisplaySettingsService.supported
        flat: true
        flatIconContainer: true
        title: qsTr("Display")
        iconName: "monitor"

        DisplayField {
        title: qsTr("Display")
        value: root.selectedName
        options: root.activeDisplays.map(output => ({
        value: output.name,
        label: (output.model || output.name) + " · " + output.name
    }))
        onAccepted: value => {
        root.selectedName = value;
        root.syncSelection();
    }
    }
        DisplayField {
        title: qsTr("Resolution")
        value: root.resolution
        options: root.resolutionOptions
        onAccepted: value => root.selectResolution(value)
    }
        DisplayField {
        title: qsTr("Refresh rate")
        value: root.selectedMode
        options: root.refreshOptions
        onAccepted: value => root.selectedMode = value
    }
        DisplayField {
        title: qsTr("Scale")
        value: String(root.selectedScale)
        options: root.scaleOptions
        onAccepted: value => root.selectedScale = Number(value)
    }
        DisplayField {
        title: qsTr("Rotation")
        value: root.selectedTransform
        options: [
        {
        value: "normal",
        label: qsTr("Normal")
    },
        {
        value: "90",
        label: qsTr("90°")
    },
        {
        value: "180",
        label: qsTr("180°")
    },
        {
        value: "270",
        label: qsTr("270°")
    },
        {
        value: "flipped",
        label: qsTr("Flipped")
    },
        {
        value: "flipped-90",
        label: qsTr("Flipped 90°")
    },
        {
        value: "flipped-180",
        label: qsTr("Flipped 180°")
    },
        {
        value: "flipped-270",
        label: qsTr("Flipped 270°")
    }
        ]
        onAccepted: value => root.selectedTransform = value
    }

        RowLayout {
        Layout.fillWidth: true
        ActionButton {
        text: qsTr("Refresh")
        enabled: !DisplaySettingsService.busy
        onClicked: DisplaySettingsService.refresh()
    }
        Item {
        Layout.fillWidth: true
    }
        ActionButton {
        id: applyButton
        text: qsTr("Apply")
        enabled: !DisplaySettingsService.busy && root.selectedMode !== ""
        onClicked: {
        root.contentY = 0;
        DisplaySettingsService.apply(root.selectedName, root.selectedMode, root.selectedScale,
        root.selectedTransform);
    }
        InlineBusyIndicator {
        anchors.right: parent.left
        anchors.rightMargin: Metrics.spacingS
        anchors.verticalCenter: parent.verticalCenter
        busy: DisplaySettingsService.busy && DisplaySettingsService.operationKind !== "layout-preview" &&
        !DisplaySettingsService.previewing
    }
    }
    }
    }

        InlineStatusBanner {
        Layout.fillWidth: true
        visible: DisplaySettingsService.supported && root.activeDisplays.length === 0 &&
        !DisplaySettingsService.busy
        message: qsTr("No active displays")
    }
        InlineStatusBanner {
        Layout.fillWidth: true
        visible: DisplaySettingsService.error !== ""
        tone: "error"
        message: DisplaySettingsService.error
    }
        InlineStatusBanner {
        Layout.fillWidth: true
        visible: DisplaySettingsService.message !== "" && !DisplaySettingsService.previewing
        message: DisplaySettingsService.message
    }
    }
    }
