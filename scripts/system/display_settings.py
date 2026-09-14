#!/usr/bin/env python3
"""Display configuration with a timed preview and explicit confirmation over stdin."""
import copy
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import select
import signal
import stat
import subprocess
import sys
import tempfile
import time

import niri_config as config

TRANSFORMS = {'Normal': 'normal', '90': '90', '180': '180', '270': '270',
              'Flipped': 'flipped', 'Flipped90': 'flipped-90',
              'Flipped180': 'flipped-180', 'Flipped270': 'flipped-270'}


def command(*args):
    result = subprocess.run(['niri', 'msg', *args], capture_output=True, text=True, timeout=5)
    if result.returncode:
        raise ValueError(result.stderr.strip() or result.stdout.strip() or 'Display operation failed')
    return result.stdout


def outputs():
    return json.loads(command('-j', 'outputs'))


def mode_text(mode):
    return f"{mode['width']}x{mode['height']}@{mode['refresh_rate'] / 1000:.3f}"


def current(output):
    index = output.get('current_mode')
    logical = output.get('logical')
    if index is None or not logical:
        raise ValueError('This display is not active')
    return dict(mode=mode_text(output['modes'][index]), scale=logical['scale'],
                transform=TRANSFORMS[logical['transform']])


def validate_settings(output, request):
    mode = request.get('mode')
    if mode not in [mode_text(item) for item in output['modes']]:
        raise ValueError('The selected display mode is no longer available')
    scale = request.get('scale')
    if isinstance(scale, bool) or not isinstance(scale, (int, float)) or not math.isfinite(scale) or not 0.5 <= scale <= 4:
        raise ValueError('Scale must be between 50% and 400%')
    transform = request.get('transform')
    if transform not in TRANSFORMS.values():
        raise ValueError('Invalid display rotation')
    return dict(mode=mode, scale=scale, transform=transform)


def output_blocks(graph, output):
    description = ' '.join(str(output.get(key) or 'Unknown') for key in ('make', 'model', 'serial'))
    identifiers = {output['name'].lower(), description.lower()}
    return [(path, node) for path, node in graph.ordered
            if node.name == 'output' and node.args and str(node.args[0]).lower() in identifiers]


def candidate(graph, output, settings):
    matches = output_blocks(graph, output)
    if len(matches) > 1:
        raise ValueError('Multiple configuration blocks match this display; merge them before saving')
    path = config.path_key(graph.main)
    if matches:
        path, original = matches[0]
        node = copy.deepcopy(original)
        # Keep all unrelated settings (position, VRR, color, focus, etc.).
        node.nodes = [child for child in node.nodes if child.name not in settings]
    else:
        original = None
        node = config.kdl.Node('output', args=[output['name']])
    node.nodes.extend(config.kdl.Node(key, props=value) if key == 'position'
                      else config.kdl.Node(key, args=[value]) for key, value in settings.items())
    text = graph.files[path]
    replacement = config.render(node)
    if original:
        text = text[:original.source_start] + replacement + text[original.source_end:]
    else:
        text += '\n' + replacement
    # Reject symlinked include paths, not just their resolved targets.
    for logical, target in graph.logical_targets.items():
        if target == path:
            config.safe_target(logical)
    config.safe_target(path)
    return path, text


def apply(name, settings):
    for key in ('mode', 'scale', 'transform'):
        command('output', name, key, str(settings[key]))


def restore(name, settings):
    if name not in outputs():
        return  # Unplugged displays will use the unchanged saved configuration.
    errors = []
    for key in ('mode', 'scale', 'transform'):
        try:
            command('output', name, key, str(settings[key]))
        except (ValueError, subprocess.TimeoutExpired) as error:
            errors.append(str(error))
    if errors:
        raise ValueError('; '.join(errors))


def matches_settings(output, settings):
    actual = current(output)
    return (actual['mode'] == settings['mode'] and actual['transform'] == settings['transform']
            and abs(actual['scale'] - settings['scale']) < 0.01)


def emit(**data):
    print(json.dumps(dict(schemaVersion=1, **data)), flush=True)


def active_outputs(snapshot):
    return {name: output for name, output in snapshot.items()
            if output.get('current_mode') is not None and output.get('logical')}


def validate_layout(snapshot, positions):
    active = active_outputs(snapshot)
    if not isinstance(positions, dict) or not active or set(positions) != set(active):
        raise ValueError('The connected displays changed; refresh the layout before applying')
    for position in positions.values():
        if not isinstance(position, dict) or set(position) != {'x', 'y'}:
            raise ValueError('Invalid display position')
        if any(type(value) is not int or abs(value) > 100000 for value in position.values()):
            raise ValueError('Display positions must be whole numbers between -100000 and 100000')
    names = list(active)
    for i, name in enumerate(names):
        a, size_a = positions[name], active[name]['logical']
        for other in names[i + 1:]:
            b, size_b = positions[other], active[other]['logical']
            if (a['x'] < b['x'] + size_b['width'] and b['x'] < a['x'] + size_a['width']
                    and a['y'] < b['y'] + size_b['height'] and b['y'] < a['y'] + size_a['height']):
                raise ValueError('Displays overlap; move them apart before applying')


def layout_matches(snapshot, positions):
    active = active_outputs(snapshot)
    return set(active) == set(positions) and all(
        all(active[name]['logical'][axis] == position[axis] for axis in ('x', 'y'))
        for name, position in positions.items())


