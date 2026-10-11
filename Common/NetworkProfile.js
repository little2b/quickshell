.pragma library

// Only these non-secret properties are read or edited. nmcli handles D-Bus types.
var fields = ["connection.id", "connection.autoconnect", "connection.autoconnect-priority"];
var ipKeys = ["method", "addresses", "gateway", "dns", "ignore-auto-dns", "route-metric", "never-default"];
for (var family of ["ipv4", "ipv6"])
    for (var key of ipKeys)
        fields.push(family + "." + key);

function splitList(value) {
    return String(value || "").trim().split(/[\s,]+/).filter(function(item) { return item.length > 0; });
}

function ipv4(value) {
    var parts = String(value).split(".");
    return parts.length === 4 && parts.every(function(part) {
        return /^(0|[1-9]\d{0,2})$/.test(part) && Number(part) <= 255;
    });
}

function ipv6(value) {
    var text = String(value).toLowerCase();
    if (text.indexOf(":") < 0 || /[^0-9a-f:.]/.test(text))
        return false;
    if (text.indexOf(".") >= 0) {
        var end = text.lastIndexOf(":");
        if (!ipv4(text.slice(end + 1)))
            return false;
        text = text.slice(0, end + 1) + "0:0";
    }
    var halves = text.split("::");
    if (halves.length > 2)
        return false;
    var groups = halves[0] ? halves[0].split(":") : [];
    if (halves.length === 2 && halves[1])
        groups = groups.concat(halves[1].split(":"));
    return groups.every(function(group) { return /^[0-9a-f]{1,4}$/.test(group); })
            && (halves.length === 2 ? groups.length < 8 : groups.length === 8);
}

function addressValid(value, family) {
    return family === "ipv6" ? ipv6(value) : ipv4(value);
}

function cidrValid(value, family) {
    var parts = String(value).split("/");
    return parts.length === 2 && addressValid(parts[0], family) && /^\d{1,3}$/.test(parts[1])
            && Number(parts[1]) <= (family === "ipv6" ? 128 : 32);
}

function integerValid(value, minimum, maximum) {
    return /^-?\d+$/.test(String(value)) && Number(value) >= minimum && Number(value) <= maximum;
}

function parse(text) {
    var result = {};
    for (var line of String(text).split("\n")) {
        var separator = line.indexOf(":");
        if (separator < 0)
            continue;
        var key = line.slice(0, separator);
        if (fields.indexOf(key) >= 0)
            result[key] = line.slice(separator + 1).replace(/\\([\\:])/g, "$1");
    }
    // An incomplete read must never be mistaken for default values.
    if (!fields.every(function(key) { return result[key] !== undefined; }))
        return null;
    return result;
}

function canonicalAddress(value) {
    var parts = String(value).split("/");
    var address = parts[0].toLowerCase();
    if (ipv6(address)) {
        if (address.indexOf(".") >= 0) {
            var colon = address.lastIndexOf(":");
            var bytes = address.slice(colon + 1).split(".").map(Number);
            address = address.slice(0, colon + 1) + (bytes[0] * 256 + bytes[1]).toString(16)
                    + ":" + (bytes[2] * 256 + bytes[3]).toString(16);
        }
        var halves = address.split("::");
        var left = halves[0] ? halves[0].split(":") : [];
        var right = halves.length > 1 && halves[1] ? halves[1].split(":") : [];
        if (halves.length > 1)
            while (left.length + right.length < 8)
                left.push("0");
        address = left.concat(right).map(function(group) { return parseInt(group, 16).toString(16); }).join(":");
    }
    return address + (parts.length === 2 ? "/" + Number(parts[1]) : "");
}

function normalized(key, value) {
    var text = String(value === undefined ? "" : value).trim();
    if (/\.(addresses|dns)$/.test(key))
        return splitList(text).map(canonicalAddress).join(",");
    if (/\.gateway$/.test(key))
        return canonicalAddress(text);
    if (/\.(route-metric|autoconnect-priority)$/.test(key) && /^-?\d+$/.test(text))
        return String(Number(text));
    return text;
}

function changed(original, draft, key) {
    return normalized(key, original[key]) !== normalized(key, draft[key]);
}

function dirty(original, draft) {
    return !!original && fields.some(function(key) { return changed(original, draft, key); });
}

function fieldError(key, value, draft) {
    var text = String(value === undefined ? "" : value).trim();
    if (key === "connection.id")
        return text.length === 0 ? "name" : "";
    if (key === "connection.autoconnect-priority")
        return integerValid(text, -999, 999) ? "" : "priority";
    var family = key.split(".")[0];
    var property = key.slice(family.length + 1);
    if (family !== "ipv4" && family !== "ipv6")
        return "";
    if (property === "route-metric")
        return integerValid(text, -1, 4294967295) ? "" : "metric";
    if (property === "addresses") {
        var addresses = splitList(text);
        return (draft[family + ".method"] !== "manual" || addresses.length > 0)
                && addresses.every(function(item) { return cidrValid(item, family); }) ? "" : "address";
    }
    if (property === "gateway")
        return !text || addressValid(text, family) ? "" : "gateway";
    if (property === "dns")
        return splitList(text).every(function(item) { return addressValid(item, family); }) ? "" : "dns";
    return "";
}

function validation(original, draft) {
    if (!original)
        return "unavailable";
    for (var key of fields) {
        if (changed(original, draft, key) && fieldError(key, draft[key], draft))
            return key;
    }
    for (var family of ["ipv4", "ipv6"]) {
        if (changed(original, draft, family + ".method") && draft[family + ".method"] === "manual"
                && fieldError(family + ".addresses", draft[family + ".addresses"], draft))
            return family + ".addresses";
    }
    return "";
}

function withValue(draft, key, value) {
    var next = Object.assign({}, draft);
    next[key] = String(value);
    var family = key.split(".")[0];
    if (key === family + ".method" && (value === "disabled" || value === "ignore" || value === "link-local")) {
        for (var property of ["addresses", "gateway", "dns"])
            next[family + "." + property] = "";
        next[family + ".ignore-auto-dns"] = "no";
    }
    if (key === family + ".never-default" && value === "yes")
        next[family + ".gateway"] = "";
    return next;
}

// Read again before writing. Reject edits to fields changed by another editor,
// while keeping unrelated properties (including extra routes/addresses) intact.
function prepare(original, current, draft) {
    var invalid = validation(original, draft);
    if (invalid)
        return { error: "invalid", field: invalid, args: [] };
    if (!current)
        return { error: "unavailable", args: [] };
    var args = [];
    var expected = {};
    for (var key of fields) {
        if (!changed(original, draft, key))
            continue;
        if (changed(original, current, key) && changed(current, draft, key))
            return { error: "conflict", field: key, args: [] };
        // A changed IP method can invalidate otherwise untouched IP fields.
        var family = key.split(".")[0];
        if ((family === "ipv4" || family === "ipv6") && changed(original, current, family + ".method")
                && changed(current, draft, family + ".method"))
            return { error: "conflict", field: family + ".method", args: [] };
        var value = normalized(key, draft[key]);
        args.push(key, value);
        expected[key] = value;
    }
    return { error: "", args: args, expected: expected };
}

function matches(actual, expected) {
    return !!actual && Object.keys(expected).every(function(key) {
        return normalized(key, actual[key]) === normalized(key, expected[key]);
    });
}
