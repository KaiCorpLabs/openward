//! [`TermEngine`] backed by libghostty-vt.

use std::ffi::c_void;
use std::mem::{MaybeUninit, size_of};
use std::ptr;

use openward_term::frame::attrs;
use openward_term::{
    Color, CursorShape, CursorState, FrameEncoder, FrameStats, Size, Style, TermEngine,
};

use crate::sys;

pub mod find;
pub mod input;
pub mod select;

/// Nominal cell size passed to libghostty-vt. Only pixel-based reports
/// (XTWINOPS) use it; the UI measures its own font.
const CELL_W_PX: u32 = 8;
const CELL_H_PX: u32 = 16;

/// `ghostty_mode_new(2027, false)`: DEC private mode 2027 (a static inline
/// in modes.h, so bindgen does not generate it).
const GRAPHEME_CLUSTER_MODE: sys::GhosttyMode = 2027 & 0x7FFF;

/// What the terminal reports back while parsing, and what it needs to know
/// to answer the program's queries.
struct Effects {
    host_writes: Vec<u8>,
    size: Size,
    /// Cell size in pixels for XTWINOPS size reports.
    cell_px: (u32, u32),
    /// The UI's theme, for color scheme queries (DSR 996).
    dark: bool,
    /// A BEL arrived since the UI last asked.
    bell: bool,
}

/// Theme defaults reported to OSC 10/11 queries (programs use them to pick
/// a dark or light scheme). The UI resolves `Color::Default` itself.
const DEFAULT_FG: sys::GhosttyColorRgb = sys::GhosttyColorRgb {
    r: 0xD4,
    g: 0xD4,
    b: 0xD4,
};
const DEFAULT_BG: sys::GhosttyColorRgb = sys::GhosttyColorRgb {
    r: 0x16,
    g: 0x18,
    b: 0x1D,
};
const XTVERSION: &[u8] = concat!("OpenWard ", env!("CARGO_PKG_VERSION")).as_bytes();
const TERMINFO_NAME: &[u8] = b"xterm-256color";

unsafe extern "C" fn on_xtversion(
    _terminal: sys::GhosttyTerminal,
    _userdata: *mut c_void,
) -> sys::GhosttyString {
    sys::GhosttyString {
        ptr: XTVERSION.as_ptr(),
        len: XTVERSION.len(),
    }
}

unsafe extern "C" fn on_size(
    _terminal: sys::GhosttyTerminal,
    userdata: *mut c_void,
    out: *mut sys::GhosttySizeReportSize,
) -> bool {
    if userdata.is_null() || out.is_null() {
        return false;
    }
    // SAFETY: userdata is the engine's boxed Effects; out is valid for the call.
    unsafe {
        let effects = &*userdata.cast::<Effects>();
        *out = sys::GhosttySizeReportSize {
            rows: effects.size.rows,
            columns: effects.size.cols,
            cell_width: effects.cell_px.0,
            cell_height: effects.cell_px.1,
        };
    }
    true
}

unsafe extern "C" fn on_color_scheme(
    _terminal: sys::GhosttyTerminal,
    userdata: *mut c_void,
    out: *mut sys::GhosttyColorScheme,
) -> bool {
    if userdata.is_null() || out.is_null() {
        return false;
    }
    // SAFETY: userdata is the engine's boxed Effects; out is valid for the call.
    unsafe {
        let effects = &*userdata.cast::<Effects>();
        *out = if effects.dark {
            sys::GHOSTTY_COLOR_SCHEME_DARK
        } else {
            sys::GHOSTTY_COLOR_SCHEME_LIGHT
        };
    }
    true
}

unsafe extern "C" fn on_bell(_terminal: sys::GhosttyTerminal, userdata: *mut c_void) {
    if userdata.is_null() {
        return;
    }
    // SAFETY: userdata is the engine's boxed Effects, alive for as long as
    // the terminal that calls back.
    unsafe { (*userdata.cast::<Effects>()).bell = true };
}

unsafe extern "C" fn on_write_pty(
    _terminal: sys::GhosttyTerminal,
    userdata: *mut c_void,
    data: *const u8,
    len: usize,
) {
    if userdata.is_null() || data.is_null() || len == 0 {
        return;
    }
    // SAFETY: userdata is the engine's boxed Effects, alive for as long as
    // the terminal that calls back; data/len are valid for this call.
    let effects = unsafe { &mut *userdata.cast::<Effects>() };
    effects
        .host_writes
        .extend_from_slice(unsafe { std::slice::from_raw_parts(data, len) });
}

fn ok(result: sys::GhosttyResult, what: &str) {
    assert_eq!(result, sys::GHOSTTY_SUCCESS, "libghostty-vt: {what} failed");
}

/// A `#[repr(C)]` struct whose first field is its own size, as libghostty-vt
/// expects for versioned out-parameters (GHOSTTY_INIT_SIZED).
fn sized<T: Default>(set_size: impl FnOnce(&mut T, usize)) -> T {
    let mut value = T::default();
    set_size(&mut value, size_of::<T>());
    value
}

/// Memory before and after compressing scrollback.
#[derive(Clone, Copy, Debug, Default)]
pub struct CompressionReport {
    pub supported: bool,
    pub resident_before: u64,
    pub resident_after: u64,
}

