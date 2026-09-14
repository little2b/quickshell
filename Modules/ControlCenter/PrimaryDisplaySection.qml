import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets.common

SettingsSection {
    id: root
    title: qsTr("主显示器")
    iconName: "desktop_windows"
    Component.onCompleted: PrimaryDisplayService.initialize()

    SettingsRow {
        Layout.fillWidth: true
        title: qsTr("首选主显示器")
        supportingText: qsTr("连接时切换到此屏幕；断开后保留选择，下次连接时恢复。")
        trailing: SearchSelectMenuField {
            objectName: "primaryDisplaySelector"
            implicitWidth: 250
            enabled: PrimaryDisplayService.ready && !PrimaryDisplayService.busy
            options: {
                const items = [{label: qsTr("不指定主显示器"), value: ""}];
                for (const output of PrimaryDisplayService.outputs)
                    items.push({label: (output.model || output.name) + " · " + output.name, value: output.name});
                const preferred = PrimaryDisplayService.preferences.primary;
                if (preferred && !items.some(item => item.value === PrimaryDisplayService.selectedName))
                    items.push({label: (preferred.model || preferred.name) + qsTr("（未连接）"), value: preferred.name});
                return items;
            }
            value: PrimaryDisplayService.selectedName
            closeOnAccept: true
            Accessible.name: qsTr("首选主显示器")
            onAccepted: value => PrimaryDisplayService.setPrimary(value)
        }
    }
    SettingsRow {
        Layout.fillWidth: true
        title: qsTr("连接主显示器时自动迁移窗口")
        supportingText: qsTr("将其他屏幕上的窗口连同工作区移过来，保留原来的排列。")
        trailing: StyledSwitch {
            objectName: "primaryDisplayAutoMove"
            checked: PrimaryDisplayService.preferences.autoMove
            enabled: PrimaryDisplayService.ready && !PrimaryDisplayService.busy
            Accessible.name: qsTr("连接主显示器时自动迁移窗口")
            onToggled: PrimaryDisplayService.setAutoMove(checked)
        }
    }
    InlineStatusBanner {
        Layout.fillWidth: true
        visible: PrimaryDisplayService.preferences.primary !== null && PrimaryDisplayService.activePrimary === ""
        message: qsTr("首选主显示器未连接，当前使用可用屏幕。接回后将自动恢复。")
    }
    ActionButton {
        objectName: "primaryDisplayMoveNow"
        text: qsTr("立即将窗口移至主显示器")
        iconName: "move_group"
        enabled: PrimaryDisplayService.ready && !PrimaryDisplayService.busy && PrimaryDisplayService.activePrimary !== ""
        onClicked: PrimaryDisplayService.moveNow()
    }
    InlineStatusBanner {
        Layout.fillWidth: true
        visible: PrimaryDisplayService.error !== ""
        tone: "error"
        message: PrimaryDisplayService.error
    }
    InlineStatusBanner {
        Layout.fillWidth: true
        visible: PrimaryDisplayService.message !== ""
        message: PrimaryDisplayService.message
    }
}
