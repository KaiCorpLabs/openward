#!/usr/bin/env bash
# No downloaded tool runs before its repository-pinned digest is checked.
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
server=''
cleanup() {
  if [[ -n "$server" ]]; then kill "$server"; wait "$server" 2>/dev/null || true; fi
  rm -rf "$tmp"
}
trap cleanup EXIT
checked_download() {
  local url="$1" sha="$2" destination="$3"
  mkdir -p "$(dirname "$destination")"
  curl -fsSLo "$destination" "$url"
  echo "$sha  $destination" | sha256sum -c -
}
stage() {
  local list="$1" url="$2" destination="$3"
  while read -r sha path; do
    [[ -z "$sha" || "$sha" == \#* ]] && continue
    checked_download "$url/$path" "$sha" "$destination/$path"
  done < "$list"
}

init="$tmp/rustup-init"
checked_download "https://static.rust-lang.org/rustup/archive/$RUSTUP_VERSION/$RUSTUP_TARGET/rustup-init" "$RUSTUP_SHA256" "$init"
dist="$tmp/dist"
rust_dist="$dist/rust/dist"
manifest="channel-rust-$RUST.toml"
checked_download "https://static.rust-lang.org/dist/$manifest" "$RUST_MANIFEST_SHA256" "$rust_dist/$manifest"
echo "$RUST_MANIFEST_SHA256  $manifest" > "$rust_dist/$manifest.sha256"
stage "$here/rust-$(uname -m).sha256" https://static.rust-lang.org/dist "$rust_dist"
arch=x64
[[ "$(uname -m)" == aarch64 ]] && arch=arm64
stage "$here/flutter-$arch.sha256" https://storage.googleapis.com "$dist"

git clone --depth 1 --branch "$FLUTTER" https://github.com/flutter/flutter.git "$prefix/flutter"
actual="$(git -C "$prefix/flutter" rev-parse HEAD)"
[[ "$actual" == "$FLUTTER_COMMIT" ]] || {
  echo "Flutter source does not match reviewed commit: $actual" >&2
  exit 1
}

# The verified scripts consume a closed local mirror. They cannot replace a
# manifest/hash pair or fetch an extra executable from the remote origin.
python3 "$here/serve-tools.py" "$dist" "$tmp/server-url" &
server=$!
for ((i=0; i<100; i++)); do
  [[ ! -s "$tmp/server-url" ]] || break
  kill -0 "$server" || { echo 'tool mirror failed to start' >&2; exit 1; }
  sleep 0.05
done
mirror="$(cat "$tmp/server-url")"
export RUSTUP_DIST_SERVER="$mirror/rust"
chmod +x "$init"
"$init" -y --profile minimal --default-toolchain "$RUST"

RUNNER_TEMP="$prefix" bash "$here/install-zig.sh"
ln -s "$prefix/zig/zig-$(uname -m)-linux-$ZIG/zig" "$prefix/zig-bin"
export FLUTTER_STORAGE_BASE_URL="$mirror"
export PATH="$prefix/flutter/bin:$PATH"
flutter config --no-analytics --no-cli-animations
flutter precache --linux
