# Content pins for the Linux packaging bootstrap. Update these together
# with .fvmrc/core/rust-toolchain.toml after reviewing the official sources.
# Rustup: static.rust-lang.org/rustup/archive/1.29.3/<target>/rustup-init.sha256
# Flutter: github.com/flutter/flutter, refs/tags/3.47.6
RUSTUP_VERSION=1.29.3
RUST_VERSION=1.99.0
FLUTTER_VERSION=3.47.6
FLUTTER_COMMIT=5fc346839b5d0eef006ed8404392afb4dfae428d
ZIG_VERSION=0.16.0

case "$(uname -m)" in
  x86_64)
    RUSTUP_TARGET=x86_64-unknown-linux-gnu
    RUSTUP_SHA256=b1c8cb14e30889e7e2999e6b69e62d9e9b9ffc0f4df8180564d306d9680e6c55 ;;
  aarch64)
    RUSTUP_TARGET=aarch64-unknown-linux-gnu
    RUSTUP_SHA256=9f608c142e0e38a78957d0661ba1dfaf0b6fb37184cfaa4b9a0aa57af6184282 ;;
  *) echo "unsupported Linux toolchain architecture" >&2; exit 1 ;;
esac