pub struct GhosttyEngine {
    term: sys::GhosttyTerminal,
    render: sys::GhosttyRenderState,
    rows: sys::GhosttyRenderStateRowIterator,
    cells: sys::GhosttyRenderStateRowCells,
    // Boxed so its address stays fixed while libghostty-vt holds it.
    effects: Box<Effects>,
    size: Size,
    force_full: bool,
    graphemes: Vec<u32>,
    text: String,
    input: input::Input,
    select: select::Gesture,
    /// The find bar's search, while one is open; null otherwise.
    search: sys::GhosttySearch,
}

// SAFETY: the handles are only touched through `&mut self` or, for the
// read-only queries, `&self` without concurrent mutation; libghostty-vt has no
// thread affinity.
unsafe impl Send for GhosttyEngine {}

impl GhosttyEngine {
    pub fn new(size: Size, scrollback_lines: usize) -> Self {
        let mut effects = Box::new(Effects {
            host_writes: Vec::new(),
            size,
            cell_px: (CELL_W_PX, CELL_H_PX),
            dark: true,
            bell: false,
        });
        // SAFETY: every out-pointer is valid; option values follow the
        // documented input types (pointer values, size_t*, function pointers).
        unsafe {
            let mut term: sys::GhosttyTerminal = ptr::null_mut();
            ok(
                sys::ghostty_terminal_new(ptr::null(), &mut term, size.cols, size.rows),
                "terminal_new",
            );
            ok(
                sys::ghostty_terminal_set(
                    term,
                    sys::GHOSTTY_TERMINAL_OPT_USERDATA,
                    (&mut *effects as *mut Effects).cast::<c_void>(),
                ),
                "set userdata",
            );
            let write_pty: unsafe extern "C" fn(
                sys::GhosttyTerminal,
                *mut c_void,
                *const u8,
                usize,
            ) = on_write_pty;
            ok(
                sys::ghostty_terminal_set(
                    term,
                    sys::GHOSTTY_TERMINAL_OPT_WRITE_PTY,
                    write_pty as *const c_void,
                ),
                "set write_pty",
            );
            // Answers to queries: our name, the size, a dark scheme, the
            // theme's default colors and the terminfo entry we advertise.
            let xtversion: unsafe extern "C" fn(
                sys::GhosttyTerminal,
                *mut c_void,
            ) -> sys::GhosttyString = on_xtversion;
            let size_fn: unsafe extern "C" fn(
                sys::GhosttyTerminal,
                *mut c_void,
                *mut sys::GhosttySizeReportSize,
            ) -> bool = on_size;
            let bell_fn: unsafe extern "C" fn(sys::GhosttyTerminal, *mut c_void) = on_bell;
            let scheme_fn: unsafe extern "C" fn(
                sys::GhosttyTerminal,
                *mut c_void,
                *mut sys::GhosttyColorScheme,
            ) -> bool = on_color_scheme;
            for (opt, value, what) in [
                (
                    sys::GHOSTTY_TERMINAL_OPT_XTVERSION,
                    xtversion as *const c_void,
                    "set xtversion",
                ),
                (
                    sys::GHOSTTY_TERMINAL_OPT_SIZE,
                    size_fn as *const c_void,
                    "set size",
                ),
                (
                    sys::GHOSTTY_TERMINAL_OPT_BELL,
                    bell_fn as *const c_void,
                    "set bell",
                ),
                (
                    sys::GHOSTTY_TERMINAL_OPT_COLOR_SCHEME,
                    scheme_fn as *const c_void,
                    "set color scheme",
                ),
                (
                    sys::GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND,
                    (&DEFAULT_FG as *const sys::GhosttyColorRgb).cast::<c_void>(),
                    "set foreground",
                ),
                (
                    sys::GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND,
                    (&DEFAULT_BG as *const sys::GhosttyColorRgb).cast::<c_void>(),
                    "set background",
                ),
            ] {
                ok(sys::ghostty_terminal_set(term, opt, value), what);
            }
            let terminfo = sys::GhosttyString {
                ptr: TERMINFO_NAME.as_ptr(),
                len: TERMINFO_NAME.len(),
            };
            ok(
                sys::ghostty_terminal_set(
                    term,
                    sys::GHOSTTY_TERMINAL_OPT_TERMINFO_NAME,
                    (&terminfo as *const sys::GhosttyString).cast::<c_void>(),
                ),
                "set terminfo name",
            );
            // Same retention rule as the other engine: a line limit only.
            let lines: usize = scrollback_lines;
            ok(
                sys::ghostty_terminal_set(
                    term,
                    sys::GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES,
                    (&lines as *const usize).cast::<c_void>(),
                ),
                "set scrollback lines",
            );
            ok(
                sys::ghostty_terminal_set(
                    term,
                    sys::GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES,
                    ptr::null(),
                ),
                "clear scrollback byte limit",
            );
            // Grapheme clustering (DEC mode 2027) on by default, as in the
            // Ghostty app: emoji with modifiers or ZWJ stay in one cell.
            let grapheme_cluster = sys::GhosttyTerminalModeConfig {
                mode: GRAPHEME_CLUSTER_MODE,
                value: true,
            };
            ok(
                sys::ghostty_terminal_set(
                    term,
                    sys::GHOSTTY_TERMINAL_OPT_MODE_DEFAULT,
                    (&grapheme_cluster as *const sys::GhosttyTerminalModeConfig).cast::<c_void>(),
                ),
                "enable grapheme clustering",
            );
            ok(
                sys::ghostty_terminal_resize(term, size.cols, size.rows, CELL_W_PX, CELL_H_PX),
                "resize",
            );

            let mut render: sys::GhosttyRenderState = ptr::null_mut();
            ok(
                sys::ghostty_render_state_new(ptr::null(), &mut render),
                "render_state_new",
            );
            let mut rows: sys::GhosttyRenderStateRowIterator = ptr::null_mut();
            ok(
                sys::ghostty_render_state_row_iterator_new(ptr::null(), &mut rows),
                "row_iterator_new",
            );
            let mut cells: sys::GhosttyRenderStateRowCells = ptr::null_mut();
            ok(
                sys::ghostty_render_state_row_cells_new(ptr::null(), &mut cells),
                "row_cells_new",
            );

            Self {
                term,
                render,
                rows,
                cells,
                effects,
                size,
                force_full: true,
                graphemes: Vec::with_capacity(16),
                text: String::with_capacity(16),
                input: input::Input::new(),
                select: select::Gesture::new(),
                search: ptr::null_mut(),
            }
        }
    }

