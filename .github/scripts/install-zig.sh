#!/usr/bin/env bash
# Installs Zig 0.17.1 (libghostty-vt's toolchain, ADR-002) on a CI runner,
# verified against the SHA-256 that ziglang.org publishes in its index.
set -euo pipefail

version=0.17.1
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    name="zig-x86_64-linux-$version" ext=tar.xz
    sha=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a ;;
  Linux-aarch64)
    name="zig-aarch64-linux-$version" ext=tar.xz
    sha=a1546d5646eb184437918d6635ca6b762a0e889eac09cef720ee7a1ed3fe7795 ;;
  Darwin-arm64)
    name="zig-aarch64-macos-$version" ext=tar.xz
    sha=75f1bc7a1e9852f17ec9a0c1895f767c4ec56d46bc8a834920eece1d0359dd8d ;;
  MINGW*-x86_64 | MSYS*-x86_64)
    name="zig-x86_64-windows-$version" ext=zip
    sha=b03f477a1943673e02aca0f570e8030dffd536ce1f45cbc4d3326ec31159562e ;;
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
