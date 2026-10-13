//! [`TermEngine`] backed by `alacritty_terminal` (candidate A in spike S1).

use std::sync::{Arc, Mutex};

use alacritty_terminal::event::{Event, EventListener};
use alacritty_terminal::grid::{Dimensions, Scroll};
use alacritty_terminal::index::{Column, Line};
use alacritty_terminal::term::cell::{Cell, Flags};
use alacritty_terminal::term::{Config, Term, TermDamage};
use alacritty_terminal::vte::ansi::{
    Color as AColor, CursorShape as ACursorShape, NamedColor, Processor,
};

use crate::engine::{CursorShape, CursorState, Size, TermEngine};
use crate::frame::{Color, FrameEncoder, FrameStats, Style, attrs};

#[derive(Default)]
struct Pending {
    host_writes: Vec<u8>,
    title: Option<String>,
}

/// Collects what the terminal reports back while parsing.
#[derive(Clone, Default)]
struct Listener(Arc<Mutex<Pending>>);

impl Listener {
    fn with<R>(&self, f: impl FnOnce(&mut Pending) -> R) -> R {
        // A poisoned lock only means a panic elsewhere mid-update; the data
        // (bytes and a title) stays usable.
        let mut pending = self.0.lock().unwrap_or_else(|e| e.into_inner());
        f(&mut pending)
    }
}

impl EventListener for Listener {
    fn send_event(&self, event: Event) {
        match event {
            Event::PtyWrite(text) => {
                self.with(|p| p.host_writes.extend_from_slice(text.as_bytes()))
            }
            Event::Title(title) => self.with(|p| p.title = Some(title)),
            Event::ResetTitle => self.with(|p| p.title = None),
            _ => {}
        }
    }
}

struct Dims(Size);

impl Dimensions for Dims {
    fn total_lines(&self) -> usize {
        usize::from(self.0.rows)
    }

    fn screen_lines(&self) -> usize {
        usize::from(self.0.rows)
    }

    fn columns(&self) -> usize {
        usize::from(self.0.cols)
    }
}

pub struct AlacrittyEngine {
    term: Term<Listener>,
    parser: Processor,
    listener: Listener,
    size: Size,
    force_full: bool,
}

impl AlacrittyEngine {
    pub fn new(size: Size, scrollback_lines: usize) -> Self {
        let listener = Listener::default();
        let config = Config {
            scrolling_history: scrollback_lines,
            ..Config::default()
        };
        Self {
            term: Term::new(config, &Dims(size), listener.clone()),
            parser: Processor::new(),
            listener,
            size,
            force_full: true,
        }
    }

    fn cursor_state(&self) -> CursorState {
        let cursor = self.term.renderable_content().cursor;
        let offset = self.term.grid().display_offset() as i32;
        let row = cursor.point.line.0 + offset;
        let on_screen = (0..i32::from(self.size.rows)).contains(&row);
        CursorState {
            row: row.clamp(0, i32::from(self.size.rows) - 1) as u16,
            col: cursor.point.column.0.min(usize::from(self.size.cols) - 1) as u16,
            shape: match cursor.shape {
                ACursorShape::Underline => CursorShape::Underline,
                ACursorShape::Beam => CursorShape::Beam,
                ACursorShape::HollowBlock => CursorShape::HollowBlock,
                ACursorShape::Block | ACursorShape::Hidden => CursorShape::Block,
            },
            visible: on_screen && cursor.shape != ACursorShape::Hidden,
        }
    }

    /// Grid line shown at viewport row `row`.
    fn viewport_line(&self, row: u16) -> Line {
        Line(i32::from(row) - self.term.grid().display_offset() as i32)
    }
}

