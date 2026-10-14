//! Text selection. Ghostty's gesture state machine turns presses and drags
//! into a selection (a word on double click, a line on triple click), which
//! is installed as the terminal's own so it follows the content as it
//! scrolls. The UI only paints the selected range of each visible row and
//! asks for the text to copy.

use std::ffi::c_void;
use std::ptr;
use std::time::Instant;

use super::{GhosttyEngine, ok, sized};
use crate::sys;

/// Surface units per logical pixel: the gesture API takes whole-pixel
/// geometry, and cells are fractional.
const SCALE: f32 = 4.0;

/// Clicks closer together than this make a double or triple click.
const REPEAT_INTERVAL_NS: u64 = 500_000_000;

/// One visible row's selected columns, both inclusive.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SelectedRow {
    pub row: u16,
    pub start: u16,
    pub end: u16,
}

/// The gesture state and its reusable events.
pub(super) struct Gesture {
    handle: sys::GhosttySelectionGesture,
    press: sys::GhosttySelectionGestureEvent,
    drag: sys::GhosttySelectionGestureEvent,
    release: sys::GhosttySelectionGestureEvent,
    epoch: Instant,
}

impl Gesture {
    pub(super) fn new() -> Self {
        let event = |kind| {
            let mut e: sys::GhosttySelectionGestureEvent = ptr::null_mut();
            // SAFETY: valid out-pointer; default allocator.
            ok(
                unsafe { sys::ghostty_selection_gesture_event_new(ptr::null(), &mut e, kind) },
                "selection event",
            );
            e
        };
        let mut handle: sys::GhosttySelectionGesture = ptr::null_mut();
        // SAFETY: valid out-pointer; default allocator.
        ok(
            unsafe { sys::ghostty_selection_gesture_new(ptr::null(), &mut handle) },
            "selection gesture",
        );
        Self {
            handle,
            press: event(sys::GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_PRESS),
            drag: event(sys::GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DRAG),
            release: event(sys::GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_RELEASE),
            epoch: Instant::now(),
        }
    }

    /// # Safety
    /// `term` is the live terminal the gesture was used with.
    pub(super) unsafe fn free(&mut self, term: sys::GhosttyTerminal) {
        // SAFETY: handles created in `new`, freed once.
        unsafe {
            sys::ghostty_selection_gesture_event_free(self.press);
            sys::ghostty_selection_gesture_event_free(self.drag);
            sys::ghostty_selection_gesture_event_free(self.release);
            sys::ghostty_selection_gesture_free(self.handle, term);
        }
    }
}

/// Sets an event option from a value of its documented type.
///
/// # Safety
/// `T` is the type `option` documents.
unsafe fn set<T>(event: sys::GhosttySelectionGestureEvent, option: i32, value: &T) {
    // SAFETY: as the caller promises; the event copies what it keeps.
    ok(
        unsafe {
            sys::ghostty_selection_gesture_event_set(
                event,
                option,
                (value as *const T).cast::<c_void>(),
            )
        },
        "selection event option",
    );
}

impl GhosttyEngine {
    /// The cell under a position in logical pixels, clamped to the screen.
    fn cell_at(&self, x: f32, y: f32) -> (u16, u16) {
        let col = (x / self.input.cell_w).floor().max(0.0) as u32;
        let row = (y / self.input.cell_h).floor().max(0.0) as u32;
        (
            col.min(u32::from(self.size.cols.saturating_sub(1))) as u16,
            row.min(u32::from(self.size.rows.saturating_sub(1))) as u16,
        )
    }

    fn grid_ref(&self, col: u16, row: u16) -> Option<sys::GhosttyGridRef> {
        let mut point = sys::GhosttyPoint {
            tag: sys::GHOSTTY_POINT_TAG_VIEWPORT,
            ..Default::default()
        };
        point.value.coordinate = sys::GhosttyPointCoordinate {
            x: col,
            y: u32::from(row),
        };
        let mut r: sys::GhosttyGridRef = sized(|r: &mut sys::GhosttyGridRef, s| r.size = s);
        // SAFETY: valid terminal; out-pointer to a sized local.
        let found = unsafe { sys::ghostty_terminal_grid_ref(self.term, point, &mut r) };
        (found == sys::GHOSTTY_SUCCESS).then_some(r)
    }

