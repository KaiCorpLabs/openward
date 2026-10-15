//! Finding things on the screen: text through the history with Ghostty's
//! search, and the link under the pointer (an OSC 8 hyperlink, or a URL
//! written in the text).
//!
//! The search lives with the engine while a find bar is open. Matches are
//! read back for the visible rows only, already split into one range per
//! row, the way the UI paints the selection.

use std::ffi::c_void;
use std::ptr;

use super::{GhosttyEngine, ok, sized};
use crate::sys;

/// A match's part on one visible row; columns inclusive.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchHit {
    pub row: u16,
    pub start: u16,
    pub end: u16,
    /// The match the find bar points at.
    pub selected: bool,
}

/// Where a search stands: for the find bar's "3 of 12" and the highlights.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SearchState {
    pub total: usize,
    /// 1-based, counting from the newest match; `None` before the first step.
    pub selected: Option<usize>,
    pub hits: Vec<SearchHit>,
}

/// A link on the screen; columns inclusive, on one row.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Link {
    pub url: String,
    pub row: u16,
    pub start: u16,
    pub end: u16,
}

/// Reads a search field of its documented type.
///
/// # Safety
/// `T` is the type `data` documents.
unsafe fn get<T>(search: sys::GhosttySearch, data: i32, out: &mut T) -> sys::GhosttyResult {
    // SAFETY: as the caller promises; `out` is valid for the call.
    unsafe { sys::ghostty_search_get(search, data, (out as *mut T).cast::<c_void>()) }
}

fn empty_selection() -> sys::GhosttySelection {
    let mut s: sys::GhosttySelection = sized(|s: &mut sys::GhosttySelection, n| s.size = n);
    s.start = sized(|r: &mut sys::GhosttyGridRef, n| r.size = n);
    s.end = sized(|r: &mut sys::GhosttyGridRef, n| r.size = n);
    s
}

impl GhosttyEngine {
    /// Looks for `needle` on the screen and through the history (ASCII
    /// letters in any case). An empty needle ends the search.
    pub fn search(&mut self, needle: &str) {
        if needle.is_empty() {
            return self.end_search();
        }
        if self.search.is_null() {
            // SAFETY: valid out-pointer and terminal; default allocator.
            ok(
                unsafe { sys::ghostty_search_new(ptr::null(), &mut self.search, self.term) },
                "search_new",
            );
        }
        let s = sys::GhosttyString {
            ptr: needle.as_ptr(),
            len: needle.len(),
        };
        // SAFETY: valid search; the needle is a GhosttyString*, copied.
        ok(
            unsafe {
                sys::ghostty_search_set(
                    self.search,
                    sys::GHOSTTY_SEARCH_OPT_NEEDLE,
                    (&s as *const sys::GhosttyString).cast::<c_void>(),
                )
            },
            "search needle",
        );
        self.catch_up();
        self.force_full = true;
    }

    /// Closes the find bar's search.
    pub fn end_search(&mut self) {
        if self.search.is_null() {
            return;
        }
        // SAFETY: created by ghostty_search_new and freed once; the terminal
        // is alive (and freed after it in Drop).
        unsafe { sys::ghostty_search_free(self.search) };
        self.search = ptr::null_mut();
        self.force_full = true;
    }

    /// Selects the next match towards older output (or towards newer),
    /// scrolling the history to it when it is out of view. Wraps around.
    pub fn search_step(&mut self, older: bool) {
        if self.search.is_null() {
            return;
        }
        self.catch_up();
        let option = if older {
            sys::GHOSTTY_SEARCH_OPT_SELECT_NEXT
        } else {
            sys::GHOSTTY_SEARCH_OPT_SELECT_PREV
        };
        // SAFETY: valid search; the select options take NULL. No matches
        // is not an error worth reporting.
        unsafe { sys::ghostty_search_set(self.search, option, ptr::null()) };
        self.force_full = true;
    }

    /// Feeds the terminal's changes to the search until it is caught up.
    fn catch_up(&mut self) {
        // SAFETY: valid search; `&mut self` serializes it with the terminal.
        ok(
            unsafe { sys::ghostty_search_run(self.search) },
            "search_run",
        );
    }