impl TermEngine for AlacrittyEngine {
    fn name(&self) -> &'static str {
        "alacritty_terminal"
    }

    fn size(&self) -> Size {
        self.size
    }

    fn resize(&mut self, size: Size) {
        self.term.resize(Dims(size));
        self.size = size;
        self.force_full = true;
    }

    fn feed(&mut self, bytes: &[u8]) {
        self.parser.advance(&mut self.term, bytes);
    }

    fn encode_damage(&mut self, enc: &mut FrameEncoder) -> FrameStats {
        let mut full = self.force_full;
        let mut rows: Vec<u16> = Vec::new();
        match self.term.damage() {
            TermDamage::Full => full = true,
            TermDamage::Partial(damaged) => {
                if !full {
                    rows.extend(damaged.map(|d| d.line as u16));
                }
            }
        }
        self.term.reset_damage();
        self.force_full = false;

        if full {
            rows = (0..self.size.rows).collect();
        } else {
            rows.retain(|&r| r < self.size.rows);
            rows.sort_unstable();
            rows.dedup();
        }

        let display_offset = self.term.grid().display_offset() as u32;
        enc.begin(
            full,
            self.size.cols,
            self.size.rows,
            self.cursor_state(),
            display_offset,
        );
        let mut text = String::new();
        for row in rows {
            enc.begin_row(row);
            let line = &self.term.grid()[self.viewport_line(row)];
            for col in 0..usize::from(self.size.cols) {
                let cell = &line[Column(col)];
                if cell
                    .flags
                    .intersects(Flags::WIDE_CHAR_SPACER | Flags::LEADING_WIDE_CHAR_SPACER)
                {
                    continue;
                }
                let style = style_of(cell);
                let c = visible_char(cell.c);
                if c == ' ' && style == Style::default() && cell.zerowidth().is_none() {
                    continue;
                }
                text.clear();
                text.push(c);
                if let Some(marks) = cell.zerowidth() {
                    text.extend(marks);
                }
                let width = if cell.flags.contains(Flags::WIDE_CHAR) {
                    2
                } else {
                    1
                };
                enc.push_cell(col as u16, &text, width, style);
            }
            enc.end_row();
        }
        enc.finish()
    }

    fn scroll_display(&mut self, delta_lines: i32) {
        self.term.scroll_display(Scroll::Delta(delta_lines));
        self.force_full = true;
    }

    fn take_host_writes(&mut self) -> Vec<u8> {
        self.listener.with(|p| std::mem::take(&mut p.host_writes))
    }

    fn title(&self) -> Option<String> {
        self.listener.with(|p| p.title.clone())
    }

    fn screen_text(&self) -> String {
        let mut out = Vec::with_capacity(usize::from(self.size.rows));
        for row in 0..self.size.rows {
            let line = &self.term.grid()[self.viewport_line(row)];
            let mut text = String::new();
            for col in 0..usize::from(self.size.cols) {
                let cell = &line[Column(col)];
                if cell
                    .flags
                    .intersects(Flags::WIDE_CHAR_SPACER | Flags::LEADING_WIDE_CHAR_SPACER)
                {
                    continue;
                }
                text.push(visible_char(cell.c));
                if let Some(marks) = cell.zerowidth() {
                    text.extend(marks);
                }
            }
            out.push(text.trim_end().to_owned());
        }
        out.join("\n")
    }
}

/// alacritty keeps a `\t` in the cell a tab started from, so copying text
/// gives the tab back. On screen it is a blank.
fn visible_char(c: char) -> char {
    if c == '\t' { ' ' } else { c }
}

fn style_of(cell: &Cell) -> Style {
    const MAP: [(Flags, u16); 11] = [
        (Flags::BOLD, attrs::BOLD),
        (Flags::DIM, attrs::DIM),
        (Flags::ITALIC, attrs::ITALIC),
        (Flags::UNDERLINE, attrs::UNDERLINE),
        (Flags::DOUBLE_UNDERLINE, attrs::DOUBLE_UNDERLINE),
        (Flags::UNDERCURL, attrs::UNDERCURL),
        (Flags::DOTTED_UNDERLINE, attrs::DOTTED_UNDERLINE),
        (Flags::DASHED_UNDERLINE, attrs::DASHED_UNDERLINE),
        (Flags::INVERSE, attrs::INVERSE),
        (Flags::HIDDEN, attrs::HIDDEN),
        (Flags::STRIKEOUT, attrs::STRIKEOUT),
    ];
    let attrs = MAP
        .iter()
        .filter(|(flag, _)| cell.flags.contains(*flag))
        .fold(0, |acc, (_, bit)| acc | bit);
    Style {
        fg: color(cell.fg),
        bg: color(cell.bg),
        attrs,
    }
}

fn color(c: AColor) -> Color {
    match c {
        AColor::Named(named) => named_color(named),
        AColor::Indexed(i) => Color::Indexed(i),
        AColor::Spec(rgb) => Color::Rgb(rgb.r, rgb.g, rgb.b),
    }
}

