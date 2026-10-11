import QtQuick
import QtQuick.Layouts
import qs.Common
import "../../Common/NetworkProfile.js" as NetworkProfile
import qs.Widgets.common

SettingsSection {
    id: root

    required property string family
    required property var draft
    required property var original
    signal valueEdited(string key, string value)

    readonly property string method: String(draft[family + ".method"] || "auto")
    readonly property bool configurable: ["auto", "manual", "dhcp", "shared"].indexOf(method) >= 0
    readonly property bool automatic: method === "auto" || method === "dhcp"
    readonly property var methodOptions: {
        const options = [
                  {
                      "value": "auto",
                      "label": root.family === "ipv6" ? qsTr("Automatic (SLAAC)") : qsTr("Automatic (DHCP)")
                  },
                  {
                      "value": "manual",
                      "label": qsTr("Manual")
                  },
                  {
                      "value": "link-local",
                      "label": qsTr("Link-local only")
                  },
                  {
                      "value": "disabled",
                      "label": qsTr("Disabled")
                  }
              ];
        if (root.family === "ipv6")
            options.splice(1, 0, {
                               "value": "dhcp",
                               "label": qsTr("DHCP only")
                           });
        if (!options.some(option => option.value === root.method))
            options.push({
                             "value": root.method,
                             "label": qsTr("Current mode: %1").arg(root.method)
                         });
        return options;
    }

    function value(key) {
        return String(root.draft[root.family + "." + key] || "");
    }

    function edit(key, value) {
        if (String(value) !== root.value(key))
            root.valueEdited(root.family + "." + key, String(value));
    }

    function invalid(key) {
        const fullKey = root.family + "." + key;
        const changed = root.original && NetworkProfile.changed(root.original, root.draft, fullKey);
        const manualSelected = key === "addresses" && root.method === "manual" && root.original
              && NetworkProfile.changed(root.original, root.draft, root.family + ".method");
        return (changed || manualSelected) && NetworkProfile.fieldError(fullKey, root.draft[fullKey], root.draft).length
                > 0;
    }

    title: family === "ipv6" ? "IPv6" : "IPv4"
    iconName: "network_manage"
    contentSpacing: Metrics.spacingM

    SettingsRow {
        Layout.fillWidth: true
        title: qsTr("IP assignment")
        trailing: SearchSelectMenuField {
            implicitWidth: 235
            options: root.methodOptions
            value: root.method
            popupBoundsItem: root
            closeOnAccept: true
            onAccepted: value => root.edit("method", value)
        }
    }

    OutlinedTextField {
        Layout.fillWidth: true
        visible: root.configurable
        labelText: qsTr("Addresses / prefix")
        placeholderText: root.family === "ipv6" ? "2001:db8::10/64" : "192.168.1.50/24"
        supportingText: qsTr("Separate multiple addresses with commas; automatic modes may leave this blank.")
        text: root.value("addresses")
        errorText: root.invalid("addresses") ? qsTr("Enter valid addresses with a prefix length") : ""
        onTextChanged: root.edit("addresses", text)
    }

    OutlinedTextField {
        Layout.fillWidth: true
        visible: root.configurable
        enabled: root.value("never-default") !== "yes"
        labelText: qsTr("Gateway")
        text: root.value("gateway")
        errorText: root.invalid("gateway") ? qsTr("Enter a valid gateway address") : ""
        onTextChanged: root.edit("gateway", text)
    }

    SettingsRow {
        Layout.fillWidth: true
        visible: root.automatic
        title: qsTr("Automatic DNS")
        trailing: StyledSwitch {
            checked: root.value("ignore-auto-dns") !== "yes"
            onToggled: root.edit("ignore-auto-dns", checked ? "no" : "yes")
        }
    }

    OutlinedTextField {
        Layout.fillWidth: true
        visible: root.configurable
        labelText: root.automatic && root.value("ignore-auto-dns") !== "yes" ? qsTr("Additional DNS servers") :
                                                                               qsTr("DNS servers")
        supportingText: qsTr("Separate servers with commas.")
        text: root.value("dns")
        errorText: root.invalid("dns") ? qsTr("Enter valid DNS server addresses") : ""
        onTextChanged: root.edit("dns", text)
    }

    SettingsRow {
        Layout.fillWidth: true
        visible: root.configurable
        title: qsTr("Use for internet access")
        trailing: StyledSwitch {
            checked: root.value("never-default") !== "yes"
            onToggled: root.edit("never-default", checked ? "no" : "yes")
        }
    }

    OutlinedTextField {
        Layout.fillWidth: true
        visible: root.configurable
        labelText: qsTr("Route metric")
        supportingText: qsTr(
                            "Lower values take priority; -1 selects automatically. For example: wired 100, Wi-Fi 600.")
        text: root.value("route-metric")
        errorText: root.invalid("route-metric") ? qsTr("Enter -1 or an integer from 0 to 4294967295") : ""
        onTextChanged: root.edit("route-metric", text)
    }
}
