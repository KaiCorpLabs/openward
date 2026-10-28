//! asciicast v2, the format of the recordings: a JSON header on the first
//! line, then one JSON array per event, `[seconds, code, data]`. Codes:
//! `o` output, `r` a new size (`"80x24"`), `m` a marker. What asciinema
//! and its player read.
//!
//! Commands are markers whose label starts with `$ `; OpenWard's own
//! markers ([`Mark`]) never do.

use std::fmt::Write as _;
use std::io::BufRead;

use serde::{Deserialize, Serialize};

/// The first line.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Header {
    pub version: u8,
    pub width: u16,
    pub height: u16,
    /// When it started, in seconds since the epoch.
    #[serde(default)]
    pub timestamp: i64,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub title: String,
    #[serde(default, skip_serializing_if = "Env::is_empty")]
    pub env: Env,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Env {
    #[serde(rename = "TERM", default, skip_serializing_if = "String::is_empty")]
    pub term: String,
}

impl Env {
    fn is_empty(&self) -> bool {
        self.term.is_empty()
    }
}

impl Header {
    pub fn new(width: u16, height: u16, timestamp: i64, title: &str, term: &str) -> Self {
        Self {
            version: 2,
            width,
            height,
            timestamp,
            title: title.to_owned(),
            env: Env {
                term: term.to_owned(),
            },
        }
    }

    pub(crate) fn line(&self) -> String {
        let mut line = serde_json::to_string(self).expect("a header always encodes");
        line.push('\n');
        line
    }
}

/// OpenWard's own markers, besides the commands.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mark {
    /// The user paused the recording: what follows until [`Mark::Resume`]
    /// was not kept.
    Pause,
    Resume,
    /// The connection stopped answering; it is being tried again.
    Lost,
    /// It came back.
    Back,
    /// Output came faster than it could be written, and some was left out.
    Omitted,
    /// The session reached the most a recording keeps: nothing after this.
    Full,
}

impl Mark {
    pub fn label(self) -> &'static str {
        match self {
            Self::Pause => "pause",
            Self::Resume => "resume",
            Self::Lost => "lost",
            Self::Back => "back",
            Self::Omitted => "omitted",
            Self::Full => "full",
        }
    }

    pub fn from_label(label: &str) -> Option<Self> {
        [
            Self::Pause,
            Self::Resume,
            Self::Lost,
            Self::Back,
            Self::Omitted,
            Self::Full,
        ]
        .into_iter()
        .find(|m| m.label() == label)
    }
}

/// The label of a command's marker.
pub(crate) fn command_label(command: &str) -> String {
    format!("$ {command}")
}

/// The command a marker stands for, if it is one.
pub fn command_of(label: &str) -> Option<&str> {
    label.strip_prefix("$ ")
}

#[derive(Clone, Debug, PartialEq)]
pub enum Event {
    Output(String),
    Resize(u16, u16),
    Marker(String),
}

/// A recording read back.
#[derive(Clone, Debug, PartialEq)]
pub struct Recording {
    pub header: Header,
    /// In time order, in seconds from the start.
    pub events: Vec<(f64, Event)>,
    /// Ended properly; false when the file stops short (the app closed
    /// suddenly, or it is still being written).
    pub complete: bool,
}

impl Recording {
    /// Seconds from the start to the last event.
    pub fn duration(&self) -> f64 {
        self.events.last().map_or(0.0, |(t, _)| *t)
    }
}

/// Appends one event line.
pub(crate) fn push_event(out: &mut String, t: f64, code: char, data: &str) {
    let _ = write!(out, "[{t:.6}, \"{code}\", ");
    push_json_str(out, data);
    out.push_str("]\n");
}

/// Copies the runs between the characters that need escaping in one go:
/// those are all ASCII, so every cut falls between two characters.
fn push_json_str(out: &mut String, s: &str) {
    out.push('"');
    let mut start = 0;
    for (i, &b) in s.as_bytes().iter().enumerate() {
        let escaped = match b {
            b'"' => "\\\"",
            b'\\' => "\\\\",
            b'\n' => "\\n",
            b'\r' => "\\r",
            b'\t' => "\\t",
            0..=0x1f | 0x7f => "",
            _ => continue,
        };
        out.push_str(&s[start..i]);
        if escaped.is_empty() {
            let _ = write!(out, "\\u{b:04x}");
        } else {
            out.push_str(escaped);
        }
        start = i + 1;
    }
    out.push_str(&s[start..]);
    out.push('"');
}

