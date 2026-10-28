//! The plain text of a recording, line by line with the moment each began,
//! for searching: escape sequences dropped, carriage returns, backspaces
//! and line edits applied to the line being written. What a full-screen
//! program draws (the alternate screen: vim, htop, less) is left out; it
//! is in the replay.
//!
//! A filter, not a terminal: it follows one line at a time. Output that
//! moves the cursor between rows outside the alternate screen comes out
//! approximate, which is enough to find it.

/// Longer lines are cut: a search shows lines, not pages.
const MAX_LINE: usize = 2000;
/// A sequence with more parameters than this is not a real one.
const MAX_PARAMS: usize = 64;

#[derive(Debug, Default)]
pub(crate) struct TextFilter {
    line: Vec<char>,
    /// The line as text when it ends, kept to write the next one into.
    text: String,
    col: usize,
    /// When the current line got its first character.
    since: Option<f64>,
    state: State,
    params: String,
    /// In the alternate screen: nothing is kept.
    alt: bool,
}

#[derive(Debug, Default, PartialEq, Eq)]
enum State {
    #[default]
    Ground,
    Esc,
    /// ESC followed by an intermediate: one more character ends it.
    EscArg,
    Csi,
    /// OSC, DCS, SOS, PM, APC: until BEL or ESC.
    Text,
}

impl TextFilter {
    /// Takes output that arrived at `t`; each line it completes goes to
    /// `emit` with the moment it began.
    pub(crate) fn feed(&mut self, t: f64, text: &str, emit: &mut impl FnMut(f64, &str)) {
        let bytes = text.as_bytes();
        let mut i = 0;
        while i < bytes.len() {
            // Runs of printable ASCII, most of any output, in one go.
            if self.state == State::Ground && !self.alt {
                let run = bytes[i..]
                    .iter()
                    .take_while(|b| (0x20..0x7f).contains(*b))
                    .count();
                if run > 0 {
                    self.put_ascii(t, &bytes[i..i + run]);
                    i += run;
                    continue;
                }
            }
            let c = text[i..].chars().next().expect("a character starts here");
            i += c.len_utf8();
            match self.state {
                State::Ground => self.ground(t, c, emit),
                State::Esc => self.esc(c, t, emit),
                State::EscArg => self.state = State::Ground,
                State::Csi => self.csi(c, t, emit),
                State::Text => match c {
                    '\x07' => self.state = State::Ground,
                    '\x1b' => self.state = State::Esc,
                    _ => {}
                },
            }
        }
    }

    /// The last line, unfinished.
    pub(crate) fn finish(&mut self, emit: &mut impl FnMut(f64, &str)) {
        self.end_line(0.0, emit);
    }

    fn ground(&mut self, t: f64, c: char, emit: &mut impl FnMut(f64, &str)) {
        match c {
            '\x1b' => self.state = State::Esc,
            '\r' => self.col = 0,
            '\n' | '\x0b' | '\x0c' => self.end_line(t, emit),
            '\x08' => self.col = self.col.saturating_sub(1),
            '\t' => self.col = ((self.col / 8 + 1) * 8).min(MAX_LINE),
            c if (c as u32) < 0x20 || ('\u{7f}'..='\u{9f}').contains(&c) => {}
            c => self.put(t, c),
        }
    }

    fn esc(&mut self, c: char, t: f64, emit: &mut impl FnMut(f64, &str)) {
        self.state = State::Ground;
        match c {
            '[' => {
                self.params.clear();
                self.state = State::Csi;
            }
            ']' | 'P' | 'X' | '^' | '_' => self.state = State::Text,
            '(' | ')' | '*' | '+' | '-' | '.' | '/' | '#' | '%' | ' ' => {
                self.state = State::EscArg;
            }
            // Next line.
            'E' => self.end_line(t, emit),
            // A full reset.
            'c' => {
                self.end_line(t, emit);
                self.alt = false;
            }
            _ => {}
        }
    }

    fn csi(&mut self, c: char, t: f64, emit: &mut impl FnMut(f64, &str)) {
        match c {
            '\x30'..='\x3f' | '\x20'..='\x2f' => {
                if self.params.len() < MAX_PARAMS {
                    self.params.push(c);
                } else {
                    self.state = State::Ground;
                }
            }
            '\x40'..='\x7e' => {
                self.state = State::Ground;
                self.apply(c, t, emit);
            }
            // Not a sequence after all.
            _ => self.state = State::Ground,
        }
    }

    fn param(&self, i: usize, default: usize) -> usize {
        self.params
            .trim_start_matches(['?', '>', '<', '='])
            .split(';')
            .nth(i)
            .and_then(|p| p.parse().ok())
            .filter(|&n| n > 0)
            .unwrap_or(default)
    }

