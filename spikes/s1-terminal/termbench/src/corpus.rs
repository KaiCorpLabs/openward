//! Deterministic synthetic corpus. Real sessions recorded with asciinema
//! complement it (see `replay`); this covers the patterns that stress an
//! engine in isolation.

use std::fmt::Write as _;
use std::fs;
use std::path::Path;

use crate::Opts;

/// xorshift64* — deterministic, so every run and machine sees the same bytes.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_f491_4f6c_dd1d)
    }

    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }

    fn pick<'a, T>(&mut self, items: &'a [T]) -> &'a T {
        &items[self.below(items.len())]
    }
}

const WORDS: &[&str] = &[
    "connection",
    "accepted",
    "user",
    "session",
    "opened",
    "for",
    "from",
    "port",
    "ssh2",
    "key",
    "fingerprint",
    "request",
    "GET",
    "/api/v1/hosts",
    "200",
    "latency",
    "ms",
    "worker",
    "started",
    "queue",
    "drained",
];

/// Builds one corpus file: (rng, target bytes, cols, rows) -> contents.
type Generator = fn(&mut Rng, usize, usize, usize) -> String;

pub fn generate(dir: &Path, o: &Opts) -> Result<(), String> {
    fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let target = o.mb * 1024 * 1024;
    let cols = usize::from(o.cols);
    let rows = usize::from(o.rows);
    let files: [(&str, Generator); 5] = [
        ("ascii.txt", ascii),
        ("sgr-log.txt", sgr_log),
        ("unicode.txt", unicode),
        ("fullscreen.txt", fullscreen),
        ("scroll-region.txt", scroll_region),
    ];
    for (i, (name, make)) in files.iter().enumerate() {
        let mut rng = Rng(0x9e37_79b9_7f4a_7c15 ^ (i as u64 + 1));
        let data = make(&mut rng, target, cols, rows);
        let path = dir.join(name);
        fs::write(&path, data.as_bytes()).map_err(|e| format!("{}: {e}", path.display()))?;
        println!(
            "{:>8.1} MiB  {}",
            data.len() as f64 / 1_048_576.0,
            path.display()
        );
    }
    Ok(())
}

/// Plain printable text, like `cat` of a large log.
fn ascii(rng: &mut Rng, target: usize, cols: usize, _rows: usize) -> String {
    let mut s = String::with_capacity(target + cols);
    while s.len() < target {
        let len = 20 + rng.below(cols.saturating_sub(20).max(1));
        for _ in 0..len {
            s.push((b' ' + rng.below(95) as u8) as char);
        }
        s.push_str("\r\n");
    }
    s
}

/// Log lines with 16-color, 256-color and truecolor SGR.
fn sgr_log(rng: &mut Rng, target: usize, _cols: usize, _rows: usize) -> String {
    let levels = [
        ("INFO", "32"),
        ("WARN", "33"),
        ("ERROR", "1;31"),
        ("DEBUG", "2;37"),
    ];
    let mut s = String::with_capacity(target + 512);
    let mut n = 0u64;
    while s.len() < target {
        n += 1;
        let (level, sgr) = rng.pick(&levels);
        let _ = write!(
            s,
            "\x1b[90m2026-10-08T12:{:02}:{:02}.{:03}Z\x1b[0m \x1b[{sgr}m{level:<5}\x1b[0m ",
            n / 60 % 60,
            n % 60,
            n % 1000
        );
        match rng.below(4) {
            0 => {
                let _ = write!(s, "\x1b[38;5;{}m", 16 + rng.below(216));
            }
            1 => {
                let _ = write!(
                    s,
                    "\x1b[38;2;{};{};{}m",
                    rng.below(256),
                    rng.below(256),
                    rng.below(256)
                );
            }
            _ => {}
        }
        for _ in 0..6 + rng.below(12) {
            s.push_str(rng.pick(WORDS));
            s.push(' ');
        }
        s.push_str("\x1b[0m\r\n");
    }
    s
}

/// Wide CJK, emoji, combining marks and box drawing.
fn unicode(rng: &mut Rng, target: usize, _cols: usize, _rows: usize) -> String {
    let pieces = [
        "漢字",
        "かな",
        "カタカナ",
        "한국어",
        "中文测试",
        "🙂",
        "🚀",
        "👍🏽",
        "e\u{301}",
        "n\u{303}",
        "─┼─",
        "│",
        "┌┐└┘",
        "ascii",
        "Ωμέγα",
        "Привет",
    ];
    let mut s = String::with_capacity(target + 256);
    while s.len() < target {
        for _ in 0..8 + rng.below(16) {
            s.push_str(rng.pick(&pieces));
            s.push(' ');
        }
        s.push_str("\r\n");
    }
    s
}

/// htop-like: alternate screen, cursor addressing and full redraws.
fn fullscreen(rng: &mut Rng, target: usize, cols: usize, rows: usize) -> String {
    let mut s = String::with_capacity(target + cols * rows * 4);
    s.push_str("\x1b[?1049h\x1b[?25l");
    while s.len() < target {
        s.push_str("\x1b[H");
        for row in 1..=rows {
            let _ = write!(s, "\x1b[{row};1H");
            let bar = rng.below(cols / 3 + 1);
            let _ = write!(s, "\x1b[1;36m{row:>3}\x1b[0m [\x1b[32m");
            s.push_str(&"|".repeat(bar));
            let _ = write!(
                s,
                "\x1b[0m{:>width$}]",
                "",
                width = (cols / 3).saturating_sub(bar)
            );
            let _ = write!(
                s,
                " \x1b[{}m{:>6.1}%\x1b[0m ",
                31 + rng.below(6),
                rng.below(1000) as f64 / 10.0
            );
            s.push_str(rng.pick(WORDS));
            s.push_str("\x1b[K");
        }
    }
    s.push_str("\x1b[?25h\x1b[?1049l");
    s
}

/// vim/less-like: scrolling inside a DECSTBM region with fixed status lines.
fn scroll_region(rng: &mut Rng, target: usize, cols: usize, rows: usize) -> String {
    let bottom = rows.saturating_sub(2).max(3);
    let mut s = String::with_capacity(target + cols * 4);
    let _ = write!(s, "\x1b[2;{bottom}r");
    let mut line = 0u64;
    while s.len() < target {
        line += 1;
        let _ = writeln!(s, "\x1b[{bottom};1H");
        for _ in 0..4 + rng.below(10) {
            s.push_str(rng.pick(WORDS));
            s.push(' ');
        }
        if line.is_multiple_of(25) {
            let _ = write!(
                s,
                "\x1b7\x1b[{rows};1H\x1b[7m -- line {line} -- \x1b[0m\x1b[K\x1b8"
            );
        }
    }
    s.push_str("\x1b[r");
    s
}
