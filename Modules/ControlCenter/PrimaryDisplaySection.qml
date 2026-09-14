import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets.common

SettingsSection {
    id: root
    title: qsTr("Primary display")
    iconName: "desktop_windows"
    Component.onCompleted: PrimaryDisplayService.initialize()

    SettingsRow {
        Layout.fillWidth: true
        title: qsTr("Preferred primary display")
        supportingText: qsTr(
                            "Switch to this display when connected. Remember the preference while disconnected and restore it on reconnection.")
        trailing: SearchSelectMenuField {
            objectName: "primaryDisplaySelector"
            implicitWidth: 250
            enabled: PrimaryDisplayService.ready && !PrimaryDisplayService.busy
            options: {
                const items = [
                          {
                              label: qsTr("No preferred primary display"),
                              value: ""
                          }
                      ];
                for (const output of PrimaryDisplayService.outputs)
                    items.push({
                                   label: (output.model || output.name) + " · " + output.name,
                                   value: output.name
                               });
                const preferred = PrimaryDisplayService.preferences.primary;
                if (preferred && !items.some(item => item.value === PrimaryDisplayService.selectedName))
                    items.push({
                                   label: (preferred.model || preferred.name) + qsTr(" (disconnected)"),
                                   value: preferred.name
                               });
                return items;
            }
            value: PrimaryDisplayService.selectedName
            closeOnAccept: true
            Accessible.name: qsTr("Preferred primary display")
            onAccepted: value => PrimaryDisplayService.setPrimary(value)
        }
    }
    SettingsRow {
        Layout.fillWidth: true
        title: qsTr("Move windows automatically when the primary display connects")
        supportingText: qsTr(
                            "Move windows and their workspaces from other displays while preserving their arrangement.")
        trailing: StyledSwitch {
            objectName: "primaryDisplayAutoMove"
            checked: PrimaryDisplayService.preferences.autoMove
            enabled: PrimaryDisplayService.ready && !PrimaryDisplayService.busy
            Accessible.name: qsTr("Move windows automatically when the primary display connects")
            onToggled: PrimaryDisplayService.setAutoMove(checked)
        }
    }
    InlineStatusBanner {
        Layout.fillWidth: true
        visible: PrimaryDisplayService.preferences.primary !== null && PrimaryDisplayService.activePrimary
                 === ""
        message: qsTr(
                     "The preferred primary display is disconnected. Use an available display until it reconnects.")
    }
    ActionButton {
        objectName: "primaryDisplayMoveNow"
        text: qsTr("Move windows to the primary display now")
        iconName: "move_group"
        enabled: PrimaryDisplayService.ready && !PrimaryDisplayService.busy
                 && PrimaryDisplayService.activePrimary !== ""
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