    fn position(x: f32, y: f32) -> sys::GhosttySurfacePosition {
        sys::GhosttySurfacePosition {
            x: f64::from(x * SCALE),
            y: f64::from(y * SCALE),
        }
    }

    /// Makes `selection` the terminal's (or clears it with `None`).
    fn install(&mut self, selection: Option<&sys::GhosttySelection>) {
        let value = selection.map_or(ptr::null(), |s| (s as *const sys::GhosttySelection).cast());
        // SAFETY: valid terminal; the value is a GhosttySelection* or NULL,
        // copied by the terminal.
        ok(
            unsafe {
                sys::ghostty_terminal_set(self.term, sys::GHOSTTY_TERMINAL_OPT_SELECTION, value)
            },
            "set selection",
        );
    }

    /// Runs a gesture event and installs what it selects. Returns whether
    /// there is a selection now.
    fn apply(&mut self, event: sys::GhosttySelectionGestureEvent) -> bool {
        let mut selection: sys::GhosttySelection =
            sized(|s: &mut sys::GhosttySelection, n| s.size = n);
        // SAFETY: valid handles; out-pointer to a sized local.
        let result = unsafe {
            sys::ghostty_selection_gesture_event(
                self.select.handle,
                self.term,
                event,
                &mut selection,
            )
        };
        match result {
            sys::GHOSTTY_SUCCESS => {
                self.install(Some(&selection));
                true
            }
            _ => false,
        }
    }

    /// Mouse button down at a position in logical pixels. A double click
    /// selects a word and a triple click a line; a single click clears the
    /// selection until it drags.
    pub fn select_press(&mut self, x: f32, y: f32) {
        let (col, row) = self.cell_at(x, y);
        let Some(r) = self.grid_ref(col, row) else {
            return;
        };
        let event = self.select.press;
        let time = self.select.epoch.elapsed().as_nanos() as u64;
        let distance = f64::from(self.input.cell_w * SCALE);
        // SAFETY: each value has the type its option documents.
        unsafe {
            set(event, sys::GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &r);
            set(
                event,
                sys::GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION,
                &Self::position(x, y),
            );
            set(
                event,
                sys::GHOSTTY_SELECTION_GESTURE_EVENT_OPT_TIME_NS,
                &time,
            );
            set(
                event,
                sys::GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_INTERVAL_NS,
                &REPEAT_INTERVAL_NS,
            );
            set(
                event,
                sys::GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_DISTANCE,
                &distance,
            );
        }
        if !self.apply(event) {
            self.install(None);
        }
    }

    /// The pointer moved with the button down. `rectangle` selects a block
    /// (Option/Alt held).
    pub fn select_drag(&mut self, x: f32, y: f32, rectangle: bool) {
        let (col, row) = self.cell_at(x, y);
        let Some(r) = self.grid_ref(col, row) else {
            return;
        };
        let geometry = sys::GhosttySelectionGestureGeometry {
            columns: u32::from(self.size.cols.max(1)),
            cell_width: ((self.input.cell_w * SCALE).round() as u32).max(1),
            padding_left: 0,
            screen_height: ((f32::from(self.size.rows) * self.input.cell_h * SCALE).round() as u32)
                .max(1),
        };
        let event = self.select.drag;
        // SAFETY: each value has the type its option documents.
        unsafe {
            set(event, sys::GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &r);
            set(
                event,
                sys::GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION,
                &Self::position(x, y),
            );
            set(
                event,
                sys::GHOSTTY_SELECTION_GESTURE_EVENT_OPT_GEOMETRY,
                &geometry,
            );
            set(
                event,
                sys::GHOSTTY_SELECTION_GESTURE_EVENT_OPT_RECTANGLE,
                &rectangle,
            );
        }
        self.apply(event);
    }

