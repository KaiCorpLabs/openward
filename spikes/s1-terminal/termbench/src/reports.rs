//! What each engine answers to the queries programs send (spike S1.6).
//!
//! vttest's report tests only show the reference terminal's answers when
//! replayed, so queries are checked live here: feed one, read what the
//! engine would write back to the program.

use serde_json::json;

use crate::{Opts, make_engine};
use openward_term::Size;

/// (name, query, what a modern xterm-compatible terminal answers).
const QUERIES: &[(&str, &str, &str)] = &[
    (
        "DA1 primary attributes",
        "\x1b[c",
        "CSI ? 6x ; … c (VT220+ with features)",
    ),
    (
        "DA2 secondary attributes",
        "\x1b[>c",
        "CSI > Pp ; Pv ; Pc c",
    ),
    ("DSR status", "\x1b[5n", "CSI 0 n"),
    ("CPR cursor position", "\x1b[3;5H\x1b[6n", "CSI 3 ; 5 R"),
    (
        "DECXCPR",
        "\x1b[3;5H\x1b[?6n",
        "CSI ? 3 ; 5 R (; page optional)",
    ),
    (
        "DECRQM bracketed paste (2004)",
        "\x1b[?2004$p",
        "CSI ? 2004 ; 2 $ y",
    ),
    (
        "DECRQM sync output (2026)",
        "\x1b[?2026$p",
        "CSI ? 2026 ; 2 $ y",
    ),
    (
        "DECRQM grapheme clusters (2027)",
        "\x1b[?2027$p",
        "CSI ? 2027 ; 1|2 $ y",
    ),
    ("Kitty keyboard flags", "\x1b[?u", "CSI ? 0 u"),
    ("XTVERSION", "\x1b[>0q", "DCS > | name version ST"),
    ("OSC 10 foreground", "\x1b]10;?\x1b\\", "OSC 10 ; rgb:… ST"),
    ("OSC 11 background", "\x1b]11;?\x1b\\", "OSC 11 ; rgb:… ST"),
    (
        "OSC 4 palette entry 1",
        "\x1b]4;1;?\x1b\\",
        "OSC 4 ; 1 ; rgb:… ST",
    ),
    (
        "Text area in cells (XTWINOPS 18)",
        "\x1b[18t",
        "CSI 8 ; 24 ; 80 t",
    ),
    (
        "Text area in pixels (XTWINOPS 14)",
        "\x1b[14t",
        "CSI 4 ; h ; w t",
    ),
    (
        "DECRQSS SGR",
        "\x1b[1;31m\x1bP$qm\x1b\\\x1b[0m",
        "DCS 1 $ r 0;1;31 m ST",
    ),
    ("XTGETTCAP TN", "\x1bP+q544e\x1b\\", "DCS 1 + r 544e=… ST"),
    ("Color scheme (DSR 996)", "\x1b[?996n", "CSI ? 997 ; 1|2 n"),
];

fn printable(bytes: &[u8]) -> String {
    let mut s = String::new();
    for chunk in bytes.utf8_chunks() {
        for c in chunk.valid().chars() {
            match c {
                '\x1b' => s.push_str("ESC "),
                '\x07' => s.push_str(" BEL"),
                c if (c as u32) < 0x20 => s.push_str(&format!("^{}", (b'@' + c as u8) as char)),
                c => s.push(c),
            }
        }
        for b in chunk.invalid() {
            s.push_str(&format!("\\x{b:02x}"));
        }
    }
    s
}

pub fn reports(o: &Opts) -> Result<(), String> {
    let size = Size::new(80, 24);
    let mut rows = Vec::new();
    for (name, query, expected) in QUERIES {
        let mut answers = serde_json::Map::new();
        for engine in &o.engines {
            let mut e = make_engine(engine, size, 100)?;
            e.feed(query.as_bytes());
            let reply = e.take_host_writes();
            answers.insert(engine.clone(), json!(printable(&reply)));
        }
        rows.push(json!({"query": name, "expected": expected, "answers": answers}));
    }
    if o.json {
        println!("{}", json!({"kind": "reports", "queries": rows}));
        return Ok(());
    }
    let mut out = String::from("| Query | Expected |");
    for e in &o.engines {
        out.push_str(&format!(" {e} |"));
    }
    out.push_str("\n|---|---|");
    for _ in &o.engines {
        out.push_str("---|");
    }
    out.push('\n');
    for r in &rows {
        out.push_str(&format!(
            "| {} | `{}` |",
            r["query"].as_str().unwrap_or(""),
            r["expected"].as_str().unwrap_or("")
        ));
        for e in &o.engines {
            let a = r["answers"][e].as_str().unwrap_or("");
            if a.is_empty() {
                out.push_str(" — |");
            } else {
                out.push_str(&format!(" `{a}` |"));
            }
        }
        out.push('\n');
    }
    print!("{out}");
    Ok(())
}
