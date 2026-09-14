"""Resolve a tray item's owner without activating it or reading application data."""
import concurrent.futures
import json
import subprocess
import sys


def bus(*args):
    result = subprocess.run(
        ["busctl", "--user", "--timeout=1", "--json=short", *args],
        capture_output=True, text=True, timeout=2, check=True,
    )
    return json.loads(result.stdout)["data"]


def owner(address, wanted):
    try:
        service, path = address.split("/", 1)
        path = "/" + path
        def prop(name):
            return bus("get-property", service, path, "org.kde.StatusNotifierItem", name)
        if prop("Id") != wanted.get("id", ""):
            return None
        if prop("Title") != wanted.get("title", ""):
            return None
        try:
            tooltip = prop("ToolTip")[2]
        except (subprocess.SubprocessError, ValueError, IndexError, KeyError):
            tooltip = ""
        if tooltip != wanted.get("tooltipTitle", ""):
            return None
        return bus("call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
                   "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", service)[0]
    except (subprocess.SubprocessError, ValueError, IndexError, KeyError):
        return None


def resolve(wanted):
    addresses = bus("get-property", "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                    "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems")
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        owners = {pid for pid in pool.map(lambda address: owner(address, wanted), addresses) if pid}
    # Identical metadata from different applications is ambiguous.
    return next(iter(owners)) if len(owners) == 1 else 0


if __name__ == "__main__":
    try:
        print(json.dumps({"pid": resolve(json.loads(sys.argv[1]))}))
    except (subprocess.SubprocessError, ValueError, IndexError, KeyError):
        print('{"pid":0}')
