#!/usr/bin/env bash
# Fails if any recording contains data from the host that recorded it:
# user name, host names or home paths. Run before committing casts.
set -euo pipefail

user="$(id -un)"
patterns=("$user" "$HOME" "/Users/" "$(hostname -s)" "$(hostname)")
status=0
for dir in "$@"; do
  for cast in "$dir"/*.cast; do
    [[ -e "$cast" ]] || continue
    for p in "${patterns[@]}"; do
      [[ -n "$p" ]] || continue
      if grep -q -F -- "$p" "$cast"; then
        echo "LEAK: $(basename "$cast") contains '$p'" >&2
        status=1
      fi
    done
    size=$(wc -c < "$cast")
    printf "ok   %-24s %10s KB\n" "$(basename "$cast")" "$((size / 1024))"
  done
done
exit $status
