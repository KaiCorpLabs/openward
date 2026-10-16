#!/usr/bin/env bash
# Writes Termius/IndexedDB from make.html with headless Chrome, the way
# Termius (an Electron app loaded from file://) keeps its data. make.html
# comes from `cargo test -p openward-import --test termius -- --ignored
# write_page`. Needs Google Chrome; macOS path by default, or $CHROME.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
profile="$(mktemp -d)"
trap 'rm -rf "$profile"' EXIT

# Chrome does not exit on its own; 20 s is plenty for a few records.
perl -e 'alarm shift; exec @ARGV' 20 "$chrome" --headless=new --disable-gpu \
  --no-first-run --user-data-dir="$profile" "file://$here/make.html" \
  >/dev/null 2>&1 || true

src="$profile/Default/IndexedDB/file__0.indexeddb.leveldb"
dest="$here/Termius/IndexedDB/file__0.indexeddb.leveldb"
[[ -f "$src/CURRENT" ]] || { echo "Chrome wrote no IndexedDB" >&2; exit 1; }
rm -rf "$here/Termius"
mkdir -p "$dest"
# The lock and Chrome's own log are not part of the data.
for f in "$src"/*; do
  case "$(basename "$f")" in LOCK | LOG | LOG.old) ;; *) cp "$f" "$dest/" ;; esac
done
ls -l "$dest"
