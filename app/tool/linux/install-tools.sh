#!/usr/bin/env bash
# Run only after installing the distribution's curl, Git and CA keyring.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/toolchain-pins.sh"
[[ "${RUST:?}" == "$RUST_VERSION" && "${FLUTTER:?}" == "$FLUTTER_VERSION" && "${ZIG:?}" == "$ZIG_VERSION" ]] || {
  echo 'tool versions differ from reviewed Linux content pins' >&2
  exit 1
}
prefix="${1:-/opt}"
mkdir -p "$prefix"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

init="$tmp/rustup-init"
curl -fsSLo "$init" "https://static.rust-lang.org/rustup/archive/$RUSTUP_VERSION/$RUSTUP_TARGET/rustup-init"
echo "$RUSTUP_SHA256  $init" | sha256sum -c -
chmod +x "$init"
"$init" -y --profile minimal --default-toolchain "$RUST"

# Reuse the runner's reviewed archive hashes, including Linux arm64.
RUNNER_TEMP="$prefix" bash "$here/install-zig.sh"
ln -s "$prefix/zig/zig-$(uname -m)-linux-$ZIG/zig" "$prefix/zig-bin"

git clone --depth 1 --branch "$FLUTTER" https://github.com/flutter/flutter.git "$prefix/flutter"
actual="$(git -C "$prefix/flutter" rev-parse HEAD)"
[[ "$actual" == "$FLUTTER_COMMIT" ]] || {
  echo "Flutter source does not match reviewed commit: $actual" >&2
  exit 1
}
