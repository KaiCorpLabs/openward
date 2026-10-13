//! Writes damage-frame fixtures for the Dart decoder tests:
//! `<dir>/<name>.bin` (wire bytes) and `<dir>/<name>.json` (what the Rust
//! reference decoder reads from them).
//!
//! cargo run --example gen_fixtures -- ../test/fixtures

use std::{env, fs, path::Path};

use openward_term::alacritty::AlacrittyEngine;
use openward_term::frame::{DecodedFrame, decode};
use openward_term::{FrameEncoder, Size, TermEngine};
use serde_json::{Value, json};

fn frame_json(f: &DecodedFrame) -> Value {
    json!({
        "full": f.full,
        "cols": f.cols,
        "rows": f.rows,
        "cursor": {
            "row": f.cursor.row,
            "col": f.cursor.col,
            "shape": format!("{:?}", f.cursor.shape),
            "visible": f.cursor.visible,
        },
        "display_offset": f.display_offset,
        "lines": f.lines.iter().map(|l| json!({
            "index": l.index,
            "spans": l.spans.iter().map(|s| json!({
                "col": s.col,
                "width": s.width,
                "fg": s.style.fg.to_raw(),
                "bg": s.style.bg.to_raw(),
                "attrs": s.style.attrs,
                "text": s.text,
            })).collect::<Vec<_>>(),
        })).collect::<Vec<_>>(),
    })
}

fn write(dir: &Path, name: &str, engine: &mut AlacrittyEngine) {
    let mut enc = FrameEncoder::new();
    engine.encode_damage(&mut enc);
    let bytes = enc.bytes();
    let decoded = decode(bytes).expect("engine output decodes");
    fs::write(dir.join(format!("{name}.bin")), bytes).unwrap();
    let json = serde_json::to_string_pretty(&frame_json(&decoded)).unwrap();
    fs::write(dir.join(format!("{name}.json")), json + "\n").unwrap();
    println!("{name}: {} bytes", bytes.len());
}

fn main() {
    let dir = env::args().nth(1).expect("usage: gen_fixtures <dir>");
    let dir = Path::new(&dir);
    fs::create_dir_all(dir).unwrap();

    let mut e = AlacrittyEngine::new(Size::new(30, 4), 100);
    e.feed(b"hello \x1b[31mred\x1b[0m \x1b[1;4;38;2;10;20;30mrgb\x1b[0m \x1b[7minv\x1b[0m");
    write(dir, "styled", &mut e);

    let mut e = AlacrittyEngine::new(Size::new(20, 2), 100);
    e.feed("漢字a🙂e\u{301}".as_bytes());
    write(dir, "wide", &mut e);

    let mut e = AlacrittyEngine::new(Size::new(20, 6), 100);
    e.feed(b"one");
    e.encode_damage(&mut FrameEncoder::new());
    e.feed(b"\r\n\x1b[38;5;200mtwo\x1b[0m\x1b[4 q");
    write(dir, "partial", &mut e);

    let mut e = AlacrittyEngine::new(Size::new(12, 4), 100);
    for i in 0..20 {
        e.feed(format!("line{i}\r\n").as_bytes());
    }
    e.encode_damage(&mut FrameEncoder::new());
    e.scroll_display(3);
    write(dir, "scrolled", &mut e);
}
