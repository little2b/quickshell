#!/usr/bin/python3
"""Remember a preferred niri output and move workspaces when it reconnects."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import socket
import sys
import tempfile
import time


CONFIG_HOME = Path(os.environ.get('CLAVIS_CONFIG_HOME', Path.home() / '.config/clavis'))
CONFIG = CONFIG_HOME / 'primary-display.json'
SOCKET = os.environ.get('NIRI_SOCKET', '')
KEY = hashlib.sha256((str(CONFIG) + SOCKET).encode()).hexdigest()[:20]
RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp')) / ('clavis-primary-' + KEY)
STATE = RUNTIME.with_suffix('.json')
LOCK = RUNTIME.with_suffix('.lock')


def request(data):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(SOCKET)
        connection.sendall(json.dumps(data).encode() + b'\n')
        result = json.loads(connection.makefile('rb').readline())
    if 'Err' in result:
        raise RuntimeError(str(result['Err']))
    return result['Ok']


def query(name):
    return request(name)[name]


def action(name, **arguments):
    request({'Action': {name: arguments}})


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.primary-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def identity(output):
    return {key: output.get(key) for key in ('name', 'make', 'model', 'serial')}


def active_outputs(outputs):
    return {name: output for name, output in outputs.items()
            if output.get('current_mode') is not None and output.get('logical')}


def preferred_output(preferred, outputs):
    if not preferred:
        return None
    matches = [name for name, output in outputs.items()
               if all(output.get(key) == preferred.get(key) for key in ('make', 'model', 'serial'))]
    if preferred['name'] in matches:
        return preferred['name']
    return sorted(matches)[0] if matches else None


def move_plan(workspaces, windows, target):
    # Preserve workspace/column layout, and leave helper-only workspaces alone.
    populated = {window['workspace_id'] for window in windows
                 if window.get('app_id') != 'xwaylandvideobridge'}
    return sorted([workspace for workspace in workspaces
                   if workspace['output'] != target and workspace['id'] in populated
                   and workspace.get('name') != '后台桥接'],
                  key=lambda item: (item.get('output') or '', item['idx']))


def migrate(target, move=True):
    workspaces = query('Workspaces')
    windows = query('Windows')
    plan = move_plan(workspaces, windows, target) if move else []
    focused = next((workspace for workspace in workspaces if workspace['is_focused']), None)
    moved = []
    try:
        for workspace in plan:
            action('MoveWorkspaceToMonitor', output=target, reference={'Id': workspace['id']})
            moved.append(workspace)
        action('FocusMonitor', output=target)
        if focused and (focused['output'] == target or focused in moved):
            action('FocusWorkspace', reference={'Id': focused['id']})
        final = {item['id']: item['output'] for item in query('Workspaces')}
        if any(final.get(item['id']) != target for item in moved):
            raise RuntimeError('部分工作区未能迁移，显示器连接状态可能已变化。')
    except Exception as original:
        rollback_errors = []
        available = active_outputs(query('Outputs'))
        for workspace in moved:
            if workspace['output'] in available:
                try:
                    action('MoveWorkspaceToMonitor', output=workspace['output'], reference={'Id': workspace['id']})
                except Exception as error:
                    rollback_errors.append(str(error))
        if focused:
            try:
                action('FocusWorkspace', reference={'Id': focused['id']})
            except Exception:
                pass
        if rollback_errors:
            raise RuntimeError(str(original) + '；部分工作区无法恢复：' + '; '.join(rollback_errors)) from original
        raise
    return len(moved)


def preferences():
    values = read_json(CONFIG, {'primary': None, 'autoMove': True})
    if not isinstance(values, dict) or type(values.get('autoMove')) is not bool:
        raise ValueError('主显示器配置无效。')
    primary = values.get('primary')
    if primary is not None and (not isinstance(primary, dict) or not isinstance(primary.get('name'), str)):
        raise ValueError('主显示器信息无效。')
    return values


def reconcile(force=False, apply=True):
    values = preferences()
    outputs = active_outputs(query('Outputs'))
    target = preferred_output(values['primary'], outputs)
    if force and not target:
        raise ValueError('首选主显示器未连接。')
    signature = {'preferences': values, 'target': target}
    state = read_json(STATE, {})
    if apply and (force or state.get('signature') != signature):
        count = migrate(target, force or values['autoMove']) if target else 0
        state = {'signature': signature, 'moved': count, 'appliedAt': time.time()}
        atomic_json(STATE, state)
    fallback = next((name for name in sorted(outputs) if name.startswith(('eDP', 'LVDS'))),
                    next(iter(sorted(outputs)), ''))
    return dict(ok=True, preferences=values, outputs=[identity(outputs[name]) for name in sorted(outputs)],
                activePrimary=target or '', fallback=fallback,
                selectedName=target or (values['primary']['name'] if values['primary'] else ''),
                moved=state.get('moved', 0), appliedAt=state.get('appliedAt', 0))


def locked(operation):
    fd = os.open(LOCK, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return operation()


def configure(data):
    values = preferences()
    previous = dict(values)
    if 'primary' in data:
        name = data['primary']
        if not isinstance(name, str):
            raise ValueError('请选择主显示器。')
        if name:
            output = active_outputs(query('Outputs')).get(name)
            if not output:
                raise ValueError('所选显示器已断开，请刷新后重试。')
            values['primary'] = identity(output)
        else:
            values['primary'] = None
    if 'autoMove' in data:
        if type(data['autoMove']) is not bool:
            raise ValueError('自动迁移选项无效。')
        values['autoMove'] = data['autoMove']
    atomic_json(CONFIG, values)
    try:
        return reconcile()
    except Exception:
        atomic_json(CONFIG, previous)
        raise


def emit(result):
    print(json.dumps(result, ensure_ascii=False), flush=True)


def watch():
    previous = None
    candidate = None
    while True:
        try:
            # Wait for a stable topology before moving workspaces after hotplug.
            snapshot = locked(lambda: reconcile(apply=False))
            key = [snapshot['preferences'], snapshot['activePrimary']]
            if key == candidate:
                snapshot = locked(reconcile)
            candidate = key
            if snapshot != previous:
                emit(snapshot)
                previous = snapshot
        except Exception as error:
            result = {'ok': False, 'error': str(error)}
            if result != previous:
                emit(result)
                previous = result
        readable, _, _ = select.select([sys.stdin], [], [], 1.5)
        if readable and not os.read(sys.stdin.fileno(), 4096):
            return


def main():
    try:
        if len(sys.argv) == 2 and sys.argv[1] == 'watch':
            watch()
            return 0
        data = json.loads(sys.argv[1])
        operation = data.get('operation')
        if operation == 'configure':
            result = locked(lambda: configure(data))
        elif operation == 'move':
            result = locked(lambda: reconcile(force=True))
        elif operation == 'status':
            result = locked(lambda: reconcile(apply=False))
        else:
            raise ValueError('未知的主显示器操作。')
        emit(result)
        return 0
    except Exception as error:
        emit({'ok': False, 'error': str(error)})
        return 1


if __name__ == '__main__':
    sys.exit(main())
