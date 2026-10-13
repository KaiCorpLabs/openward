#!/usr/bin/env python3
"""Pages through `man tmux` in less, searches and quits."""

from drive import repeat, run

run(
    ["man", "tmux"],
    repeat(" ", 40, 0.08)
    + [("/OPTIONS\r", 0.4)]
    + repeat("n", 8, 0.15)
    + repeat("b", 20, 0.06)
    + [("G", 0.3), ("g", 0.3), ("q", 0.5)],
    env={"MANPAGER": "less -R", "MANWIDTH": "200"},
)
