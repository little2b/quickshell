pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Widgets.common

SettingsSection {
    id: root

    title: qsTr("笔记本合盖")
    iconName: "laptop_mac"
    property bool ready: false
    readonly property bool busy: operation.running
    property var saved: ({})
    property var capabilities: ({})
    property string batteryAction: "suspend"
    property string externalAction: ""
    property string dockedAction: "ignore"
    property string error: ""
    property string message: ""
    property var inhibitors: []
    property bool docked: false
    readonly property bool dirty: ready && (batteryAction !== saved.battery
        || externalAction !== saved.external || dockedAction !== saved.docked)

    function options(inherit) {
        const items = [
            {label: qsTr("不执行动作"), value: "ignore", enabled: true},
            {label: qsTr("睡眠"), value: "suspend", enabled: !!root.capabilities.suspend},
            {label: qsTr("休眠"), value: "hibernate", enabled: !!root.capabilities.hibernate},
            {label: qsTr("先睡眠后休眠"), value: "suspend-then-hibernate", enabled: !!root.capabilities["suspend-then-hibernate"]}
        ];
        if (inherit)
            items.unshift({label: qsTr("与使用电池时相同"), value: "", enabled: true});
        return items;
    }

    function refresh() {
        if (root.busy)
            return;
        root.error = "";
        root.message = "";
        operation.applying = false;
        operation.command = ["/usr/bin/python3", "-I", Paths.systemScriptsDir + "/lid_settings.py", "status"];
        operation.running = true;
    }

    function apply() {
        if (!root.ready || root.busy || !root.dirty)
            return;
        root.error = "";
        root.message = "";
        operation.applying = true;
        operation.command = ["/usr/bin/pkexec", "/usr/bin/python3", "-I",
            Paths.systemScriptsDir + "/lid_settings.py", "apply", JSON.stringify({
                battery: root.batteryAction, external: root.externalAction, docked: root.dockedAction
            })];
        operation.running = true;
    }

    Component.onCompleted: refresh()

    InlineStatusBanner {
        Layout.fillWidth: true
        message: root.busy ? (operation.applying ? qsTr("正在验证身份并应用合盖设置…") : qsTr("正在读取合盖设置…"))
            : qsTr("选择后点击“应用合盖设置”。系统会请求管理员身份验证，设置对所有桌面会话生效。")
    }

    InlineStatusBanner {
        Layout.fillWidth: true
        visible: root.error !== ""
        tone: "error"
        message: root.error
    }

    InlineStatusBanner {
        Layout.fillWidth: true
        visible: root.message !== ""
        message: root.message
    }

    InlineStatusBanner {
        Layout.fillWidth: true
        visible: root.inhibitors.length > 0
        message: qsTr("以下程序正在接管合盖动作，系统合盖策略可能暂不执行：%1").arg(root.inhibitors.join("、"))
    }

    SettingsRow {
        Layout.fillWidth: true
        iconName: "battery_std"
        title: qsTr("使用电池时合盖")
        trailing: SearchSelectMenuField {
            objectName: "lidBatteryAction"
            implicitWidth: 210
            enabled: root.ready && !root.busy
            options: root.options(false)
            value: root.batteryAction
            closeOnAccept: true
            Accessible.name: qsTr("使用电池时合盖动作")
            onAccepted: value => root.batteryAction = value
        }
    }

    SettingsRow {
        Layout.fillWidth: true
        iconName: "power"
        title: qsTr("接通电源时合盖")
        trailing: SearchSelectMenuField {
            objectName: "lidExternalAction"
            implicitWidth: 210
            enabled: root.ready && !root.busy
            options: root.options(true)
            value: root.externalAction
            closeOnAccept: true
            Accessible.name: qsTr("接通电源时合盖动作")
            onAccepted: value => root.externalAction = value
        }
    }

    SettingsRow {
        Layout.fillWidth: true
        iconName: "desktop_windows"
        title: qsTr("外接显示器或扩展坞时合盖")
        supportingText: root.docked ? qsTr("当前正在使用此场景，优先于电池与电源设置。") : qsTr("此场景优先于电池与电源设置。")
        trailing: SearchSelectMenuField {
            objectName: "lidDockedAction"
            implicitWidth: 210
            enabled: root.ready && !root.busy
            options: root.options(false)
            value: root.dockedAction
            closeOnAccept: true
            Accessible.name: qsTr("外接显示器或扩展坞时合盖动作")
            onAccepted: value => root.dockedAction = value
        }
    }

    InlineStatusBanner {
        Layout.fillWidth: true
        message: qsTr("niri 会在合盖时关闭内置屏幕，开盖时恢复。“不执行动作”可用于合盖后继续使用外接显示器；保持唤醒开关不控制这里的合盖策略。")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.spacingS

        ActionButton {
            objectName: "lidApplyButton"
            text: qsTr("应用合盖设置")
            iconName: "check"
            filled: true
            enabled: root.dirty && !root.busy
            onClicked: root.apply()
        }

        ActionButton {
            text: root.dirty ? qsTr("撤销未应用改动") : qsTr("刷新")
            iconName: "refresh"
            enabled: !root.busy
            onClicked: root.refresh()
        }
    }

    Process {
        id: operation
        property bool applying: false
        stdout: StdioCollector { id: response }
        stderr: StdioCollector { id: diagnostics }
        onExited: code => {
            try {
                if (code === 126)
                    throw new Error(qsTr("已取消身份验证，合盖设置未更改。"));
                const result = JSON.parse(response.text || "{}");
                if (code !== 0 || !result.ok)
                    throw new Error(result.error || diagnostics.text.trim() || qsTr("无法读取或应用合盖设置。"));
                root.saved = result.values;
                root.batteryAction = result.values.battery;
                root.externalAction = result.values.external;
                root.dockedAction = result.values.docked;
                root.capabilities = result.capabilities;
                root.inhibitors = result.inhibitors;
                root.docked = result.docked;
                root.ready = true;
                if (operation.applying)
                    root.message = qsTr("合盖设置已保存并生效，无需注销或重启。 ");
            } catch (exception) {
                root.error = String(exception.message || exception);
            }
        }
    }
}
