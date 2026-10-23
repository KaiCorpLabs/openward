//! Damage frames: the binary format the core sends to the UI.
//!
//! A frame lists only the rows that changed, each as runs ("spans") of cells
//! sharing one style. The UI paints a span at `col * cell_width` without
//! shaping across spans, so every span holds either single-width cells or
//! exactly one wide (two-column) cell.
//!
//! Layout, all integers little-endian:
//!
//! ```text
//! frame  := version:u8 flags:u8 cols:u16 rows:u16
//!           cursor_row:u16 cursor_col:u16 cursor_shape:u8 cursor_visible:u8
//!           display_offset:u32 row_count:u16 row*
//! row    := index:u16 span_count:u16 span*
//! span   := col:u16 width:u16 fg:u32 bg:u32 attrs:u16 text_len:u16 text:utf8
//! ```
//!
//! `flags` bit 0 marks a full frame: the UI must clear rows it did not get.
//! Every row in a frame is repainted from scratch: the UI clears it to the
//! default background and then paints its spans. Blank cells with the default
//! style are therefore omitted.

use crate::engine::{CursorShape, CursorState};

pub const FRAME_VERSION: u8 = 1;

/// The most bytes of text a span holds (its length is a u16).
const MAX_SPAN_TEXT: usize = u16::MAX as usize;

/// `text` cut to at most `max` bytes, at a character boundary.
fn truncate(text: &str, max: usize) -> &str {
    if text.len() <= max {
        return text;
    }
    let mut end = max;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    &text[..end]
}
pub const FLAG_FULL: u8 = 1;

/// Text attributes, as a bit set in [`Style::attrs`].
pub mod attrs {
    pub const BOLD: u16 = 1 << 0;
    pub const DIM: u16 = 1 << 1;
    pub const ITALIC: u16 = 1 << 2;
    pub const UNDERLINE: u16 = 1 << 3;
    pub const DOUBLE_UNDERLINE: u16 = 1 << 4;
    pub const UNDERCURL: u16 = 1 << 5;
    pub const DOTTED_UNDERLINE: u16 = 1 << 6;
    pub const DASHED_UNDERLINE: u16 = 1 << 7;
    pub const INVERSE: u16 = 1 << 8;
    pub const HIDDEN: u16 = 1 << 9;
    pub const STRIKEOUT: u16 = 1 << 10;
}

/// A color as the host requested it. The UI resolves palette entries against
/// the active theme, so themes can change without re-encoding the screen.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Color {
    /// Theme default foreground or background, depending on the slot.
    Default,
    /// One of the 16 ANSI colors (0–15) or a dim variant (16–23).
    Named(u8),
    /// 256-color palette index.
    Indexed(u8),
    Rgb(u8, u8, u8),
}

impl Color {
    /// Wire value: tag in the high byte (0 default, 1 named, 2 indexed, 3 RGB).
    pub fn to_raw(self) -> u32 {
        match self {
            Self::Default => 0,
            Self::Named(i) => (1 << 24) | u32::from(i),
            Self::Indexed(i) => (2 << 24) | u32::from(i),
            Self::Rgb(r, g, b) => {
                (3 << 24) | (u32::from(r) << 16) | (u32::from(g) << 8) | u32::from(b)
            }
        }
    }

