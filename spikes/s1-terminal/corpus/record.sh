#!/usr/bin/env bash
# Records the S1 real-session corpus in a disposable, offline container and
# checks the result for host data before anything can be committed.
#
#   ./record.sh            # build image, record, check
#
# casts/      small recordings (< 5 MB), committed
# casts-big/  large recordings, regenerated, never committed
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
runtime="$(command -v podman || command -v docker || true)"
if [[ -z "$runtime" ]]; then
  echo "error: podman or docker required" >&2
  exit 1
fi
mkdir -p "$here/casts" "$here/casts-big"

"$runtime" build -t openward-s1-corpus -f "$here/record/Containerfile" "$here/record"
"$runtime" run --rm -t --network=none \
  -v "$here/casts:/out/small" \
  -v "$here/casts-big:/out/big" \
  openward-s1-corpus

"$here/check-casts.sh" "$here/casts" "$here/casts-big"
