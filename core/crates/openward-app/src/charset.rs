//! A host's character set: its bytes are read into UTF-8 before the
//! terminal's engine sees them, and what is typed goes back in its bytes.
//! The engine, the screen and the session log only ever see UTF-8.
//!
//! `encoding_rs` has the encodings browsers know (Latin-1, Shift-JIS,
//! Big5…); CP437, the IBM PC's, is here as a table.

use encoding_rs::{CoderResult, Encoding};
use openward_vault::proto::{Backspace, Settings};

/// The labels the app offers, UTF-8 first; [`Charset::of`] reads others
/// that `encoding_rs` knows too.
pub const OFFERED: &[&str] = &[
    "utf-8",
    "iso-8859-1",
    "iso-8859-15",
    "windows-1252",
    "cp437",
    "iso-8859-2",
    "windows-1250",
    "windows-1251",
    "koi8-r",
    "ibm866",
    "shift_jis",
    "euc-jp",
    "big5",
    "gb18030",
    "euc-kr",
];

/// How a host's bytes are read and written: its character set and what
/// Backspace sends. The default is today's: UTF-8 and DEL.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Coding {
    /// `None` for UTF-8.
    pub charset: Option<Charset>,
    /// Backspace sends `^H` (and Ctrl+Backspace, DEL).
    pub backspace_h: bool,
}

impl Coding {
    /// What a host's effective settings ask for.
    pub fn of(settings: &Settings) -> Self {
        Self {
            charset: settings.encoding.as_deref().and_then(Charset::of),
            backspace_h: settings.backspace == Some(Backspace::ControlH),
        }
    }

    /// The same, in UTF-8: what Mosh always is.
    pub fn utf8(self) -> Self {
        Self {
            charset: None,
            ..self
        }
    }
}

/// A character set other than UTF-8.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Charset {
    Whatwg(&'static Encoding),
    /// The IBM PC's: box drawing and accented letters above 0x7f.
    Cp437,
}

impl Charset {
    /// The one `label` names; `None` for UTF-8 (nothing to translate)
    /// and for a label no one knows.
    pub fn of(label: &str) -> Option<Self> {
        let label = label.trim();
        if label.eq_ignore_ascii_case("cp437")
            || label.eq_ignore_ascii_case("ibm437")
            || label.eq_ignore_ascii_case("437")
        {
            return Some(Self::Cp437);
        }
        match Encoding::for_label(label.as_bytes()) {
            Some(e) if e == encoding_rs::UTF_8 => None,
            // Not text a terminal can be written in.
            Some(e) if e == encoding_rs::UTF_16LE || e == encoding_rs::UTF_16BE => None,
            Some(e) if e == encoding_rs::REPLACEMENT => None,
            Some(e) => Some(Self::Whatwg(e)),
            None => None,
        }
    }

    /// A reader of this host's output, which keeps a character cut in two
    /// between reads for the next one.
    pub fn decoder(self) -> Decoder {
        match self {
            Self::Whatwg(e) => Decoder::Whatwg(e.new_decoder_without_bom_handling()),
            Self::Cp437 => Decoder::Cp437,
        }
    }

    /// `utf8` (what the engine encoded: keys, typed text, a paste) in this
    /// host's bytes. Characters it does not have go as `?`. Bytes that are
    /// not UTF-8 (old mouse reports) go as they are.
    pub fn encode(self, utf8: &[u8]) -> Vec<u8> {
        if utf8.is_ascii() {
            return utf8.to_vec();
        }
        let Ok(text) = std::str::from_utf8(utf8) else {
            return utf8.to_vec();
        };
        match self {
            Self::Cp437 => text
                .chars()
                .map(|c| {
                    if c.is_ascii() {
                        c as u8
                    } else {
                        CP437_HIGH
                            .iter()
                            .position(|&h| h == c)
                            .map_or(b'?', |i| 0x80 + i as u8)
                    }
                })
                .collect(),
            Self::Whatwg(e) => {
                let mut encoder = e.new_encoder();
                let mut out = Vec::with_capacity(text.len() * 2);
                let mut rest = text;
                loop {
                    out.reserve(
                        encoder
                            .max_buffer_length_from_utf8_without_replacement(rest.len())
                            .unwrap_or(rest.len() * 4)
                            + 4,
                    );
                    let (result, read) =
                        encoder.encode_from_utf8_to_vec_without_replacement(rest, &mut out, true);
                    rest = &rest[read..];
                    match result {
                        encoding_rs::EncoderResult::InputEmpty => break,
                        encoding_rs::EncoderResult::OutputFull => {}
                        encoding_rs::EncoderResult::Unmappable(_) => out.push(b'?'),
                    }
                }
                out
            }
        }
    }
}

/// Reads a host's output into UTF-8, a piece at a time.
pub enum Decoder {
    Whatwg(encoding_rs::Decoder),
    Cp437,
}