    /// The button went up.
    pub fn select_release(&mut self, x: f32, y: f32) {
        let (col, row) = self.cell_at(x, y);
        let event = self.select.release;
        match self.grid_ref(col, row) {
            // SAFETY: the value has the type the option documents.
            Some(r) => unsafe { set(event, sys::GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &r) },
            // SAFETY: NULL clears the option.
            None => unsafe {
                sys::ghostty_selection_gesture_event_set(
                    event,
                    sys::GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF,
                    ptr::null(),
                );
            },
        }
        // Release updates the gesture without selecting anything new.
        self.apply(event);
    }

    /// Everything: screen and scrollback.
    pub fn select_all(&mut self) {
        let mut selection: sys::GhosttySelection =
            sized(|s: &mut sys::GhosttySelection, n| s.size = n);
        // SAFETY: valid terminal; out-pointer to a sized local.
        let found = unsafe { sys::ghostty_terminal_select_all(self.term, &mut selection) };
        if found == sys::GHOSTTY_SUCCESS {
            self.install(Some(&selection));
        }
    }

    pub fn clear_selection(&mut self) {
        if self.has_selection() {
            self.install(None);
        }
    }

    pub fn has_selection(&self) -> bool {
        let mut selection: sys::GhosttySelection =
            sized(|s: &mut sys::GhosttySelection, n| s.size = n);
        // SAFETY: valid terminal; the output type is GhosttySelection.
        let found = unsafe { self.get_raw(sys::GHOSTTY_TERMINAL_DATA_SELECTION, &mut selection) };
        found == sys::GHOSTTY_SUCCESS
    }

    /// The selected text as a clipboard wants it: soft-wrapped lines joined
    /// and trailing blanks trimmed. `None` without a selection.
    pub fn selection_text(&self) -> Option<String> {
        if !self.has_selection() {
            return None;
        }
        let options = sys::GhosttyTerminalSelectionFormatOptions {
            size: size_of::<sys::GhosttyTerminalSelectionFormatOptions>(),
            emit: sys::GHOSTTY_FORMATTER_FORMAT_PLAIN,
            unwrap: true,
            trim: true,
            // The active selection.
            selection: ptr::null(),
        };
        let mut len = 0usize;
        // SAFETY: valid terminal; a NULL buffer asks for the length.
        let first = unsafe {
            sys::ghostty_terminal_selection_format_buf(
                self.term,
                options,
                ptr::null_mut(),
                0,
                &mut len,
            )
        };
        if first != sys::GHOSTTY_OUT_OF_SPACE && first != sys::GHOSTTY_SUCCESS {
            return None;
        }
        let mut buf = vec![0u8; len];
        let mut written = 0usize;
        // SAFETY: the buffer holds `len` bytes.
        let second = unsafe {
            sys::ghostty_terminal_selection_format_buf(
                self.term,
                options,
                buf.as_mut_ptr(),
                buf.len(),
                &mut written,
            )
        };
        if second != sys::GHOSTTY_SUCCESS {
            return None;
        }
        buf.truncate(written);
        Some(String::from_utf8_lossy(&buf).into_owned())
    }

    /// The selected range of each visible row that has one.
    pub fn selected_rows(&mut self) -> Vec<SelectedRow> {
        if !self.has_selection() {
            return Vec::new();
        }
        self.update_render_state();
        let mut out = Vec::new();
        self.for_each_row(true, |this, row| {
            let mut range: sys::GhosttyRenderStateRowSelection =
                sized(|r: &mut sys::GhosttyRenderStateRowSelection, s| r.size = s);
            // SAFETY: the iterator is on this row; the output type is
            // GhosttyRenderStateRowSelection.
            let found = unsafe {
                sys::ghostty_render_state_row_get(
                    this.rows,
                    sys::GHOSTTY_RENDER_STATE_ROW_DATA_SELECTION,
                    (&mut range as *mut sys::GhosttyRenderStateRowSelection).cast::<c_void>(),
                )
            };
            if found == sys::GHOSTTY_SUCCESS {
                out.push(SelectedRow {
                    row,
                    start: range.start_x,
                    end: range.end_x,
                });
            }
        });
        out
    }
}