def place_outputs(positions):
    active = active_outputs(outputs())
    if not set(positions) <= set(active):
        raise ValueError('A display was disconnected')
    if all(all(active[name]['logical'][axis] == position[axis] for axis in ('x', 'y'))
           for name, position in positions.items()):
        return
    # Vacate the destination rectangles first, including when two screens swap
    # places. Otherwise niri can automatically relocate overlapping outputs.
    stage_x = max([o['logical']['x'] + o['logical']['width'] for o in active.values()]
                  + [p['x'] + active[n]['logical']['width'] for n, p in positions.items()]) + 1024
    for name in positions:
        command('output', name, 'position', 'set', '--', str(stage_x), '0')
        stage_x += active[name]['logical']['width'] + 1024
    for name, position in positions.items():
        command('output', name, 'position', 'set', '--', str(position['x']), str(position['y']))


def check_layout(positions):
    deadline = time.monotonic() + 2
    while True:
        if layout_matches(outputs(), positions):
            return
        if time.monotonic() >= deadline:
            raise ValueError('The display layout changed or was not accepted; refresh and try again')
        time.sleep(0.05)


def publish_layout(graph, replacements):
    published = []
    try:
        for path, text in replacements.items():
            # Includes may be edited while a different file is being published.
            for source, original in graph.files.items():
                expected = replacements[source] if source in published else original
                actual = config.read_text(source) if source.exists() else None
                if actual != expected:
                    raise ValueError('Configuration changed externally; reload before saving')
            config.safe_target(path)
            config.replace_file(path, text)
            published.append(path)
    except BaseException:
        for path in reversed(published):
            if config.read_text(path) == replacements[path]:
                config.replace_file(path, graph.files[path])
        raise


def preview_layout(request, decision, send):
    # Called under the same configuration lock as individual display changes.
    snapshot = outputs()
    positions = request.get('positions')
    validate_layout(snapshot, positions)
    previous = {name: {axis: o['logical'][axis] for axis in ('x', 'y')}
                for name, o in active_outputs(snapshot).items()}
    graph = config.Graph(config.main_path({}))
    replacements = {}
    selected_blocks = set()
    for name, position in positions.items():
        for source, node in output_blocks(graph, snapshot[name]):
            key = (source, node.source_start)
            if key in selected_blocks:
                raise ValueError('Several displays share one configuration block; use separate connector names before saving')
            selected_blocks.add(key)
        staged = config.Graph(graph.main, replacements=replacements)
        path, text = candidate(staged, snapshot[name], {'position': position})
        replacements[path] = text
    config.Graph(graph.main, replacements=replacements).validate()
    graph.unchanged()
    saved = False
    try:
        place_outputs(positions)
        check_layout(positions)
        send(event='preview', seconds=20)
        accepted = decision() if decision else wait_for_confirmation()
        if accepted:
            check_layout(positions)
            graph.unchanged()
            publish_layout(graph, replacements)
            saved = True
    finally:
        if not saved:
            connected = active_outputs(outputs())
            remaining = {name: value for name, value in previous.items() if name in connected}
            if remaining:
                place_outputs(remaining)
    send(event='saved' if saved else 'reverted')


def preview(request, decision=None, send=emit):
    main = config.main_path({})
    config.safe_target(main)
    lock_dir = Path(os.environ.get('XDG_RUNTIME_DIR', tempfile.gettempdir()))
    lock_path = lock_dir / ('clavis-niri-' + str(os.getuid()) + '-' + hashlib.sha256(str(main).encode()).hexdigest()[:20] + '.lock')
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lock:
        info = os.fstat(lock.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise ValueError('Unsafe configuration lock file')
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Another configuration change is in progress') from None
        if request.get('operation') == 'layout-preview':
            return preview_layout(request, decision, send)
        name = request.get('name')
        output = outputs().get(name)
        if not output:
            raise ValueError('The display was disconnected')
        previous = current(output)
        settings = validate_settings(output, request)
        graph = config.Graph(main)
        path, text = candidate(graph, output, settings)
        config.Graph(main, replacements={path: text}).validate()
        graph.unchanged()
        saved = False
        try:
            apply(name, settings)
            actual = outputs().get(name)
            if not actual or not matches_settings(actual, settings):
                raise ValueError('The display did not accept these settings')
            send(event='preview', seconds=20)
            accepted = decision() if decision else wait_for_confirmation()
            if accepted:
                actual = outputs().get(name)
                if not actual or not matches_settings(actual, settings):
                    raise ValueError('Display settings changed during the preview; try again')
                graph.unchanged()
                config.safe_target(path)
                config.replace_file(path, text)
                saved = True
        finally:
            if not saved:
                restore(name, previous)
        send(event='saved' if saved else 'reverted')


def wait_for_confirmation():
    # EOF (including a closed/reloaded shell) is a rejection. The deadline lives
    # outside the UI so a frozen settings window still restores the display.
    ready, _, _ = select.select([sys.stdin], [], [], 20)
    return bool(ready) and os.read(sys.stdin.fileno(), 128) == b'confirm\n'


def interrupted(_signum, _frame):
    raise ValueError('Display preview was interrupted')


def main():
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    try:
        request = json.loads(sys.argv[1])
        if request.get('operation') == 'status':
            emit(event='status', outputs=list(outputs().values()))
        elif request.get('operation') in ('preview', 'layout-preview'):
            preview(request)
        else:
            raise ValueError('Unknown display operation')
    except (ValueError, OSError, KeyError, config.kdl.ParseError, subprocess.TimeoutExpired) as error:
        emit(event='error', error=str(error))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