impl Decoder {
    pub fn decode(&mut self, bytes: &[u8]) -> Vec<u8> {
        match self {
            // Controls (and so escape sequences) are the same in CP437.
            Self::Cp437 => {
                let mut out = String::with_capacity(bytes.len() * 2);
                for &b in bytes {
                    out.push(if b < 0x80 {
                        b as char
                    } else {
                        CP437_HIGH[usize::from(b - 0x80)]
                    });
                }
                out.into_bytes()
            }
            Self::Whatwg(d) => {
                let mut out = String::with_capacity(
                    d.max_utf8_buffer_length(bytes.len())
                        .unwrap_or(bytes.len() * 3),
                );
                let mut rest = bytes;
                loop {
                    let (result, read, _) = d.decode_to_string(rest, &mut out, false);
                    rest = &rest[read..];
                    match result {
                        CoderResult::InputEmpty => break,
                        CoderResult::OutputFull => out.reserve(rest.len() * 3 + 16),
                    }
                }
                out.into_bytes()
            }
        }
    }
}

/// CP437 from 0x80 to 0xff.
const CP437_HIGH: [char; 128] = [
    'Ç', 'ü', 'é', 'â', 'ä', 'à', 'å', 'ç', 'ê', 'ë', 'è', 'ï', 'î', 'ì', 'Ä', 'Å', //
    'É', 'æ', 'Æ', 'ô', 'ö', 'ò', 'û', 'ù', 'ÿ', 'Ö', 'Ü', '¢', '£', '¥', '₧', 'ƒ', //
    'á', 'í', 'ó', 'ú', 'ñ', 'Ñ', 'ª', 'º', '¿', '⌐', '¬', '½', '¼', '¡', '«', '»', //
    '░', '▒', '▓', '│', '┤', '╡', '╢', '╖', '╕', '╣', '║', '╗', '╝', '╜', '╛', '┐', //
    '└', '┴', '┬', '├', '─', '┼', '╞', '╟', '╚', '╔', '╩', '╦', '╠', '═', '╬', '╧', //
    '╨', '╤', '╥', '╙', '╘', '╒', '╓', '╫', '╪', '┘', '┌', '█', '▄', '▌', '▐', '▀', //
    'α', 'ß', 'Γ', 'π', 'Σ', 'σ', 'µ', 'τ', 'Φ', 'Θ', 'Ω', 'δ', '∞', 'φ', 'ε', '∩', //
    '≡', '±', '≥', '≤', '⌠', '⌡', '÷', '≈', '°', '∙', '·', '√', 'ⁿ', '²', '■', '\u{a0}',
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf8_and_unknown_labels_translate_nothing() {
        assert_eq!(Charset::of("utf-8"), None);
        assert_eq!(Charset::of("UTF8"), None);
        assert_eq!(Charset::of("klingon"), None);
        assert_eq!(Charset::of("utf-16le"), None);
        assert!(Charset::of("latin1").is_some());
        assert_eq!(Charset::of("IBM437"), Some(Charset::Cp437));
        for label in OFFERED.iter().skip(1) {
            assert!(Charset::of(label).is_some(), "{label}");
        }
    }

    #[test]
    fn latin1_reads_and_writes_its_bytes() {
        let latin1 = Charset::of("iso-8859-1").unwrap();
        let mut d = latin1.decoder();
        assert_eq!(
            String::from_utf8(d.decode(b"\x1b[1mcanci\xf3n\x1b[0m")).unwrap(),
            "\x1b[1mcanción\x1b[0m"
        );
        assert_eq!(latin1.encode("año".as_bytes()), b"a\xf1o");
        // Not in Latin-1: a question mark, not an HTML entity.
        assert_eq!(latin1.encode("→".as_bytes()), b"?");
        assert_eq!(latin1.encode(b"\x1b[A"), b"\x1b[A");
    }

    #[test]
    fn a_character_cut_between_reads_is_kept_for_the_next() {
        let sjis = Charset::of("shift_jis").unwrap();
        let bytes = sjis.encode("日本".as_bytes());
        assert_eq!(bytes.len(), 4);
        let mut d = sjis.decoder();
        let mut out = d.decode(&bytes[..1]);
        out.extend(d.decode(&bytes[1..3]));
        out.extend(d.decode(&bytes[3..]));
        assert_eq!(String::from_utf8(out).unwrap(), "日本");
    }

    #[test]
    fn cp437_draws_boxes_and_keeps_controls() {
        let mut d = Charset::Cp437.decoder();
        assert_eq!(
            String::from_utf8(d.decode(b"\xc9\xcd\xbb\r\n\x1b[0m\xb0")).unwrap(),
            "╔═╗\r\n\x1b[0m░"
        );
        assert_eq!(Charset::Cp437.encode("ñ╬".as_bytes()), b"\xa4\xce");
        assert_eq!(Charset::Cp437.encode("€".as_bytes()), b"?");
    }

    #[test]
    fn bytes_that_are_not_utf8_go_as_they_are() {
        let latin1 = Charset::of("latin1").unwrap();
        // An X10 mouse report past column 95.
        assert_eq!(latin1.encode(b"\x1b[M \xa0!"), b"\x1b[M \xa0!");
    }
}
