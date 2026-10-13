"""Drives a full-screen program through a PTY: sends scripted keystrokes with
sub-second delays while relaying its output continuously, so a recording
keeps realistic timing (expect only relays output while it is matching)."""

import fcntl
import os
import pty
import select
import struct
import sys
import termios
import time

COLS, ROWS = 200, 50


def _pump(fd, seconds):
    """Relays output for `seconds`. Returns False once the program exits."""
    out = sys.stdout.buffer
    end = time.monotonic() + seconds
    while True:
        left = end - time.monotonic()
        if left <= 0:
            return True
        ready, _, _ = select.select([fd], [], [], left)
        if fd in ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return False
            if not data:
                return False
            out.write(data)
            out.flush()


def run(argv, steps, env=None, settle=1.0):
    """`steps` is a list of (keys, delay_after_seconds)."""
    pid, fd = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        os.execvpe(argv[0], argv, {**os.environ, **(env or {})})
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
    _pump(fd, settle)
    for keys, delay in steps:
        os.write(fd, keys.encode())
        if not _pump(fd, delay):
            break
    while _pump(fd, 1.0):
        pass
    os.waitpid(pid, 0)


def repeat(keys, times, delay):
    return [(keys, delay)] * times
