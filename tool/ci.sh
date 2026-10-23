#!/usr/bin/env bash
# The CI of .github/workflows/ci.yml, run on this machine. Actions does not
# run jobs for this repository, so main only moves forward with a passing
# run here:
#
#   tool/ci.sh           # everything, as before a release or a push to main
#   tool/ci.sh --quick   # without the window tests, for each commit
#   tool/ci.sh --check   # exit 0 if HEAD has a full passing run
#
# A full run on a clean tree leaves a note on HEAD (git notes --ref=ci),
# which --check looks for. The S2 test servers are started and stopped
# here, and the SSH tests fail instead of skipping without them.
#
# Needs Zig 0.16, FVM, cargo-deny, and podman (or docker); the window tests
# need macOS. They stall while someone uses the Mac ("Failed to foreground
# app"), so each runs under a time limit.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
mode=full
case "${1:-}" in
  "") ;;
  --quick) mode=quick ;;
  --check)
    note="$(git notes --ref=ci show HEAD 2>/dev/null || true)"
    if [[ "$note" == "ok full "* ]]; then
      echo "ci: $note"
      exit 0
    fi
    echo "ci: no full passing run for $(git rev-parse --short HEAD) (tool/ci.sh)" >&2
    exit 1
    ;;
  *) echo "usage: tool/ci.sh [--quick | --check]" >&2; exit 2 ;;
esac

started="$(date +%s)"
step() { printf '\n== %s (%ss)\n' "$1" "$(($(date +%s) - started))"; }
# Kills a command that runs longer than $1 seconds.
limit() { perl -e 'alarm shift; exec @ARGV' "$@"; }

# A window test stalls when its app cannot come to the front ("Failed to
# foreground app", while someone uses the Mac). Runs `limit "$@"` and, each
# time the output goes quiet for 25 s, brings the app under test to the
# front: only the one already running, never a new one on the real data.
window_test() {
  local log pid quiet app=build/macos/Build/Products/Debug/OpenWard.app
  log="$(mktemp)"
  limit "$@" > >(tee "$log") 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
    quiet=$(($(date +%s) - $(stat -f %m "$log")))
    if ((quiet >= 25)) && pgrep -f "$app/Contents/MacOS/OpenWard" >/dev/null; then
      open "$app"
      touch "$log"
    fi
  done
  local status=0
  wait "$pid" || status=$?
  rm -f "$log"
  return "$status"
}

# Whether this run tested HEAD as committed.
clean=true
[[ -z "$(git status --porcelain)" ]] || clean=false

step "libghostty-vt"
core/crates/openward-ghostty/build-libghostty.sh

step "Rust: format and lints"
(cd core && cargo fmt --all -- --check)
(cd core && cargo clippy --workspace --all-targets -- -D warnings)
(cd core && cargo clippy -p openward-term --features alacritty --all-targets -- -D warnings)

step "Rust: mobile targets compile"
# As the mobile-check job: the crates that build C or need a prebuilt
# library are left out until phase 2.
mobile=(aarch64-apple-ios aarch64-apple-ios-sim aarch64-linux-android x86_64-linux-android)
(cd core && rustup target add "${mobile[@]}" >/dev/null)
for target in "${mobile[@]}"; do
  (cd core && cargo check --workspace --target "$target" \
    --exclude openward-ghostty --exclude openward-ssh --exclude openward-pty \
    --exclude openward-vault --exclude openward-app --exclude openward-ffi)
done

step "Rust: dependencies"
(cd core && cargo deny check)

step "Spikes: lints"
(cd spikes/s1-terminal/termbench && cargo fmt -- --check && cargo clippy --all-targets -- -D warnings)
(cd spikes/s2-ssh/sshprobe && cargo fmt -- --check && cargo clippy --all-targets -- -D warnings && cargo test)
make bench

step "S2 test servers"
runtime="${S2_RUNTIME:-$(command -v podman || command -v docker || true)}"
[[ -n "$runtime" ]] || { echo "error: podman or docker required" >&2; exit 1; }
export S2_RUNTIME="$runtime"
machine=false
if [[ "$(basename "$runtime")" == podman && "$(uname)" == Darwin ]] && ! podman info >/dev/null 2>&1; then
  podman machine start
  machine=true
fi
cleanup() {
  "$root/spikes/s2-ssh/servers/down.sh"
  if $machine; then podman machine stop >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
spikes/s2-ssh/servers/up.sh
export OPENWARD_REQUIRE_SERVERS=1

step "Rust: tests"
(cd core && cargo test --workspace)
(cd core && cargo test -p openward-term --features alacritty)
(cd spikes/s2-ssh/sshprobe && cargo run --release -- matrix)

step "App: analysis and unit tests"
cd app
fvm flutter pub get >/dev/null
fvm flutter analyze
fvm dart format --output=none --set-exit-if-changed lib test integration_test tool
fvm flutter test test/

if [[ "$mode" == full ]]; then
  if [[ "$(uname)" != Darwin ]]; then
    echo "error: the window tests run on macOS; use --quick here" >&2
    exit 1
  fi
  shots="${OPENWARD_SHOTS:-${TMPDIR:-/tmp}/openward-shots}"
  defines=(--dart-define=OPENWARD_REQUIRE_SERVERS=true "--dart-define=OPENWARD_SHOTS=$shots")
  for test in ffi_test ui_test a11y_test; do
    step "App: integration_test/$test.dart"
    window_test 1800 fvm flutter test "integration_test/$test.dart" -d macos "${defines[@]}"
  done
  step "App: gallery"
  window_test 1800 fvm flutter drive -d macos --driver=test_driver/integration_test.dart \
    --target=integration_test/gallery_test.dart "${defines[@]}"
fi
cd "$root"

step "Done"
if [[ "$mode" == full ]] && $clean; then
  git notes --ref=ci add -f -m "ok full $(date -u +%Y-%m-%dT%H:%M:%SZ)" HEAD
  echo "ci: noted on $(git rev-parse --short HEAD)"
elif [[ "$mode" == full ]]; then
  echo "ci: passed, but the tree has changes: not noted on HEAD"
fi
