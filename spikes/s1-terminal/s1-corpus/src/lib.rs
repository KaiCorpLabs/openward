//! Deterministic synthetic terminal output for spike S1.
//!
//! Real sessions recorded with asciinema complement these workloads; each
//! one stresses a single pattern so engines and renderers can be compared in
//! isolation. The same workload always produces the same bytes.

use std::fmt::Write as _;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Workload {
    /// Plain printable text, like `cat` of a large log.
    Ascii,
    /// Log lines with 16-color, 256-color and truecolor SGR.
    SgrLog,
    /// Wide CJK, emoji, combining marks and box drawing.
    Unicode,
    /// htop-like: alternate screen, cursor addressing and full redraws.
    Fullscreen,
    /// vim/less-like: scrolling inside a DECSTBM region with fixed status lines.
    ScrollRegion,
}

impl Workload {
    pub const ALL: [Workload; 5] = [
        Workload::Ascii,
        Workload::SgrLog,
        Workload::Unicode,
        Workload::Fullscreen,
        Workload::ScrollRegion,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Self::Ascii => "ascii",
            Self::SgrLog => "sgr-log",
            Self::Unicode => "unicode",
            Self::Fullscreen => "fullscreen",
            Self::ScrollRegion => "scroll-region",
        }
    }

    pub fn from_name(name: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|w| w.name() == name)
    }

    /// At least `target_bytes` of output for a `cols`×`rows` terminal.
    pub fn generate(self, target_bytes: usize, cols: usize, rows: usize) -> String {
        let seed = Self::ALL.iter().position(|w| *w == self).unwrap_or(0) as u64 + 1;
        let mut rng = Rng(0x9e37_79b9_7f4a_7c15 ^ seed);
        let cols = cols.max(10);
        let rows = rows.max(5);
        match self {
            Self::Ascii => ascii(&mut rng, target_bytes, cols),
            Self::SgrLog => sgr_log(&mut rng, target_bytes),
            Self::Unicode => unicode(&mut rng, target_bytes),
            Self::Fullscreen => fullscreen(&mut rng, target_bytes, cols, rows),
            Self::ScrollRegion => scroll_region(&mut rng, target_bytes, cols, rows),
        }
    }
}

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

fn ascii(rng: &mut Rng, target: usize, cols: usize) -> String {
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

fn sgr_log(rng: &mut Rng, target: usize) -> String {
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

fn unicode(rng: &mut Rng, target: usize) -> String {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workloads_are_deterministic_and_reach_the_target() {
        for w in Workload::ALL {
            let a = w.generate(64 * 1024, 120, 40);
            assert!(a.len() >= 64 * 1024, "{}", w.name());
            assert_eq!(a, w.generate(64 * 1024, 120, 40), "{}", w.name());
            assert_eq!(Workload::from_name(w.name()), Some(w));
        }
    }
}