#[cfg(test)]
mod tests {
    use super::SelectedRow;
    use crate::GhosttyEngine;
    use openward_term::{Size, TermEngine};

    /// 20×5 cells of 10×20 logical pixels.
    fn engine(text: &[u8]) -> GhosttyEngine {
        let mut e = GhosttyEngine::new(Size::new(20, 5), 100);
        e.set_cell_pixels(10.0, 20.0);
        e.feed(text);
        e
    }

    /// The middle of a cell, in pixels.
    fn at(col: u16, row: u16) -> (f32, f32) {
        (f32::from(col) * 10.0 + 5.0, f32::from(row) * 20.0 + 10.0)
    }

    /// Drags forward to `to`'s right edge: as in other text views, a cell
    /// is taken once the pointer passes its middle.
    fn drag(e: &mut GhosttyEngine, from: (u16, u16), to: (u16, u16)) {
        let (x, y) = at(from.0, from.1);
        e.select_press(x - 4.0, y);
        let (x, y) = at(to.0, to.1);
        e.select_drag(x + 4.0, y, false);
        e.select_release(x + 4.0, y);
    }

    #[test]
    fn a_drag_selects_and_copies() {
        let mut e = engine(b"hello world\r\nsecond line");
        assert!(!e.has_selection());
        drag(&mut e, (0, 0), (4, 0));
        assert_eq!(e.selection_text().as_deref(), Some("hello"));
        assert_eq!(
            e.selected_rows(),
            [SelectedRow {
                row: 0,
                start: 0,
                end: 4
            }]
        );

        drag(&mut e, (6, 0), (5, 1));
        assert_eq!(e.selection_text().as_deref(), Some("world\nsecond"));
        assert_eq!(e.selected_rows().len(), 2);
    }

    #[test]
    fn double_click_a_word_triple_click_a_line() {
        let mut e = engine(b"hello world\r\nsecond line");
        let (x, y) = at(8, 0);
        e.select_press(x, y);
        e.select_release(x, y);
        e.select_press(x, y);
        e.select_release(x, y);
        assert_eq!(e.selection_text().as_deref(), Some("world"));
        e.select_press(x, y);
        e.select_release(x, y);
        assert_eq!(e.selection_text().as_deref(), Some("hello world"));
    }

    #[test]
    fn a_click_clears_and_select_all_takes_everything() {
        let mut e = engine(b"hello world\r\nsecond line");
        drag(&mut e, (0, 0), (4, 0));
        let (x, y) = at(2, 1);
        // Later than a double click.
        std::thread::sleep(std::time::Duration::from_millis(600));
        e.select_press(x, y);
        e.select_release(x, y);
        assert!(!e.has_selection());
        assert_eq!(e.selection_text(), None);
        assert!(e.selected_rows().is_empty());

        e.select_all();
        assert_eq!(
            e.selection_text().as_deref(),
            Some("hello world\nsecond line")
        );
        e.clear_selection();
        assert!(!e.has_selection());
    }

    /// The selection stays on its text when output scrolls the screen.
    #[test]
    fn the_selection_follows_the_text() {
        let mut e = engine(b"keep me\r\n");
        drag(&mut e, (0, 0), (3, 0));
        assert_eq!(e.selected_rows()[0].row, 0);
        e.feed(b"one\r\ntwo\r\n");
        assert_eq!(e.selection_text().as_deref(), Some("keep"));
        assert_eq!(e.selected_rows().len(), 1);
        // Scrolled off the top: still selected, no longer visible.
        e.feed(b"3\r\n4\r\n5\r\n6\r\n");
        assert_eq!(e.selection_text().as_deref(), Some("keep"));
        assert!(e.selected_rows().is_empty());
    }
}
