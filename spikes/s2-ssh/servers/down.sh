#!/usr/bin/env bash
# Stops and removes the S2 test servers and their networks.
set -uo pipefail

runtime="${S2_RUNTIME:-$(command -v podman || command -v docker || true)}"
[[ -n "$runtime" ]] || exit 0
"$runtime" rm -f s2-openssh-8.9 s2-openssh-9.2 bastion s2-freeze s2-dropbear target1 target2 >/dev/null 2>&1
"$runtime" network rm s2-jump-a s2-jump-b >/dev/null 2>&1
exit 0
