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
    let archive = out.join("libghostty-vt.a");
    if env::var("CARGO_CFG_TARGET_VENDOR").as_deref() == Ok("apple") {
        prelink_apple(&lib.join("libghostty-vt.a"), &out);
    } else {
        std::fs::copy(lib.join("libghostty-vt.a"), &archive).expect("copy libghostty-vt.a");
    }
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=ghostty-vt");
}

/// Zig bundles its compiler_rt into static libraries. On Apple targets a Rust
/// staticlib embedding this archive gets linked with -force_load (Flutter
/// plugins are), which loads every member, and compiler_rt then clashes with
/// Rust's compiler_builtins (duplicate ___subvsi3 & co.). Dropping it is not
/// an option: Zig code needs builtins Rust lacks (___extendxftf2).
///
/// So prelink the archive into one object that exports only the C API
/// (`_ghostty_*`); compiler_rt, the Zig std and the bundled C++ become
/// internal to it. Same as Xcode's "single-object prelink".
fn prelink_apple(src: &std::path::Path, out: &std::path::Path) {
    let arch = match env::var("CARGO_CFG_TARGET_ARCH").as_deref() {
        Ok("aarch64") => "arm64".to_owned(),
        Ok(other) => other.to_owned(),
        Err(_) => panic!("CARGO_CFG_TARGET_ARCH"),
    };
    let os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let simulator = env::var("CARGO_CFG_TARGET_ABI").as_deref() == Ok("sim");
    let platform = match (os.as_str(), simulator) {
        ("macos", _) => "macos",
        ("ios", false) => "ios",
        ("ios", true) => "ios-simulator",
        (other, _) => panic!("prelink: unsupported Apple OS {other}"),
    };
    let exports = out.join("ghostty-vt.exports");
    std::fs::write(&exports, "_ghostty_*\n").expect("write export list");
    let object = out.join("ghostty-vt.o");
    let archive = out.join("libghostty-vt.a");
    let _ = std::fs::remove_file(&archive);
    // 13.0: the minimum Zig builds libghostty-vt for, on both platforms.
    run_xcrun(&[
        "ld".as_ref(),
        "-r".as_ref(),
        "-arch".as_ref(),
        arch.as_ref(),
        "-platform_version".as_ref(),
        platform.as_ref(),
        "13.0".as_ref(),
        "13.0".as_ref(),
        "-exported_symbols_list".as_ref(),
        exports.as_os_str(),
        "-o".as_ref(),
        object.as_os_str(),
        "-force_load".as_ref(),
        src.as_os_str(),
    ]);
    run_xcrun(&[
        "ar".as_ref(),
        "rcs".as_ref(),
        archive.as_os_str(),
        object.as_os_str(),
    ]);
}

fn run_xcrun(args: &[&std::ffi::OsStr]) {
    let status = std::process::Command::new("xcrun")
        .args(args)
        .status()
        .unwrap_or_else(|e| panic!("xcrun: {e}"));
    assert!(status.success(), "xcrun {args:?} failed");
}
