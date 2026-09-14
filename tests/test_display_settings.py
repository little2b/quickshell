"""Display preview contract: confirm commits; timeout/failure preserves saved state."""
import copy
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/system'))
import display_settings as display


class DisplaySettingsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.main = Path(self.directory.name) / 'config.kdl'
        self.original = '// User configuration\noutput "eDP-1" {\n position x=10 y=20\n scale 1.25\n}\n'
        self.main.write_text(self.original)
        self.output = dict(name='eDP-1', make='Vendor', model='Panel', serial='123',
                           modes=[dict(width=1920, height=1080, refresh_rate=60000),
                                  dict(width=1920, height=1080, refresh_rate=120000)],
                           current_mode=0, logical=dict(scale=1.25, transform='Normal', x=10, y=20, width=1536, height=864))
        self.request = dict(name='eDP-1', mode='1920x1080@120.000', scale=1.75, transform='normal')
        self.calls = []
        self.events = []
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, NIRI_CONFIG=str(self.main), XDG_RUNTIME_DIR=self.directory.name).start()
        patch.object(display, 'outputs', side_effect=lambda: {'eDP-1': copy.deepcopy(self.output)}).start()
        patch.object(display, 'command', side_effect=self.command).start()
        # The real candidate validator runs niri against temporary config only.

    def command(self, *args):
        self.calls.append(args)
        if args[2] == 'position':
            self.output['logical'].update(x=int(args[-2]), y=int(args[-1]))
            return
        key, value = args[2:]
        if key == 'mode':
            self.output['current_mode'] = next(i for i, m in enumerate(self.output['modes']) if display.mode_text(m) == value)
        elif key == 'scale':
            self.output['logical']['scale'] = float(value)
        elif key == 'transform':
            self.output['logical']['transform'] = next(k for k, v in display.TRANSFORMS.items() if v == value)

    def run_preview(self, decision):
        display.preview(self.request, decision=decision, send=lambda **event: self.events.append(event))

    def test_confirmation_preserves_other_settings_and_commits(self):
        def confirm():
            self.assertEqual(self.main.read_text(), self.original)
            return True
        self.run_preview(confirm)
        node = display.config.parse(self.main.read_text()).nodes[0]
        children = {n.name: n for n in node.nodes}
        self.assertEqual(children['position'].props, dict(x=10, y=20))
        self.assertEqual(children['scale'].args, [1.75])
        self.assertEqual(children['mode'].args, ['1920x1080@120.000'])
        self.assertEqual(self.events[-1]['event'], 'saved')

    def test_rejection_leaves_config_untouched_and_restores(self):
        before = display.current(self.output)
        self.run_preview(lambda: False)
        self.assertEqual(self.main.read_text(), self.original)
        self.assertEqual(display.current(self.output), before)
        self.assertEqual(self.events[-1]['event'], 'reverted')

    def test_external_edit_is_not_overwritten(self):
        before = display.current(self.output)
        def changed():
            self.main.write_text('// External change\n' + self.original)
            return True
        with self.assertRaisesRegex(ValueError, 'changed externally'):
            self.run_preview(changed)
        self.assertEqual(self.main.read_text(), '// External change\n' + self.original)
        self.assertEqual(display.current(self.output), before)

    def test_partial_apply_failure_restores_all_settings(self):
        original_command = self.command
        before = display.current(self.output)
        def fail(*args):
            if args[2:] == ('scale', '1.75'):
                raise ValueError('Device failed')
            return original_command(*args)
        with patch.object(display, 'command', side_effect=fail):
            with self.assertRaisesRegex(ValueError, 'Device failed'):
                self.run_preview(lambda: True)
        self.assertEqual(display.current(self.output), before)
        self.assertEqual(self.main.read_text(), self.original)

    def test_unavailable_mode_rejected_before_apply(self):
        self.request['mode'] = '800x600@144.000'
        with self.assertRaisesRegex(ValueError, 'no longer available'):
            self.run_preview(lambda: True)
        self.assertFalse(self.calls)

    def test_included_output_is_updated_without_changing_main(self):
        child = self.main.parent / 'monitor.kdl'
        child.write_text(self.original)
        self.main.write_text('include "monitor.kdl"\n')
        self.run_preview(lambda: True)
        self.assertEqual(self.main.read_text(), 'include "monitor.kdl"\n')
        node = display.config.parse(child.read_text()).nodes[0]
        self.assertEqual(next(n for n in node.nodes if n.name == 'scale').args, [1.75])

    def test_duplicate_output_blocks_rejected_before_apply(self):
        self.main.write_text(self.original + 'output "Vendor Panel 123" { scale 2; }\n')
        with self.assertRaisesRegex(ValueError, 'Multiple configuration blocks'):
            self.run_preview(lambda: True)
        self.assertFalse(self.calls)

    def test_timeout_and_eof_reject_confirmation(self):
        with patch.object(display.select, 'select', return_value=([], [], [])):
            self.assertFalse(display.wait_for_confirmation())
        with patch.object(display.select, 'select', return_value=([sys.stdin], [], [])), patch.object(display.os, 'read', return_value=b''):
            self.assertFalse(display.wait_for_confirmation())

    def test_invalid_scale_rejected(self):
        for value in (float('nan'), float('inf'), True, 0, 10, '1.75'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                display.validate_settings(self.output, dict(self.request, scale=value))



class MultiDisplayLayoutTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.main = Path(self.directory.name) / 'config.kdl'
        self.main.write_text('output "A" { scale 1.5; }\noutput "B" { scale 2; }\n')
        self.original = self.main.read_text()
        self.snapshot = {name: dict(name=name, make='Vendor', model=name, serial=name,
            current_mode=0, logical=dict(x=x, y=0, width=1000, height=800))
            for name, x in [('A', 0), ('B', 1000)]}
        self.previous = {'A': {'x': 0, 'y': 0}, 'B': {'x': 1000, 'y': 0}}
        self.positions = {'A': {'x': 1000, 'y': 0}, 'B': {'x': 0, 'y': 0}}
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, NIRI_CONFIG=str(self.main), XDG_RUNTIME_DIR=self.directory.name).start()
        patch.object(display, 'outputs', side_effect=lambda: copy.deepcopy(self.snapshot)).start()
        patch.object(display, 'command', side_effect=self.command).start()

    def command(self, *args):
        self.snapshot[args[1]]['logical'].update(x=int(args[-2]), y=int(args[-1]))

    def run_preview(self, decision):
        display.preview(dict(operation='layout-preview', positions=self.positions), decision=decision, send=lambda **event: None)

    def test_swap_commits_all_positions_and_preserves_scale(self):
        self.run_preview(lambda: True)
        graph = display.config.Graph(self.main)
        for _, node in graph.ordered:
            children = {child.name: child for child in node.nodes}
            self.assertEqual(children['position'].props, self.positions[node.args[0]])
            self.assertEqual(children['scale'].args, [1.5 if node.args[0] == 'A' else 2])
        self.assertTrue(display.layout_matches(self.snapshot, self.positions))

    def test_cancel_restores_entire_layout(self):
        self.run_preview(lambda: False)
        self.assertTrue(display.layout_matches(self.snapshot, self.previous))
        self.assertEqual(self.main.read_text(), self.original)

    def test_overlapping_layout_rejected(self):
        self.positions['A']['x'] = 500
        with self.assertRaisesRegex(ValueError, 'overlap'):
            self.run_preview(lambda: True)
        self.assertTrue(display.layout_matches(self.snapshot, self.previous))

    def test_negative_coordinates_are_preserved(self):
        self.positions = {'A': {'x': -1000, 'y': -200}, 'B': {'x': 0, 'y': 0}}
        self.run_preview(lambda: True)
        self.assertTrue(display.layout_matches(self.snapshot, self.positions))

    def test_hot_unplug_during_preview_restores_remaining_screen(self):
        def unplug():
            del self.snapshot['B']
            return False
        self.run_preview(unplug)
        self.assertEqual(self.snapshot['A']['logical']['x'], 0)
        self.assertEqual(self.main.read_text(), self.original)

    def test_partial_command_failure_restores_both_screens(self):
        command = self.command
        failed = False
        def fail(*args):
            nonlocal failed
            if args[1] == 'B' and not failed:
                failed = True
                raise ValueError('Device failed')
            command(*args)
        with patch.object(display, 'command', side_effect=fail):
            with self.assertRaisesRegex(ValueError, 'Device failed'):
                self.run_preview(lambda: True)
        self.assertTrue(display.layout_matches(self.snapshot, self.previous))
        self.assertEqual(self.main.read_text(), self.original)

    def test_multiple_include_files_roll_back_on_write_failure(self):
        a = self.main.parent / 'a.kdl'
        b = self.main.parent / 'b.kdl'
        a.write_text('output "A" { scale 1.5; }\n')
        b.write_text('output "B" { scale 2; }\n')
        self.main.write_text('include "a.kdl"\ninclude "b.kdl"\n')
        original = {p: p.read_text() for p in [self.main, a, b]}
        write = display.config.replace_file
        def fail(path, text):
            if path == b:
                raise OSError('Disk full')
            write(path, text)
        with patch.object(display.config, 'replace_file', side_effect=fail):
            with self.assertRaisesRegex(OSError, 'Disk full'):
                self.run_preview(lambda: True)
        self.assertTrue(display.layout_matches(self.snapshot, self.previous))
        self.assertEqual({p: p.read_text() for p in original}, original)

    def test_changed_display_set_rejected(self):
        del self.positions['B']
        with self.assertRaisesRegex(ValueError, 'connected displays changed'):
            self.run_preview(lambda: True)

    def test_noninteger_coordinates_rejected(self):
        for value in [0.5, True, '100', 100001]:
            self.positions['A']['x'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.run_preview(lambda: True)


if __name__ == '__main__':
    unittest.main()