    pub fn from_raw(v: u32) -> Option<Self> {
        let payload = v & 0x00ff_ffff;
        Some(match v >> 24 {
            0 => Self::Default,
            1 => Self::Named(payload as u8),
            2 => Self::Indexed(payload as u8),
            3 => Self::Rgb((payload >> 16) as u8, (payload >> 8) as u8, payload as u8),
            _ => return None,
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Style {
    pub fg: Color,
    pub bg: Color,
    pub attrs: u16,
}

impl Default for Style {
    fn default() -> Self {
        Self {
            fg: Color::Default,
            bg: Color::Default,
            attrs: 0,
        }
    }
}

/// Counters for one encoded frame, used by benchmarks.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FrameStats {
    pub full: bool,
    pub rows: u32,
    pub spans: u32,
    pub bytes: u32,
}

struct OpenSpan {
    col: u16,
    width: u16,
    style: Style,
    wide: bool,
    text: String,
}

/// Builds one frame at a time into a reusable buffer.
#[derive(Default)]
pub struct FrameEncoder {
    buf: Vec<u8>,
    row_count: u16,
    row_count_at: usize,
    span_count: u16,
    span_count_at: usize,
    open: Option<OpenSpan>,
    stats: FrameStats,
}

impl FrameEncoder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn begin(
        &mut self,
        full: bool,
        cols: u16,
        rows: u16,
        cursor: CursorState,
        display_offset: u32,
    ) {
        self.buf.clear();
        self.row_count = 0;
        self.open = None;
        self.stats = FrameStats {
            full,
            ..FrameStats::default()
        };
        self.buf.push(FRAME_VERSION);
        self.buf.push(if full { FLAG_FULL } else { 0 });
        self.put_u16(cols);
        self.put_u16(rows);
        self.put_u16(cursor.row);
        self.put_u16(cursor.col);
        self.buf.push(cursor.shape.code());
        self.buf.push(u8::from(cursor.visible));
        self.buf.extend_from_slice(&display_offset.to_le_bytes());
        self.row_count_at = self.buf.len();
        self.put_u16(0);
    }

    pub fn begin_row(&mut self, index: u16) {
        self.put_u16(index);
        self.span_count = 0;
        self.span_count_at = self.buf.len();
        self.put_u16(0);
    }

    /// Append one cell. `text` is the base character plus any combining
    /// marks; `width` is 1 or 2 columns. Spacer cells behind a wide character
    /// must not be pushed. Blank default cells may be skipped by the caller.
    pub fn push_cell(&mut self, col: u16, text: &str, width: u16, style: Style) {
        let wide = width > 1;
        // A cell may hold dozens of combining marks, so a row of them can
        // pass what a span's u16 length says: such a span is split.
        let text = truncate(text, MAX_SPAN_TEXT);
        if let Some(span) = &mut self.open
            && !wide
            && !span.wide
            && span.style == style
            && span.col + span.width == col
            && span.text.len() + text.len() <= MAX_SPAN_TEXT
        {
            span.width += width;
            span.text.push_str(text);
            return;
        }
        self.flush_span();
        self.open = Some(OpenSpan {
            col,
            width,
            style,
            wide,
            text: text.to_owned(),
        });
    }

    pub fn end_row(&mut self) {
        self.flush_span();
        let at = self.span_count_at;
        self.buf[at..at + 2].copy_from_slice(&self.span_count.to_le_bytes());
        self.row_count += 1;
        self.stats.rows += 1;
    }

    pub fn finish(&mut self) -> FrameStats {
        let at = self.row_count_at;
        self.buf[at..at + 2].copy_from_slice(&self.row_count.to_le_bytes());
        self.stats.bytes = self.buf.len() as u32;
        self.stats
    }

    pub fn bytes(&self) -> &[u8] {
        &self.buf
    }

    fn flush_span(&mut self) {
        let Some(span) = self.open.take() else {
            return;
        };
        // `push_cell` keeps it within a u16.
        let text = span.text.as_bytes();
        self.put_u16(span.col);
        self.put_u16(span.width);
        self.buf
            .extend_from_slice(&span.style.fg.to_raw().to_le_bytes());
        self.buf
            .extend_from_slice(&span.style.bg.to_raw().to_le_bytes());
        self.put_u16(span.style.attrs);
        self.put_u16(text.len() as u16);
        self.buf.extend_from_slice(text);
        self.span_count += 1;
        self.stats.spans += 1;
    }

    fn put_u16(&mut self, v: u16) {
        self.buf.extend_from_slice(&v.to_le_bytes());
    }
}

/// A decoded frame. The UI decodes in Dart; this Rust decoder documents the
/// format and backs the tests.
#[derive(Debug, PartialEq, Eq)]
pub struct DecodedFrame {
    pub full: bool,
    pub cols: u16,
    pub rows: u16,
    pub cursor: CursorState,
    pub display_offset: u32,
    pub lines: Vec<DecodedRow>,
}

#[derive(Debug, PartialEq, Eq)]
pub struct DecodedRow {
    pub index: u16,
    pub spans: Vec<DecodedSpan>,
}

#[derive(Debug, PartialEq, Eq)]
pub struct DecodedSpan {
    pub col: u16,
    pub width: u16,
    pub style: Style,
    pub text: String,
}

#[derive(Debug, PartialEq, Eq)]
pub enum DecodeError {
    Truncated,
    UnsupportedVersion(u8),
    InvalidValue,
}

pub fn decode(bytes: &[u8]) -> Result<DecodedFrame, DecodeError> {
    let mut r = Reader { bytes, pos: 0 };
    let version = r.u8()?;
    if version != FRAME_VERSION {
        return Err(DecodeError::UnsupportedVersion(version));
    }
    let flags = r.u8()?;
    let cols = r.u16()?;
    let rows = r.u16()?;
    let cursor = CursorState {
        row: r.u16()?,
        col: r.u16()?,
        shape: CursorShape::from_code(r.u8()?).ok_or(DecodeError::InvalidValue)?,
        visible: r.u8()? != 0,
    };
    let display_offset = r.u32()?;
    let row_count = r.u16()?;
    let mut lines = Vec::with_capacity(usize::from(row_count));
    for _ in 0..row_count {
        let index = r.u16()?;
        let span_count = r.u16()?;
        let mut spans = Vec::with_capacity(usize::from(span_count));
        for _ in 0..span_count {
            let col = r.u16()?;
            let width = r.u16()?;
            let fg = Color::from_raw(r.u32()?).ok_or(DecodeError::InvalidValue)?;
            let bg = Color::from_raw(r.u32()?).ok_or(DecodeError::InvalidValue)?;
            let attrs = r.u16()?;
            let len = usize::from(r.u16()?);
            let text = std::str::from_utf8(r.take(len)?).map_err(|_| DecodeError::InvalidValue)?;
            spans.push(DecodedSpan {
                col,
                width,
                style: Style { fg, bg, attrs },
                text: text.to_owned(),
            });
        }
        lines.push(DecodedRow { index, spans });
    }
    if r.pos != bytes.len() {
        return Err(DecodeError::InvalidValue);
    }
    Ok(DecodedFrame {
        full: flags & FLAG_FULL != 0,
        cols,
        rows,
        cursor,
        display_offset,
        lines,
    })
}

struct Reader<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8], DecodeError> {
        let end = self.pos.checked_add(n).ok_or(DecodeError::Truncated)?;
        let slice = self
            .bytes
            .get(self.pos..end)
            .ok_or(DecodeError::Truncated)?;
        self.pos = end;
        Ok(slice)
    }

