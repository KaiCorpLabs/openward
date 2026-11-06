#!/usr/bin/env bash
# The licenses of what the core ships, for the app's list of licenses
# (Ajustes → Acerca de → Licencias), into app/assets/licenses/core.json:
#
#   tool/licenses.sh           write it
#   tool/licenses.sh --check   fail if it is not what it would write
#
# The Rust crates come from cargo-about (core/about.toml), each license
# text once with the crates under it. libghostty-vt is built by Zig, which
# cargo knows nothing of: Ghostty's license and those of what it builds in
# (simdutf, Highway, Wuffs, uucode) come from its sources at the commit in
# GHOSTTY_COMMIT and from Zig's package cache, both left by
# build-libghostty.sh; HIDAPI's (the C the hidapi crate builds in), from
# that crate's sources. Needs cargo-about and jq (`make setup`).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/app/assets/licenses/core.json"
check=false
[[ "${1:-}" == "--check" ]] && check=true

command -v cargo-about >/dev/null || {
  echo "cargo-about is missing: cargo install cargo-about --locked --features cli" >&2
  exit 1
}
command -v jq >/dev/null || { echo "jq is missing" >&2; exit 1; }

if [[ "$(uname)" == Darwin ]]; then
  cache="${OPENWARD_CACHE:-$HOME/Library/Caches/openward}"
else
  cache="${OPENWARD_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/openward}"
fi
src="$cache/ghostty/src"
zig_cache="${ZIG_GLOBAL_CACHE_DIR:-$HOME/.cache/zig}/p"
commit="$(cat "$root/core/crates/openward-ghostty/GHOSTTY_COMMIT")"
[[ "$(git -C "$src" rev-parse HEAD 2>/dev/null)" == "$commit" ]] || {
  echo "Ghostty's sources are not at $commit: run core/crates/openward-ghostty/build-libghostty.sh" >&2
  exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A Zig package's file, by the hash its build.zig.zon gives.
zig_file() {
  local zon="$1" name="$2" file="$3" hash
  hash="$(grep -A3 "\\.$name = " "$zon" | sed -n 's/.*\.hash = "\(.*\)".*/\1/p' | head -1)"
  [[ -n "$hash" && -f "$zig_cache/$hash.tar.gz" ]] || {
    echo "$name is not in Zig's cache ($zig_cache): build libghostty-vt first" >&2
    exit 1
  }
  tar -xzOf "$zig_cache/$hash.tar.gz" "$hash/$file"
}

# Rust: one entry per license text, with the crates that have it; the
# workspace's own crates are the app's.
(cd "$root/core" && cargo about generate --format json --offline --fail \
  -m crates/openward-ffi/Cargo.toml -o "$tmp/about.json" 2>/dev/null)
jq '[.licenses
     | group_by(.text)[]
     | {packages: ([.[].used_by[].crate.name]
                   | map(select(startswith("openward-") | not))
                   | unique),
        text: .[0].text}
     | select(.packages | length > 0)]
    | sort_by(.packages[0])' "$tmp/about.json" > "$tmp/rust.json"

# libghostty-vt and what it builds in.
cp "$src/LICENSE" "$tmp/ghostty.txt"
{
  cat <<'EOF'
MIT License (simdutf is also available under the Apache License 2.0)

Copyright 2021 The simdutf authors

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Its CPU detection comes from PyTorch:

EOF
  # The notice simdutf carries for it, as it carries it.
  sed -n '/^\/\* From$/,/^\*\/$/p' "$src/pkg/simdutf/vendor/simdutf.h" | sed '1d;$d'
} > "$tmp/simdutf.txt"
zig_file "$src/pkg/highway/build.zig.zon" highway LICENSE > "$tmp/highway.txt"
zig_file "$src/pkg/wuffs/build.zig.zon" wuffs LICENSE > "$tmp/wuffs.txt"
# Its package leaves out the licenses it names: its UTF-8 decoder is under
# the MIT license, and its Unicode data under Unicode's, the text the crates
# that carry Unicode data come with.
{
  zig_file "$src/build.zig.zon" uucode LICENSE.md
  cat <<'EOF'

Its UTF-8 decoder: Copyright (c) 2008-2010 Bjoern Hoehrmann
<bjoern@hoehrmann.de>, under the MIT License, as above.

Its Unicode data, under the Unicode License v3:

EOF
  jq -r '[.licenses[] | select(.id == "Unicode-3.0")][0].text' "$tmp/about.json"
} > "$tmp/uucode.txt"
jq -n \
  --rawfile ghostty "$tmp/ghostty.txt" \
  --rawfile simdutf "$tmp/simdutf.txt" \
  --rawfile highway "$tmp/highway.txt" \
  --rawfile wuffs "$tmp/wuffs.txt" \
  --rawfile uucode "$tmp/uucode.txt" \
  '[{packages: ["libghostty-vt (Ghostty)"], text: $ghostty},
    {packages: ["simdutf"], text: $simdutf},
    {packages: ["Highway"], text: $highway},
    {packages: ["Wuffs"], text: $wuffs},
    {packages: ["uucode"], text: $uucode}]' > "$tmp/ghostty.json"

# HIDAPI, the C that hidapi (security keys) builds in, under the BSD-style
# one of its three licenses.
hidapi="$(cd "$root/core" && cargo metadata --format-version 1 --offline 2>/dev/null |
  jq -r '.packages[] | select(.name == "hidapi") | .manifest_path')"
[[ -n "$hidapi" ]] || { echo "hidapi is not among the crates" >&2; exit 1; }
{
  echo "HIDAPI can be used under one of three licenses: OpenWard takes the BSD-style one."
  echo
  cat "$(dirname "$hidapi")/etc/hidapi/LICENSE-bsd.txt"
} > "$tmp/hidapi.txt"
jq -n --rawfile hidapi "$tmp/hidapi.txt" \
  '[{packages: ["HIDAPI (hidapi)"], text: $hidapi}]' > "$tmp/c.json"

jq -s '.[0] + .[1] + .[2]' "$tmp/ghostty.json" "$tmp/c.json" "$tmp/rust.json" > "$tmp/core.json"

if $check; then
  if ! cmp -s "$tmp/core.json" "$out"; then
    echo "app/assets/licenses/core.json is out of date: run tool/licenses.sh" >&2
    exit 1
  fi
  echo "licenses: up to date"
else
  mkdir -p "$(dirname "$out")"
  cp "$tmp/core.json" "$out"
  echo "licenses: $(jq length "$out") texts in ${out#"$root"/}"
fi
