import QtQuick
import QtTest
import "../../Common/NetworkProfile.js" as Profile

TestCase {
    name: "NetworkProfile"

    function fixture() {
        const result = {
            "connection.id": "Office",
            "connection.autoconnect": "yes",
            "connection.autoconnect-priority": "-999"
        };
        for (const family of ["ipv4", "ipv6"]) {
            result[family + ".method"] = "auto";
            result[family + ".addresses"] = "";
            result[family + ".gateway"] = "";
            result[family + ".dns"] = "";
            result[family + ".ignore-auto-dns"] = "no";
            result[family + ".route-metric"] = "-1";
            result[family + ".never-default"] = "no";
        }
        return result;
    }

    function test_addressValidation_data() {
        return [
                    {
                        tag: "v4",
                        family: "ipv4",
                        address: "192.168.2.10/24",
                        valid: true
                    },
                    {
                        tag: "v4-range",
                        family: "ipv4",
                        address: "192.168.2.256/24",
                        valid: false
                    },
                    {
                        tag: "v4-prefix",
                        family: "ipv4",
                        address: "192.168.2.10/33",
                        valid: false
                    },
                    {
                        tag: "v6",
                        family: "ipv6",
                        address: "2001:db8::10/64",
                        valid: true
                    },
                    {
                        tag: "v6-full",
                        family: "ipv6",
                        address: "2001:db8:1:2:3:4:5:6/128",
                        valid: true
                    },
                    {
                        tag: "v6-mapped",
                        family: "ipv6",
                        address: "::ffff:192.0.2.1/128",
                        valid: true
                    },
                    {
                        tag: "v6-double",
                        family: "ipv6",
                        address: "2001::db8::1/64",
                        valid: false
                    },
                    {
                        tag: "v6-too-many",
                        family: "ipv6",
                        address: "1:2:3:4:5:6:7:8::/64",
                        valid: false
                    },
                    {
                        tag: "v6-prefix",
                        family: "ipv6",
                        address: "::1/129",
                        valid: false
                    },
                    {
                        tag: "wrong-family",
                        family: "ipv4",
                        address: "2001:db8::1/64",
                        valid: false
                    }
                ];
    }

    function test_addressValidation(data) {
        compare(Profile.cidrValid(data.address, data.family), data.valid);
    }

    function test_parseEscapedOutputAndRejectIncompleteRead() {
        const original = fixture();
        original["connection.id"] = "Lab: wired\\backup";
        original["ipv6.dns"] = "2606:4700:4700::1111";
        const output = Profile.fields.map(key => key + ":" + original[key].replace(/\\/g, "\\\\").replace(/:/g,
                                                                                                          "\\:")).join(
                  "\n");
        compare(Profile.parse(output), original);
        compare(Profile.parse("connection.id:Lab\n"), null);
    }

    function test_dnsEditPreservesMultipleAddressesAndOtherFamily() {
        const original = fixture();
        original["ipv4.method"] = "manual";
        original["ipv4.addresses"] = "192.0.2.5/24, 192.0.2.6/24";
        original["ipv4.gateway"] = "192.0.2.1";
        original["ipv6.method"] = "dhcp";
        const draft = Profile.withValue(original, "ipv4.dns", "1.1.1.1, 9.9.9.9");
        const plan = Profile.prepare(original, original, draft);
        compare(plan.error, "");
        compare(plan.args, ["ipv4.dns", "1.1.1.1,9.9.9.9"]);
        compare(original["ipv4.addresses"], "192.0.2.5/24, 192.0.2.6/24");
    }

    function test_prioritiesAreIndependent() {
        const original = fixture();
        let draft = Profile.withValue(original, "ipv4.route-metric", "100");
        draft = Profile.withValue(draft, "ipv6.route-metric", "100");
        const plan = Profile.prepare(original, original, draft);
        compare(plan.args, ["ipv4.route-metric", "100", "ipv6.route-metric", "100"]);
        compare(plan.expected["connection.autoconnect-priority"], undefined);
        verify(Profile.integerValid("-999", -999, 999));
        verify(!Profile.integerValid("1000", -999, 999));
        verify(!Profile.integerValid("-2", -1, 4294967295));
    }

    function test_conflictingEditsFailButUnrelatedChangesSurvive() {
        const original = fixture();
        const draft = Profile.withValue(original, "ipv4.dns", "1.1.1.1");
        const current = Profile.withValue(original, "ipv4.dns", "9.9.9.9");
        compare(Profile.prepare(original, current, draft).error, "conflict");
        const renamed = Profile.withValue(original, "connection.id", "New name");
        compare(Profile.prepare(original, renamed, draft).args, ["ipv4.dns", "1.1.1.1"]);
    }

    function test_manualRequiresAddressAndDisabledClearsOnlyIpValues() {
        const original = fixture();
        const draft = Profile.withValue(original, "ipv6.method", "manual");
        compare(Profile.prepare(original, original, draft).error, "invalid");
        original["ipv6.addresses"] = "2001:db8::10/64";
        original["ipv6.gateway"] = "2001:db8::1";
        original["ipv6.dns"] = "2001:db8::53";
        original["ipv6.route-metric"] = "123";
        const disabled = Profile.withValue(original, "ipv6.method", "disabled");
        compare(disabled["ipv6.addresses"], "");
        compare(disabled["ipv6.gateway"], "");
        compare(disabled["ipv6.dns"], "");
        compare(disabled["ipv6.route-metric"], "123");
        compare(disabled["ipv4.method"], "auto");
    }

    function test_ipv6ReadbackAcceptsEquivalentSpellings() {
        const expected = {
            "ipv6.addresses": "2001:0DB8:0:0:0:0:0:10/064",
            "ipv6.dns": "2001:db8:0:0::53"
        };
        verify(Profile.matches({
                                   "ipv6.addresses": "2001:db8::10/64",
                                   "ipv6.dns": "2001:db8::53"
                               }, expected));
        verify(!Profile.matches({
                                    "ipv6.addresses": "2001:db8::11/64",
                                    "ipv6.dns": "2001:db8::53"
                                }, expected));
    }

    function test_untouchedAdvancedDnsIsNotRewritten() {
        const original = fixture();
        original["ipv6.dns"] = "dns+tls://[2001:db8::53]#resolver.example";
        const draft = Profile.withValue(original, "connection.autoconnect-priority", "100");
        compare(Profile.prepare(original, original, draft).args, ["connection.autoconnect-priority", "100"]);
    }
}
