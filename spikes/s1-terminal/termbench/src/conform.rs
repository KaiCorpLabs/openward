//! Correctness against a reference terminal (spike S1.6).
//!
//! The capture (corpus/record/scenarios/vttest_capture.py) ran a program in
//! tmux and recorded, at every screen it stopped at, the byte offset reached
//! in the program's raw output plus tmux's screen and cursor. Here the raw
//! output is replayed into each engine and compared at the same offsets.

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::fs;

use openward_term::frame::{DecodedFrame, attrs, decode};
use openward_term::{Color, FrameEncoder, Size, Style};
use serde_json::{Value, json};

use crate::{Opts, make_engine};

struct Reference {
    label: String,
    offset: usize,
    cursor: (u16, u16),
    screen: Vec<String>,
    /// The screen as tmux re-encodes it, with SGR sequences (optional).
    screen_sgr: Option<Vec<String>>,
}

#[derive(Default)]
struct Tally {
    steps: usize,
    screen_ok: usize,
    cursor_ok: usize,
    /// Steps whose colors and attributes match (when the reference has them).
    style_ok: usize,
    styled: usize,
    /// Steps not compared: the engine switched to 132 columns (DECCOLM),
    /// which tmux, the reference, does not implement.
    wide: usize,
}

/// One step where some engine differs from the reference.
struct Mismatch {
    step: usize,
    /// Engine → what it showed.
    got: BTreeMap<String, Seen>,
}

struct Seen {
    /// The reference this engine was compared against.
    reference: Vec<String>,
    screen: Vec<String>,
    cursor: (u16, u16),
    /// Cells whose style differs from the reference: (row, col, ours, ref).
    styles: Vec<(u16, u16, String, String)>,
}

fn load(path: &str) -> Result<(Size, Vec<Reference>), String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
    let mut size = Size::new(80, 24);
    let mut refs = Vec::new();
    for (n, line) in text.lines().enumerate() {
        let v: Value = serde_json::from_str(line).map_err(|e| format!("{path}:{}: {e}", n + 1))?;
        if let (Some(c), Some(r)) = (v["cols"].as_u64(), v["rows"].as_u64()) {
            size = Size::new(c as u16, r as u16);
            continue;
        }
        let screen = v["screen"]
            .as_array()
            .ok_or_else(|| format!("{path}:{}: no screen", n + 1))?
            .iter()
            .map(|l| l.as_str().unwrap_or_default().trim_end().to_owned())
            .collect();
        let screen_sgr = v["screen_sgr"].as_array().map(|lines| {
            lines
                .iter()
                .map(|l| l.as_str().unwrap_or_default().to_owned())
                .collect()
        });
        refs.push(Reference {
            screen_sgr,
            label: v["label"].as_str().unwrap_or_default().to_owned(),
            offset: v["offset"].as_u64().unwrap_or(0) as usize,
            cursor: (
                v["cursor"][0].as_u64().unwrap_or(0) as u16,
                v["cursor"][1].as_u64().unwrap_or(0) as u16,
            ),
            screen,
        });
    }
    Ok((size, refs))
}

/// The test a step belongs to: its label up to " #" (vttest menu path).
fn test_of(label: &str) -> &str {
    label.split(" #").next().unwrap_or(label)
}

