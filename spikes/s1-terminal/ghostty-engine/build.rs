//! Links the prebuilt static libghostty-vt for the current target.
//!
//! Build it first with `./build-libghostty.sh [zig-target]`, or point
//! GHOSTTY_VT_DIR at a directory containing `lib/libghostty-vt.a`.

use std::env;
use std::path::PathBuf;

fn cache_dir() -> PathBuf {
    if let Ok(dir) = env::var("OPENWARD_CACHE") {
        return PathBuf::from(dir);
    }
    let home = PathBuf::from(env::var("HOME").unwrap_or_default());
    if cfg!(target_os = "macos") {
        home.join("Library/Caches/openward")
    } else {
        env::var("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| home.join(".cache"))
            .join("openward")
    }
}

/// Rust target triple → the directory name build-libghostty.sh uses.
fn zig_target(rust_target: &str) -> String {
    match rust_target {
        "aarch64-apple-darwin" => "aarch64-macos",
        "x86_64-apple-darwin" => "x86_64-macos",
        "aarch64-apple-ios" => "aarch64-ios",
        "aarch64-apple-ios-sim" => "aarch64-ios-simulator",
        "aarch64-linux-android" => "aarch64-linux-android",
        "x86_64-linux-android" => "x86_64-linux-android",
        "x86_64-unknown-linux-gnu" => "x86_64-linux",
        "aarch64-unknown-linux-gnu" => "aarch64-linux",
        "x86_64-pc-windows-msvc" => "x86_64-windows",
        other => other,
    }
    .to_owned()
}

fn main() {
    println!("cargo:rerun-if-changed=GHOSTTY_COMMIT");
    println!("cargo:rerun-if-env-changed=GHOSTTY_VT_DIR");
    println!("cargo:rerun-if-env-changed=OPENWARD_CACHE");

    let dir = match env::var("GHOSTTY_VT_DIR") {
        Ok(dir) => PathBuf::from(dir),
        Err(_) => {
            let commit = std::fs::read_to_string("GHOSTTY_COMMIT").expect("GHOSTTY_COMMIT");
            let target = env::var("TARGET").expect("TARGET");
            cache_dir()
                .join("ghostty/build")
                .join(&commit.trim()[..8])
                .join(zig_target(&target))
        }
    };
    let lib = dir.join("lib");
    if !lib.join("libghostty-vt.a").exists() {
        panic!(
            "libghostty-vt not found in {}. Run spikes/s1-terminal/ghostty-engine/build-libghostty.sh \
             (or set GHOSTTY_VT_DIR).",
            lib.display()
        );
    }
    println!(
        "cargo:rerun-if-changed={}",
        lib.join("libghostty-vt.a").display()
    );
    // The install dir also has the .dylib/.so, which the macOS linker would
    // pick over the archive. Link from a directory that only has the archive.
    let out = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR")).join("lib");
    std::fs::create_dir_all(&out).expect("create OUT_DIR/lib");
    std::fs::copy(lib.join("libghostty-vt.a"), out.join("libghostty-vt.a"))
        .expect("copy libghostty-vt.a");
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=ghostty-vt");
}
