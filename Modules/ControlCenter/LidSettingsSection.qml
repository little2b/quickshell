pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Widgets.common

SettingsSection {
    id: root

    title: qsTr("Laptop lid")
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
    readonly property bool dirty: ready && (batteryAction !== saved.battery || externalAction !== saved.external
                                            || dockedAction !== saved.docked)

    function options(inherit) {
        const items = [
                  {
                      label: qsTr("Do nothing"),
                      value: "ignore",
                      enabled: true
                  },
                  {
                      label: qsTr("Suspend"),
                      value: "suspend",
                      enabled: !!root.capabilities.suspend
                  },
                  {
                      label: qsTr("Hibernate"),
                      value: "hibernate",
                      enabled: !!root.capabilities.hibernate
                  },
                  {
                      label: qsTr("Suspend then hibernate"),
                      value: "suspend-then-hibernate",
                      enabled: !!root.capabilities["suspend-then-hibernate"]
                  }
              ];
        if (inherit)
            items.unshift({
                              label: qsTr("Same as on battery"),
                              value: "",
                              enabled: true
                          });
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
        operation.command = ["/usr/bin/pkexec", "/usr/bin/python3", "-I", Paths.systemScriptsDir
                             + "/lid_settings.py", "apply", JSON.stringify({
                                                                               battery: root.batteryAction,
                                                                               external: root.externalAction,
                                                                               docked: root.dockedAction
                                                                           })];
        operation.running = true;
    }

    Component.onCompleted: refresh()

    InlineStatusBanner {
        Layout.fillWidth: true
        message: root.busy ? (operation.applying ? qsTr("Authenticating and applying lid settings…") : qsTr(
                                                       "Reading lid settings…")) : qsTr(
                                 "Click Apply lid settings after making your selections. Administrator authentication is required, and these settings apply to all desktop sessions.")
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
        message: qsTr(
                     "These applications are handling lid events and may override the system lid policy: %1").arg(
                     root.inhibitors.join("、"))
    }

    SettingsRow {
        Layout.fillWidth: true
        iconName: "battery_std"
        title: qsTr("Lid closed on battery")
        trailing: SearchSelectMenuField {
            objectName: "lidBatteryAction"
            implicitWidth: 210
            enabled: root.ready && !root.busy
            options: root.options(false)
            value: root.batteryAction
            closeOnAccept: true
            Accessible.name: qsTr("Lid action on battery")
            onAccepted: value => root.batteryAction = value
        }
    }

    SettingsRow {
        Layout.fillWidth: true
        iconName: "power"
        title: qsTr("Lid closed on external power")
        trailing: SearchSelectMenuField {
            objectName: "lidExternalAction"
            implicitWidth: 210
            enabled: root.ready && !root.busy
            options: root.options(true)
            value: root.externalAction
            closeOnAccept: true
            Accessible.name: qsTr("Lid action on external power")
            onAccepted: value => root.externalAction = value
        }
    }

    SettingsRow {
        Layout.fillWidth: true
        iconName: "desktop_windows"
        title: qsTr("Lid closed with an external display or dock")
        supportingText: root.docked ? qsTr(
                                          "This scenario is currently active and takes priority over battery and external power settings.") :
                                      qsTr("This scenario takes priority over battery and external power settings.")
        trailing: SearchSelectMenuField {
            objectName: "lidDockedAction"
            implicitWidth: 210
            enabled: root.ready && !root.busy
            options: root.options(false)
            value: root.dockedAction
            closeOnAccept: true
            Accessible.name: qsTr("Lid action with an external display or dock")
            onAccepted: value => root.dockedAction = value
        }
    }

    InlineStatusBanner {
        Layout.fillWidth: true
        message: qsTr(
                     "Niri disables the internal display when the lid closes and restores it when opened. Choose Do nothing to keep using an external display with the lid closed. Keep awake does not control this lid policy.")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.spacingS

        ActionButton {
            objectName: "lidApplyButton"
            text: qsTr("Apply lid settings")
            iconName: "check"
            filled: true
            enabled: root.dirty && !root.busy
            onClicked: root.apply()
        }

        ActionButton {
            text: root.dirty ? qsTr("Discard pending changes") : qsTr("Refresh")
            iconName: "refresh"
            enabled: !root.busy
            onClicked: root.refresh()
        }
    }

    Process {
        id: operation
        property bool applying: false
        stdout: StdioCollector {
            id: response
        }
        stderr: StdioCollector {
            id: diagnostics
        }
        onExited: code => {
            try {
                if (code === 126)
                    throw new Error(qsTr("Authentication was canceled. Lid settings were not changed."));
                const result = JSON.parse(response.text || "{}");
                if (code !== 0 || !result.ok)
                    throw new Error(result.error || diagnostics.text.trim() || qsTr(
                                        "Cannot read or apply lid settings."));
                root.saved = result.values;
                root.batteryAction = result.values.battery;
                root.externalAction = result.values.external;
                root.dockedAction = result.values.docked;
                root.capabilities = result.capabilities;
                root.inhibitors = result.inhibitors;
                root.docked = result.docked;
                root.ready = true;
                if (operation.applying)
                    root.message = qsTr(
                                "Lid settings have been saved and applied. No logout or restart is required. ");
            } catch (exception) {
                root.error = String(exception.message || exception);
            }
        }
    }
}
