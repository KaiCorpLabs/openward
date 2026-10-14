#!/usr/bin/env bash
# Builds OpenWard for macOS (Apple silicon and Intel) and packs it in a .dmg:
#
#   app/tool/package-macos.sh        # → app/build/OpenWard-<version>-macos.dmg
#
# macOS 13 or later (libghostty-vt targets it).
# Unsigned and not notarized (alpha): the app is signed ad hoc, so macOS
# asks before opening it the first time (see docs/plan/alfa-escritorio.md).
# Needs libghostty-vt for both architectures:
#   core/crates/openward-ghostty/build-libghostty.sh
#   core/crates/openward-ghostty/build-libghostty.sh x86_64-macos
set -euo pipefail

app_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$app_dir"
flutter=(${FLUTTER:-fvm flutter})

# 0.1.0+1 in pubspec.yaml → 0.1.0-alfa
version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)-alfa"

rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
"${flutter[@]}" build macos --release

built=build/macos/Build/Products/Release/OpenWard.app
lipo -archs "$built/Contents/MacOS/OpenWard"
codesign --verify --deep "$built"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$built" "$stage/"
ln -s /Applications "$stage/Applications"
dmg="build/OpenWard-$version-macos.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname "OpenWard $version" -srcfolder "$stage" \
  -fs HFS+ -format UDZO "$dmg"
shasum -a 256 "$dmg"
