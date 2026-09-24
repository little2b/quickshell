.pragma library

function app(id) {
    return {
        kind: "app",
        id: id
    };
}
function key(entry) {
    return entry ? entry.kind + ":" + entry.id : "";
}
function clone(entries) {
    return JSON.parse(JSON.stringify(entries));
}
function validId(id) {
    return typeof id === "string" && id.length > 0 && id.length <= 512 && !/[\u0000-\u001f/\\]/.test(id);
}

// Reject malformed files rather than silently overwriting a user's layout.
function decode(text) {
    try {
        const value = JSON.parse(text);
        if (!value || value.schemaVersion !== 1 || !Array.isArray(value.entries) || value.entries.length
                > 10000)

            return null;
        const apps = new Set();
        const folders = new Set();
        function accept(id) {
            if (!validId(id) || apps.has(id))
                return false;
            apps.add(id);
            return true;
        }
        for (const entry of value.entries) {
            if (!entry)
                return null;
            if (entry.kind === "app") {
                if (!accept(entry.id))
                    return null;
            } else if (entry.kind === "folder") {
                if (!validId(entry.id) || folders.has(entry.id) || typeof entry.name !== "string" ||
                        !entry.name.trim() || entry.name.length > 80 || !Array.isArray(entry.children) ||
                        !entry.children.length || !entry.children.every(accept))
                    return null;
                folders.add(entry.id);
            } else
                return null;
        }
        return clone(value.entries);
    } catch (error) {
        return null;
    }
}

function clean(entries) {
    return entries.filter(entry => entry.kind === "app" || entry.children.length > 0).map(entry => entry.kind
                                                                                                   === "folder"
                                                                                                   && entry.children.length
                                                                                                   === 1 ? app(
                                                                                                               entry.children[0]) :
                                                                                                           entry);
}

// A catalogue refresh is a projection only. Never persist a temporarily empty
// DesktopEntries enumeration over the saved layout during shell startup.
function reconcile(saved, installed) {
    const remaining = new Set(installed);
    const entries = [];
    for (const entry of saved) {
        if (entry.kind === "app") {
            if (remaining.delete(entry.id))
                entries.push(app(entry.id));
        } else {
            const children = entry.children.filter(id => remaining.delete(id));
            if (children.length)
                entries.push({
                                 kind: "folder",
                                 id: entry.id,
                                 name: entry.name,
                                 children: children
                             });
        }
    }
    return clean(entries).concat(Array.from(remaining).map(app));
}

function folder(entries, id) {
    return entries.find(entry => entry.kind === "folder" && entry.id === id) || null;
}
function contents(entries, folderId) {
    const group = folder(entries, folderId);
    return group ? group.children.map(app) : entries;
}
function locate(entries, entryKey) {
    for (let index = 0; index < entries.length; ++index) {
        const entry = entries[index];
        if (key(entry) === entryKey)
            return {
                entry: entry,
                parent: "",
                index: index
            };
        if (entry.kind === "folder") {
            const child = entry.children.findIndex(id => key(app(id)) === entryKey);
            if (child >= 0)
                return {
                    entry: app(entry.children[child]),
                    parent: entry.id,
                    index: child
                };
        }
    }
    return null;
}
function detach(entries, location) {
    if (location.parent)
        folder(entries, location.parent).children.splice(location.index, 1);
    else
        entries.splice(location.index, 1);
}

// Index is a gap in the destination before removal, including the trailing gap.
function move(entries, entryKey, folderId, index) {
    const next = clone(entries);
    const source = locate(next, entryKey);
    const destination = folderId ? folder(next, folderId) : null;
    if (!source || (folderId && !destination) || (folderId && source.entry.kind !== "app"))
        return null;
    const list = destination ? destination.children : next;
    let slot = Math.max(0, Math.min(list.length, Math.floor(Number(index) || 0)));
    if (source.parent === folderId && source.index < slot)
        --slot;
    detach(next, source);
    list.splice(slot, 0, destination ? source.entry.id : source.entry);
    return clean(next);
}

function merge(entries, sourceKey, targetKey, folderId, name) {
    const next = clone(entries);
    const source = locate(next, sourceKey);
    const target = locate(next, targetKey);
    if (!source || !target || sourceKey === targetKey || source.entry.kind !== "app" || target.parent)
        return null;
    if (target.entry.kind === "folder") {
        if (source.parent === target.entry.id)
            return null;
        detach(next, source);
        target.entry.children.push(source.entry.id);
    } else {
        if (!validId(folderId) || folder(next, folderId) || !String(name || "").trim())
            return null;
        detach(next, source);
        const index = next.findIndex(entry => key(entry) === targetKey);
        next[index] = {
            kind: "folder",
            id: folderId,
            name: String(name).trim().slice(0, 80),
            children: [target.entry.id, source.entry.id]
        };
    }
    return clean(next);
}

function rename(entries, id, name) {
    const title = String(name || "").trim().slice(0, 80);
    const next = clone(entries);
    const group = folder(next, id);
    if (!group || !title)
        return null;
    group.name = title;
    return next;
}

function dissolve(entries, id) {
    const next = clone(entries);
    const index = next.findIndex(entry => entry.kind === "folder" && entry.id === id);
    if (index < 0)
        return null;
    next.splice(index, 1, ...next[index].children.map(app));
    return next;
}
