#!/usr/bin/env bash
# Builds OpenWard for macOS (Apple silicon and Intel) and packs it in a .dmg:
#
#   app/tool/package-macos.sh             # → app/build/OpenWard-<version>-macos.dmg
#   app/tool/package-macos.sh --snapshot  # → OpenWard-<version>+<commit>-macos.dmg
#
# app/tool/release-tap.sh then publishes it in the Homebrew tap. A package
# is only made from the tag v<version> on a clean tree, with the same
# version in pubspec.yaml and core/Cargo.toml, so every published .dmg
# matches a commit (written next to it, in <dmg>.commit). Anything else
# needs --snapshot, whose name release-tap.sh does not publish.
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
snapshot=false
case "${1:-}" in
  "") ;;
  --snapshot) snapshot=true ;;
  *) echo "usage: tool/package-macos.sh [--snapshot]" >&2; exit 2 ;;
esac

# 0.2.0-beta.1+2 in pubspec.yaml → 0.2.0-beta.1
version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
core="$(sed -n 's/^version = "\(.*\)"/\1/p' ../core/Cargo.toml)"
[[ "$core" == "$version" ]] ||
  { echo "error: pubspec.yaml says $version and core/Cargo.toml $core" >&2; exit 1; }
commit="$(git rev-parse HEAD)"
clean=true
[[ -z "$(git status --porcelain)" ]] || clean=false
if $snapshot; then
  name="$version+$(git rev-parse --short HEAD)"
  $clean || name="$name-dirty"
else
  $clean || { echo "error: the tree has changes (commit them, or --snapshot)" >&2; exit 1; }
  git tag --points-at HEAD | grep -qx "v$version" ||
    { echo "error: HEAD is not the tag v$version (tag it, or --snapshot)" >&2; exit 1; }
  name="$version"
fi

rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
"${flutter[@]}" build macos --release

built=build/macos/Build/Products/Release/OpenWard.app
archs="$(lipo -archs "$built/Contents/MacOS/OpenWard")"
[[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]] ||
  { echo "error: the app has $archs, not arm64 and x86_64" >&2; exit 1; }
codesign --verify --deep "$built"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$built" "$stage/"
ln -s /Applications "$stage/Applications"
dmg="build/OpenWard-$name-macos.dmg"
rm -f "$dmg" "$dmg.commit"
hdiutil create -quiet -volname "OpenWard $version" -srcfolder "$stage" \
  -fs HFS+ -format UDZO "$dmg"
echo "$commit" > "$dmg.commit"
shasum -a 256 "$dmg"
echo "commit $commit"
