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
    # Any CPU of the kind, not only this one's: a library built on a newer
    # machine (a CI runner, the one that packs a release) must not stop
    # with SIGILL on an older one. A named target is baseline already.
    target_flag=("-Dcpu=baseline")
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
# sha256sum on Linux and in Git for Windows' bash; shasum on macOS.
sha256() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi; }
key="$({ echo "zig $zig_version"; echo "${flags[*]}"; cat "$0"; } | sha256 | cut -d' ' -f1)"
# The library is there. A glob with the folder quoted: on Windows it has
# backslashes (D:\a\_temp), and `compgen -G` reads them as escapes, so it
# never found a build and Windows rebuilt every time.
built() {
  local f
  for f in "$out"/lib/*ghostty-vt*; do
    [[ -e "$f" ]] && return 0
  done
  return 1
}
# Already built so for this commit and target.
if ! $bindings && built &&
  [[ "$(cat "$out/.build-key" 2>/dev/null)" == "$key" ]]; then
  echo "libghostty-vt: $out (cached)"
  exit 0
fi

# Zig's own HTTP client fails on some hosts where curl does not: on the
# Windows runners, GitHub's archives end in `HttpConnectionClosing`. When
# the build stops on a package it could not fetch, curl gets that one,
# `zig fetch` files it under its hash, and the build goes again.
build() {
  local log tmp where file line url tried=" "
  log="$(mktemp)"
  tmp="$(mktemp -d)"
  while true; do
    if (cd "$src" && zig build "${flags[@]}" --prefix "$out") 2>&1 | tee "$log"; then
      rm -rf "$log" "$tmp"
      return 0
    fi
    # `<dir>/build.zig.zon:<line>:<col>: error: …` points at the URL.
    where="$(sed -nE 's/^(.*build\.zig\.zon):([0-9]+):[0-9]+: error: .*/\1|\2/p' "$log" | head -1)"
    [[ -n "$where" ]] || return 1
    file="${where%|*}"
    line="${where##*|}"
    if command -v cygpath >/dev/null; then file="$(cygpath -u "$file")"; fi
    url="$(sed -n "${line}p" "$file" | grep -oE 'https?://[^"]+' | head -1)"
    # Not a URL, or one already fetched this way: a real failure.
    [[ -n "$url" && "$tried" != *" $url "* ]] || return 1
    tried+="$url "
    echo "libghostty-vt: Zig could not fetch $url; fetching it with curl" >&2
    curl -fsSL --retry 5 --retry-all-errors -o "$tmp/${url##*/}" "$url"
    (cd "$src" && zig fetch "$tmp/${url##*/}")
  done
}

rm -rf "$out"
build
echo "$key" > "$out/.build-key"
echo "libghostty-vt: $out"

if $bindings; then
  (cd "$here/bindgen-gen" && cargo run --release -- "$out/include" "$here/src/sys.rs")
fi
