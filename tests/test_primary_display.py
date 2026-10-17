#!/usr/bin/env python3
"""Exercise display recovery through the watch process and a private Niri socket."""
import copy
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


def panel(name, enabled=False):
    return dict(name=name, make='Test', model='Panel', serial=name,
                modes=[dict(width=1920, height=1080, refresh_rate=60000)],
                current_mode=0 if enabled else None,
                logical=dict(x=0, y=0, width=1920, height=1080, scale=1) if enabled else None)


class DisplayRecoveryContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='clavis-display-recovery-')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.config = self.directory / 'primary-display.json'
        self.config.write_text(json.dumps({'primary': None, 'autoMove': False}))
        self.saved_outputs = self.directory / 'outputs.kdl'
        self.saved_outputs.write_text('output "eDP-1" { off; }\n')
        self.peer = socket.socket(socket.AF_UNIX)
        self.peer.bind(str(self.directory / 'niri.sock'))
        self.peer.listen()
        self.peer.settimeout(0.1)
        self.state = {}
        self.commands = []
        self.rejected = set()
        self.queries = 0
        self.mutex = threading.Lock()
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()
        self.process = None
        self.addCleanup(self.finish)

    def finish(self):
        if self.process:
            self.process.communicate(timeout=10)  # EOF ends the watcher.
            self.assertEqual(self.process.returncode, 0)
        self.stop.set()
        self.thread.join(timeout=2)
        self.peer.close()

    def serve(self):
        while not self.stop.is_set():
            try:
                connection, _ = self.peer.accept()
            except (TimeoutError, OSError):
                continue
            with connection:
                connection.settimeout(2)
                try:
                    with connection.makefile('rb') as stream:
                        data = json.loads(stream.readline())
                    with self.mutex:
                        if data == 'Outputs':
                            self.queries += 1
                            response = {'Ok': {'Outputs': copy.deepcopy(self.state)}}
                        elif isinstance(data, dict) and 'Output' in data:
                            name = data['Output']['output']
                            self.commands.append(data)
                            if name in self.rejected or name not in self.state:
                                response = {'Err': 'Output cannot be enabled'}
                            elif data['Output']['action'] == 'On':
                                self.state[name] = panel(name, True)
                                response = {'Ok': {'OutputConfigChanged': 'Applied'}}
                            else:
                                response = {'Err': 'Unexpected action'}
                        else:
                            response = {'Err': 'Unexpected request'}
                    connection.sendall((json.dumps(response) + '\n').encode())
                except (OSError, ValueError):
                    pass

    def start(self):
        env = dict(os.environ, NIRI_SOCKET=str(self.directory / 'niri.sock'),
                   XDG_RUNTIME_DIR=str(self.directory), CLAVIS_CONFIG_HOME=str(self.directory))
        self.process = subprocess.Popen(
            [sys.executable, '-I', str(ROOT / 'scripts/system/primary_display.py'), 'watch'],
            env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def until(self, predicate):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            with self.mutex:
                if predicate():
                    return
            time.sleep(0.025)
        self.fail('Watcher did not reach the expected output state')

    def test_unplug_last_active_display_recovers_internal_and_preserves_preferences(self):
        self.state = {'DP-2': panel('DP-2', True), 'eDP-1': panel('eDP-1')}
        original = self.config.read_bytes()
        self.start()
        self.until(lambda: self.queries >= 2)
        with self.mutex:
            self.assertEqual(self.commands, [])
            del self.state['DP-2']
        self.until(lambda: self.state['eDP-1']['current_mode'] is not None)
        with self.mutex:
            self.assertEqual(self.commands, [{'Output': {'output': 'eDP-1', 'action': 'On'}}])
            self.state['DP-2'] = panel('DP-2', True)
            count = self.queries
        self.until(lambda: self.queries >= count + 3)
        self.assertEqual(len(self.commands), 1)
        self.assertEqual(self.config.read_bytes(), original)
        self.assertEqual(self.saved_outputs.read_text(), 'output "eDP-1" { off; }\n')

    def test_internal_failure_tries_another_connected_display_even_with_bad_preferences(self):
        self.state = {'DP-1': panel('DP-1'), 'eDP-1': panel('eDP-1')}
        self.rejected.add('eDP-1')
        self.config.write_text('invalid json')
        self.start()
        self.until(lambda: self.state['DP-1']['current_mode'] is not None)
        self.assertEqual([item['Output']['output'] for item in self.commands], ['eDP-1', 'DP-1'])
        self.assertEqual(self.config.read_text(), 'invalid json')

    def test_no_connected_display_waits_for_hotplug(self):
        self.start()
        self.until(lambda: self.queries >= 2)
        with self.mutex:
            self.assertEqual(self.commands, [])
            self.state['HDMI-A-1'] = panel('HDMI-A-1')
        self.until(lambda: self.state['HDMI-A-1']['current_mode'] is not None)

    def test_dpms_blanking_does_not_enable_disabled_internal_display(self):
        self.state = {'DP-2': dict(panel('DP-2', True), is_powered_on=False),
                      'eDP-1': panel('eDP-1')}
        self.start()
        self.until(lambda: self.queries >= 5)
        self.assertEqual(self.commands, [])


if __name__ == '__main__':
    unittest.main()
