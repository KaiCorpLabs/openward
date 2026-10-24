#!/usr/bin/env bash
# Sets the version everywhere the build reads it, in one go:
#
#   tool/bump-version.sh 0.3.2-beta.6
#
# pubspec.yaml (and its build number, one more), app/lib/core/version.dart,
# core/Cargo.toml and, through it, core/Cargo.lock. The plan's row and the
# release notes are words: they are written by hand. `app/test/version_test`
# and `integration_test/ffi_test` check that the three agree.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
version="${1:?usage: tool/bump-version.sh <version>, as 0.3.2-beta.6}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] ||
  { echo "not a version: $version" >&2; exit 2; }

pubspec=app/pubspec.yaml
build="$(sed -n 's/^version: *[^+]*+\([0-9]*\).*/\1/p' "$pubspec")"
[[ -n "$build" ]] || { echo "no build number in $pubspec" >&2; exit 1; }
next=$((build + 1))

sed -i.bak "s/^version: .*/version: $version+$next/" "$pubspec"
sed -i.bak "s/^const appVersion = '.*';/const appVersion = '$version';/" \
  app/lib/core/version.dart
# The workspace's own version, the only top-level `version =` line.
sed -i.bak "s/^version = \".*\"/version = \"$version\"/" core/Cargo.toml
rm -f "$pubspec.bak" app/lib/core/version.dart.bak core/Cargo.toml.bak
(cd core && cargo update -w --quiet)

echo "version $version (build $next): pubspec.yaml, version.dart, Cargo.toml, Cargo.lock"
echo "by hand: the plan's C5 row and the release notes"
