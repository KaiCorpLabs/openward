#!/usr/bin/env bash
# Builds libghostty-vt at the pinned commit (GHOSTTY_COMMIT) into the user
# cache, where ghostty-engine's build.rs looks for it.
#
#   ./build-libghostty.sh                 # host target
#   ./build-libghostty.sh aarch64-linux-android
#   ./build-libghostty.sh --bindings      # host build + regenerate src/sys.rs
#
# Needs Zig 0.16.0 exactly (brew install zig@0.16) and git.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
commit="$(tr -d '[:space:]' < "$here/GHOSTTY_COMMIT")"
if [[ "$(uname)" == Darwin ]]; then
  cache="${OPENWARD_CACHE:-$HOME/Library/Caches/openward}"
else
  cache="${OPENWARD_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/openward}"
fi
src="$cache/ghostty/src"

bindings=false
target=native
for arg in "$@"; do
  case "$arg" in
    --bindings) bindings=true ;;
    *) target="$arg" ;;
  esac
done

zig_version="$(zig version)"
if [[ "$zig_version" != 0.16.0 ]]; then
  echo "error: Zig 0.16.0 required, found $zig_version (brew install zig@0.16)" >&2
  exit 1
fi

if [[ ! -d "$src/.git" ]]; then
  git clone --filter=blob:none https://github.com/ghostty-org/ghostty.git "$src"
fi
if ! git -C "$src" cat-file -e "$commit^{commit}" 2>/dev/null; then
  git -C "$src" fetch --quiet origin
fi
git -C "$src" -c advice.detachedHead=false checkout --quiet "$commit"

if [[ "$target" == native ]]; then
  arch="$(uname -m)"; [[ "$arch" == arm64 ]] && arch=aarch64
  os="$(uname | tr '[:upper:]' '[:lower:]')"; [[ "$os" == darwin ]] && os=macos
  name="$arch-$os"
  target_flag=()
else
  name="$target"
  target_flag=("-Dtarget=$target")
fi
out="$cache/ghostty/build/${commit:0:8}/$name"

(cd "$src" && zig build -Demit-lib-vt=true -Doptimize=ReleaseFast "${target_flag[@]}" --prefix "$out")
echo "libghostty-vt: $out"

if $bindings; then
  (cd "$here/bindgen-gen" && cargo run --release -- "$out/include" "$here/src/sys.rs")
fi