    /// The search's counts and its matches on the visible rows; `None`
    /// without a search.
    pub fn search_state(&mut self) -> Option<SearchState> {
        if self.search.is_null() {
            return None;
        }
        self.catch_up();
        let search = self.search;
        let mut total = 0usize;
        let mut index = 0usize;
        let mut chosen = empty_selection();
        // SAFETY: each field is read with its documented type.
        let (selected, has_chosen) = unsafe {
            get(search, sys::GHOSTTY_SEARCH_DATA_TOTAL_MATCHES, &mut total);
            let selected = (get(search, sys::GHOSTTY_SEARCH_DATA_SELECTED_INDEX, &mut index)
                == sys::GHOSTTY_SUCCESS)
                .then_some(index + 1);
            let has_chosen = get(search, sys::GHOSTTY_SEARCH_DATA_SELECTED_MATCH, &mut chosen)
                == sys::GHOSTTY_SUCCESS;
            (selected, has_chosen)
        };
        let chosen_at = if has_chosen {
            self.viewport_point(&chosen.start)
                .zip(self.viewport_point(&chosen.end))
        } else {
            None
        };

        let mut storage = vec![empty_selection(); 64];
        let count = loop {
            let mut buf = sys::GhosttySelectionBuffer {
                ptr: storage.as_mut_ptr(),
                cap: storage.len(),
                len: 0,
            };
            // SAFETY: the buffer points at `cap` sized selections.
            let r = unsafe { get(search, sys::GHOSTTY_SEARCH_DATA_VIEWPORT_MATCHES, &mut buf) };
            if r == sys::GHOSTTY_OUT_OF_SPACE && buf.len > storage.len() {
                storage.resize(buf.len, empty_selection());
                continue;
            }
            break if r == sys::GHOSTTY_SUCCESS {
                buf.len
            } else {
                0
            };
        };

        let rows = u32::from(self.size.rows);
        let last_col = self.size.cols.saturating_sub(1);
        let mut hits = Vec::new();
        for m in &storage[..count] {
            // Matches that start above the view, or below it, are skipped:
            // the list covers whole pages around the viewport.
            let (Some(a), Some(b)) = (self.viewport_point(&m.start), self.viewport_point(&m.end))
            else {
                continue;
            };
            if a.y >= rows {
                continue;
            }
            let selected =
                chosen_at.is_some_and(|(ca, cb)| (ca.x, ca.y, cb.x, cb.y) == (a.x, a.y, b.x, b.y));
            for y in a.y..=b.y.min(rows - 1) {
                hits.push(SearchHit {
                    row: y as u16,
                    start: if y == a.y { a.x } else { 0 },
                    end: if y == b.y { b.x } else { last_col },
                    selected,
                });
            }
        }
        Some(SearchState {
            total,
            selected,
            hits,
        })
    }

    fn viewport_point(&self, r: &sys::GhosttyGridRef) -> Option<sys::GhosttyPointCoordinate> {
        let mut out = sys::GhosttyPointCoordinate::default();
        // SAFETY: valid terminal; `r` comes from a read made after the last
        // change to the terminal.
        let found = unsafe {
            sys::ghostty_terminal_point_from_grid_ref(
                self.term,
                r,
                sys::GHOSTTY_POINT_TAG_VIEWPORT,
                &mut out,
            )
        };
        (found == sys::GHOSTTY_SUCCESS).then_some(out)
    }

    /// The link under a point in logical pixels: an OSC 8 hyperlink, or else
    /// a URL written in the text of that row.
    pub fn link_at(&self, x: f32, y: f32) -> Option<Link> {
        let (col, row) = self.cell_at(x, y);
        if let Some(url) = self.hyperlink(col, row) {
            // The run of neighbouring cells with the same link.
            let same = |c: u16| self.hyperlink(c, row).as_deref() == Some(url.as_str());
            let mut start = col;
            while start > 0 && same(start - 1) {
                start -= 1;
            }
            let mut end = col;
            while end + 1 < self.size.cols && same(end + 1) {
                end += 1;
            }
            return Some(Link {
                url,
                row,
                start,
                end,
            });
        }
        let cells: Vec<String> = (0..self.size.cols)
            .map(|c| self.cell_text(c, row))
            .collect();
        url_in_row(&cells, col).map(|(start, end, url)| Link {
            url,
            row,
            start,
            end,
        })
    }

