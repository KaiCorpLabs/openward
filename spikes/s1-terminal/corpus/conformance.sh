#!/usr/bin/env bash
# Records the S1.6 conformance references in the disposable, offline
# container: vttest's menus and the Unicode width cases, each run inside
# tmux, which renders the reference screens and answers queries.
#
#   ./conformance.sh       # then: termbench conform (see docs/spikes/S1-terminal.md)
#
# conformance/<name>.out          the program's raw output
# conformance/<name>.ref.jsonl    tmux's screen and cursor at every stop
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
runtime="$(command -v podman || command -v docker || true)"
if [[ -z "$runtime" ]]; then
  echo "error: podman or docker required" >&2
  exit 1
fi
mkdir -p "$here/conformance"

"$runtime" build -t openward-s1-corpus -f "$here/record/Containerfile" "$here/record"
for name in vttest unicode apps; do
  "$runtime" run --rm --network=none \
    -v "$here/conformance:/out" \
    --entrypoint python3 \
    openward-s1-corpus "/scenarios/${name}_capture.py"
done

"$here/check-casts.sh" "$here/conformance"
