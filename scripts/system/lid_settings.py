#!/usr/bin/python3
"""Read logind lid policy or apply a validated, dedicated system drop-in."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from gi.repository import Gio, GLib


TARGET = Path('/etc/systemd/logind.conf.d/90-clavis-lid.conf')
FIELDS = {
    'battery': 'HandleLidSwitch',
    'external': 'HandleLidSwitchExternalPower',
    'docked': 'HandleLidSwitchDocked',
}
ACTIONS = {'ignore', 'suspend', 'hibernate', 'suspend-then-hibernate'}


def call(interface, method, parameters=None):
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    return bus.call_sync(
        'org.freedesktop.login1', '/org/freedesktop/login1', interface,
        method, parameters, None, Gio.DBusCallFlags.NONE, 5000, None,
    ).unpack()


def status():
    props = call('org.freedesktop.DBus.Properties', 'GetAll',
                 GLib.Variant('(s)', ('org.freedesktop.login1.Manager',)))[0]
    values = {key: props[name] for key, name in FIELDS.items()}
    # logind rejects an empty HandleLidSwitchExternalPower value. Persist the
    # resolved action and retain the UI's inheritance choice as a comment.
    config = TARGET.read_text() if TARGET.exists() else ''
    if '# ExternalPowerFollowsBattery=yes' in config and values['external'] == values['battery']:
        values['external'] = ''
    capabilities = {'ignore': True}
    for action, method in [('suspend', 'CanSuspend'), ('hibernate', 'CanHibernate'),
                           ('suspend-then-hibernate', 'CanSuspendThenHibernate')]:
        try:
            capabilities[action] = call('org.freedesktop.login1.Manager', method)[0] in ('yes', 'challenge')
        except GLib.Error:
            capabilities[action] = False
    inhibitors = call('org.freedesktop.login1.Manager', 'ListInhibitors')[0]
    owners = sorted({entry[1] for entry in inhibitors
                    if 'handle-lid-switch' in entry[0].split(':') and entry[3] == 'block'})
    return dict(values=values, capabilities=capabilities,
                docked=props.get('Docked', False), lidClosed=props.get('LidClosed', False),
                externalPower=props.get('OnExternalPower', False), inhibitors=owners)


def validate(values):
    if not isinstance(values, dict) or set(values) != set(FIELDS):
        raise ValueError('合盖设置字段不完整。')
    for key, value in values.items():
        if not isinstance(value, str) or value not in ACTIONS | ({''} if key == 'external' else set()):
            raise ValueError('不支持的合盖动作：' + str(value))
    return values


def atomic_write(data):
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.clavis-lid-', dir=TARGET.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
            os.fchmod(stream.fileno(), 0o644)
        os.replace(name, TARGET)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def reload_logind():
    subprocess.run(['/usr/bin/systemctl', 'reload', 'systemd-logind.service'],
                   check=True, capture_output=True, text=True, timeout=30)


def apply(values):
    validate(values)
    if os.geteuid() != 0:
        raise PermissionError('更改合盖设置需要管理员身份验证。')
    available = status()['capabilities']
    for action in values.values():
        if action and not available.get(action, False):
            raise ValueError('系统当前不支持所选的睡眠或休眠方式。')
    can_reload = subprocess.run(
        ['/usr/bin/systemctl', 'show', 'systemd-logind.service', '-p', 'CanReload', '--value'],
        check=True, capture_output=True, text=True, timeout=5).stdout.strip()
    if can_reload != 'yes':
        raise RuntimeError('当前系统不支持即时重载合盖设置。')
    if TARGET.is_symlink():
        raise RuntimeError('合盖配置文件是符号链接，无法安全写入。')
    previous = TARGET.read_bytes() if TARGET.exists() else None
    content = '# Managed by Clavis power settings.\n'
    if values['external'] == '':
        content += '# ExternalPowerFollowsBattery=yes\n'
    content += '[Login]\n'
    content += ''.join(f'{name}={values[key] or values["battery"]}\n' for key, name in FIELDS.items())
    atomic_write(content.encode())
    try:
        reload_logind()
        result = status()
        if result['values'] != values:
            raise RuntimeError('合盖设置被其他系统配置覆盖，未能生效。')
        return result
    except Exception as original:
        try:
            if previous is None:
                TARGET.unlink(missing_ok=True)
            else:
                atomic_write(previous)
            reload_logind()
        except Exception as rollback:
            raise RuntimeError(f'{original}；恢复原配置失败：{rollback}') from original
        raise


def main():
    try:
        if len(sys.argv) == 2 and sys.argv[1] == 'status':
            result = status()
        elif len(sys.argv) == 3 and sys.argv[1] == 'apply':
            result = apply(json.loads(sys.argv[2]))
        else:
            raise ValueError('无效的合盖设置请求。')
        print(json.dumps(dict(ok=True, **result), ensure_ascii=False))
        return 0
    except Exception as error:
        print(json.dumps(dict(ok=False, error=str(error)), ensure_ascii=False))
        return 1


if __name__ == '__main__':
    sys.exit(main())
