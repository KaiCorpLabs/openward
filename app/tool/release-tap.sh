#!/usr/bin/env bash
# Publishes the macOS package in the KaiCorpLabs Homebrew tap, so the team
# installs and updates OpenWard with `brew install/upgrade --cask openward`:
#
#   app/tool/package-macos.sh
#   app/tool/release-tap.sh
#
# While this repository is private, Homebrew cannot download its releases,
# so the .dmg goes up as a release of the tap (openward-v<version>) and the
# cask points there. A package already published is never replaced: a
# different build needs a new version.
# Needs the tap (brew tap kaicorplabs/tap) and gh with push access to it.
set -euo pipefail

app_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$app_dir"

# 0.2.0-beta.1+2 in pubspec.yaml → 0.2.0-beta.1
version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
dmg="build/OpenWard-$version-macos.dmg"
[[ -f "$dmg" ]] || { echo "no $dmg: run tool/package-macos.sh first" >&2; exit 1; }
sha="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"

repo=KaiCorpLabs/homebrew-tap
tap="$(brew --repo kaicorplabs/tap)"
cask="$tap/Casks/openward.rb"
tag="openward-v$version"
[[ -z "$(git -C "$tap" status --porcelain)" ]] ||
  { echo "the tap at $tap has uncommitted changes" >&2; exit 1; }
git -C "$tap" pull --quiet --ff-only

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  published="$(gh release view "$tag" --repo "$repo" --json assets \
    -q ".assets[] | select(.name == \"$(basename "$dmg")\") | .digest")"
  if [[ -z "$published" ]]; then
    gh release upload "$tag" "$dmg" --repo "$repo"
  elif [[ "$published" != "sha256:$sha" ]]; then
    echo "$tag already has a different $(basename "$dmg"); bump the version" >&2
    exit 1
  fi
else
  pre=()
  [[ "$version" == *-* ]] && pre=(--prerelease)
  gh release create "$tag" "$dmg" --repo "$repo" --target main ${pre[@]+"${pre[@]}"} \
    --latest=false --title "OpenWard $version" --notes "$(cat <<EOF
Paquete de macOS de OpenWard $version para el cask \`openward\` de este tap.

\`\`\`sh
brew install --cask openward    # o brew upgrade --cask openward
\`\`\`

sha256 \`$sha\`
EOF
)"
fi

sed -E -i '' \
  -e "s/^  version \".*\"/  version \"$version\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$cask"
brew style --cask "$cask"
# Downloads the published file and checks it against the cask's sha256.
brew fetch --cask --force kaicorplabs/tap/openward

if ! git -C "$tap" diff --quiet -- "$cask"; then
  git -C "$tap" commit --quiet -m "openward $version" -- "$cask"
fi
git -C "$tap" push --quiet origin main
echo "openward $version in kaicorplabs/tap ($sha)"