fn named_color(named: NamedColor) -> Color {
    let i = named as usize;
    let dim_black = NamedColor::DimBlack as usize;
    match i {
        0..=15 => Color::Named(i as u8),
        _ if (dim_black..dim_black + 8).contains(&i) => Color::Named(16 + (i - dim_black) as u8),
        // Foreground, background, cursor and their bright/dim variants follow
        // the theme default for the slot.
        _ => Color::Default,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frame::{DecodedFrame, decode};

    fn engine(cols: u16, rows: u16) -> AlacrittyEngine {
        AlacrittyEngine::new(Size::new(cols, rows), 1_000)
    }

    fn frame(e: &mut AlacrittyEngine) -> DecodedFrame {
        let mut enc = FrameEncoder::new();
        e.encode_damage(&mut enc);
        decode(enc.bytes()).expect("engine output decodes")
    }

    fn spans_of(frame: &DecodedFrame, row: u16) -> Vec<(u16, u16, String, Color)> {
        frame
            .lines
            .iter()
            .find(|l| l.index == row)
            .map(|l| {
                l.spans
                    .iter()
                    .map(|s| (s.col, s.width, s.text.clone(), s.style.fg))
                    .collect()
            })
            .unwrap_or_default()
    }

    #[test]
    fn tabs_are_blanks_on_screen() {
        let mut e = AlacrittyEngine::new(Size::new(20, 2), 100);
        e.feed(b"a\tb");
        assert_eq!(e.screen_text().lines().next(), Some("a       b"));
        let mut enc = FrameEncoder::new();
        e.encode_damage(&mut enc);
        let f = crate::frame::decode(enc.bytes()).unwrap();
        let texts: Vec<_> = f.lines[0].spans.iter().map(|s| s.text.clone()).collect();
        assert_eq!(texts, ["a", "b"]);
    }

    #[test]
    fn first_frame_is_full_and_carries_styles() {
        let mut e = engine(20, 4);
        e.feed(b"hello \x1b[31mred\x1b[0m");
        assert_eq!(e.screen_text().lines().next(), Some("hello red"));

        let f = frame(&mut e);
        assert!(f.full);
        assert_eq!(f.lines.len(), 4);
        assert_eq!(
            spans_of(&f, 0),
            vec![
                (0, 5, "hello".into(), Color::Default),
                (6, 3, "red".into(), Color::Named(1)),
            ]
        );
        assert_eq!((f.cursor.row, f.cursor.col), (0, 9));
    }

    #[test]
    fn later_frames_only_carry_damaged_rows() {
        let mut e = engine(20, 10);
        e.feed(b"one");
        frame(&mut e);
        e.feed(b"\r\ntwo");
        let f = frame(&mut e);
        assert!(!f.full);
        let rows: Vec<u16> = f.lines.iter().map(|l| l.index).collect();
        assert!(rows.contains(&1), "row 1 changed: {rows:?}");
        assert!(rows.len() < 10, "partial frame: {rows:?}");
    }

    #[test]
    fn wide_characters_get_their_own_span() {
        let mut e = engine(20, 2);
        e.feed("漢字a".as_bytes());
        let f = frame(&mut e);
        assert_eq!(
            spans_of(&f, 0),
            vec![
                (0, 2, "漢".into(), Color::Default),
                (2, 2, "字".into(), Color::Default),
                (4, 1, "a".into(), Color::Default),
            ]
        );
    }

    #[test]
    fn answers_cursor_position_reports() {
        let mut e = engine(20, 4);
        e.feed(b"ab\x1b[6n");
        assert_eq!(e.take_host_writes(), b"\x1b[1;3R");
        assert!(e.take_host_writes().is_empty());
    }

    #[test]
    fn tracks_the_window_title() {
        let mut e = engine(20, 4);
        e.feed(b"\x1b]0;hola\x07");
        assert_eq!(e.title().as_deref(), Some("hola"));
    }

    #[test]
    fn scrolling_into_history_sends_a_full_frame() {
        let mut e = engine(10, 5);
        for i in 0..50 {
            e.feed(format!("line{i}\r\n").as_bytes());
        }
        frame(&mut e);
        e.scroll_display(3);
        let f = frame(&mut e);
        assert!(f.full);
        assert_eq!(f.display_offset, 3);
        assert_eq!(spans_of(&f, 0)[0].2, "line43");
    }

    #[test]
    fn resize_sends_a_full_frame_with_the_new_size() {
        let mut e = engine(10, 5);
        frame(&mut e);
        e.resize(Size::new(30, 8));
        let f = frame(&mut e);
        assert!(f.full);
        assert_eq!((f.cols, f.rows), (30, 8));
        assert_eq!(f.lines.len(), 8);
    }
}
