#!/usr/bin/python3
"""Delay logind sleep until Clavis confirms the compositor has secured its lock."""
import json
import os
import sys

from gi.repository import Gio, GLib

DESTINATION = 'org.freedesktop.login1'
MANAGER = '/org/freedesktop/login1'
INTERFACE = 'org.freedesktop.login1.Manager'


class SleepGuard:
    def __init__(self, acquire, emit, close=os.close):
        self.acquire = acquire
        self.emit = emit
        self.close = close
        self.fd = None
        self.serial = 0
        self.pending = None

    def hold(self):
        if self.fd is None:
            self.fd = self.acquire()

    def release(self):
        if self.fd is not None:
            self.close(self.fd)
            self.fd = None

    def prepare(self, sleeping):
        if sleeping:
            if self.pending is not None:
                return
            self.serial += 1
            self.pending = self.serial
            self.emit({'event': 'prepare', 'serial': self.pending})
        else:
            self.pending = None
            self.hold()
            self.emit({'event': 'resume'})

    def acknowledge(self, serial):
        if self.pending is not None and serial == self.pending:
            self.release()


def main():
    connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    loop = GLib.MainLoop()

    def emit(event):
        print(json.dumps(event), flush=True)

    def acquire():
        result, descriptors = connection.call_with_unix_fd_list_sync(
            DESTINATION, MANAGER, INTERFACE, 'Inhibit',
            GLib.Variant('(ssss)', ('sleep', 'Clavis screen lock',
                                   'Lock the session before sleep', 'delay')),
            GLib.VariantType.new('(h)'), Gio.DBusCallFlags.NONE, 5000, None, None)
        return descriptors.get(result.unpack()[0])

    guard = SleepGuard(acquire, emit)

    def prepare_signal(_connection, _sender, _path, _interface, _signal, parameters, _data):
        try:
            guard.prepare(parameters.unpack()[0])
        except Exception as error:
            print('Sleep lock bridge: ' + str(error), file=sys.stderr, flush=True)
            loop.quit()

    def owner_changed(_connection, _sender, _path, _interface, _signal, parameters, _data):
        _name, _old, new = parameters.unpack()
        guard.release()
        guard.pending = None
        if new:
            try:
                guard.hold()
            except Exception as error:
                print('Sleep lock bridge: ' + str(error), file=sys.stderr, flush=True)
                loop.quit()

    connection.signal_subscribe(DESTINATION, INTERFACE, 'PrepareForSleep', MANAGER,
                                None, Gio.DBusSignalFlags.NONE, prepare_signal, None)
    connection.signal_subscribe('org.freedesktop.DBus', 'org.freedesktop.DBus', 'NameOwnerChanged',
                                '/org/freedesktop/DBus', DESTINATION, Gio.DBusSignalFlags.NONE,
                                owner_changed, None)
    connection.connect('closed', lambda *_args: loop.quit())
    buffer = bytearray()

    def receive(_source, condition):
        if condition & (GLib.IO_HUP | GLib.IO_ERR):
            loop.quit()
            return False
        chunk = os.read(sys.stdin.fileno(), 4096)
        if not chunk:
            loop.quit()
            return False
        buffer.extend(chunk)
        while b'\n' in buffer:
            line, _, remaining = buffer.partition(b'\n')
            buffer[:] = remaining
            try:
                message = json.loads(line)
                guard.acknowledge(message.get('secured'))
            except (ValueError, AttributeError):
                print('Sleep lock bridge: invalid acknowledgement', file=sys.stderr, flush=True)
        return True

    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, receive)
    try:
        guard.hold()
        emit({'event': 'ready'})
        loop.run()
    finally:
        guard.release()


if __name__ == '__main__':
    main()