    /// Bytes resident for screen and scrollback, as libghostty-vt counts them.
    pub fn resident_bytes(&self) -> u64 {
        let usage = self.memory_usage();
        usage.primary_resident_bytes
            + usage.primary_image_bytes
            + usage.alternate_resident_bytes
            + usage.alternate_image_bytes
    }

    fn memory_usage(&self) -> sys::GhosttyTerminalMemoryUsage {
        let mut usage = sized(|u: &mut sys::GhosttyTerminalMemoryUsage, n| u.size = n);
        // SAFETY: valid terminal and a correctly sized out-struct.
        unsafe {
            ok(
                sys::ghostty_terminal_get(
                    self.term,
                    sys::GHOSTTY_TERMINAL_DATA_MEMORY_USAGE,
                    (&mut usage as *mut sys::GhosttyTerminalMemoryUsage).cast::<c_void>(),
                ),
                "memory usage",
            );
        }
        usage
    }

    /// The program can change the grid itself (DECCOLM, 80/132 columns,
    /// when it also enabled mode 40). Track it so frames carry the real size.
    fn sync_size(&mut self) {
        let (mut cols, mut rows) = (0u16, 0u16);
        // SAFETY: valid terminal; both queries write a uint16_t.
        unsafe {
            sys::ghostty_terminal_get(
                self.term,
                sys::GHOSTTY_TERMINAL_DATA_COLS,
                (&mut cols as *mut u16).cast::<c_void>(),
            );
            sys::ghostty_terminal_get(
                self.term,
                sys::GHOSTTY_TERMINAL_DATA_ROWS,
                (&mut rows as *mut u16).cast::<c_void>(),
            );
        }
        let actual = Size::new(cols, rows);
        if cols > 0 && rows > 0 && actual != self.size {
            self.size = actual;
            self.effects.size = actual;
            self.force_full = true;
        }
    }

    /// The UI's theme: whether it is dark, and its default foreground and
    /// background, which programs ask for (OSC 10/11, DSR 996) to pick
    /// their own colors.
    pub fn set_theme(&mut self, dark: bool, foreground: [u8; 3], background: [u8; 3]) {
        self.effects.dark = dark;
        for (opt, [r, g, b], what) in [
            (
                sys::GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND,
                foreground,
                "set foreground",
            ),
            (
                sys::GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND,
                background,
                "set background",
            ),
        ] {
            let rgb = sys::GhosttyColorRgb { r, g, b };
            // SAFETY: valid terminal; the value is a GhosttyColorRgb*, copied.
            ok(
                unsafe {
                    sys::ghostty_terminal_set(
                        self.term,
                        opt,
                        (&rgb as *const sys::GhosttyColorRgb).cast::<c_void>(),
                    )
                },
                what,
            );
        }
    }

    /// The next damage frame repaints everything (the UI dropped its
    /// cached rows: new font, theme or pixel density).
    pub fn redraw(&mut self) {
        self.force_full = true;
    }

    /// Back to the live screen (what terminals do on input).
    pub fn scroll_to_bottom(&mut self) {
        if self.display_offset() == 0 {
            return;
        }
        let behavior = sys::GhosttyTerminalScrollViewport {
            tag: sys::GHOSTTY_SCROLL_VIEWPORT_BOTTOM,
            value: sys::GhosttyTerminalScrollViewportValue { delta: 0 },
        };
        // SAFETY: valid terminal; the BOTTOM tag reads no union member.
        unsafe { sys::ghostty_terminal_scroll_viewport(self.term, behavior) };
        self.force_full = true;
    }

    /// Compresses scrollback as far as possible (an idle-time operation).
    pub fn compress_scrollback(&mut self) -> CompressionReport {
        let before = self.resident_bytes();
        let supported = self.memory_usage().compression_supported;
        loop {
            let mut result: sys::GhosttyTerminalCompressionResult = 0;
            // SAFETY: valid terminal, out-pointer to a local.
            unsafe {
                ok(
                    sys::ghostty_terminal_compress(
                        self.term,
                        sys::GHOSTTY_TERMINAL_COMPRESSION_MODE_INCREMENTAL,
                        &mut result,
                    ),
                    "compress",
                );
            }
            if result != sys::GHOSTTY_TERMINAL_COMPRESSION_RESULT_PENDING {
                break;
            }
        }
        CompressionReport {
            supported,
            resident_before: before,
            resident_after: self.resident_bytes(),
        }
    }