/// Reads a recording, keeping what is whole: a file cut short (by a
/// sudden exit, or one still being written) gives every complete line
/// before the cut.
pub fn read(mut input: impl BufRead) -> std::io::Result<Recording> {
    let mut line = String::new();
    input.read_line(&mut line)?;
    let header: Header = serde_json::from_str(line.trim_end())
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    let mut events = Vec::new();
    let mut complete = true;
    loop {
        line.clear();
        match input.read_line(&mut line) {
            Ok(0) => break,
            Ok(_) if !line.ends_with('\n') => {
                complete = false;
                break;
            }
            Ok(_) => {}
            // A gzip stream cut short: everything before is good.
            Err(_) => {
                complete = false;
                break;
            }
        }
        let Ok((t, code, data)) = serde_json::from_str::<(f64, String, String)>(&line) else {
            complete = false;
            break;
        };
        let event = match code.as_str() {
            "o" => Event::Output(data),
            "r" => match parse_size(&data) {
                Some((cols, rows)) => Event::Resize(cols, rows),
                None => continue,
            },
            "m" => Event::Marker(data),
            // Input, or something newer: not ours to replay.
            _ => continue,
        };
        events.push((t, event));
    }
    Ok(Recording {
        header,
        events,
        complete,
    })
}

pub(crate) fn size_data(cols: u16, rows: u16) -> String {
    format!("{cols}x{rows}")
}

fn parse_size(data: &str) -> Option<(u16, u16)> {
    let (cols, rows) = data.split_once('x')?;
    Some((cols.parse().ok()?, rows.parse().ok()?))
}

/// Turns output bytes into text, holding back a character cut in two
/// between reads until the rest arrives. Invalid bytes become U+FFFD.
#[derive(Debug, Default)]
pub(crate) struct Utf8Stream {
    carry: Vec<u8>,
}

impl Utf8Stream {
    pub(crate) fn decode(&mut self, bytes: &[u8]) -> String {
        let mut buf = std::mem::take(&mut self.carry);
        buf.extend_from_slice(bytes);
        let mut out = String::with_capacity(buf.len());
        let mut rest = &buf[..];
        loop {
            match std::str::from_utf8(rest) {
                Ok(s) => {
                    out.push_str(s);
                    break;
                }
                Err(e) => {
                    let (good, bad) = rest.split_at(e.valid_up_to());
                    out.push_str(std::str::from_utf8(good).expect("valid up to here"));
                    match e.error_len() {
                        Some(n) => {
                            out.push('\u{fffd}');
                            rest = &bad[n..];
                        }
                        None => {
                            self.carry = bad.to_vec();
                            break;
                        }
                    }
                }
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn events_are_json_that_reads_back() {
        let header = Header::new(80, 24, 1_761_000_000, "web-1", "xterm-256color");
        let mut text = header.line();
        push_event(
            &mut text,
            0.0,
            'o',
            "hola \"mundo\"\r\n\x1b[31mrojo\x1b[0m\ttab\\",
        );
        push_event(&mut text, 1.5, 'r', &size_data(100, 30));
        push_event(&mut text, 2.25, 'm', &command_label("ls -la"));
        push_event(&mut text, 3.0, 'i', "secreto");
        assert!(text.starts_with(r#"{"version":2,"width":80,"height":24,"timestamp":1761000000,"title":"web-1","env":{"TERM":"xterm-256color"}}"#));
        assert!(
            text.contains(r#"[0.000000, "o", "hola \"mundo\"\r\n\u001b[31mrojo\u001b[0m\ttab\\"]"#)
        );
        let rec = read(text.as_bytes()).unwrap();
        assert_eq!(rec.header, header);
        assert!(rec.complete);
        assert_eq!(
            rec.events,
            [
                (
                    0.0,
                    Event::Output("hola \"mundo\"\r\n\x1b[31mrojo\x1b[0m\ttab\\".into())
                ),
                (1.5, Event::Resize(100, 30)),
                (2.25, Event::Marker("$ ls -la".into())),
            ],
            "input is never replayed"
        );
        assert_eq!(rec.duration(), 2.25);
        assert_eq!(command_of("$ ls -la"), Some("ls -la"));
        assert_eq!(command_of("pause"), None);
        assert_eq!(Mark::from_label("lost"), Some(Mark::Lost));
    }

    #[test]
    fn a_file_cut_short_keeps_its_whole_lines() {
        let mut text = Header::new(80, 24, 0, "", "").line();
        push_event(&mut text, 0.5, 'o', "uno\r\n");
        push_event(&mut text, 1.0, 'o', "dos\r\n");
        let cut = &text[..text.len() - 4];
        let rec = read(cut.as_bytes()).unwrap();
        assert!(!rec.complete);
        assert_eq!(rec.events, [(0.5, Event::Output("uno\r\n".into()))]);
    }

    #[test]
    fn characters_split_between_reads_come_out_whole() {
        let mut s = Utf8Stream::default();
        let bytes = "añ€😀".as_bytes();
        let mut out = String::new();
        for b in bytes {
            out.push_str(&s.decode(&[*b]));
        }
        assert_eq!(out, "añ€😀");
        assert_eq!(s.decode(b"a\xffb"), "a\u{fffd}b");
    }
}
