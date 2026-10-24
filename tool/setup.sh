#!/usr/bin/env bash
# From a fresh clone to `make ci`: what the build needs, at the versions it
# pins. What can be installed for the project alone is (the Rust toolchain,
# cargo's tools, Flutter through FVM, libghostty-vt); system programs are
# only checked, with how to get them, since they are the machine's.
#
#   make setup
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

missing=()
need() {
  local cmd="$1" how="$2"
  if command -v "$cmd" >/dev/null; then
    echo "ok: $cmd"
  else
    echo "missing: $cmd ($how)"
    missing+=("$cmd")
  fi
}

brew=""
[[ "$(uname)" == Darwin ]] && brew="brew install "
need git "${brew}git"
need rustup "https://rustup.rs"
need fvm "${brew}fvm"
need zig "${brew}zig@0.16"
need jq "${brew}jq"
# The S2 SSH servers of the tests: podman, or docker.
command -v docker >/dev/null || need podman "${brew}podman"
if [[ "$(uname)" == Darwin ]] && ! xcode-select -p >/dev/null 2>&1; then
  echo "missing: Xcode (from the App Store, then: sudo xcode-select -s /Applications/Xcode.app)"
  missing+=(xcode)
fi
if ((${#missing[@]})); then
  echo "Install what is missing, then run make setup again." >&2
  exit 1
fi

if [[ "$(zig version)" != 0.16.0 ]]; then
  echo "error: Zig 0.16.0 required, found $(zig version) (${brew}zig@0.16)" >&2
  exit 1
fi

echo "== Rust $(sed -n 's/^channel = "\(.*\)"/\1/p' core/rust-toolchain.toml), from core/rust-toolchain.toml"
(cd core && rustup show active-toolchain >/dev/null)

# cargo's tools, at the versions the repository is checked with. The
# bindings' generator must be the bridge's own version.
frb="$(sed -n 's/^flutter_rust_bridge = "=\(.*\)"/\1/p' core/crates/openward-ffi/Cargo.toml)"
cargo_tool() {
  local crate="$1" bin="$2" version="$3"; shift 3
  if "$bin" --version 2>/dev/null | grep -q "$version"; then
    echo "ok: $crate $version"
  else
    echo "== $crate $version"
    cargo install "$crate" --locked --version "$version" "$@"
  fi
}
cargo_tool cargo-deny cargo-deny 0.20.2
cargo_tool cargo-about cargo-about 0.9.2 --features cli
cargo_tool flutter_rust_bridge_codegen flutter_rust_bridge_codegen "$frb"

echo "== Flutter $(jq -r .flutter .fvmrc), through FVM"
fvm install
(cd app && fvm flutter pub get >/dev/null)

echo "== libghostty-vt"
core/crates/openward-ghostty/build-libghostty.sh

echo
echo "Ready: make test (the core), make ci (everything, as before a push)."