    fn hyperlink(&self, col: u16, row: u16) -> Option<String> {
        let r = self.grid_ref(col, row)?;
        let mut len = 0usize;
        // SAFETY: a NULL buffer asks for the length.
        let first =
            unsafe { sys::ghostty_grid_ref_hyperlink_uri(&r, ptr::null_mut(), 0, &mut len) };
        if (first != sys::GHOSTTY_OUT_OF_SPACE && first != sys::GHOSTTY_SUCCESS) || len == 0 {
            return None;
        }
        let mut buf = vec![0u8; len];
        let mut written = 0usize;
        // SAFETY: the buffer holds `len` bytes.
        let second = unsafe {
            sys::ghostty_grid_ref_hyperlink_uri(&r, buf.as_mut_ptr(), buf.len(), &mut written)
        };
        if second != sys::GHOSTTY_SUCCESS {
            return None;
        }
        buf.truncate(written);
        String::from_utf8(buf).ok()
    }

    /// The text of one visible cell; empty for a blank cell or the tail of
    /// a wide character.
    fn cell_text(&self, col: u16, row: u16) -> String {
        let Some(r) = self.grid_ref(col, row) else {
            return String::new();
        };
        let mut cps = [0u32; 16];
        let mut len = 0usize;
        // SAFETY: the buffer holds 16 code points; longer clusters are not
        // part of a URL anyway.
        let found =
            unsafe { sys::ghostty_grid_ref_graphemes(&r, cps.as_mut_ptr(), cps.len(), &mut len) };
        if found != sys::GHOSTTY_SUCCESS {
            return String::new();
        }
        cps[..len.min(cps.len())]
            .iter()
            .filter_map(|&c| char::from_u32(c))
            .collect()
    }
}

/// Schemes a written URL may start with.
const SCHEMES: &[&str] = &["https://", "http://", "ftp://", "file://", "mailto:"];

/// The URL written across a row's cells that covers column `col`, as
/// (first column, last column, URL). Trailing punctuation and closing
/// brackets without their opening one are left out, as people write URLs in
/// sentences.
pub fn url_in_row(cells: &[String], col: u16) -> Option<(u16, u16, String)> {
    // The row's text, and the column each character came from.
    let mut chars: Vec<(char, u16)> = Vec::new();
    for (c, text) in cells.iter().enumerate() {
        if text.is_empty() {
            // A blank cell ends a URL; a wide character's tail adds nothing.
            let tail = c > 0 && cells[c - 1].chars().any(is_wide);
            if !tail {
                chars.push((' ', c as u16));
            }
            continue;
        }
        for ch in text.chars() {
            chars.push((ch, c as u16));
        }
    }
    let text: String = chars.iter().map(|&(ch, _)| ch).collect();
    let lower = text.to_ascii_lowercase();
    let at: Vec<usize> = text.char_indices().map(|(i, _)| i).collect();
    for scheme in SCHEMES {
        let mut from = 0;
        while let Some(found) = lower[from..].find(scheme) {
            let begin = from + found;
            from = begin + scheme.len();
            let first = at.partition_point(|&i| i < begin);
            if first > 0 && chars[first - 1].0.is_alphanumeric() {
                continue;
            }
            let mut last = first + scheme.chars().count();
            while last < chars.len() && is_url_char(chars[last].0) {
                last += 1;
            }
            // Nothing after the scheme is not a link.
            if last == first + scheme.chars().count() {
                continue;
            }
            let mut end = last;
            let body = first + scheme.chars().count();
            while end > body {
                let ch = chars[end - 1].0;
                let open = match ch {
                    ')' => Some('('),
                    ']' => Some('['),
                    _ => None,
                };
                let unbalanced = open.is_some_and(|o| {
                    let span = &chars[first..end];
                    span.iter().filter(|c| c.0 == o).count()
                        < span.iter().filter(|c| c.0 == ch).count()
                });
                if ".,;:!?'\"".contains(ch) || unbalanced {
                    end -= 1;
                } else {
                    break;
                }
            }
            if end == body {
                continue;
            }
            let (start_col, end_col) = (chars[first].1, chars[end - 1].1);
            if (start_col..=end_col).contains(&col) {
                let url: String = chars[first..end].iter().map(|c| c.0).collect();
                return Some((start_col, end_col, url));
            }
        }
    }
    None
}