pub fn conform(o: &Opts) -> Result<(), String> {
    let (raw_path, ref_path) = match o.positional.as_slice() {
        [raw, refs, ..] => (raw, refs),
        _ => return Err("conform needs <raw output> <reference.jsonl> [report.md]".into()),
    };
    let raw = fs::read(raw_path).map_err(|e| format!("{raw_path}: {e}"))?;
    let (size, refs) = load(ref_path)?;
    let rows = usize::from(size.rows);

    let mut tallies: BTreeMap<String, BTreeMap<String, Tally>> = BTreeMap::new();
    let mut mismatches: BTreeMap<usize, Mismatch> = BTreeMap::new();
    // Engine → step → what it showed (None when not compared), to compare
    // the engines with each other as well as with tmux.
    let mut shown: Vec<Vec<Option<Shown>>> = vec![vec![None; refs.len()]; o.engines.len()];
    // Step → engine → cursor, for the short captures (Unicode widths).
    let mut cursors: BTreeMap<usize, BTreeMap<String, (u16, u16)>> = BTreeMap::new();
    for (engine_index, engine) in o.engines.iter().enumerate() {
        for (step, r) in refs.iter().enumerate() {
            // A fresh engine per step: its first frame is a full one.
            let end = r.offset.min(raw.len());
            let mut e = make_engine(engine, size, 1_000)?;
            e.feed(&raw[..end]);
            // Replies went to tmux during the capture; drop ours.
            e.take_host_writes();
            let mut screen: Vec<String> = e.screen_text().split('\n').map(str::to_owned).collect();
            screen.resize(rows, String::new());
            let frame = full_frame(e.as_mut())?;
            let cursor = (frame.cursor.row, frame.cursor.col);
            if frame.cols != size.cols {
                tallies
                    .entry(test_of(&r.label).to_owned())
                    .or_default()
                    .entry(engine.clone())
                    .or_default()
                    .wide += 1;
                continue;
            }
            // With tmux's SGR capture, the reference is that capture decoded
            // by one fixed engine (alacritty) for every engine compared:
            // it turns tmux's SO/SI line-drawing cells into the Unicode
            // characters engines show, and gives styles to compare.
            let (ref_screen, styles) = match &r.screen_sgr {
                Some(sgr) => {
                    let mut reference = make_engine("alacritty", size, 1_000)?;
                    reference.feed(&replay_sgr(sgr));
                    let mut text: Vec<String> = reference
                        .screen_text()
                        .split('\n')
                        .map(str::to_owned)
                        .collect();
                    text.resize(rows, String::new());
                    let ref_frame = full_frame(reference.as_mut())?;
                    (text, Some(style_diff(&frame, &ref_frame, size)))
                }
                None => (r.screen.clone(), None),
            };

            cursors
                .entry(step)
                .or_default()
                .insert(engine.clone(), cursor);
            shown[engine_index][step] = Some((screen.clone(), cells(&frame, size)));
            let t = tallies
                .entry(test_of(&r.label).to_owned())
                .or_default()
                .entry(engine.clone())
                .or_default();
            t.steps += 1;
            let screen_ok = screen == ref_screen;
            let cursor_ok = cursor == r.cursor;
            let style_ok = styles.as_ref().is_none_or(Vec::is_empty);
            t.screen_ok += usize::from(screen_ok);
            t.cursor_ok += usize::from(cursor_ok);
            if styles.is_some() {
                t.styled += 1;
                t.style_ok += usize::from(style_ok);
            }
            if !screen_ok || !cursor_ok || !style_ok {
                mismatches
                    .entry(step)
                    .or_insert_with(|| Mismatch {
                        step,
                        got: BTreeMap::new(),
                    })
                    .got
                    .insert(
                        engine.clone(),
                        Seen {
                            reference: ref_screen,
                            screen,
                            cursor,
                            styles: styles.unwrap_or_default(),
                        },
                    );
            }
        }
    }

    // Where the first two engines disagree with each other, per test.
    let mut disagree: BTreeMap<String, (usize, usize, usize)> = BTreeMap::new();
    let mut agree_total = (0usize, 0usize, 0usize);
    if let [a, b, ..] = shown.as_slice() {
        for (step, r) in refs.iter().enumerate() {
            let (Some((sa, ga)), Some((sb, gb))) = (&a[step], &b[step]) else {
                continue;
            };
            let text_same = sa == sb;
            let style_same = grid_diff(ga, gb).is_empty();
            let entry = disagree.entry(test_of(&r.label).to_owned()).or_default();
            entry.0 += 1;
            entry.1 += usize::from(!text_same);
            entry.2 += usize::from(!style_same);
            agree_total.0 += 1;
            agree_total.1 += usize::from(text_same);
            agree_total.2 += usize::from(style_same);
        }
    }

    let mut totals: BTreeMap<&str, Tally> = BTreeMap::new();
    for per_engine in tallies.values() {
        for (engine, t) in per_engine {
            let total = totals.entry(engine).or_default();
            total.steps += t.steps;
            total.screen_ok += t.screen_ok;
            total.cursor_ok += t.cursor_ok;
            total.style_ok += t.style_ok;
            total.styled += t.styled;
            total.wide += t.wide;
        }
    }
    if o.json {
        let tests: Vec<Value> = tallies
            .iter()
            .map(|(test, per)| {
                let engines: serde_json::Map<String, Value> = per
                    .iter()
                    .map(|(e, t)| (e.clone(), tally_json(t)))
                    .collect();
                json!({"test": test, "engines": engines})
            })
            .collect();
        let summary: serde_json::Map<String, Value> = totals
            .iter()
            .map(|(e, t)| ((*e).to_owned(), tally_json(t)))
            .collect();
        println!(
            "{}",
            json!({"kind": "conform", "reference": ref_path, "size": [size.cols, size.rows],
                   "total": summary, "tests": tests,
                   "engines_agree": {"steps": agree_total.0, "screen": agree_total.1,
                                     "style": agree_total.2}})
        );
    } else {
        for (engine, t) in &totals {
            println!(
                "{engine:>10}: {}/{} screens, {}/{} cursors, {}/{} styles match the reference \
                 ({} steps at 132 columns not compared)",
                t.screen_ok, t.steps, t.cursor_ok, t.steps, t.style_ok, t.styled, t.wide
            );
        }
        if agree_total.0 > 0 {
            println!(
                "{:>10}: {}/{} screens and {}/{} styles identical in both engines",
                "agree", agree_total.1, agree_total.0, agree_total.2, agree_total.0
            );
        }
    }

    if let Some(report) = o.positional.get(2) {
        fs::write(
            report,
            render_report(
                &refs,
                &tallies,
                &mismatches,
                &cursors,
                &disagree,
                &o.engines,
            ),
        )
        .map_err(|e| format!("{report}: {e}"))?;
    }
    Ok(())
}

