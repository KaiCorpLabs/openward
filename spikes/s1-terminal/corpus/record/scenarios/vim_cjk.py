#!/usr/bin/env python3
"""Scrolls and types mixed-script text (CJK, Hangul, accents, emoji)."""

from drive import repeat, run

typed = [(piece, 0.15) for piece in ["漢字テスト ", "かなカナ ", "한국어 입력 ", "中文测试 ", "café ñandú ", "👍🏽 🚀 ", "─┼─ │ "]]
run(
    ["vim", "-N", "-u", "NONE", "-c", "set number", "-c", "set encoding=utf-8", "/data/cjk.txt"],
    repeat("\x04", 12, 0.1)
    + [("Go", 0.2)]
    + typed
    + [("\x1b", 0.3), ("gg", 0.3)]
    + repeat("w", 20, 0.05)
    + [(":q!\r", 0.5)],
)
