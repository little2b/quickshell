#!/usr/bin/env python3
"""Request an application's own tray Quit action; never signal its process."""
import concurrent.futures
import json
from pathlib import Path
import re
import sys
import time


def normalize(value):
    return str(value or '').strip().removesuffix('.desktop').casefold()


def quit_item(layout, labels):
    """Only explicit, enabled top-level Quit entries, never Logout/submenus."""
    names = {normalize(label) for label in labels if label}
    allowed = {'quit', 'exit', '退出', '結束', '结束', '離開'}
    for name in names:
        allowed.update({'quit ' + name, 'exit ' + name, '退出' + name,
                        '退出 ' + name, '結束' + name, '结束' + name})
    candidates = []
    for item_id, properties, children in layout[2]:
        label = re.sub(r'\s*\(&?[A-Za-z]\)\s*$', '', str(properties.get('label', '')))
        label = normalize(label.replace('&', ''))
        if (label in allowed and properties.get('enabled', True)
                and properties.get('visible', True)
                and properties.get('type') != 'separator'
                and properties.get('children-display') != 'submenu' and not children):
            candidates.append(item_id)
    return candidates[0] if len(candidates) == 1 else None


def main(request, inspect_only=False):
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    props = 'org.freedesktop.DBus.Properties'
    tray = 'org.kde.StatusNotifierItem'
    labels = {normalize(label) for label in request.get('labels', []) if label}
    pids = {int(pid) for pid in request.get('pids', []) if int(pid) > 0}
    if not labels:
        return {'handled': False}

    def call(service, path, interface, method, signature, args):
        return bus.call_sync(service, path, interface, method, GLib.Variant(signature, args),
                             None, Gio.DBusCallFlags.NONE, 750, None).unpack()

    def prop(service, path, name):
        return call(service, path, props, 'Get', '(ss)', (tray, name))[0]

    def candidate(address):
        try:
            service, separator, path = address.partition('/')
            path = '/' + path if separator else '/StatusNotifierItem'
            owner = call('org.freedesktop.DBus', '/org/freedesktop/DBus',
                         'org.freedesktop.DBus', 'GetNameOwner', '(s)', (service,))[0]
            pid = call('org.freedesktop.DBus', '/org/freedesktop/DBus',
                       'org.freedesktop.DBus', 'GetConnectionUnixProcessID', '(s)', (owner,))[0]
            try:
                process = Path(f'/proc/{pid}/exe').readlink().name.casefold()
            except OSError:
                process = ''
            # Niri reports satellite's PID for X11 windows. Never treat a
            # shared display server or the shell as the application owner.
            shared = process.startswith(('xwayland', 'quickshell')) or process in ('qs', 'niri')
            if shared:
                return None
            identities = {normalize(prop(owner, path, 'Id')), normalize(prop(owner, path, 'Title'))}
            if process:
                identities.add(process)
            if pid not in pids and not identities.intersection(labels):
                tooltip = prop(owner, path, 'ToolTip')
                if len(tooltip) < 3 or normalize(tooltip[2]) not in labels:
                    return None
            menu = prop(owner, path, 'Menu')
            if not isinstance(menu, str) or not menu.startswith('/') or menu == '/':
                return None
            return owner, menu
        except (GLib.Error, ValueError, IndexError, TypeError):
            return None

    addresses = call('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher', props,
                     'Get', '(ss)', ('org.kde.StatusNotifierWatcher', 'RegisteredStatusNotifierItems'))[0]
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        candidates = {item for item in pool.map(candidate, addresses) if item}
    if len(candidates) != 1:
        return {'handled': False}
    owner, menu = next(iter(candidates))
    call(owner, menu, 'com.canonical.dbusmenu', 'AboutToShow', '(i)', (0,))
    layout = call(owner, menu, 'com.canonical.dbusmenu', 'GetLayout', '(iias)',
                  (0, 1, ['label', 'enabled', 'visible', 'type', 'children-display']))[1]
    action = quit_item(layout, request.get('labels', []))
    if action is None:
        return {'handled': False}
    if inspect_only:
        return {'handled': False, 'nativeQuitAvailable': True}
    # Once dispatched, an absent reply is not a reason to close windows too:
    # a successful Quit may disconnect the application before it replies.
    try:
        call(owner, menu, 'com.canonical.dbusmenu', 'Event', '(isvu)',
             (action, 'clicked', GLib.Variant('i', 0), int(time.monotonic() * 1000) & 0xffffffff))
    except GLib.Error:
        pass
    return {'handled': True}


if __name__ == '__main__':
    try:
        result = main(json.loads(sys.argv[1]), '--inspect' in sys.argv[2:])
    except Exception:
        # Missing optional D-Bus/GObject support and stale tray entries fall
        # back to polite compositor close requests, not process termination.
        result = {'handled': False}
    print(json.dumps(result))
