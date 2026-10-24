#!/usr/bin/env bash
# Builds libghostty-vt at the pinned commit (GHOSTTY_COMMIT) into the user
# cache, where openward-ghostty's build.rs looks for it.
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
  os="$(uname | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    darwin) os=macos ;;
    # Git Bash / MSYS on Windows: Rust's default target uses the MSVC ABI.
    mingw* | msys* | cygwin*) os=windows-msvc ;;
  esac
  name="$arch-$os"
  if [[ "$os" == windows-msvc ]]; then
    target_flag=("-Dtarget=$name")
  else
    target_flag=()
  fi
else
  name="$target"
  target_flag=("-Dtarget=$target")
fi
out="$cache/ghostty/build/${commit:0:8}/$name"
# ${a[@]+"${a[@]}"}: an empty array under `set -u` in macOS's bash 3.2.
flags=(-Demit-lib-vt=true -Doptimize=ReleaseFast ${target_flag[@]+"${target_flag[@]}"})
# What else makes the build: another Zig, other flags or another script
# make another library, though the commit and target are the same.
key="$({ echo "zig $zig_version"; echo "${flags[*]}"; cat "$0"; } | shasum -a 256 | cut -d' ' -f1)"
# Already built so for this commit and target.
if ! $bindings && compgen -G "$out/lib/*ghostty-vt*" >/dev/null &&
  [[ "$(cat "$out/.build-key" 2>/dev/null)" == "$key" ]]; then
  echo "libghostty-vt: $out (cached)"
  exit 0
fi

rm -rf "$out"
(cd "$src" && zig build "${flags[@]}" --prefix "$out")
echo "$key" > "$out/.build-key"
echo "libghostty-vt: $out"

if $bindings; then
  (cd "$here/bindgen-gen" && cargo run --release -- "$out/include" "$here/src/sys.rs")
fi
