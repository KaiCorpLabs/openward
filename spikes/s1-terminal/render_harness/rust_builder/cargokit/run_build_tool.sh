#!/usr/bin/env bash
set -e
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "${FLUTTER_ROOT:-}" ]]; then
  DART=dart
else
  DART="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"
fi
exec "$DART" "$BASEDIR/bootstrap.dart" "$@"