    /// Whether a BEL arrived since the last call.
    pub fn take_bell(&mut self) -> bool {
        std::mem::take(&mut self.effects.bell)
    }

    /// The cursor programs get until they set their own (and after they
    /// reset it), and whether it blinks.
    pub fn set_cursor_defaults(&mut self, shape: CursorShape, blink: bool) {
        let style = match shape {
            CursorShape::Beam => sys::GHOSTTY_TERMINAL_CURSOR_STYLE_BAR,
            CursorShape::Underline => sys::GHOSTTY_TERMINAL_CURSOR_STYLE_UNDERLINE,
            CursorShape::HollowBlock => sys::GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK_HOLLOW,
            _ => sys::GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK,
        };
        // SAFETY: valid terminal; the values are GhosttyTerminalCursorStyle*
        // and bool*, copied.
        unsafe {
            ok(
                sys::ghostty_terminal_set(
                    self.term,
                    sys::GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_STYLE,
                    (&style as *const sys::GhosttyTerminalCursorStyle).cast::<c_void>(),
                ),
                "set default cursor style",
            );
            ok(
                sys::ghostty_terminal_set(
                    self.term,
                    sys::GHOSTTY_TERMINAL_OPT_DEFAULT_CURSOR_BLINK,
                    (&blink as *const bool).cast::<c_void>(),
                ),
                "set default cursor blink",
            );
        }
        // DECSCUSR 0, here and not from the program: back to the default.
        let reset = b"\x1b[0 q";
        // SAFETY: valid terminal and buffer.
        unsafe { sys::ghostty_terminal_vt_write(self.term, reset.as_ptr(), reset.len()) };
        self.force_full = true;
    }

    /// Whether the cursor blinks, as the program (or the default) asks.
    pub fn cursor_blinks(&self) -> bool {
        let mut c = sized(|c: &mut sys::GhosttyRenderStateCursor, n| c.size = n);
        // SAFETY: valid render state, correctly sized out-struct.
        let r = unsafe {
            sys::ghostty_render_state_get(
                self.render,
                sys::GHOSTTY_RENDER_STATE_DATA_CURSOR,
                (&mut c as *mut sys::GhosttyRenderStateCursor).cast::<c_void>(),
            )
        };
        r == sys::GHOSTTY_SUCCESS && c.blinking
    }

    fn display_offset(&self) -> u32 {
        let mut bar = sys::GhosttyTerminalScrollbar::default();
        // SAFETY: valid terminal, out-pointer to a local.
        let r = unsafe {
            sys::ghostty_terminal_get(
                self.term,
                sys::GHOSTTY_TERMINAL_DATA_SCROLLBAR,
                (&mut bar as *mut sys::GhosttyTerminalScrollbar).cast::<c_void>(),
            )
        };
        if r != sys::GHOSTTY_SUCCESS {
            return 0;
        }
        bar.total.saturating_sub(bar.offset + bar.len) as u32
    }

    fn cursor_state(&self) -> CursorState {
        let mut c = sized(|c: &mut sys::GhosttyRenderStateCursor, n| c.size = n);
        // SAFETY: valid render state, correctly sized out-struct.
        unsafe {
            ok(
                sys::ghostty_render_state_get(
                    self.render,
                    sys::GHOSTTY_RENDER_STATE_DATA_CURSOR,
                    (&mut c as *mut sys::GhosttyRenderStateCursor).cast::<c_void>(),
                ),
                "cursor",
            );
        }
        CursorState {
            row: c.viewport_y.min(self.size.rows.saturating_sub(1)),
            col: c.viewport_x.min(self.size.cols.saturating_sub(1)),
            shape: match c.visual_style {
                sys::GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR => CursorShape::Beam,
                sys::GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE => CursorShape::Underline,
                sys::GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW => {
                    CursorShape::HollowBlock
                }
                _ => CursorShape::Block,
            },
            visible: c.visible && c.viewport_has_value,
        }
    }

    fn update_render_state(&self) {
        // SAFETY: valid handles.
        unsafe {
            ok(
                sys::ghostty_render_state_update(self.render, self.term),
                "render_state_update",
            )
        };
    }

    /// Point the row iterator at the current render state.
    fn reset_rows(&self) {
        let mut rows = self.rows;
        // SAFETY: the iterator handle is filled in place by libghostty-vt.
        unsafe {
            ok(
                sys::ghostty_render_state_get(
                    self.render,
                    sys::GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR,
                    (&mut rows as *mut sys::GhosttyRenderStateRowIterator).cast::<c_void>(),
                ),
                "row iterator",
            );
        }
    }

    /// Point the cell iterator at the row the row iterator is on.
    fn load_cells(&self) {
        let mut cells = self.cells;
        // SAFETY: the cells handle is filled in place by libghostty-vt.
        unsafe {
            ok(
                sys::ghostty_render_state_row_get(
                    self.rows,
                    sys::GHOSTTY_RENDER_STATE_ROW_DATA_CELLS,
                    (&mut cells as *mut sys::GhosttyRenderStateRowCells).cast::<c_void>(),
                ),
                "row cells",
            );
        }
    }

