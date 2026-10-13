"""Records a program's raw output and a reference rendering of it, using
tmux as the reference terminal (it also answers the program's queries).

For every screen the program stops at, the reference file gets one JSON line
with the byte offset reached in the raw output, tmux's screen and its cursor.
Replaying the raw output into another engine up to each offset must give the
same screen (termbench conform). The first line holds the size and versions.
"""

import json
import os
import subprocess
import sys
import time

OUT = "/out"
CONF = "/tmp/capture-tmux.conf"
SESSION = "cap"


def tmux(*args, check=True):
    return subprocess.run(
        ["tmux", "-f", CONF, *args],
        check=check,
        capture_output=True,
        text=True,
    ).stdout


class Capture:
    def __init__(self, name, command, cols, rows, program, term=None):
        self.raw = f"{OUT}/{name}.out"
        self.cols, self.rows = cols, rows
        self.step = 0
        os.makedirs(OUT, exist_ok=True)
        if os.path.exists(self.raw):
            os.remove(self.raw)
        # No status line: the pane gets every row.
        with open(CONF, "w") as f:
            f.write("set -g status off\n")
            if term:
                # What programs see as TERM inside the pane.
                f.write(f'set -g default-terminal "{term}"\n')
        # Start the program only once pipe-pane is attached, so no byte of
        # its output is missed.
        tmux(
            "new-session", "-d", "-s", SESSION, "-x", str(cols), "-y", str(rows),
            f"sh -c 'read go; exec {command}'",
        )
        tmux("pipe-pane", "-O", "-t", SESSION, f"cat > {self.raw}")
        time.sleep(0.3)
        self.ref = open(f"{OUT}/{name}.ref.jsonl", "w")
        meta = {"cols": cols, "rows": rows, "program": program,
                "reference": tmux("-V").strip()}
        self.ref.write(json.dumps(meta) + "\n")
        self.send(["Enter"])

    def raw_size(self):
        try:
            return os.path.getsize(self.raw)
        except FileNotFoundError:
            return 0

    def settle(self, quiet=0.8, timeout=20.0):
        """Waits until the program has produced nothing for `quiet` s."""
        deadline = time.monotonic() + timeout
        last, since = self.raw_size(), time.monotonic()
        while time.monotonic() < deadline:
            time.sleep(0.05)
            size = self.raw_size()
            if size != last:
                last, since = size, time.monotonic()
            elif time.monotonic() - since >= quiet:
                return
        print(f"warning: output never settled ({last} bytes)", file=sys.stderr)

    def screen(self):
        lines = tmux("capture-pane", "-p", "-N", "-t", SESSION).split("\n")
        lines = [l.rstrip() for l in lines[: self.rows]]
        return lines + [""] * (self.rows - len(lines))

    def capture(self, label):
        """Records the current screen; returns its lines."""
        while True:
            self.settle()
            offset = self.raw_size()
            lines = self.screen()
            # The same screen with its attributes as SGR sequences, so
            # colors and styles can be compared too.
            sgr = tmux("capture-pane", "-p", "-e", "-N", "-t", SESSION).split("\n")
            cursor = tmux("display", "-p", "-t", SESSION, "#{cursor_x} #{cursor_y}")
            if self.raw_size() == offset:
                break
        x, y = (int(v) for v in cursor.split())
        self.ref.write(
            json.dumps(
                {"step": self.step, "label": label, "offset": offset,
                 "cursor": [y, x], "screen": lines,
                 "screen_sgr": sgr[: self.rows]},
                ensure_ascii=False,
            )
            + "\n"
        )
        self.step += 1
        return lines

    def send(self, keys):
        tmux("send-keys", "-t", SESSION, *keys)

    def close(self):
        time.sleep(1)
        tmux("kill-server", check=False)
        self.ref.close()
        print(f"{self.step} screens, {self.raw_size()} bytes", file=sys.stderr)