    fn apply(&mut self, finale: char, t: f64, emit: &mut impl FnMut(f64, &str)) {
        if self.alt && !matches!(finale, 'h' | 'l') {
            return;
        }
        let n = self.param(0, 1).min(MAX_LINE);
        match finale {
            // Erase in line: to the end, to the start, all of it.
            'K' => match self.param(0, 0) {
                0 => self.line.truncate(self.col),
                1 => {
                    let end = (self.col + 1).min(self.line.len());
                    self.line[..end].fill(' ');
                }
                _ => self.line.clear(),
            },
            'C' | 'a' => self.col = (self.col + n).min(MAX_LINE),
            'D' => self.col = self.col.saturating_sub(n),
            'G' | '`' => self.col = n - 1,
            // A position: only the column means anything on one line.
            'H' | 'f' => self.col = self.param(1, 1).min(MAX_LINE) - 1,
            'X' => {
                let end = (self.col + n).min(self.line.len());
                if self.col < end {
                    self.line[self.col..end].fill(' ');
                }
            }
            'P' => {
                if self.col < self.line.len() {
                    let end = (self.col + n).min(self.line.len());
                    self.line.drain(self.col..end);
                }
            }
            '@' => {
                if self.col < self.line.len() {
                    let room = MAX_LINE.saturating_sub(self.line.len()).min(n);
                    self.line
                        .splice(self.col..self.col, std::iter::repeat_n(' ', room));
                }
            }
            // Erase in display: below the cursor, or everything (`clear`).
            'J' => match self.param(0, 0) {
                0 => self.line.truncate(self.col),
                1 => {}
                _ => {
                    self.line.clear();
                    self.col = 0;
                    self.since = None;
                }
            },
            'h' | 'l' if self.params.starts_with('?') => {
                let alt = self
                    .params
                    .trim_start_matches('?')
                    .split(';')
                    .any(|p| matches!(p, "1049" | "1047" | "47"));
                if alt {
                    if finale == 'h' {
                        self.end_line(t, emit);
                        self.alt = true;
                    } else {
                        self.alt = false;
                        self.line.clear();
                        self.col = 0;
                        self.since = None;
                    }
                }
            }
            _ => {}
        }
    }

    fn put_ascii(&mut self, t: f64, run: &[u8]) {
        if self.since.is_none() {
            self.since = Some(t);
        }
        if self.col > self.line.len() {
            self.line.resize(self.col.min(MAX_LINE), ' ');
        }
        for &b in run {
            if self.col >= MAX_LINE {
                break;
            }
            match self.line.get_mut(self.col) {
                Some(cell) => *cell = char::from(b),
                None => self.line.push(char::from(b)),
            }
            self.col += 1;
        }
    }

    fn put(&mut self, t: f64, c: char) {
        if self.alt || self.col >= MAX_LINE {
            return;
        }
        if self.since.is_none() {
            self.since = Some(t);
        }
        if self.col < self.line.len() {
            self.line[self.col] = c;
        } else {
            self.line.resize(self.col, ' ');
            self.line.push(c);
        }
        self.col += 1;
    }

    fn end_line(&mut self, t: f64, emit: &mut impl FnMut(f64, &str)) {
        self.text.clear();
        self.text.extend(self.line.iter());
        let text = self.text.trim_end();
        if !text.trim_start().is_empty() {
            emit(self.since.unwrap_or(t), text);
        }
        self.line.clear();
        self.col = 0;
        self.since = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(chunks: &[(f64, &str)]) -> Vec<(f64, String)> {
        let mut f = TextFilter::default();
        let mut out = Vec::new();
        let mut emit = |t: f64, s: &str| out.push((t, s.to_owned()));
        for (t, text) in chunks {
            f.feed(*t, text, &mut emit);
        }
        f.finish(&mut emit);
        out
    }

    fn texts(chunks: &[(f64, &str)]) -> Vec<String> {
        lines(chunks).into_iter().map(|(_, s)| s).collect()
    }

    #[test]
    fn colors_and_titles_go_lines_keep_their_start() {
        let out = lines(&[
            (0.0, "\x1b]0;ops@web-1: ~\x07\x1b[32mops@web-1\x1b[0m:~$ "),
            (1.0, "ls\r\n"),
            (1.2, "\x1b[01;34mapp\x1b[0m  notes.txt\r\n"),
        ]);
        assert_eq!(
            out,
            [
                (0.0, "ops@web-1:~$ ls".into()),
                (1.2, "app  notes.txt".into())
            ]
        );
    }

    #[test]
    fn line_edits_apply_to_the_line() {
        // A progress bar redrawn with \r, a backspace, zsh erasing a
        // suggestion, a tab, and a cursor moved back to fix a typo.
        assert_eq!(
            texts(&[(
                0.0,
                "10%\r55%\r100% hecho\r\nlz\x08s -l\x1b[K\r\na\tb\r\nsudo nginx -y\x1b[1Dt\r\n"
            )]),
            ["100% hecho", "ls -l", "a       b", "sudo nginx -t"]
        );
        assert_eq!(
            texts(&[(0.0, "% ls\x1b[90mof\x1b[0m\x1b[2D\x1b[K\r\n")]),
            ["% ls"]
        );
        assert_eq!(texts(&[(0.0, "abcdef\x1b[3G\x1b[2P\r\n")]), ["abef"]);
    }

    #[test]
    fn full_screen_programs_are_left_out() {
        assert_eq!(
            texts(&[(
                0.0,
                "$ vim notas\r\n\x1b[?1049h\x1b[H\x1b[2Jsecreto en pantalla\r\n~\r\n\x1b[?1049l$ echo fin\r\nfin\r\n"
            )]),
            ["$ vim notas", "$ echo fin", "fin"]
        );
    }

    #[test]
    fn wide_and_combined_text_survives() {
        assert_eq!(texts(&[(0.0, "漢字 ñandú 😀\r\n")]), ["漢字 ñandú 😀"]);
    }

    #[test]
    fn sequences_split_between_chunks_still_go() {
        assert_eq!(
            texts(&[(0.0, "a\x1b["), (0.1, "31mb\x1b"), (0.2, "]0;t\x07c\r\n")]),
            ["abc"]
        );
    }
}
