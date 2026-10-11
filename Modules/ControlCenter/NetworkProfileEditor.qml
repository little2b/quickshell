import QtQuick
import QtQuick.Layouts
import qs.Common
import "../../Common/NetworkProfile.js" as NetworkProfile
import qs.Services
import qs.Widgets.common

ColumnLayout {
    id: root

    property var target: null
    readonly property bool isWired: target && target.type === "wired"
    property bool profileRemoved: false
    readonly property var profile: {
        if (!target || profileRemoved)
            return null;

        if (target.nativeSettings) {
            const profiles = isWired ? NetworkService.wiredProfiles : NetworkService.savedWifiProfiles;
            return profiles.find(item => {
                return item.uuid === target.uuid;
            }) || null;
        }
        const currentNetwork = !isWired ? NetworkService.allWifiNetworks.find(item => {
            return item.deviceName === target.deviceName && item.ssid === target.ssid;
        }) : null;
        const currentProfiles = currentNetwork ? currentNetwork.profiles : target.profiles;
        if (currentProfiles && currentProfiles.length > 0)
            return currentProfiles[0];

        if (isWired) {
            const interfaceName = String(target.deviceName || target.name || "");
            for (const wiredProfile of NetworkService.wiredProfiles) {
                if (wiredProfile.deviceName === interfaceName)
                    return wiredProfile;
            }
        }
        return null;
    }
    readonly property var nativeNetwork: target && target.nativeNetwork ? target.nativeNetwork : profile
                                                                          ? profile.nativeNetwork : null
    readonly property bool connectionIsActive: !!(nativeNetwork && nativeNetwork.connected)
    readonly property var wiredDevice: isWired && profile ? NetworkService.wiredDevices.find(device => {
        return device.deviceName === profile.deviceName;
    }) || null : null
    property var original: null
    property var draft: ({})
    property string loadedProfileUuid: ""
    property bool loading: false
    property bool saving: false
    property string errorMessage: ""
    property string successMessage: ""
    readonly property bool dirty: NetworkProfile.dirty(original, draft)
    readonly property bool formValid: original !== null && NetworkProfile.validation(original, draft).length
                                      === 0

    signal profileForgotten

    function edit(key, value) {
        if (!root.original || String(root.draft[key]) === String(value))
            return;
        root.draft = NetworkProfile.withValue(root.draft, key, value);
        root.successMessage = "";
    }

    function resetEditor() {
        const uuid = String(root.profile ? root.profile.uuid || "" : "");
        if (root.saving || (root.loading && uuid === root.loadedProfileUuid))
            return;
        root.original = null;
        root.draft = ({});
        root.errorMessage = "";
        root.successMessage = "";
        root.loadedProfileUuid = uuid;
        root.loading = uuid.length > 0;
        if (root.loading)
            NetworkService.requestProfileDetails(root.profile);
    }

    function discardChanges() {
        root.draft = Object.assign({}, root.original);
        root.errorMessage = "";
        root.successMessage = "";
    }

    spacing: Metrics.spacingM
    onTargetChanged: {
        root.profileRemoved = false;
        root.resetEditor();
    }
    onProfileChanged: {
        const uuid = String(root.profile ? root.profile.uuid || "" : "");
        if (uuid !== root.loadedProfileUuid)
            root.resetEditor();
    }
    Component.onCompleted: root.resetEditor()

    Connections {
        target: NetworkService

        function onProfileLoaded(uuid, snapshot) {
            if (uuid !== root.loadedProfileUuid)
                return;
            root.original = snapshot;
            root.draft = Object.assign({}, snapshot);
            root.loading = false;
        }

        function onProfileLoadFailed(uuid, message) {
            if (uuid !== root.loadedProfileUuid)
                return;
            root.loading = false;
            root.errorMessage = message;
        }

        function onProfileWriteSucceeded(uuid) {
            if (uuid !== root.loadedProfileUuid)
                return;
            root.saving = false;
            root.errorMessage = "";
            root.successMessage = root.connectionIsActive ? qsTr(
                                                                "Saved. Reconnect to apply the new network settings.") :
                                                            qsTr("Profile saved");
        }

        function onProfileWriteFailed(uuid, message) {
            if (uuid !== root.loadedProfileUuid)
                return;
            root.saving = false;
            root.errorMessage = message;
        }

        function onProfileForgetSucceeded(uuid) {
            if (!root.target || uuid !== String(root.target.uuid || ""))
                return;
            root.profileRemoved = true;
            root.profileForgotten();
        }

        function onProfileForgetFailed(uuid, message) {
            if (uuid === root.loadedProfileUuid)
                root.errorMessage = message;
        }
    }

    StyledFlickable {
        id: formScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + Metrics.spacingM * 2

        ColumnLayout {
            id: contentColumn
            width: Math.max(0, formScroll.width - Metrics.spacingS * 2)
            x: Metrics.spacingS
            y: Metrics.spacingM
            spacing: Metrics.spacingL

            InlineStatusBanner {
                Layout.fillWidth: true
                visible: root.errorMessage.length > 0
                tone: "error"
                message: root.errorMessage
            }

            InlineStatusBanner {
                Layout.fillWidth: true
                visible: root.successMessage.length > 0
                tone: "info"
                iconName: "check_circle"
                message: root.successMessage
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spacingS

                ActionButton {
                    visible: root.connectionIsActive
                    text: qsTr("Disconnect")
                    iconName: "link_off"
                    enabled: !NetworkService.busy && !root.saving
                    onClicked: NetworkService.disconnectNetwork(root.target)
                }

                ActionButton {
                    visible: root.nativeNetwork && !root.connectionIsActive
                    text: qsTr("Connect")
                    iconName: "link"
                    enabled: !NetworkService.busy && !root.saving && (!root.isWired || root.wiredDevice
                                                                      && root.wiredDevice.hasLink)
                    onClicked: NetworkService.connectProfile(root.profile)
                }

                ActionButton {
                    visible: root.profile !== null && !root.isWired
                    text: qsTr("Forget")
                    iconName: "delete"
                    enabled: !NetworkService.busy && !root.saving
                    onClicked: NetworkService.forgetProfile(root.profile)
                }

                Item {
                    Layout.fillWidth: true
                }

                ActionButton {
                    text: qsTr("Reload")
                    iconName: "refresh"
                    enabled: !root.loading && !root.saving && !NetworkService.busy && !root.dirty
                    onClicked: root.resetEditor()
                    InlineBusyIndicator {
                        anchors.right: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        busy: root.loading
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                enabled: root.original !== null && !root.loading && !root.saving
                spacing: Metrics.spacingL

                SettingsSection {
                    Layout.fillWidth: true
                    title: qsTr("Connection")
                    iconName: root.isWired ? "lan" : "wifi"
                    contentSpacing: Metrics.spacingM

                    OutlinedTextField {
                        Layout.fillWidth: true
                        labelText: qsTr("Profile name")
                        text: String(root.draft["connection.id"] || "")
                        errorText: root.original && NetworkProfile.fieldError("connection.id", text,
                                                                              root.draft) ? qsTr(
                                                                                                "Enter a connection name") :
                                                                                            ""
                        onTextChanged: root.edit("connection.id", text)
                    }

                    SettingsRow {
                        Layout.fillWidth: true
                        title: qsTr("Interface")
                        supportingText: root.profile ? root.profile.deviceName : "—"
                    }

                    SettingsRow {
                        Layout.fillWidth: true
                        title: qsTr("Connect automatically")
                        trailing: StyledSwitch {
                            checked: root.draft["connection.autoconnect"] === "yes"
                            onToggled: root.edit("connection.autoconnect", checked ? "yes" : "no")
                        }
                    }

                    OutlinedTextField {
                        Layout.fillWidth: true
                        enabled: root.draft["connection.autoconnect"] === "yes"
                        labelText: qsTr("Auto-connect priority")
                        supportingText: qsTr(
                                            "Higher values are preferred when choosing a connection on the same device (-999 to 999).")
                        text: String(root.draft["connection.autoconnect-priority"] || "0")
                        errorText: root.original && NetworkProfile.fieldError(
                                       "connection.autoconnect-priority", text, root.draft) ? qsTr(
                                                                                                  "Enter an integer from -999 to 999") :
                                                                                              ""
                        onTextChanged: root.edit("connection.autoconnect-priority", text)
                    }
                }

                NetworkIpSettings {
                    Layout.fillWidth: true
                    family: "ipv4"
                    original: root.original
                    draft: root.draft
                    onValueEdited: (key, value) => root.edit(key, value)
                }

                NetworkIpSettings {
                    Layout.fillWidth: true
                    family: "ipv6"
                    original: root.original
                    draft: root.draft
                    onValueEdited: (key, value) => root.edit(key, value)
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.spacingS

        ActionButton {
            text: qsTr("Reset changes")
            iconName: "undo"
            enabled: root.dirty && !root.saving
            onClicked: root.discardChanges()
        }

        Item {
            Layout.fillWidth: true
        }

        ActionButton {
            text: qsTr("Apply")
            iconName: "save"
            filled: true
            enabled: root.dirty && root.formValid && !root.saving && !root.loading && !NetworkService.busy
            onClicked: {
                root.errorMessage = "";
                root.successMessage = "";
                root.saving = true;
                NetworkService.writeProfile(root.profile, root.original, root.draft);
            }
            InlineBusyIndicator {
                anchors.right: parent.left
                anchors.rightMargin: Metrics.spacingS
                anchors.verticalCenter: parent.verticalCenter
                busy: root.saving
            }
        }
    }
}
