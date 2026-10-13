#!/usr/bin/env python3
"""Real full-screen programs in tmux (tmux_capture.py), driven step by step
from a shell with TERM=xterm-256color, as OpenWard will set it.
Writes /out/apps.out and /out/apps.ref.jsonl."""

import subprocess

from tmux_capture import Capture

subprocess.run(["python3", "/scenarios/gen_data.py", "/data"], check=True)

# (label, keys for tmux send-keys) — one capture after each.
STEPS = [
    ("vim open", ["vim -N -u NONE -c 'syntax on' -c 'set number' -c 'set laststatus=2' /data/sample.py", "Enter"]),
    ("vim page down", ["C-d", "C-d"]),
    ("vim search", ["/def connect", "Enter"]),
    ("vim insert line", ["o", "        # retry with exponential backoff", "Escape"]),
    ("vim visual block", ["C-v", "j", "j", "l", "l"]),
    ("vim vsplit", ["Escape", ":vsplit", "Enter"]),
    ("vim split", [":split /data/cjk.txt", "Enter"]),
    ("vim cjk insert", ["G", "o", "漢字 かな 한국어 café 👍🏽 ─┼─", "Escape"]),
    ("vim quit", [":qa!", "Enter"]),
    ("less open", ["less -R /data/sample.py", "Enter"]),
    ("less search", ["/class", "Enter"]),
    ("less end", ["G"]),
    ("less quit", ["q"]),
    ("man", ["MANPAGER='less -R' MANWIDTH=100 man tmux", "Enter"]),
    ("man page", ["Space"]),
    ("man quit", ["q"]),
    ("htop", ["htop -d 50", "Enter"]),
    ("htop tree", ["F5"]),
    ("htop quit", ["q"]),
    ("colors 256", ["for i in $(seq 0 255); do printf '\\033[48;5;%sm%4s' $i $i; done; printf '\\033[0m\\n'", "Enter"]),
    ("colors truecolor", ["for i in $(seq 0 8 255); do printf '\\033[38;2;%s;100;%sm#' $i $((255-i)); done; printf '\\033[0m\\n'", "Enter"]),
    ("styles", ["printf '\\033[1mbold\\033[0m \\033[2mdim\\033[0m \\033[3mitalic\\033[0m \\033[4munder\\033[0m \\033[7minverse\\033[0m \\033[9mstrike\\033[0m \\033[4:3mcurly\\033[0m\\n'", "Enter"]),
]

rec = Capture("apps", "bash --norc --noprofile", 120, 40,
              "vim, less, man, htop and bash", term="xterm-256color")
rec.capture("shell")
for label, keys in STEPS:
    rec.send(keys)
    rec.capture(label)
rec.send(["exit", "Enter"])
rec.close()
