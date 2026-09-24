import QtQuick
import QtTest
import "../../Common/functions/LaunchpadLayout.js" as Layout

TestCase {
    name: "LaunchpadLayout"
    function apps() {
        return ["a", "b", "c", "d"].map(Layout.app);
    }
    function ids(entries) {
        return entries.map(entry => entry.id).join(",");
    }
    function allApps(entries) {
        return entries.reduce((result, entry) => result.concat(entry.kind === "folder" ? entry.children :
                                                                                         [entry.id]), []).sort(
                    ).join(",");
    }
    function test_reorderAcrossPagesAndSelfDrop() {
        const original = apps();
        compare(ids(Layout.move(original, "app:a", "", 4)), "b,c,d,a");
        compare(ids(Layout.move(original, "app:d", "", 0)), "d,a,b,c");
        compare(ids(Layout.move(original, "app:b", "", 2)), "a,b,c,d");
        compare(ids(original), "a,b,c,d");
        compare(Layout.move(original, "app:missing", "", 0), null);
    }
    function test_createFolderThenMoveInOutAndDissolve() {
        let entries = Layout.merge(apps(), "app:a", "app:c", "group", "Tools");
        compare(ids(entries), "b,group,d");
        compare(Layout.folder(entries, "group").children.join(","), "c,a");
        entries = Layout.merge(entries, "app:d", "folder:group", "unused", "Unused");
        compare(Layout.folder(entries, "group").children.join(","), "c,a,d");
        entries = Layout.move(entries, "app:d", "group", 0);
        compare(Layout.folder(entries, "group").children.join(","), "d,c,a");
        entries = Layout.move(entries, "app:c", "", 0);
        compare(ids(entries), "c,b,group");
        compare(allApps(entries), "a,b,c,d");
        entries = Layout.dissolve(entries, "group");
        compare(ids(entries), "c,b,d,a");
    }
    function test_oneRemainingAppReplacesFolderAndEmptyFolderDisappears() {
        const entries = Layout.merge(apps(), "app:a", "app:b", "group", "Tools");
        const extracted = Layout.move(entries, "app:a", "", 3);
        compare(ids(extracted), "b,c,d,a");
        compare(Layout.folder(extracted, "group"), null);
        const single = [
                  {
                      kind: "folder",
                      id: "g",
                      name: "Group",
                      children: ["a"]
                  },
                  Layout.app("b")];
        compare(ids(Layout.move(single, "app:a", "", 2)), "b,a");
    }
    function test_betweenFoldersAndNoNestingOrDuplicates() {
        let entries = Layout.merge(apps(), "app:a", "app:b", "one", "One");
        entries = Layout.merge(entries, "app:c", "app:d", "two", "Two");
        compare(Layout.merge(entries, "folder:one", "folder:two", "three", "Three"), null);
        compare(Layout.merge(entries, "app:a", "folder:one", "three", "Three"), null);
        compare(Layout.merge(entries, "app:a", "app:a", "three", "Three"), null);
        compare(Layout.move(entries, "folder:one", "two", 0), null);
        compare(Layout.move(entries, "app:a", "missing", 0), null);
        entries = Layout.merge(entries, "app:a", "folder:two", "three", "Three");
        compare(ids(entries), "b,two");
        compare(Layout.folder(entries, "two").children.join(","), "d,c,a");
        compare(allApps(entries), "a,b,c,d");
    }
    function test_catalogChangesNeverMutateSavedLayout() {
        const saved = Layout.merge(apps(), "app:a", "app:b", "group", "Tools");
        compare(ids(Layout.reconcile(saved, ["a", "b", "d", "new"])), "group,d,new");
        compare(ids(Layout.reconcile(saved, ["a", "d"])), "a,d");
        compare(Layout.reconcile(saved, []).length, 0);
        compare(Layout.reconcile(saved, ["a", "b", "c", "d"]), saved);
        compare(allApps(saved), "a,b,c,d");
    }
    function test_persistenceAndRename() {
        const entries = Layout.merge(apps(), "app:a", "app:b", "group", "Tools");
        const renamed = Layout.rename(entries, "group", "  Work  ");
        compare(Layout.folder(renamed, "group").name, "Work");
        compare(Layout.folder(entries, "group").name, "Tools");
        compare(Layout.rename(entries, "group", "  "), null);
        compare(Layout.decode(JSON.stringify({
                                                 schemaVersion: 1,
                                                 entries: renamed
                                             })), renamed);
    }
    function test_corruptOrDuplicateLayoutRejected() {
        for (const text of ["", "{}", "null", "{broken", '{"schemaVersion":2,"entries":[]}'])
            compare(Layout.decode(text), null);
        for (const entries of [[Layout.app("a"), Layout.app("a")], [
                                   {
                                       kind: "folder",
                                       id: "g",
                                       name: "Group",
                                       children: ["a", "a"]
                                   }
                               ], [
                                   {
                                       kind: "folder",
                                       id: "g",
                                       name: "Group",
                                       children: ["a"]
                                   },
                                   Layout.app("a")], [
                                   {
                                       kind: "folder",
                                       id: "g",
                                       name: "Group",
                                       children: []
                                   }
                               ], [
                                   {
                                       kind: "app",
                                       id: "bad/path"
                                   }
                               ], [
                                   {
                                       kind: "folder",
                                       id: "g",
                                       name: "Group",
                                       children: [Layout.app("a")]
                                   }
                               ]])
            compare(Layout.decode(JSON.stringify({
                                                     schemaVersion: 1,
                                                     entries: entries
                                                 })), null);
    }
}
