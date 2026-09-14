import QtQuick

// Keep delegates alive when NetworkManager publishes a new scan snapshot.
ListModel {
    id: root

    property var sourceItems: []
    property var keyFields: ["deviceName", "ssid"]
    property bool holdStructure: false
    dynamicRoles: true

    function itemKey(item) {
        return JSON.stringify(keyFields.map(field => String(item[field] || "")));
    }

    function synchronize() {
        const items = sourceItems || [];
        const byKey = new Map();
        for (const item of items)
            byKey.set(itemKey(item), item);

        // During password entry, update signal/state in place but defer adds,
        // removals and reordering, including temporarily missing access points.
        if (holdStructure && count > 0) {
            for (let i = 0; i < count; ++i) {
                const item = byKey.get(get(i).rowKey);
                if (item !== undefined)
                    setProperty(i, "entry", item);
            }
            return;
        }

        for (let i = count - 1; i >= 0; --i) {
            if (!byKey.has(get(i).rowKey))
                remove(i);
        }
        let destination = 0;
        for (const [key, item] of byKey) {
            let source = destination;
            while (source < count && get(source).rowKey !== key)
                ++source;
            if (source === count)
                insert(destination, {rowKey: key, entry: item});
            else {
                if (source !== destination)
                    move(source, destination, 1);
                setProperty(destination, "entry", item);
            }
            ++destination;
        }
    }

    onSourceItemsChanged: Qt.callLater(synchronize)
    onHoldStructureChanged: Qt.callLater(synchronize)
    Component.onCompleted: Qt.callLater(synchronize)
}
