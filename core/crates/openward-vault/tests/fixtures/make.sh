#!/usr/bin/env bash
# Writes vault-<version>.sqlite with the vault code of a published tag, so
# the tests open a vault exactly as that version left it:
#
#   core/crates/openward-vault/tests/fixtures/make.sh v0.3.1-beta.9 0.3.1
#
# gen-<version>.rs, with that version's types, goes into a worktree of the
# tag as an example of openward-vault and runs there. One more with each
# version that adds fields to the vault.
set -euo pipefail

tag="${1:?usage: make.sh <tag> <version>}"
version="${2:?usage: make.sh <tag> <version>}"
here="$(cd "$(dirname "$0")" && pwd)"
gen="$here/gen-$version.rs"
[[ -f "$gen" ]] || { echo "no $gen" >&2; exit 1; }

tree="$(mktemp -d)/openward-$version"
git -C "$here" worktree add --quiet --detach "$tree" "$tag"
trap 'git -C "$here" worktree remove --force "$tree"' EXIT
mkdir -p "$tree/core/crates/openward-vault/examples"
cp "$gen" "$tree/core/crates/openward-vault/examples/fixture.rs"
out="$here/vault-$version.sqlite"
rm -f "$out" "$out.lock" "$out-shm" "$out-wal"
(cd "$tree/core" && cargo run --quiet -p openward-vault --example fixture -- "$out")
rm -f "$out.lock" "$out-shm" "$out-wal"
echo "$out from $tag"
