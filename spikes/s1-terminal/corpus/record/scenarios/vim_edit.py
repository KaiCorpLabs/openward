#!/usr/bin/env python3
"""Navigates, searches, edits, substitutes and undoes in a Python file."""

from drive import repeat, run

run(
    ["vim", "-N", "-u", "NONE", "-c", "syntax on", "-c", "set number", "-c", "set laststatus=2", "/data/sample.py"],
    repeat("\x04", 15, 0.08)
    + repeat("\x15", 10, 0.08)
    + [("/def connect\r", 0.3)]
    + repeat("n", 12, 0.12)
    + [("o        # retry with exponential backoff\x1b", 0.3), ("yyp", 0.2), (":%s/self/this/g\r", 0.5), ("u", 0.3), ("G", 0.3), ("gg", 0.3)]
    + repeat("j", 30, 0.03)
    + [(":vsplit\r", 0.4)]
    + repeat("\x04", 10, 0.08)
    + [(":qa!\r", 0.5)],
)
