#!/usr/bin/env python3
"""An AI coding agent's terminal UI, as rendered by Ink-style frameworks: the
answer streams above while a bordered status/input box at the bottom is
erased and redrawn many times per second. About 25 seconds, seeded."""

import random
import sys
import time

rng = random.Random(11)
w = sys.stdout.write
COLS = 200
spin = "✻✳✢·✢✳"
box_lines = 0


def draw_box(status, tokens):
    global box_lines
    if box_lines:
        w(f"\x1b[{box_lines}A\r\x1b[J")
    top = "╭" + "─" * (COLS - 2) + "╮"
    mid1 = f"│ \x1b[38;5;208m{spin[int(time.time() * 10) % len(spin)]}\x1b[0m {status:<60} \x1b[90m({tokens} tokens · esc to interrupt)\x1b[0m"
    mid2 = "│ \x1b[90m> \x1b[0m"
    bottom = "╰" + "─" * (COLS - 2) + "╯"
    lines = [top, mid1, mid2, bottom, "  \x1b[90m? for shortcuts\x1b[0m"]
    w("\r\n".join(lines) + "\r\n")
    box_lines = len(lines)


def stream(text, status, tokens):
    """Writes `text` above the box, a few characters at a time."""
    global box_lines
    i = 0
    while i < len(text):
        chunk = text[i:i + rng.randint(2, 9)]
        i += len(chunk)
        if box_lines:
            w(f"\x1b[{box_lines}A\r\x1b[J")
            box_lines = 0
        w(chunk)
        # Ink re-renders the box after every update; keep the partial line.
        if not chunk.endswith("\n"):
            w("\r\n")
            draw_box(status, tokens)
            w(f"\x1b[{box_lines + 1}A\x1b[{(len(text[:i].rsplit(chr(10), 1)[-1]) % COLS) + 1}G")
            w(f"\x1b[{box_lines + 1}B\r")
        else:
            draw_box(status, tokens)
        tokens += rng.randint(1, 4)
        sys.stdout.flush()
        time.sleep(rng.uniform(0.008, 0.03))
    return tokens


words = ("the vault manifest is signed by an admin device and every member key is wrapped with "
         "hpke so the relay never sees plaintext; when a member leaves we rotate the key and "
         "re-encrypt items lazily on the next write").split()
tokens = 0
start = time.time()
w("\x1b[1m\x1b[38;5;208m● OpenWard agent\x1b[0m  \x1b[90mcwd ~/project\x1b[0m\r\n\r\n")
round_ = 0
while time.time() - start < 25:
    round_ += 1
    para = " ".join(rng.choice(words) for _ in range(rng.randint(40, 90)))
    tokens = stream("\x1b[37m" + para + "\x1b[0m\r\n\r\n", "Thinking…", tokens)
    w(f"\x1b[1m⏺ Edit\x1b[0m(src/sync/manifest_{round_}.rs)\r\n")
    for n in range(rng.randint(6, 14)):
        sign, color = rng.choice([("+", "32"), ("-", "31"), (" ", "90")])
        code = " ".join(rng.choice(words) for _ in range(rng.randint(3, 10)))
        w(f"\x1b[{color}m  {rng.randint(10, 400):>4} {sign} {code}\x1b[0m\r\n")
    tokens = stream("\r\n", "Running cargo test…", tokens)
    for _ in range(rng.randint(20, 40)):
        draw_box("Running cargo test…", tokens)
        sys.stdout.flush()
        time.sleep(0.05)
w("\r\n\x1b[32m✔ done\x1b[0m\r\n")
sys.stdout.flush()
