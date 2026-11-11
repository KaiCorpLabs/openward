#!/usr/bin/env bash
# Builds OpenWard for Linux in a container (podman or docker), from the
# working tree as it is, and packs the bundle:
#
#   app/tool/package-linux.sh   # → app/build/OpenWard-<version>[+<commit>]-linux-<arch>.tar.gz
#
# The architecture is the machine's (x86_64, or aarch64 on Apple silicon);
# ARCH=x86_64 on another asks for an emulated container, which works but
# takes long. Unsigned, a tar.gz of Flutter's bundle: run `openward` in it.
# Downloads, the first time, what the image needs (Flutter, Rust, Zig) and
# Ghostty's sources; both stay in the image and in a volume for the next.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
runtime="${RUNTIME:-$(command -v podman || command -v docker || true)}"
[[ -n "$runtime" ]] || { echo "error: podman or docker required" >&2; exit 1; }

machine=false
if [[ "$(basename "$runtime")" == podman && "$(uname)" == Darwin ]] && ! podman info >/dev/null 2>&1; then
  podman machine start
  machine=true
fi
tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
  if $machine; then podman machine stop >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

host="$(uname -m)"
[[ "$host" == arm64 ]] && host=aarch64
arch="${ARCH:-$host}"
platform=()
[[ "$arch" != "$host" ]] && platform=(--platform "linux/${arch/x86_64/amd64}")

rust="$(sed -n 's/^channel = "\(.*\)"/\1/p' core/rust-toolchain.toml)"
flutter="$(jq -r .flutter .fvmrc)"
zig=0.16.0
image="openward-linux-build:flutter-$flutter-rust-$rust-zig-$zig-$arch"
context="$tmp/context"
mkdir -p "$context"
cp app/tool/linux/Containerfile app/tool/linux/install-tools.sh app/tool/linux/toolchain-pins.sh "$context/"
cp .github/scripts/install-zig.sh "$context/install-zig.sh"
"$runtime" build ${platform[@]+"${platform[@]}"} -t "$image" -f "$context/Containerfile" \
  --build-arg RUST="$rust" --build-arg ZIG="$zig" --build-arg FLUTTER="$flutter" "$context"

version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' app/pubspec.yaml)"
name="$version"
if ! git tag --points-at HEAD | grep -qx "v$version" || [[ -n "$(git status --porcelain)" ]]; then
  name="$version+$(git rev-parse --short HEAD)"
  [[ -z "$(git status --porcelain)" ]] || name="$name-dirty"
fi

# The tree as it is (tracked files with their changes, and new ones), not
# this machine's build outputs.
git ls-files -z --cached --others --exclude-standard | tar --null -T - -czf "$tmp/src.tgz"
# SELinux (Fedora) would keep the container from reading the tree it is
# handed: this one container goes unlabeled.
"$runtime" run --rm ${platform[@]+"${platform[@]}"} --security-opt label=disable -v "$tmp:/io" \
  -v "openward-linux-cache-$arch:/root/.cache" \
  -v "openward-linux-cargo-$arch:/root/.cargo/registry" \
  "$image" bash -euc '
    mkdir /src && tar -xzf /io/src.tgz -C /src && cd /src
    core/crates/openward-ghostty/build-libghostty.sh
    cd app && flutter pub get && flutter build linux --release
    bundle="$(ls -d build/linux/*/release/bundle)"
    tar -czf /io/out.tgz -C "$(dirname "$bundle")" --transform "s,^bundle,OpenWard," bundle'
mkdir -p app/build
out="app/build/OpenWard-$name-linux-$arch.tar.gz"
mv "$tmp/out.tgz" "$out"
echo "$out"