fn is_url_char(c: char) -> bool {
    !c.is_whitespace() && !c.is_control() && !"<>\"`{}|\\^".contains(c)
}

/// East Asian wide characters take two cells; the second comes back empty.
fn is_wide(c: char) -> bool {
    matches!(c as u32,
        0x1100..=0x115F | 0x2E80..=0xA4CF | 0xAC00..=0xD7A3 | 0xF900..=0xFAFF
        | 0xFE30..=0xFE4F | 0xFF00..=0xFF60 | 0xFFE0..=0xFFE6 | 0x1F300..=0x1FAFF
        | 0x20000..=0x3FFFD)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::GhosttyEngine;
    use openward_term::{Size, TermEngine};

    fn cells(text: &str) -> Vec<String> {
        text.chars()
            .map(|c| {
                if c == ' ' {
                    String::new()
                } else {
                    c.to_string()
                }
            })
            .collect()
    }

    #[test]
    fn urls_in_text() {
        let row = cells("see https://openward.dev/docs. then (https://a.example/x_(y)) ok");
        assert_eq!(
            url_in_row(&row, 6),
            Some((4, 28, "https://openward.dev/docs".into()))
        );
        // The full stop after the link is not part of it.
        assert_eq!(url_in_row(&row, 29), None);
        let (start, end, url) = url_in_row(&row, 40).unwrap();
        assert_eq!(url, "https://a.example/x_(y)");
        assert_eq!((start, end), (37, 59));
        assert_eq!(url_in_row(&cells("nohttps://x"), 4), None);
        assert_eq!(url_in_row(&cells("https:// nothing"), 2), None);
        assert_eq!(url_in_row(&cells("(https://.)"), 3), None);
        assert_eq!(
            url_in_row(&cells("mailto:ana@example.com"), 0).map(|u| u.2),
            Some("mailto:ana@example.com".into())
        );
    }

    /// 40×4 cells of 10×20 logical pixels, the size the input module uses
    /// when nothing else was set.
    fn engine(text: &[u8]) -> GhosttyEngine {
        let mut e = GhosttyEngine::new(Size::new(40, 4), 100);
        e.set_cell_pixels(10.0, 20.0);
        e.feed(text);
        e
    }

    #[test]
    fn osc8_hyperlinks_and_written_urls() {
        let e =
            engine(b"\x1b]8;;https://openward.dev\x1b\\docs\x1b]8;;\x1b\\ and http://x.test/a\r\n");
        let link = e.link_at(15.0, 5.0).unwrap();
        assert_eq!(
            link,
            Link {
                url: "https://openward.dev".into(),
                row: 0,
                start: 0,
                end: 3
            }
        );
        let written = e.link_at(120.0, 5.0).unwrap();
        assert_eq!(written.url, "http://x.test/a");
        assert_eq!((written.start, written.end), (9, 23));
        assert_eq!(e.link_at(65.0, 5.0), None);
    }

    #[test]
    fn search_through_the_history() {
        let mut e = engine(b"");
        for i in 0..30 {
            e.feed(format!("line {i} {}\r\n", if i % 10 == 3 { "ERROR" } else { "ok" }).as_bytes());
        }
        assert_eq!(e.search_state(), None);
        e.search("error");
        let s = e.search_state().unwrap();
        assert_eq!((s.total, s.selected), (3, None));
        // The newest match first, scrolled into view if it is not.
        e.search_step(true);
        let s = e.search_state().unwrap();
        assert_eq!(s.selected, Some(1));
        let chosen: Vec<_> = s.hits.iter().filter(|h| h.selected).collect();
        assert_eq!(chosen.len(), 1);
        assert_eq!(chosen[0].end - chosen[0].start, 4);
        e.search_step(true);
        e.search_step(true);
        assert_eq!(e.search_state().unwrap().selected, Some(3));
        // Wraps around.
        e.search_step(true);
        assert_eq!(e.search_state().unwrap().selected, Some(1));
        e.end_search();
        assert_eq!(e.search_state(), None);
    }
}
