#!/usr/bin/env python3
"""Walks vttest's menus in tmux (tmux_capture.py) and records every screen.
Writes /out/vttest.out and /out/vttest.ref.jsonl."""

import re
import subprocess
import sys

from tmux_capture import Capture

# Menu paths left out: tests that need more than <RETURN> (keyboard, mouse,
# user-defined keys, macros), tests whose screens only echo the reference
# terminal's own answers (reports), printer and Tektronix, parameter
# editing, and items that just reopen an earlier menu (VT220 inside VT320…).
SKIP = {
    "5", "6", "12",
    "11.1.1", "11.1.4", "11.1.7",
    "11.2.1", "11.2.5",
    "11.3.1", "11.3.4", "11.3.5", "11.3.7",
    "11.4.1", "11.4.3", "11.4.4", "11.4.5",
    "11.6.1",
    "11.8.1", "11.8.2", "11.8.3", "11.8.4", "11.8.5", "11.8.6", "11.8.8", "11.8.9",
}
MENU_RE = re.compile(r"Enter choice number \(0 - (\d+)\)")
MAX_ENTERS = 60


def menu_of(lines):
    """(title, max choice) when the screen is a menu, else None."""
    text = "\n".join(lines)
    m = MENU_RE.search(text)
    if not m:
        return None
    title = next((l.strip() for l in lines if l.strip()), "")
    return title, int(m.group(1))


def run_item(rec, path):
    """After choosing an item: <RETURN> until some menu shows up."""
    for n in range(MAX_ENTERS):
        lines = rec.capture(f"{path} #{n}")
        found = menu_of(lines)
        if found:
            return lines, found
        rec.send(["Enter"])
    print(f"warning: {path} did not return to a menu", file=sys.stderr)
    return lines, menu_of(lines)


def explore(rec, lines, path):
    title, top = menu_of(lines)
    print(f"{path or 'main'}: {title} (0-{top})", file=sys.stderr)
    for item in range(1, top + 1):
        here = f"{path}.{item}" if path else f"{item}"
        if here in SKIP:
            continue
        rec.send([str(item), "Enter"])
        lines, found = run_item(rec, here)
        if not found:
            continue
        if found[0] != title:
            # A submenu: walk it, then leave it with 0.
            lines = explore(rec, lines, here)
            rec.send(["0", "Enter"])
            lines, found = run_item(rec, f"{here} exit")
    return lines


def main():
    version = subprocess.run(["vttest", "-V"], capture_output=True, text=True).stdout
    # 24x80.80: the "132-column" passes are drawn at 80 columns. tmux, the
    # reference, does not implement DECCOLM, so a real 132-column switch
    # cannot be compared (Ghostty does switch).
    rec = Capture("vttest", "vttest 24x80.80", 80, 24, version.strip())
    lines = rec.capture("main")
    explore(rec, lines, "")
    rec.send(["0", "Enter"])
    rec.close()


if __name__ == "__main__":
    main()
