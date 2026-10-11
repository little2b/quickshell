pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Common/NetworkProfile.js" as NetworkProfile

Singleton {
    id: root

    readonly property bool runtimeBusy: runtimeProcess.running || frequencyProcess.running
    readonly property bool mutationBusy: profileWriteProcess.running || _profilePhase === "preflight"
                                         || _profilePhase === "verify" || addProcess.running
                                         || activateProcess.running || cleanupProcess.running
    readonly property bool busy: runtimeBusy || mutationBusy || profileReadProcess.running
    property string lastError: ""
    property string _runtimeInterface: ""
    property bool _runtimeIsWifi: false
    property var _runtimeCallback: null
    property var _runtimeDetails: null
    property bool _runtimeStarted: false
    property bool _frequencyStarted: false
    property var _addCallback: null
    property string _connectionName: ""
    property string _ssid: ""
    property string _password: ""
    property bool _secure: false
    property bool _addStarted: false
    property bool _activateStarted: false

    property string _profileUuid: ""
    property string _profilePhase: ""
    property var _profileCallback: null
    property var _profileOriginal: null
    property var _profileDraft: null
    property var _profileExpected: ({})
    property bool _profileReadStarted: false
    property bool _profileWriteStarted: false

    function readProfile(uuid, callback) {
        return root._beginProfile(uuid, null, null, callback);
    }

    function writeProfile(uuid, original, draft, callback) {
        return root._beginProfile(uuid, original, draft, callback);
    }

    function _beginProfile(uuid, original, draft, callback) {
        if (root.mutationBusy || profileReadProcess.running || String(uuid || "").length === 0) {
            callback(false, null, qsTr("Another network operation is in progress"));
            return false;
        }
        root._profileUuid = String(uuid);
        root._profileOriginal = original;
        root._profileDraft = draft;
        root._profileCallback = callback;
        root._profilePhase = original ? "preflight" : "read";
        root._readProfile();
        return true;
    }

    function _readProfile() {
        root._profileReadStarted = false;
        profileReadProcess.command = ["env", "LC_ALL=C", "nmcli", "--wait", "15", "-t", "-e", "yes", "-f",
                                      NetworkProfile.fields.join(","), "connection", "show", "uuid",
                                      root._profileUuid];
        profileReadProcess.running = true;
    }

    function _finishProfile(success, snapshot, message) {
        const callback = root._profileCallback;
        root._profileCallback = null;
        root._profilePhase = "";
        root._profileUuid = "";
        root._profileOriginal = null;
        root._profileDraft = null;
        root._profileExpected = ({});
        if (callback)
            callback(success, snapshot, message);
    }

    Process {
        id: profileReadProcess
        onStarted: root._profileReadStarted = true
        onRunningChanged: {
            if (!running && !root._profileReadStarted && root._profileCallback)
                root._finishProfile(false, null, qsTr("Unable to start the network configuration tool"));
        }
        onExited: exitCode => {
            if (!root._profileCallback)
                return;
            if (exitCode !== 0) {
                root._finishProfile(false, null, root._error(profileReadError.text, qsTr(
                                                                 "Unable to read connection settings")));
                return;
            }
            const snapshot = NetworkProfile.parse(profileReadOutput.text);
            if (!snapshot) {
                root._finishProfile(false, null, qsTr("The connection settings response is incomplete"));
                return;
            }
            if (root._profilePhase === "preflight") {
                const plan = NetworkProfile.prepare(root._profileOriginal, snapshot, root._profileDraft);
                if (plan.error) {
                    root._finishProfile(false, null, plan.error === "conflict" ? qsTr(
                                                                                     "This connection was changed elsewhere. Reload it before saving.") :
                                                                                 qsTr("Check the connection settings before saving"));
                    return;
                }
                if (plan.args.length === 0) {
                    root._finishProfile(true, snapshot, "");
                    return;
                }
                root._profileExpected = plan.expected;
                root._profilePhase = "write";
                root._profileWriteStarted = false;
                profileWriteProcess.command = ["nmcli", "--wait", "15", "connection", "modify", "uuid",
                                               root._profileUuid].concat(plan.args);
                profileWriteProcess.running = true;
            } else if (root._profilePhase === "verify" && !NetworkProfile.matches(snapshot,
                                                                                  root._profileExpected)) {
                root._finishProfile(false, snapshot, qsTr(
                                        "The saved settings differ from the requested values. Reload this connection to review them."));
            } else {
                root._finishProfile(true, snapshot, "");
            }
        }
        stdout: StdioCollector {
            id: profileReadOutput
        }
        stderr: StdioCollector {
            id: profileReadError
        }
    }

    Process {
        id: profileWriteProcess
        onStarted: root._profileWriteStarted = true
        onRunningChanged: {
            if (!running && !root._profileWriteStarted && root._profileCallback)
                root._finishProfile(false, null, qsTr("Unable to start the network configuration tool"));
        }
        onExited: exitCode => {
            if (!root._profileCallback)
                return;
            if (exitCode !== 0) {
                root._finishProfile(false, null, root._error(profileWriteError.text, qsTr(
                                                                 "Unable to save connection settings")));
                return;
            }
            root._profilePhase = "verify";
            root._readProfile();
        }
        stderr: StdioCollector {
            id: profileWriteError
        }
    }

    function _unescape(value) {
        return String(value || "").replace(/\\:/g, ":").replace(/\\\\/g, "\\");
    }

    function _error(stderrText, fallback) {
        const message = String(stderrText || "").trim();
        return message.length > 0 ? message : fallback;
    }

    function queryRuntimeDetails(interfaceName, isWifi, callback) {
        if (root.busy || String(interfaceName || "").length === 0) {
            if (callback)
                callback(false, {}, qsTr("Network details are currently unavailable"));

            return false;
        }
        root.lastError = "";
        root._runtimeInterface = String(interfaceName);
        root._runtimeIsWifi = !!isWifi;
        root._runtimeCallback = callback;
        root._runtimeDetails = null;
        root._runtimeStarted = false;
        runtimeProcess.command = ["nmcli", "-t", "-e", "yes", "-f",
                                  "GENERAL.CONNECTION,GENERAL.CON-UUID,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,IP6.GATEWAY,IP6.DNS",
                                  "device", "show", root._runtimeInterface];
        runtimeProcess.running = true;
        return true;
    }

    function cancelRuntimeDetails() {
        root._runtimeCallback = null;
        root._runtimeDetails = null;
        root._runtimeStarted = false;
        root._frequencyStarted = false;
        runtimeProcess.running = false;
        frequencyProcess.running = false;
        runtimeProcess.command = [];
        frequencyProcess.command = [];
    }

    function createHiddenWifi(ssid, hidden, secure, password, callback) {
        if (root.busy) {
            if (callback)
                callback(false, null, qsTr("Another supplementary network operation is already in progress"));

            return false;
        }
        root.lastError = "";
        root._ssid = String(ssid || "").trim();
        root._connectionName = "Clavis Wi-Fi " + Date.now();
        root._secure = !!secure;
        root._password = root._secure ? String(password || "") : "";
        root._addCallback = callback;
        root._addStarted = false;
        const args = ["nmcli", "--wait", "30", "connection", "add", "type", "wifi", "con-name", root._connectionName,
                      "ifname", "*", "ssid", root._ssid, "--", "802-11-wireless.hidden", hidden ? "yes" :
                                                                                                  "no"];
        if (root._secure)
            args.push("802-11-wireless-security.key-mgmt", "wpa-psk");

        addProcess.command = args;
        addProcess.running = true;
        return true;
    }

    function _finishAdd(success, errorMessage) {
        const callback = root._addCallback;
        const result = success ? ({
                                      "id": root._connectionName,
                                      "ssid": root._ssid
                                  }) : null;
        root.lastError = success ? "" : String(errorMessage || qsTr("Unable to create Wi-Fi profile"));
        root._addCallback = null;
        root._password = "";
        root._secure = false;
        addProcess.command = [];
        activateProcess.command = [];
        if (callback)
            callback(success, result, root.lastError);
    }

    function _cleanupAdd(errorMessage) {
        cleanupProcess.command = ["nmcli", "--wait", "15", "connection", "delete", "id",
                                  root._connectionName];
        cleanupProcess.running = true;
        root._finishAdd(false, errorMessage);
    }

    Process {
        id: runtimeProcess

        onStarted: root._runtimeStarted = true
        onRunningChanged: {
            if (!running && !root._runtimeStarted && root._runtimeCallback) {
                const callback = root._runtimeCallback;
                root._runtimeCallback = null;
                root.lastError = qsTr("nmcli is unavailable; active IP information cannot be read");
                callback(false, {}, root.lastError);
            }
        }
        onExited: exitCode => {
            const callback = root._runtimeCallback;
            if (!callback)
                return;

            if (exitCode !== 0) {
                root._runtimeCallback = null;
                root.lastError = root._error(runtimeError.text, qsTr("Unable to read active IP information"));
                callback(false, {}, root.lastError);
                return;
            }
            const details = ({
                                 "interfaceName": root._runtimeInterface,
                                 "connectionName": "",
                                 "connectionUuid": "",
                                 "addresses": [],
                                 "gateway": "",
                                 "dns": [],
                                 "ipv6Addresses": [],
                                 "ipv6Gateway": "",
                                 "ipv6Dns": []
                             });
            for (const rawLine of String(runtimeOutput.text || "").trim().split("\n")) {
                const separator = rawLine.indexOf(":");
                if (separator < 0)
                    continue;

                const key = rawLine.substring(0, separator);
                const value = root._unescape(rawLine.substring(separator + 1));
                if (key === "GENERAL.CONNECTION")
                    details.connectionName = value;
                else if (key === "GENERAL.CON-UUID")
                    details.connectionUuid = value;
                else if (key.startsWith("IP4.ADDRESS"))
                    details.addresses.push(value);
                else if (key === "IP4.GATEWAY")
                    details.gateway = value;
                else if (key.startsWith("IP4.DNS"))
                    details.dns.push(value);
                else if (key.startsWith("IP6.ADDRESS"))
                    details.ipv6Addresses.push(value);
                else if (key === "IP6.GATEWAY")
                    details.ipv6Gateway = value;
                else if (key.startsWith("IP6.DNS"))
                    details.ipv6Dns.push(value);
            }
            if (root._runtimeIsWifi) {
                root._runtimeDetails = details;
                root._frequencyStarted = false;
                frequencyProcess.command = ["nmcli", "-t", "-e", "yes", "-f", "IN-USE,FREQ", "device", "wifi",
                                            "list", "ifname", root._runtimeInterface];
                frequencyProcess.running = true;
            } else {
                root._runtimeCallback = null;
                root.lastError = "";
                callback(true, details, "");
            }
        }

        stdout: StdioCollector {
            id: runtimeOutput
        }

        stderr: StdioCollector {
            id: runtimeError
        }
    }

    Process {
        id: frequencyProcess

        onStarted: root._frequencyStarted = true
        onRunningChanged: {
            if (!running && !root._frequencyStarted && root._runtimeCallback) {
                const callback = root._runtimeCallback;
                const details = root._runtimeDetails || {};
                root._runtimeCallback = null;
                root._runtimeDetails = null;
                callback(true, details, "");
            }
        }
        onExited: exitCode => {
            const callback = root._runtimeCallback;
            root._runtimeCallback = null;
            const details = root._runtimeDetails || {};
            root._runtimeDetails = null;
            if (exitCode === 0) {
                for (const line of String(frequencyOutput.text || "").trim().split("\n")) {
                    const separator = line.indexOf(":");
                    if (separator < 0 || line.substring(0, separator) !== "*")
                        continue;

                    details.frequency = root._unescape(line.substring(separator + 1));
                    break;
                }
            }
            root.lastError = "";
            if (callback)
                callback(true, details, "");
        }

        stdout: StdioCollector {
            id: frequencyOutput
        }
    }

    Process {
        id: addProcess

        onStarted: root._addStarted = true
        onRunningChanged: {
            if (!running && !root._addStarted && root._addCallback)
                root._finishAdd(false, qsTr(
                                    "nmcli is unavailable; a hidden network profile cannot be created"));
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root._finishAdd(false, root._error(addError.text, qsTr("Unable to create Wi-Fi profile")));
                return;
            }
            root._activateStarted = false;
            activateProcess.command = root._secure ? ["nmcli", "--ask", "--wait", "60", "connection", "up", "id",
                                                      root._connectionName] : ["nmcli", "--wait", "60",
                                                                               "connection", "up", "id",
                                                                               root._connectionName];
            activateProcess.running = true;
        }

        stderr: StdioCollector {
            id: addError
        }
    }

    Process {
        id: activateProcess

        stdinEnabled: true
        onStarted: {
            root._activateStarted = true;
            if (root._secure) {
                const secret = root._password;
                root._password = "";
                activateProcess.write(secret + "\n");
            }
        }
        onRunningChanged: {
            if (!running && !root._activateStarted && root._addCallback)
                root._cleanupAdd(qsTr(
                                     "nmcli is unavailable; the hidden network profile cannot be activated"));
        }
        onExited: exitCode => {
            root._password = "";
            if (exitCode === 0)
                root._finishAdd(true, "");
            else
                root._cleanupAdd(root._error(activateError.text, qsTr(
                                                 "The Wi-Fi profile was created but could not be activated")));
        }

        stdout: StdioCollector {}

        stderr: StdioCollector {
            id: activateError
        }
    }

    Process {
        id: cleanupProcess
    }
}