    fn cell_get<T>(&self, data: sys::GhosttyRenderStateRowCellsData, out: &mut T) -> bool {
        // SAFETY: `out` matches the documented output type of `data`.
        unsafe {
            sys::ghostty_render_state_row_cells_get(
                self.cells,
                data,
                (out as *mut T).cast::<c_void>(),
            ) == sys::GHOSTTY_SUCCESS
        }
    }

    /// Reads the current cell's grapheme into `self.text` (empty if none).
    fn read_grapheme(&mut self) {
        self.text.clear();
        let mut len: u32 = 0;
        if !self.cell_get(
            sys::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN,
            &mut len,
        ) || len == 0
        {
            return;
        }
        self.graphemes.clear();
        self.graphemes.resize(len as usize, 0);
        // SAFETY: the buffer holds `len` codepoints, as the API requires.
        unsafe {
            sys::ghostty_render_state_row_cells_get(
                self.cells,
                sys::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
                self.graphemes.as_mut_ptr().cast::<c_void>(),
            );
        }
        self.text
            .extend(self.graphemes.iter().filter_map(|&cp| char::from_u32(cp)));
    }

    /// The background of a cell that has only a color (no text, no style).
    fn cell_bg_only(&self) -> Option<Color> {
        let mut raw: sys::GhosttyCell = 0;
        if !self.cell_get(sys::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &mut raw) {
            return None;
        }
        // SAFETY: each query writes the documented output type.
        unsafe {
            let mut tag: sys::GhosttyCellContentTag = 0;
            sys::ghostty_cell_get(
                raw,
                sys::GHOSTTY_CELL_DATA_CONTENT_TAG,
                (&mut tag as *mut sys::GhosttyCellContentTag).cast::<c_void>(),
            );
            match tag {
                sys::GHOSTTY_CELL_CONTENT_BG_COLOR_PALETTE => {
                    let mut i: sys::GhosttyColorPaletteIndex = 0;
                    sys::ghostty_cell_get(
                        raw,
                        sys::GHOSTTY_CELL_DATA_COLOR_PALETTE,
                        (&mut i as *mut u8).cast::<c_void>(),
                    );
                    Some(if i < 16 {
                        Color::Named(i)
                    } else {
                        Color::Indexed(i)
                    })
                }
                sys::GHOSTTY_CELL_CONTENT_BG_COLOR_RGB => {
                    let mut rgb = sys::GhosttyColorRgb::default();
                    sys::ghostty_cell_get(
                        raw,
                        sys::GHOSTTY_CELL_DATA_COLOR_RGB,
                        (&mut rgb as *mut sys::GhosttyColorRgb).cast::<c_void>(),
                    );
                    Some(Color::Rgb(rgb.r, rgb.g, rgb.b))
                }
                _ => None,
            }
        }
    }

    fn cell_width(&self) -> sys::GhosttyCellWide {
        let mut raw: sys::GhosttyCell = 0;
        if !self.cell_get(sys::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &mut raw) {
            return sys::GHOSTTY_CELL_WIDE_NARROW;
        }
        let mut wide = MaybeUninit::<sys::GhosttyCellWide>::zeroed();
        // SAFETY: GHOSTTY_CELL_DATA_WIDE writes one GhosttyCellWide.
        unsafe {
            if sys::ghostty_cell_get(
                raw,
                sys::GHOSTTY_CELL_DATA_WIDE,
                wide.as_mut_ptr().cast::<c_void>(),
            ) != sys::GHOSTTY_SUCCESS
            {
                return sys::GHOSTTY_CELL_WIDE_NARROW;
            }
            wide.assume_init()
        }
    }

    fn cell_style(&self) -> Style {
        let mut styled = false;
        if !self.cell_get(
            sys::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_HAS_STYLING,
            &mut styled,
        ) || !styled
        {
            return Style::default();
        }
        let mut s = sized(|s: &mut sys::GhosttyStyle, n| s.size = n);
        if !self.cell_get(sys::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &mut s) {
            return Style::default();
        }
        let mut a = 0;
        let mut flag = |on: bool, bit: u16| {
            if on {
                a |= bit;
            }
        };
        flag(s.bold, attrs::BOLD);
        flag(s.faint, attrs::DIM);
        flag(s.italic, attrs::ITALIC);
        flag(s.inverse, attrs::INVERSE);
        flag(s.invisible, attrs::HIDDEN);
        flag(s.strikethrough, attrs::STRIKEOUT);
        a |= match s.underline {
            sys::GHOSTTY_SGR_UNDERLINE_SINGLE => attrs::UNDERLINE,
            sys::GHOSTTY_SGR_UNDERLINE_DOUBLE => attrs::DOUBLE_UNDERLINE,
            sys::GHOSTTY_SGR_UNDERLINE_CURLY => attrs::UNDERCURL,
            sys::GHOSTTY_SGR_UNDERLINE_DOTTED => attrs::DOTTED_UNDERLINE,
            sys::GHOSTTY_SGR_UNDERLINE_DASHED => attrs::DASHED_UNDERLINE,
            _ => 0,
        };
        Style {
            fg: color(s.fg_color),
            bg: color(s.bg_color),
            attrs: a,
        }
    }

