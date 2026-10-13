#!/usr/bin/env python3
"""Deterministic synthetic files for the recorded scenarios."""

import random
import sys
from pathlib import Path

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
rng = random.Random(2026)

# A Python module with varied, plausible code for vim.
names = ["session", "host", "tunnel", "vault", "identity", "snippet", "frame", "engine", "relay", "device"]
lines = ['"""Synthetic module for the S1 corpus."""', "", "import os", "import json", ""]
for i in range(220):
    n = rng.choice(names)
    cls = n.capitalize() + str(i)
    lines += [
        f"class {cls}:",
        f'    """Handles {n} number {i}."""',
        "",
        "    def __init__(self, name, port=22):",
        "        self.name = name",
        "        self.port = port",
        f"        self.retries = {rng.randint(1, 9)}",
        "",
        f"    def connect(self, timeout={rng.randint(1, 30)}):",
        "        for attempt in range(self.retries):",
        f'            if self.port > {rng.randint(1000, 9000)}:',
        f'                raise ValueError("port out of range: %d" % self.port)',
        "        return json.dumps({'name': self.name, 'port': self.port})",
        "",
    ]
(out / "sample.py").write_text("\n".join(lines) + "\n", encoding="utf-8")

# Mixed-script text for vim with CJK and emoji.
pieces = ["漢字", "かな", "カタカナ", "한국어", "中文测试", "Привет", "Ωμέγα", "é", "ñ", "👍🏽", "🚀", "─┼─", "ascii"]
cjk = []
for i in range(400):
    cjk.append(f"{i:04d} " + " ".join(rng.choice(pieces) for _ in range(rng.randint(6, 18))))
(out / "cjk.txt").write_text("\n".join(cjk) + "\n", encoding="utf-8")
