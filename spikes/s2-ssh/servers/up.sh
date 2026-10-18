#!/usr/bin/env bash
# Starts the S2 test servers (podman or docker), listening on 127.0.0.1 only.
#
#   up.sh            # build images, generate fixtures, start everything
#
#   127.0.0.1:22089  OpenSSH 8.9  (Ubuntu 22.04)
#   127.0.0.1:22092  OpenSSH 9.2  (Debian 12)
#   127.0.0.1:22100  OpenSSH 10.0 (Debian 13), also the jump bastion
#   127.0.0.1:22101  OpenSSH 10.0 again, for tests that freeze it (pause)
#   127.0.0.1:22200  Dropbear     (Alpine)
#   jump chain: bastion (22100) → target1 → target2, internal networks only
#
# Fixtures go to $S2_FIXTURES (default: the user cache), never the repo.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
runtime="${S2_RUNTIME:-$(command -v podman || command -v docker || true)}"
[[ -n "$runtime" ]] || { echo "error: podman or docker required" >&2; exit 1; }
if [[ "$(uname)" == Darwin ]]; then
  default_fixtures="$HOME/Library/Caches/openward/s2-fixtures"
else
  default_fixtures="${XDG_CACHE_HOME:-$HOME/.cache}/openward/s2-fixtures"
fi
fixtures="${S2_FIXTURES:-$default_fixtures}"

"$here/fixtures.sh" "$fixtures"

build() { # tag containerfile [base]
  "$runtime" build -q -t "$1" -f "$here/$2" ${3:+--build-arg "BASE=$3"} "$here" >/dev/null
}
build s2-openssh-8.9 Containerfile.openssh ubuntu:22.04
build s2-openssh-9.2 Containerfile.openssh debian:bookworm-slim
build s2-openssh-10.0 Containerfile.openssh debian:trixie-slim
build s2-dropbear Containerfile.dropbear

"$here/down.sh" >/dev/null 2>&1 || true
"$runtime" network create --internal s2-jump-a >/dev/null
"$runtime" network create --internal s2-jump-b >/dev/null

run() { # name image [extra args…]
  local name="$1" image="$2"; shift 2
  "$runtime" run -d --name "$name" --hostname "$name" \
    -v "$fixtures:/fixtures:ro" "$@" "$image" >/dev/null
}
run s2-openssh-8.9 s2-openssh-8.9 -p 127.0.0.1:22089:22
run s2-openssh-9.2 s2-openssh-9.2 -p 127.0.0.1:22092:22
run bastion s2-openssh-10.0 -p 127.0.0.1:22100:22
run s2-freeze s2-openssh-10.0 -p 127.0.0.1:22101:22
run s2-dropbear s2-dropbear -p 127.0.0.1:22200:22
"$runtime" network connect s2-jump-a bastion
run target1 s2-openssh-9.2 --network s2-jump-a
"$runtime" network connect s2-jump-b target1
run target2 s2-openssh-8.9 --network s2-jump-b

# Wait until every published server answers with its SSH banner.
for port in 22089 22092 22100 22101 22200; do
  for _ in $(seq 1 50); do
    if banner="$(nc -w 1 127.0.0.1 "$port" </dev/null 2>/dev/null | head -1)" && [[ "$banner" == SSH-* ]]; then
      printf '%-6s %s\n' "$port" "$banner"
      break
    fi
    sleep 0.2
  done
done
echo "S2_FIXTURES=$fixtures"
