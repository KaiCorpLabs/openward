#!/usr/bin/env bash
# Installs Zig 0.16.0 (libghostty-vt's toolchain, ADR-002) on a CI runner,
# verified against the SHA-256 that ziglang.org publishes in its index.
set -euo pipefail

version=0.16.0
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    name="zig-x86_64-linux-$version" ext=tar.xz
    sha=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00 ;;
  Darwin-arm64)
    name="zig-aarch64-macos-$version" ext=tar.xz
    sha=b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489 ;;
  MINGW*-x86_64 | MSYS*-x86_64)
    name="zig-x86_64-windows-$version" ext=zip
    sha=68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e ;;
  *)
    echo "error: no Zig build pinned for $(uname -s)-$(uname -m)" >&2
    exit 1 ;;
esac

dir="${RUNNER_TEMP:-/tmp}/zig"
mkdir -p "$dir"
cd "$dir"
curl -fsSLo "$name.$ext" "https://ziglang.org/download/$version/$name.$ext"
if command -v sha256sum >/dev/null; then
  echo "$sha  $name.$ext" | sha256sum -c -
else
  echo "$sha  $name.$ext" | shasum -a 256 -c -
fi
if [[ "$ext" == zip ]]; then unzip -q "$name.$ext"; else tar -xf "$name.$ext"; fi
echo "$dir/$name" >> "${GITHUB_PATH:-/dev/null}"
"$dir/$name/zig" version
