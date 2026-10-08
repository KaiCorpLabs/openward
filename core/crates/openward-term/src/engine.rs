//! The interface every terminal engine implements.

use crate::frame::{FrameEncoder, FrameStats};

/// Visible grid size in cells.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Size {
    pub cols: u16,
    pub rows: u16,
}

impl Size {
    pub fn new(cols: u16, rows: u16) -> Self {
        Self {
            cols: cols.max(1),
            rows: rows.max(1),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CursorShape {
    Block,
    Underline,
    Beam,
    HollowBlock,
}

impl CursorShape {
    pub(crate) fn code(self) -> u8 {
        match self {
            Self::Block => 0,
            Self::Underline => 1,
            Self::Beam => 2,
            Self::HollowBlock => 3,
        }
    }

    pub(crate) fn from_code(code: u8) -> Option<Self> {
        Some(match code {
            0 => Self::Block,
            1 => Self::Underline,
            2 => Self::Beam,
            3 => Self::HollowBlock,
            _ => return None,
        })
    }
}

/// Cursor position in visible-grid coordinates.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CursorState {
    pub row: u16,
    pub col: u16,
    pub shape: CursorShape,
    pub visible: bool,
}

/// A terminal emulator as the rest of OpenWard sees it.
///
/// Bytes from the remote side go in through [`feed`](Self::feed); what the UI
/// needs to repaint comes out of [`encode_damage`](Self::encode_damage).
/// Engines must never block and never perform I/O themselves.
pub trait TermEngine: Send {
    /// Short identifier used in benchmarks and logs.
    fn name(&self) -> &'static str;

    fn size(&self) -> Size;

    fn resize(&mut self, size: Size);

    /// Process output received from the host (SSH channel, PTY, recording).
    fn feed(&mut self, bytes: &[u8]);

    /// Encode every row changed since the previous call into `enc`, then
    /// clear the engine's damage. The first call after creation, a resize or
    /// a scroll of the viewport produces a full frame.
    fn encode_damage(&mut self, enc: &mut FrameEncoder) -> FrameStats;

    /// Move the viewport into (positive) or out of (negative) scrollback.
    fn scroll_display(&mut self, delta_lines: i32);

    /// Bytes the terminal wants to send back to the host, such as replies to
    /// device status or attribute queries. Draining clears them.
    fn take_host_writes(&mut self) -> Vec<u8>;

    /// Window title set by the host, if any.
    fn title(&self) -> Option<String>;

    /// Visible screen as plain text, one line per row with trailing spaces
    /// trimmed. Meant for tests and golden comparisons, not for rendering.
    fn screen_text(&self) -> String;
}
