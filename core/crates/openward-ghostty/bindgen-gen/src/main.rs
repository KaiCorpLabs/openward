//! Generates Rust FFI bindings for libghostty-vt.
//!
//! cargo run -- <ghostty include dir> <output .rs>
//!
//! The output is committed (openward-ghostty/src/sys.rs) so normal builds do
//! not need libclang. Regenerate whenever the pinned Ghostty commit changes.

use std::env;
use std::path::PathBuf;

fn main() {
    let mut args = env::args().skip(1);
    let include = PathBuf::from(args.next().expect("usage: <include dir> <output.rs>"));
    let output = PathBuf::from(args.next().expect("usage: <include dir> <output.rs>"));
    let header = include.join("ghostty").join("vt.h");

    bindgen::Builder::default()
        .header(header.to_string_lossy())
        .clang_arg(format!("-I{}", include.display()))
        .clang_arg("-DGHOSTTY_STATIC")
        .allowlist_function("ghostty_.*")
        .allowlist_type("Ghostty.*")
        .allowlist_var("GHOSTTY_.*")
        .default_enum_style(bindgen::EnumVariation::Consts)
        .prepend_enum_name(false)
        .derive_default(true)
        .generate_comments(false)
        .layout_tests(true)
        .generate()
        .expect("bindgen failed")
        .write_to_file(&output)
        .expect("cannot write bindings");
    eprintln!("wrote {}", output.display());
}