    /// Visits the rows to encode: every row, or only the dirty ones.
    fn for_each_row(&mut self, all: bool, mut visit: impl FnMut(&mut Self, u16)) {
        self.reset_rows();
        let mut index: u16 = 0;
        loop {
            // SAFETY: valid iterator handle.
            let more = unsafe {
                if all {
                    sys::ghostty_render_state_row_iterator_next(self.rows)
                } else {
                    sys::ghostty_render_state_row_iterator_next_dirty(self.rows, &mut index)
                }
            };
            if !more {
                break;
            }
            if index < self.size.rows {
                visit(self, index);
            }
            if all {
                index += 1;
            }
        }
    }
}

fn color(c: sys::GhosttyStyleColor) -> Color {
    match c.tag {
        // SAFETY: the tag says which union member is set.
        sys::GHOSTTY_STYLE_COLOR_PALETTE => {
            let i = unsafe { c.value.palette };
            if i < 16 {
                Color::Named(i)
            } else {
                Color::Indexed(i)
            }
        }
        sys::GHOSTTY_STYLE_COLOR_RGB => {
            let rgb = unsafe { c.value.rgb };
            Color::Rgb(rgb.r, rgb.g, rgb.b)
        }
        _ => Color::Default,
    }
}

impl TermEngine for GhosttyEngine {
    fn name(&self) -> &'static str {
        "libghostty-vt"
    }

    fn size(&self) -> Size {
        self.size
    }

    fn resize(&mut self, size: Size) {
        // SAFETY: valid terminal.
        unsafe {
            ok(
                sys::ghostty_terminal_resize(self.term, size.cols, size.rows, CELL_W_PX, CELL_H_PX),
                "resize",
            );
        }
        self.size = size;
        self.effects.size = size;
        self.force_full = true;
    }

    fn feed(&mut self, bytes: &[u8]) {
        // libghostty-vt at the pinned commit prints DEL (0x7F) into a cell
        // instead of ignoring it, as VT100 and xterm do in every state
        // (found by vttest, S1.6). Drop it here; the common case has none.
        let write = |term, data: &[u8]| {
            // SAFETY: valid terminal and buffer.
            unsafe { sys::ghostty_terminal_vt_write(term, data.as_ptr(), data.len()) };
        };
        if !bytes.contains(&0x7F) {
            write(self.term, bytes);
        } else {
            for piece in bytes.split(|&b| b == 0x7F) {
                if !piece.is_empty() {
                    write(self.term, piece);
                }
            }
        }
        self.sync_size();
    }

    fn encode_damage(&mut self, enc: &mut FrameEncoder) -> FrameStats {
        self.update_render_state();
        let mut dirty: sys::GhosttyRenderStateDirty = 0;
        // SAFETY: valid render state, out-pointer to a local.
        unsafe {
            ok(
                sys::ghostty_render_state_get(
                    self.render,
                    sys::GHOSTTY_RENDER_STATE_DATA_DIRTY,
                    (&mut dirty as *mut sys::GhosttyRenderStateDirty).cast::<c_void>(),
                ),
                "dirty",
            );
        }
        let full = self.force_full || dirty == sys::GHOSTTY_RENDER_STATE_DIRTY_FULL;
        self.force_full = false;

        enc.begin(
            full,
            self.size.cols,
            self.size.rows,
            self.cursor_state(),
            self.display_offset(),
        );
        if full || dirty != sys::GHOSTTY_RENDER_STATE_DIRTY_FALSE {
            self.for_each_row(full, |this, row| {
                enc.begin_row(row);
                this.load_cells();
                let mut col: u16 = 0;
                // SAFETY: valid cells handle.
                while unsafe { sys::ghostty_render_state_row_cells_next(this.cells) } {
                    let wide = this.cell_width();
                    if wide == sys::GHOSTTY_CELL_WIDE_SPACER_TAIL
                        || wide == sys::GHOSTTY_CELL_WIDE_SPACER_HEAD
                    {
                        col += 1;
                        continue;
                    }
                    let mut style = this.cell_style();
                    // Cells erased with a background color (BCE: EL, ED, ECH
                    // with a color set) hold only that color, no style.
                    if style == Style::default()
                        && let Some(bg) = this.cell_bg_only()
                    {
                        style.bg = bg;
                    }
                    this.read_grapheme();
                    // A written space with no style is as blank as an empty
                    // cell; both engines omit it from frames.
                    if this.text.is_empty() || (this.text == " " && style == Style::default()) {
                        this.text.clear();
                        if style.bg == Color::Default && style.attrs & attrs::INVERSE == 0 {
                            col += 1;
                            continue;
                        }
                        this.text.push(' ');
                    }
                    let width = if wide == sys::GHOSTTY_CELL_WIDE_WIDE {
                        2
                    } else {
                        1
                    };
                    let text = std::mem::take(&mut this.text);
                    enc.push_cell(col, &text, width, style);
                    this.text = text;
                    col += 1;
                }
                enc.end_row();
            });
        }
        // SAFETY: valid render state.
        unsafe {
            ok(
                sys::ghostty_render_state_clean(self.render),
                "render_state_clean",
            )
        };
        enc.finish()
    }

    fn scroll_display(&mut self, delta_lines: i32) {
        let behavior = sys::GhosttyTerminalScrollViewport {
            tag: sys::GHOSTTY_SCROLL_VIEWPORT_DELTA,
            // Our API scrolls into history with positive deltas; libghostty
            // moves the viewport up with negative ones.
            value: sys::GhosttyTerminalScrollViewportValue {
                delta: -(delta_lines as isize),
            },
        };
        // SAFETY: valid terminal; tag and union member agree.
        unsafe { sys::ghostty_terminal_scroll_viewport(self.term, behavior) };
        self.force_full = true;
    }

    fn take_host_writes(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.effects.host_writes)
    }

    fn title(&self) -> Option<String> {
        let mut s = sys::GhosttyString {
            ptr: ptr::null(),
            len: 0,
        };
        // SAFETY: valid terminal; the borrowed string is copied right away.
        unsafe {
            if sys::ghostty_terminal_get(
                self.term,
                sys::GHOSTTY_TERMINAL_DATA_TITLE,
                (&mut s as *mut sys::GhosttyString).cast::<c_void>(),
            ) != sys::GHOSTTY_SUCCESS
                || s.ptr.is_null()
                || s.len == 0
            {
                return None;
            }
            Some(String::from_utf8_lossy(std::slice::from_raw_parts(s.ptr, s.len)).into_owned())
        }
    }

    fn screen_text(&self) -> String {
        // A separate render state: the engine's own dirty tracking must not
        // change because a test or a CLI asked for the text.
        let mut out = Vec::with_capacity(usize::from(self.size.rows));
        // SAFETY: handles created and freed here; out-pointers are locals.
        unsafe {
            let mut render: sys::GhosttyRenderState = ptr::null_mut();
            let mut rows: sys::GhosttyRenderStateRowIterator = ptr::null_mut();
            let mut cells: sys::GhosttyRenderStateRowCells = ptr::null_mut();
            ok(
                sys::ghostty_render_state_new(ptr::null(), &mut render),
                "render_state_new",
            );
            ok(
                sys::ghostty_render_state_row_iterator_new(ptr::null(), &mut rows),
                "row_iterator_new",
            );
            ok(
                sys::ghostty_render_state_row_cells_new(ptr::null(), &mut cells),
                "row_cells_new",
            );
            ok(
                sys::ghostty_render_state_update(render, self.term),
                "render_state_update",
            );
            ok(
                sys::ghostty_render_state_get(
                    render,
                    sys::GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR,
                    (&mut rows as *mut sys::GhosttyRenderStateRowIterator).cast::<c_void>(),
                ),
                "row iterator",
            );
            let mut buf = Vec::<u32>::new();
            while sys::ghostty_render_state_row_iterator_next(rows) {
                ok(
                    sys::ghostty_render_state_row_get(
                        rows,
                        sys::GHOSTTY_RENDER_STATE_ROW_DATA_CELLS,
                        (&mut cells as *mut sys::GhosttyRenderStateRowCells).cast::<c_void>(),
                    ),
                    "row cells",
                );
                let mut line = String::new();
                while sys::ghostty_render_state_row_cells_next(cells) {
                    let mut len: u32 = 0;
                    sys::ghostty_render_state_row_cells_get(
                        cells,
                        sys::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN,
                        (&mut len as *mut u32).cast::<c_void>(),
                    );
                    let mut raw: sys::GhosttyCell = 0;
                    sys::ghostty_render_state_row_cells_get(
                        cells,
                        sys::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW,
                        (&mut raw as *mut sys::GhosttyCell).cast::<c_void>(),
                    );
                    let mut wide: sys::GhosttyCellWide = 0;
                    sys::ghostty_cell_get(
                        raw,
                        sys::GHOSTTY_CELL_DATA_WIDE,
                        (&mut wide as *mut sys::GhosttyCellWide).cast(),
                    );
                    if wide == sys::GHOSTTY_CELL_WIDE_SPACER_TAIL
                        || wide == sys::GHOSTTY_CELL_WIDE_SPACER_HEAD
                    {
                        continue;
                    }
                    if len == 0 {
                        line.push(' ');
                        continue;
                    }
                    buf.resize(len as usize, 0);
                    sys::ghostty_render_state_row_cells_get(
                        cells,
                        sys::GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
                        buf.as_mut_ptr().cast::<c_void>(),
                    );
                    line.extend(buf.iter().filter_map(|&cp| char::from_u32(cp)));
                }
                out.push(line.trim_end().to_owned());
            }
            sys::ghostty_render_state_row_cells_free(cells);
            sys::ghostty_render_state_row_iterator_free(rows);
            sys::ghostty_render_state_free(render);
        }
        out.join("\n")
    }
}