fn tally_json(t: &Tally) -> Value {
    json!({"steps": t.steps, "screen_ok": t.screen_ok, "cursor_ok": t.cursor_ok,
           "style_ok": t.style_ok, "styled": t.styled, "skipped_132_columns": t.wide})
}

fn full_frame(e: &mut dyn openward_term::TermEngine) -> Result<DecodedFrame, String> {
    let mut enc = FrameEncoder::new();
    e.encode_damage(&mut enc);
    decode(enc.bytes()).map_err(|e| format!("frame: {e:?}"))
}

/// tmux's SGR rendering of a screen, as bytes that draw it on a blank
/// terminal: each line placed explicitly, from default attributes.
fn replay_sgr(lines: &[String]) -> Vec<u8> {
    // tmux marks line-drawing cells with SO/SI: G1 is DEC special graphics.
    let mut out = String::from("\x1b(B\x1b)0\x1b[0m\x1b[H\x1b[2J");
    for (row, line) in lines.iter().enumerate() {
        let _ = write!(out, "\x1b[{};1H\x1b[0m{line}", row + 1);
    }
    out.push_str("\x1b[0m");
    out.into_bytes()
}

type Grid = Vec<Vec<(char, Style)>>;

/// A step's screen text and cells as one engine showed them.
type Shown = (Vec<String>, Grid);

/// Per-cell (char, style) from a full frame; blank default cells are absent
/// from frames and stay default here.
fn cells(f: &DecodedFrame, size: Size) -> Grid {
    let mut grid =
        vec![vec![(' ', Style::default()); usize::from(size.cols)]; usize::from(size.rows)];
    for line in &f.lines {
        let Some(row) = grid.get_mut(usize::from(line.index)) else {
            continue;
        };
        for span in &line.spans {
            let mut chars = span.text.chars();
            let per_cell = span.width as usize == span.text.chars().count();
            for i in 0..span.width {
                let ch = if per_cell || i == 0 {
                    chars.next().unwrap_or(' ')
                } else {
                    ' '
                };
                if let Some(cell) = row.get_mut(usize::from(span.col + i)) {
                    *cell = (ch, span.style);
                }
            }
        }
    }
    grid
}

/// Named colors 0–15 and the same palette indexes are one color.
fn norm(c: Color) -> Color {
    match c {
        Color::Named(n) if n < 16 => Color::Indexed(n),
        other => other,
    }
}

fn show_style(s: &Style) -> String {
    format!(
        "fg {:?} bg {:?} attrs {:#x}",
        norm(s.fg),
        norm(s.bg),
        s.attrs
    )
}

/// Cells whose visible style differs. On blanks only what shows on a blank
/// counts: background and inverse, underline, strikeout.
fn style_diff(
    ours: &DecodedFrame,
    reference: &DecodedFrame,
    size: Size,
) -> Vec<(u16, u16, String, String)> {
    grid_diff(&cells(ours, size), &cells(reference, size))
}

fn grid_diff(a: &Grid, b: &Grid) -> Vec<(u16, u16, String, String)> {
    const ON_BLANK: u16 = attrs::INVERSE | attrs::UNDERLINE | attrs::STRIKEOUT;
    let mut out = Vec::new();
    for (row, (ra, rb)) in a.iter().zip(b).enumerate() {
        for (col, ((ca, sa), (_, sb))) in ra.iter().zip(rb).enumerate() {
            let same = if *ca == ' ' {
                norm(sa.bg) == norm(sb.bg) && sa.attrs & ON_BLANK == sb.attrs & ON_BLANK
            } else {
                norm(sa.fg) == norm(sb.fg) && norm(sa.bg) == norm(sb.bg) && sa.attrs == sb.attrs
            };
            if !same {
                out.push((row as u16, col as u16, show_style(sa), show_style(sb)));
            }
        }
    }
    out
}

