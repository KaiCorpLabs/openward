#!/usr/bin/env bash
# Four tmux panes updating at once for ~15 s: htop, a log tail, progress bars
# and a clock. tmux attaches to the recording terminal; a timer ends it.
set -euo pipefail
tmux -f /dev/null new-session -d -s s -x 200 -y 50 "htop -d 5"
tmux split-window -t s -h "python3 /scenarios/logs.py --rate 25"
tmux split-window -t s -v "watch -n 0.5 'date; uptime; free -m'"
tmux select-pane -t s:0.0
tmux split-window -t s -v "python3 /scenarios/progress.py; sleep 30"
(sleep 15; tmux kill-server) &
tmux attach -t s || true
