#!/usr/bin/env python3
"""npm/cargo-like output: several progress bars and spinners redrawn in place
with cursor movement, then a summary. About 12 seconds."""

import random
import sys
import time

rng = random.Random(3)
w = sys.stdout.write
spin = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
tasks = [(f"\x1b[1m{name}\x1b[0m", rng.uniform(0.6, 1.8)) for name in
         ["resolve deps", "fetch packages", "extract tarballs", "link binaries", "build native addons", "run postinstall"]]
progress = [0.0] * len(tasks)
w("\x1b[?25l")
for i, (name, _) in enumerate(tasks):
    w(f"  {name}\r\n")
start = time.time()
frame = 0
while min(progress) < 1.0:
    frame += 1
    w(f"\x1b[{len(tasks)}A")
    for i, (name, speed) in enumerate(tasks):
        progress[i] = min(1.0, progress[i] + speed * rng.uniform(0.002, 0.012))
        filled = int(progress[i] * 40)
        mark = "\x1b[32m✔\x1b[0m" if progress[i] >= 1 else f"\x1b[36m{spin[frame % len(spin)]}\x1b[0m"
        bar = "\x1b[32m" + "█" * filled + "\x1b[90m" + "░" * (40 - filled) + "\x1b[0m"
        w(f"\r\x1b[2K{mark} {name:<32} {bar} {int(progress[i] * 100):3d}%  {rng.randint(10, 999)} files\r\n")
    sys.stdout.flush()
    time.sleep(0.05)
w("\x1b[?25h")
w(f"\r\n\x1b[32madded 1284 packages\x1b[0m in {time.time() - start:.1f}s\r\n")
for i in range(40):
    w(f"\x1b[33mwarn\x1b[0m deprecated package-{rng.getrandbits(32):08x}@{rng.randint(0, 9)}.{rng.randint(0, 20)}.{rng.randint(0, 9)}: use something else\r\n")
sys.stdout.flush()