fn render_report(
    refs: &[Reference],
    tallies: &BTreeMap<String, BTreeMap<String, Tally>>,
    mismatches: &BTreeMap<usize, Mismatch>,
    cursors: &BTreeMap<usize, BTreeMap<String, (u16, u16)>>,
    disagree: &BTreeMap<String, (usize, usize, usize)>,
    engines: &[String],
) -> String {
    let mut out = String::from(
        "# Conformance report\n\nMatching steps per test (screen text / cursor / styles). Steps where an engine switched to 132 columns are counted apart: tmux, the reference, ignores DECCOLM.\n\n| Test | Steps |",
    );
    for e in engines {
        let _ = write!(out, " {e} |");
    }
    out.push_str("\n|---|---|");
    for _ in engines {
        out.push_str("---|");
    }
    out.push('\n');
    for (test, per) in tallies {
        let steps = per.values().map(|t| t.steps + t.wide).max().unwrap_or(0);
        let _ = write!(out, "| {test} | {steps} |");
        for e in engines {
            let t = &per[e];
            let styles = if t.styled > 0 {
                t.style_ok.to_string()
            } else {
                "–".into()
            };
            let wide = if t.wide > 0 {
                format!(" (+{} a 132 col.)", t.wide)
            } else {
                String::new()
            };
            let _ = write!(out, " {} / {} / {styles}{wide} |", t.screen_ok, t.cursor_ok);
        }
        out.push('\n');
    }
    let split: Vec<_> = disagree
        .iter()
        .filter(|(_, (_, text, style))| *text + *style > 0)
        .collect();
    if !split.is_empty() {
        out.push_str(
            "\n## Where the engines disagree\n\nSteps where the two engines differ \
             from each other, whatever tmux shows.\n\n\
             | Test | Steps | Text differs | Styles differ |\n|---|---|---|---|\n",
        );
        for (test, (steps, text, style)) in split {
            let _ = writeln!(out, "| {test} | {steps} | {text} | {style} |");
        }
    }
    if refs.len() <= 40 {
        out.push_str("\n## Cursor after each step (row, column)\n\n| Step | ref |");
        for e in engines {
            let _ = write!(out, " {e} |");
        }
        out.push_str("\n|---|---|");
        for _ in engines {
            out.push_str("---|");
        }
        out.push('\n');
        for (step, r) in refs.iter().enumerate() {
            let _ = write!(out, "| {} | {:?} |", r.label, r.cursor);
            for e in engines {
                match cursors.get(&step).and_then(|c| c.get(e)) {
                    Some(c) if *c == r.cursor => {
                        let _ = write!(out, " {c:?} |");
                    }
                    Some(c) => {
                        let _ = write!(out, " **{c:?}** |");
                    }
                    None => out.push_str(" – |"),
                }
            }
            out.push('\n');
        }
    }
    out.push_str("\n## Differences\n\nRows that differ, as `ref` (tmux) and each engine; `·` marks a space. Style differences list the first cells only.\n");
    for m in mismatches.values() {
        let r = &refs[m.step];
        let _ = writeln!(out, "\n### Step {} · {}\n", m.step, r.label);
        let _ = writeln!(out, "```");
        for (engine, seen) in &m.got {
            if seen.cursor != r.cursor {
                let _ = writeln!(
                    out,
                    "cursor  ref {:?}  {engine} {:?}",
                    r.cursor, seen.cursor
                );
            }
        }
        let reference = &m
            .got
            .values()
            .next()
            .expect("a mismatch has an engine")
            .reference;
        for (row, expected) in reference.iter().enumerate() {
            let differs = m.got.values().any(|s| s.screen[row] != *expected);
            if !differs {
                continue;
            }
            let show = |s: &str| s.replace(' ', "·");
            let _ = writeln!(out, "{row:>2} ref       |{}", show(expected));
            for (engine, seen) in &m.got {
                if seen.screen[row] != *expected {
                    let _ = writeln!(out, "{row:>2} {engine:<9} |{}", show(&seen.screen[row]));
                }
            }
        }
        for (engine, seen) in &m.got {
            if seen.styles.is_empty() {
                continue;
            }
            let _ = writeln!(out, "styles  {engine}: {} cells differ", seen.styles.len());
            for (row, col, ours, theirs) in seen.styles.iter().take(4) {
                let _ = writeln!(out, "  {row},{col}  {engine} {ours}  ref {theirs}");
            }
        }
        let _ = writeln!(out, "```");
    }
    out
}
