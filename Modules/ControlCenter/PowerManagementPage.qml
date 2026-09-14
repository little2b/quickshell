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
            return qsTr("%1 秒").arg(seconds);
        if (seconds % 3600 === 0)
            return qsTr("%1 小时").arg(seconds / 3600);
        return qsTr("%1 分钟").arg(Math.round(seconds / 60 * 10) / 10);
    }

    function timeoutOptions(current) {
        const values = [60, 120, 300, 600, 900, 1800, 3600, 7200];
        if (current > 0 && values.indexOf(current) === -1)
            values.push(current);
        values.sort((a, b) => a - b);
        return [
            {
                label: qsTr("从不"),
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
            message: IdleService.policyReady ? qsTr("空闲与睡眠设置自动保存；合盖设置需点击应用。") : qsTr("正在读取电源设置…")
        }

        InlineStatusBanner {
            Layout.fillWidth: true
            visible: IdleService.lastError.length > 0
            tone: "error"
            message: IdleService.lastError
        }

        SettingsSection {
            Layout.fillWidth: true
            title: qsTr("电池与供电")
            iconName: "battery_charging_full"

            SettingsRow {
                Layout.fillWidth: true
                iconName: PowerService.onBattery ? "battery_std" : "power"
                title: PowerService.onBattery ? qsTr("正在使用电池") : qsTr("已连接外部电源")
                supportingText: {
                    if (!PowerService.ready)
                        return qsTr("正在读取电池信息…");
                    if (!PowerService.present)
                        return qsTr("未检测到电池");
                    const charge = qsTr("电量 %1%").arg(Math.round(PowerService.percentage * 100));
                    if (PowerService.full)
                        return charge + qsTr(" · 已充满");
                    if (PowerService.charging)
                        return charge + qsTr(" · 正在充电");
                    return charge;
                }
            }

            SettingsRow {
                Layout.fillWidth: true
                visible: PowerService.present && (isFinite(PowerService.timeToEmpty) || isFinite(PowerService.timeToFull))
                iconName: "schedule"
                title: PowerService.charging ? qsTr("预计充满时间") : qsTr("预计剩余时间")
                supportingText: {
                    const seconds = PowerService.charging ? PowerService.timeToFull : PowerService.timeToEmpty;
                    return isFinite(seconds) ? root.formatDuration(Math.round(seconds)) : qsTr("正在估算…");
                }
            }

            SettingsRow {
                Layout.fillWidth: true
                visible: PowerService.present && isFinite(PowerService.healthPercentage)
                iconName: "health_and_safety"
                title: qsTr("电池健康度")
                supportingText: qsTr("最大容量约为设计容量的 %1%").arg(Math.round(PowerService.healthPercentage * 10) / 10)
            }
        }

        LidSettingsSection {
            objectName: "lidSettingsSection"
            Layout.fillWidth: true
        }

        SettingsSection {
            Layout.fillWidth: true
            title: qsTr("自动电源管理")
            iconName: "energy_savings_leaf"

            SettingsRow {
                Layout.fillWidth: true
                iconName: "schedule"
                title: qsTr("启用空闲管理")
                supportingText: qsTr("空闲时按下方设置调暗屏幕、锁屏、息屏或睡眠。")
                trailing: StyledSwitch {
                    objectName: "powerPolicySwitch"
                    checked: IdleService.policyEnabled
                    enabled: IdleService.policyReady
                    Accessible.name: qsTr("启用空闲管理")
                    onToggled: IdleService.setPolicyEnabled(checked)
                }
            }

            SettingsRow {
                Layout.fillWidth: true
                iconName: "coffee"
                title: qsTr("保持唤醒")
                supportingText: qsTr("暂停遵循“保持唤醒”的空闲动作，适合演示或阅读。")
                trailing: StyledSwitch {
                    objectName: "powerKeepAwakeSwitch"
                    checked: IdleService.inhibited
                    enabled: IdleService.policyReady && !IdleService.busy
                    Accessible.name: qsTr("保持唤醒")
                    onToggled: IdleService.setInhibited(checked)
                }
            }
        }

        SettingsSection {
            Layout.fillWidth: true
            title: qsTr("屏幕与睡眠")
            iconName: "bedtime"

            StageSetting {
                stageName: "dim"
                stageTitle: qsTr("调暗屏幕")
                stageIcon: "brightness_4"
            }

            GeneralSliderSetting {
                visible: IdleService.dimEnabled
                enabled: IdleService.policyReady
                title: qsTr("调暗后的亮度比例")
                description: qsTr("相对于当前亮度；恢复操作后还原原来的亮度。")
                from: 5
                to: 100
                stepSize: 5
                suffix: "%"
                value: Math.round(IdleService.dimFraction * 100)
                onMoved: value => IdleService.setDimFraction(value / 100)
            }

            StageSetting {
                stageName: "lock"
                stageTitle: qsTr("自动锁屏")
                stageIcon: "lock"
            }
            StageSetting {
                stageName: "displayOff"
                stageTitle: qsTr("关闭显示器")
                stageIcon: "monitor"
            }
            StageSetting {
                stageName: "suspend"
                stageTitle: qsTr("自动睡眠")
                stageIcon: "bedtime"
            }

            InlineStatusBanner {
                Layout.fillWidth: true
                message: qsTr("所有时间均从最后一次操作开始计算。需要睡眠前锁屏时，请将自动锁屏时间设得更短。")
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
            supportingText: !IdleService.policyEnabled ? qsTr("空闲管理已暂停") : IdleService.inhibited && stage.respectInhibitors ? qsTr("保持唤醒期间暂停") : qsTr("无操作达到此时间后执行")
            trailing: SearchSelectMenuField {
                objectName: "powerTimeout_" + stage.stageName
                implicitWidth: 160
                implicitHeight: 40
                enabled: IdleService.policyReady
                options: root.timeoutOptions(stage.timeout)
                value: stage.stageEnabled ? String(stage.timeout) : "0"
                maxVisibleItems: 5
                closeOnAccept: true
                Accessible.name: stage.stageTitle + qsTr("等待时间")
                onAccepted: value => {
                    const seconds = Number(value);
                    IdleService.configureStage(stage.stageName, seconds > 0, seconds > 0 ? seconds : stage.timeout, stage.respectInhibitors);
                }
            }
        }

        SettingsRow {
            Layout.fillWidth: true
            visible: stage.stageEnabled
            title: qsTr("遵循保持唤醒与应用阻止请求")
            supportingText: qsTr("应用请求保持唤醒时跳过此动作。")
            trailing: StyledSwitch {
                checked: stage.respectInhibitors
                enabled: IdleService.policyReady
                Accessible.name: stage.stageTitle + qsTr("：遵循保持唤醒")
                onToggled: IdleService.configureStage(stage.stageName, stage.stageEnabled, stage.timeout, checked)
            }
        }
    }
}
