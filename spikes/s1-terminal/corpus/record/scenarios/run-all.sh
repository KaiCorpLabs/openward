#!/usr/bin/env bash
# Records every scenario into /out/small (committed, < 5 MB each) and
# /out/big (regenerated, never committed). Runs inside the container.
set -euo pipefail

COLS=200
ROWS=50
mkdir -p /home/demo /data /out/small /out/big
cd /home/demo

# Synthetic inputs, deterministic.
python3 /scenarios/gen_data.py /data

rec() {
  local out="$1"; shift
  local version
  version="$(asciinema --version | grep -oE '[0-9]+' | head -1)"
  echo "== $out"
  if [[ "$version" -ge 3 ]]; then
    asciinema rec --quiet --overwrite --window-size "${COLS}x${ROWS}" --command "$*" "$out"
  else
    asciinema rec --quiet --overwrite --cols "$COLS" --rows "$ROWS" -c "$*" "$out"
  fi
}

# Line-oriented output (also used to fill scrollback in memory tests).
rec /out/small/ls-color.cast "ls -la --color=always /usr/bin /usr/share/doc | head -n 3000"
rec /out/small/progress.cast "python3 /scenarios/progress.py"
rec /out/small/agent-tui.cast "python3 /scenarios/agent_tui.py"
rec /out/big/cat-log.cast "python3 /scenarios/logs.py --lines 300000"
rec /out/big/ls-recursive.cast "ls -laR --color=always /usr"

# Full-screen applications driven through a PTY (drive.py).
rec /out/small/man-tmux.cast "python3 /scenarios/man_page.py"
rec /out/small/vim-edit.cast "python3 /scenarios/vim_edit.py"
rec /out/small/vim-cjk.cast "python3 /scenarios/vim_cjk.py"

# htop with some load, so the process list keeps changing.
(for _ in 1 2; do timeout 14 sh -c 'while :; do :; done' & done; wait) &
# --foreground: otherwise timeout puts htop in a background process group
# and it loses the terminal.
rec /out/small/htop.cast "timeout --foreground 12 htop -d 3"
wait

# tmux with four panes updating at once.
rec /out/small/tmux-4panes.cast "bash /scenarios/tmux.sh"

ls -la /out/small /out/big