impl Drop for GhosttyEngine {
    fn drop(&mut self) {
        // SAFETY: handles created in `new`, freed once; the terminal goes
        // before `effects` (dropped after this) so no callback outlives it.
        unsafe {
            if !self.search.is_null() {
                sys::ghostty_search_free(self.search);
            }
            self.select.free(self.term);
            sys::ghostty_render_state_row_cells_free(self.cells);
            sys::ghostty_render_state_row_iterator_free(self.rows);
            sys::ghostty_render_state_free(self.render);
            sys::ghostty_terminal_free(self.term);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use openward_term::frame::{DecodedFrame, decode};

    fn engine(cols: u16, rows: u16) -> GhosttyEngine {
        GhosttyEngine::new(Size::new(cols, rows), 1_000)
    }

    fn frame(e: &mut GhosttyEngine) -> DecodedFrame {
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
    fn emoji_with_skin_tone_modifier_stays_one_wide_cell() {
        let mut e = engine(20, 2);
        e.feed("👍🏽x".as_bytes());
        let f = frame(&mut e);
        let spans = spans_of(&f, 0);
        assert_eq!(spans[0].2, "👍🏽", "spans: {spans:?}");
        assert_eq!((spans[0].0, spans[0].1), (0, 2), "spans: {spans:?}");
        assert_eq!(spans[1].0, 2, "spans: {spans:?}");
    }

    #[test]
    fn answers_cursor_position_reports() {
        let mut e = engine(20, 4);
        e.feed(b"ab\x1b[6n");
        assert_eq!(e.take_host_writes(), b"\x1b[1;3R");
        assert!(e.take_host_writes().is_empty());
    }

    #[test]
    fn erased_cells_keep_the_background_color() {
        // Erasing after X with a green background: X plus the erased cells
        // are green (one span, as they share the style).
        for (erase, green) in [(&b"\x1b[K"[..], 6), (b"\x1b[3X", 4), (b"\x1b[J", 6)] {
            let mut e = engine(6, 2);
            e.feed(b"\x1b[42mX");
            e.feed(erase);
            let f = frame(&mut e);
            let covered: u16 = f.lines[0]
                .spans
                .iter()
                .filter(|s| s.style.bg == Color::Named(2))
                .map(|s| s.width)
                .sum();
            assert_eq!(covered, green, "{erase:?}");
        }
        let mut e = engine(6, 1);
        e.feed(b"\x1b[48;2;1;2;3m\x1b[K");
        assert_eq!(
            frame(&mut e).lines[0].spans[0].style.bg,
            Color::Rgb(1, 2, 3)
        );
    }

    #[test]
    fn follows_a_program_switching_to_132_columns() {
        let mut e = engine(80, 24);
        e.feed(b"\x1b[?3h"); // DECCOLM alone is ignored (mode 40 off)
        assert_eq!(e.size(), Size::new(80, 24));
        e.feed(b"\x1b[?40h\x1b[?3h");
        assert_eq!(e.size(), Size::new(132, 24));
        let f = frame(&mut e);
        assert!(f.full);
        assert_eq!(f.cols, 132);
    }

    #[test]
    fn ignores_del() {
        let mut e = engine(20, 2);
        e.feed(b"a\x7fb\x1b[3\x7f1mc");
        assert_eq!(e.screen_text().lines().next(), Some("abc"));
    }

    #[test]
    fn answers_queries_programs_send() {
        let mut e = engine(80, 24);
        let mut ask = |q: &[u8]| {
            e.feed(q);
            String::from_utf8(e.take_host_writes()).unwrap()
        };
        assert!(ask(b"\x1b[>0q").contains("OpenWard 0."));
        assert_eq!(ask(b"\x1b[18t"), "\x1b[8;24;80t");
        assert_eq!(ask(b"\x1b[?996n"), "\x1b[?997;1n");
        assert!(ask(b"\x1b]11;?\x1b\\").contains("rgb:1616/1818/1d1d"));
        assert!(ask(b"\x1b]10;?\x1b\\").contains("rgb:d4d4/d4d4/d4d4"));
        // XTGETTCAP TN, hex-encoded both ways.
        let hex: String = "xterm-256color"
            .bytes()
            .map(|b| format!("{b:02X}"))
            .collect();
        assert!(ask(b"\x1bP+q544e\x1b\\").contains(&hex));
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
    fn scroll_to_bottom_returns_to_the_live_screen() {
        let mut e = engine(10, 3);
        for i in 0..20 {
            e.feed(format!("line {i}\r\n").as_bytes());
        }
        e.scroll_display(5);
        frame(&mut e);
        e.scroll_to_bottom();
        let f = frame(&mut e);
        assert!(f.full);
        assert_eq!(f.display_offset, 0);
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

    #[test]
    fn rings_the_bell_once() {
        let mut e = engine(20, 2);
        assert!(!e.take_bell());
        e.feed(b"ding\x07");
        assert!(e.take_bell());
        assert!(!e.take_bell());
    }

    #[test]
    fn the_cursor_the_user_chose_until_a_program_sets_one() {
        let mut e = engine(20, 2);
        e.set_cursor_defaults(CursorShape::Beam, true);
        let f = frame(&mut e);
        assert_eq!(f.cursor.shape, CursorShape::Beam);
        assert!(e.cursor_blinks());
        // A program's DECSCUSR wins (2: steady block) ...
        e.feed(b"\x1b[2 q");
        assert_eq!(frame(&mut e).cursor.shape, CursorShape::Block);
        assert!(!e.cursor_blinks());
        // ... until it resets to the default.
        e.feed(b"\x1b[0 q");
        assert_eq!(frame(&mut e).cursor.shape, CursorShape::Beam);
    }

    #[test]
    fn reports_memory_and_compresses_scrollback() {
        let mut e = GhosttyEngine::new(Size::new(80, 24), 20_000);
        for i in 0..10_000 {
            e.feed(
                format!(
                    "\x1b[3{}mline {i} repeated compressible text\x1b[0m\r\n",
                    i % 8
                )
                .as_bytes(),
            );
        }
        let report = e.compress_scrollback();
        assert!(report.resident_before > 0);
        if report.supported {
            assert!(
                report.resident_after <= report.resident_before,
                "{report:?}"
            );
        }
    }
}