    fn u8(&mut self) -> Result<u8, DecodeError> {
        Ok(self.take(1)?[0])
    }

    fn u16(&mut self) -> Result<u16, DecodeError> {
        let b = self.take(2)?;
        Ok(u16::from_le_bytes([b[0], b[1]]))
    }

    fn u32(&mut self) -> Result<u32, DecodeError> {
        let b = self.take(4)?;
        Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cursor() -> CursorState {
        CursorState {
            row: 1,
            col: 4,
            shape: CursorShape::Beam,
            visible: true,
        }
    }

    #[test]
    fn same_style_cells_merge_into_one_span() {
        let mut enc = FrameEncoder::new();
        enc.begin(true, 80, 24, cursor(), 0);
        enc.begin_row(0);
        for (i, ch) in ["a", "b", "c"].iter().enumerate() {
            enc.push_cell(i as u16, ch, 1, Style::default());
        }
        enc.end_row();
        let stats = enc.finish();
        assert_eq!(stats.spans, 1);

        let frame = decode(enc.bytes()).unwrap();
        assert!(frame.full);
        assert_eq!(frame.cursor, cursor());
        assert_eq!(frame.lines[0].spans[0].text, "abc");
        assert_eq!(frame.lines[0].spans[0].width, 3);
    }

    /// A wide row of cells with many combining marks each passes 64 KiB in
    /// one style: it goes in several spans, and decodes.
    #[test]
    fn spans_stay_within_their_u16_length() {
        let cell = format!("e{}", "\u{E0100}".repeat(64)); // 257 bytes
        let mut enc = FrameEncoder::new();
        enc.begin(true, 300, 1, cursor(), 0);
        enc.begin_row(0);
        for col in 0..300 {
            enc.push_cell(col, &cell, 1, Style::default());
        }
        enc.end_row();
        enc.finish();
        let frame = decode(enc.bytes()).unwrap();
        let spans = &frame.lines[0].spans;
        assert!(spans.len() > 1);
        assert!(spans.iter().all(|s| s.text.len() <= MAX_SPAN_TEXT));
        assert_eq!(spans.iter().map(|s| s.width).sum::<u16>(), 300);
        assert_eq!(
            spans.iter().map(|s| s.text.len()).sum::<usize>(),
            300 * cell.len()
        );
    }

    #[test]
    fn wide_cells_and_style_changes_split_spans() {
        let red = Style {
            fg: Color::Named(1),
            ..Style::default()
        };
        let mut enc = FrameEncoder::new();
        enc.begin(false, 80, 24, cursor(), 7);
        enc.begin_row(3);
        enc.push_cell(0, "a", 1, Style::default());
        enc.push_cell(1, "漢", 2, Style::default());
        enc.push_cell(3, "b", 1, Style::default());
        enc.push_cell(4, "c", 1, red);
        enc.push_cell(6, "d", 1, red); // gap at col 5 starts a new span
        enc.end_row();
        enc.finish();

        let frame = decode(enc.bytes()).unwrap();
        assert!(!frame.full);
        assert_eq!(frame.display_offset, 7);
        let spans: Vec<_> = frame.lines[0]
            .spans
            .iter()
            .map(|s| (s.col, s.width, s.text.as_str()))
            .collect();
        assert_eq!(
            spans,
            vec![
                (0, 1, "a"),
                (1, 2, "漢"),
                (3, 1, "b"),
                (4, 1, "c"),
                (6, 1, "d")
            ]
        );
        assert_eq!(frame.lines[0].spans[3].style.fg, Color::Named(1));
    }

    #[test]
    fn colors_round_trip() {
        for c in [
            Color::Default,
            Color::Named(15),
            Color::Indexed(200),
            Color::Rgb(1, 2, 3),
        ] {
            assert_eq!(Color::from_raw(c.to_raw()), Some(c));
        }
    }

    #[test]
    fn truncated_input_is_rejected() {
        let mut enc = FrameEncoder::new();
        enc.begin(true, 80, 24, cursor(), 0);
        enc.finish();
        let bytes = enc.bytes();
        assert_eq!(
            decode(&bytes[..bytes.len() - 1]),
            Err(DecodeError::Truncated)
        );
    }
}
