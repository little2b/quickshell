pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets.common

StyledFlickable {
    id: root

    property bool presentationActive: false
    clip: true
    contentWidth: width
    contentHeight: contentColumn.implicitHeight + Metrics.pageMargin * 2

    function formatDuration(seconds) {
        if (seconds < 60)
            return qsTr("%1 s").arg(seconds);
        if (seconds % 3600 === 0)
            return qsTr("%1 h").arg(seconds / 3600);
        return qsTr("%1 min").arg(Math.round(seconds / 60 * 10) / 10);
    }

    function timeoutOptions(current) {
        const values = [60, 120, 300, 600, 900, 1800, 3600, 7200];
        if (current > 0 && values.indexOf(current) === -1)
            values.push(current);
        values.sort((a, b) => a - b);
        return [
                    {
                        label: qsTr("Never"),
                        value: "0"
                    }
                ].concat(values.map(seconds => ({
                    label: root.formatDuration(seconds),
                    value: String(seconds)
                })));
    }

        ColumnLayout {
        id: contentColumn
        width: Math.min(640, Math.max(0, root.width - Metrics.pageMargin * 2))
        x: Math.max(Metrics.pageMargin, (root.width - width) / 2)
        y: Metrics.pageMargin
        spacing: Metrics.spacingL

        InlineStatusBanner {
        Layout.fillWidth: true
        message: IdleService.policyReady ? qsTr(
        "Idle and sleep settings are saved automatically. Lid settings require Apply.") : qsTr(
        "Reading power settings…")
    }

        InlineStatusBanner {
        Layout.fillWidth: true
        visible: IdleService.lastError.length > 0
        tone: "error"
        message: IdleService.lastError
    }

        SettingsSection {
        Layout.fillWidth: true
        title: qsTr("Battery and power")
        iconName: "battery_charging_full"

        SettingsRow {
        Layout.fillWidth: true
        iconName: PowerService.onBattery ? "battery_std" : "power"
        title: PowerService.onBattery ? qsTr("On battery") : qsTr("Connected to external power")
        supportingText: {
        if (!PowerService.ready)
        return qsTr("Reading battery information…");
        if (!PowerService.present)
        return qsTr("No battery detected");
        const charge = qsTr("Battery: %1%").arg(Math.round(PowerService.percentage * 100));
        if (PowerService.full)
        return charge + qsTr(" · Fully charged");
        if (PowerService.charging)
        return charge + qsTr(" · Charging");
        return charge;
    }
    }

        SettingsRow {
        Layout.fillWidth: true
        visible: PowerService.present && (isFinite(PowerService.timeToEmpty) || isFinite(
        PowerService.timeToFull))
        iconName: "schedule"
        title: PowerService.charging ? qsTr("Time until fully charged") : qsTr("Estimated remaining time")
        supportingText: {
        const seconds = PowerService.charging ? PowerService.timeToFull : PowerService.timeToEmpty;
        return isFinite(seconds) ? root.formatDuration(Math.round(seconds)) : qsTr("Estimating…");
    }
    }

        SettingsRow {
        Layout.fillWidth: true
        visible: PowerService.present && isFinite(PowerService.healthPercentage)
        iconName: "health_and_safety"
        title: qsTr("Battery health")
        supportingText: qsTr("Maximum capacity is approximately %1% of design capacity").arg(Math.round(
        PowerService.healthPercentage * 10) / 10)
    }
    }

        LidSettingsSection {
        objectName: "lidSettingsSection"
        Layout.fillWidth: true
    }

        SettingsSection {
        Layout.fillWidth: true
        title: qsTr("Automatic power management")
        iconName: "energy_savings_leaf"

        SettingsRow {
        Layout.fillWidth: true
        iconName: "schedule"
        title: qsTr("Enable idle management")
        supportingText: qsTr(
        "Dim the screen, lock, turn off displays or suspend when idle according to the settings below.")
        trailing: StyledSwitch {
        objectName: "powerPolicySwitch"
        checked: IdleService.policyEnabled
        enabled: IdleService.policyReady
        Accessible.name: qsTr("Enable idle management")
        onToggled: IdleService.setPolicyEnabled(checked)
    }
    }

        SettingsRow {
        Layout.fillWidth: true
        iconName: "coffee"
        title: qsTr("Keep awake")
        supportingText: qsTr("Pause idle actions that respect Keep awake, for presentations or reading.")
        trailing: StyledSwitch {
        objectName: "powerKeepAwakeSwitch"
        checked: IdleService.inhibited
        enabled: IdleService.policyReady && !IdleService.busy
        Accessible.name: qsTr("Keep awake")
        onToggled: IdleService.setInhibited(checked)
    }
    }
    }

        SettingsSection {
        Layout.fillWidth: true
        title: qsTr("Display and sleep")
        iconName: "bedtime"

        StageSetting {
        stageName: "dim"
        stageTitle: qsTr("Dim screen")
        stageIcon: "brightness_4"
    }

        GeneralSliderSetting {
        visible: IdleService.dimEnabled
        enabled: IdleService.policyReady
        title: qsTr("Dimmed brightness ratio")
        description: qsTr(
        "Relative to current brightness. Restore the original brightness when activity resumes.")
        from: 5
        to: 100
        stepSize: 5
        suffix: "%"
        value: Math.round(IdleService.dimFraction * 100)
        onMoved: value => IdleService.setDimFraction(value / 100)
    }

        StageSetting {
        stageName: "lock"
        stageTitle: qsTr("Automatically lock")
        stageIcon: "lock"
    }
        StageSetting {
        stageName: "displayOff"
        stageTitle: qsTr("Turn off displays")
        stageIcon: "monitor"
    }
        StageSetting {
        stageName: "suspend"
        stageTitle: qsTr("Automatically suspend")
        stageIcon: "bedtime"
    }

        InlineStatusBanner {
        Layout.fillWidth: true
        message: qsTr(
        "All delays start from the last activity. Set a shorter lock delay to lock before suspending.")
    }
    }
    }

        component StageSetting: ColumnLayout {
        id: stage
        required property string stageName
        required property string stageTitle
        required property string stageIcon
        readonly property bool stageEnabled: IdleService[stageName + "Enabled"]
        readonly property real timeout: IdleService[stageName + "Timeout"]
        readonly property bool respectInhibitors: IdleService[stageName + "RespectInhibitors"]

        Layout.fillWidth: true
        spacing: Metrics.spacingXS

        SettingsRow {
        Layout.fillWidth: true
        iconName: stage.stageIcon
        title: stage.stageTitle
        supportingText: !IdleService.policyEnabled ? qsTr("Idle management is paused") :
        IdleService.inhibited && stage.respectInhibitors ? qsTr("Paused while keeping awake") : qsTr(
        "Run after this period of inactivity")
        trailing: SearchSelectMenuField {
        objectName: "powerTimeout_" + stage.stageName
        implicitWidth: 160
        implicitHeight: 40
        enabled: IdleService.policyReady
        options: root.timeoutOptions(stage.timeout)
        value: stage.stageEnabled ? String(stage.timeout) : "0"
        maxVisibleItems: 5
        closeOnAccept: true
        Accessible.name: stage.stageTitle + qsTr("Delay")
        onAccepted: value => {
        const seconds = Number(value);
        IdleService.configureStage(stage.stageName, seconds > 0, seconds > 0 ? seconds : stage.timeout,
        stage.respectInhibitors);
    }
    }
    }

        SettingsRow {
        Layout.fillWidth: true
        visible: stage.stageEnabled
        title: qsTr("Respect keep awake and application inhibitors")
        supportingText: qsTr("Skip this action when an application requests to keep awake.")
        trailing: StyledSwitch {
        checked: stage.respectInhibitors
        enabled: IdleService.policyReady
        Accessible.name: stage.stageTitle + qsTr(": respect keep awake")
        onToggled: IdleService.configureStage(stage.stageName, stage.stageEnabled, stage.timeout, checked)
    }
    }
    }
    }
