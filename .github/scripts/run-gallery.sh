#!/usr/bin/env bash
# From app/: desktop integration bindings can return success despite a failed
# test teardown. Preserve the real process status and reject the inner failure.
set -euo pipefail
gallery_device="${1:?usage: run-gallery.sh <linux|macos|windows>}"
gallery_log="$(mktemp)"
trap 'rm -f "$gallery_log"' EXIT
flutter drive -d "$gallery_device" --driver=test_driver/integration_test.dart \
  --target=integration_test/gallery_test.dart 2>&1 | tee "$gallery_log"
if grep -q 'Some tests failed\.' "$gallery_log"; then
  echo '::error::The gallery reported failed tests despite a successful driver exit.' >&2
  exit 1
fi
