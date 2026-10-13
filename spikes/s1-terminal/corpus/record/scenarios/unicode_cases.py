#!/usr/bin/env python3
"""Prints one width test per screen, followed by a `|` marker, and waits for
<RETURN>. The column the cursor ends at gives the width the terminal
assigned. Driven by unicode_capture.py."""

import sys

# (name, text). Comments: width with grapheme clustering (mode 2027, as in
# Ghostty) / per-code-point wcwidth, where they differ.
CASES = [
    ("ascii", "a"),
    ("precomposed e-acute", "é"),
    ("e + combining acute", "é"),
    ("CJK ideograph", "日"),
    ("fullwidth A", "Ａ"),
    ("hangul syllable", "한"),
    ("hangul jamo L+V+T", "한"),  # 2 / 2
    ("emoji", "\U0001f642"),
    ("heart + VS16", "❤️"),  # 2 / 1
    ("smiley + VS15", "☺︎"),
    ("thumbs up + skin tone", "\U0001f44d\U0001f3fd"),  # 2 / 4
    ("ZWJ family", "\U0001f468‍\U0001f469‍\U0001f467"),  # 2 / 6
    ("flag ES", "\U0001f1ea\U0001f1f8"),
    ("keycap 1", "1️⃣"),  # 2 / 1
    ("devanagari conjunct", "क्षि"),
    ("thai + vowel mark", "กิ"),
    ("arabic letter", "ع"),
    ("zero-width space", "a​b"),
    ("soft hyphen", "a­b"),
    ("ellipsis (ambiguous)", "…"),
    ("greek alpha (ambiguous)", "α"),
    ("box drawing", "┌─┐"),
    ("emoji modifier alone", "\U0001f3fd"),
    ("rainbow flag (ZWJ + VS16)", "\U0001f3f3️‍\U0001f308"),
]

if __name__ == "__main__":
    for name, text in CASES:
        sys.stdout.write(f"\x1b[2J\x1b[H{name}\r\n{text}|")
        sys.stdout.flush()
        sys.stdin.readline()
