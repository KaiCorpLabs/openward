#!/usr/bin/env python3
"""Records unicode_cases.py in tmux (tmux_capture.py): one screen per case.
Writes /out/unicode.out and /out/unicode.ref.jsonl."""

from tmux_capture import Capture
from unicode_cases import CASES

rec = Capture("unicode", "python3 /scenarios/unicode_cases.py", 80, 24, "unicode_cases.py")
for name, _ in CASES:
    rec.capture(name)
    rec.send(["Enter"])
rec.close()
