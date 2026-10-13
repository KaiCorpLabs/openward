//! Keyboard, mouse, paste and focus input (spike S1.5).
//!
//! libghostty-vt's encoders turn UI events into the bytes the program on the
//! other end expects, in whatever modes it asked for: cursor keys (DECCKM),
//! kitty keyboard flags, mouse tracking and format, bracketed paste, focus
//! reports. Every call syncs the encoder with the terminal first, so a mode
//! change in the output stream applies to the very next key.

use std::ffi::{c_char, c_void};
use std::ptr;

use super::{GhosttyEngine, ok, sized};
use crate::sys;

/// Modifier bits, as libghostty-vt's `GhosttyMods`.
pub mod mods {
    use crate::sys;

    pub const SHIFT: u16 = sys::GHOSTTY_MODS_SHIFT as u16;
    pub const CTRL: u16 = sys::GHOSTTY_MODS_CTRL as u16;
    pub const ALT: u16 = sys::GHOSTTY_MODS_ALT as u16;
    pub const SUPER: u16 = sys::GHOSTTY_MODS_SUPER as u16;
    pub const CAPS_LOCK: u16 = sys::GHOSTTY_MODS_CAPS_LOCK as u16;
    pub const NUM_LOCK: u16 = sys::GHOSTTY_MODS_NUM_LOCK as u16;
    /// Right-hand side of the modifier (only meaningful with its bit set).
    pub const SHIFT_RIGHT: u16 = sys::GHOSTTY_MODS_SHIFT_SIDE as u16;
    pub const CTRL_RIGHT: u16 = sys::GHOSTTY_MODS_CTRL_SIDE as u16;
    pub const ALT_RIGHT: u16 = sys::GHOSTTY_MODS_ALT_SIDE as u16;
    pub const SUPER_RIGHT: u16 = sys::GHOSTTY_MODS_SUPER_SIDE as u16;
}

/// `ghostty_mode_new(n, false)` for the DEC private modes used here.
const MODE_FOCUS_EVENT: sys::GhosttyMode = 1004;
const MODE_ALT_SCROLL: sys::GhosttyMode = 1007;
const MODE_SGR_PIXELS_MOUSE: sys::GhosttyMode = 1016;
const MODE_BRACKETED_PASTE: sys::GhosttyMode = 2004;

/// Kitty flag: every key, printable or not, is reported as an escape code.
const KITTY_REPORT_ALL: u8 = sys::GHOSTTY_KITTY_KEY_REPORT_ALL as u8;

/// USB HID usage page of keyboard keys, in the high 16 bits of a usage
/// (as Flutter's `PhysicalKeyboardKey.usbHidUsage` gives it).
const HID_KEYBOARD_PAGE: u32 = 0x0007_0000;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum KeyAction {
    #[default]
    Press,
    Repeat,
    Release,
}

/// One key event from the UI.
#[derive(Clone, Debug, Default)]
pub struct KeyInput {
    /// Physical key as a USB HID usage (0x0007xxxx); layout independent.
    pub hid_usage: u32,
    pub action: KeyAction,
    /// [`mods`] bits.
    pub mods: u16,
    /// Text the layout produces, before any Ctrl transform. Control
    /// characters are dropped: the encoder works those out from the key.
    pub text: String,
    /// The key's character without Shift in the current layout, 0 if
    /// unknown. Lets Ctrl+key and kitty reports work on non-US layouts.
    pub unshifted: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum MouseAction {
    #[default]
    Press,
    Release,
    Motion,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum MouseButton {
    /// Motion with nothing pressed.
    #[default]
    None,
    Left,
    Middle,
    Right,
}

/// One pointer event from the UI, in logical pixels from the grid origin.
#[derive(Clone, Copy, Debug, Default)]
pub struct MouseInput {
    pub action: MouseAction,
    pub button: MouseButton,
    pub mods: u16,
    pub x: f32,
    pub y: f32,
}

/// What [`GhosttyEngine::encode_paste`] did.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Paste {
    /// Bytes to write to the pty (empty when there was nothing to paste).
    Bytes(Vec<u8>),
    /// The text could run commands (a newline outside bracketed paste, or
    /// the bracketed paste terminator). Nothing was encoded: ask the user,
    /// then call again with `allow_unsafe`.
    Unsafe,
}

/// Input-related modes the program has set, for the UI to adapt to.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct InputModes {
    /// Some mouse tracking mode is on: clicks and wheel go to the program.
    pub mouse_tracking: bool,
    pub bracketed_paste: bool,
    pub focus_events: bool,
    pub alt_screen: bool,
    pub kitty_flags: u8,
}

impl InputModes {
    /// Printable keys must go through [`GhosttyEngine::encode_key`] too
    /// (kitty "report all keys"), not as plain text.
    pub fn report_all_keys(&self) -> bool {
        self.kitty_flags & KITTY_REPORT_ALL != 0
    }
}

/// Encoder handles and the bits of UI state they need.
pub(super) struct Input {
    key_encoder: sys::GhosttyKeyEncoder,
    key_event: sys::GhosttyKeyEvent,
    mouse_encoder: sys::GhosttyMouseEncoder,
    mouse_event: sys::GhosttyMouseEvent,
    option_as_alt: bool,
    cell_w: f32,
    cell_h: f32,
    /// Mouse buttons held down: bit 0 left, 1 middle, 2 right.
    held: u8,
    /// Cell of the last report, to drop motion within the same cell. Kept
    /// here because libghostty-vt forgets its own copy on every sync with
    /// the terminal, and the encoder is synced before each event.
    last_cell: Option<(i32, i32)>,
}

impl Input {
    pub(super) fn new() -> Self {
        // SAFETY: valid out-pointers; the handles are freed in Drop.
        unsafe {
            let mut key_encoder = ptr::null_mut();
            ok(
                sys::ghostty_key_encoder_new(ptr::null(), &mut key_encoder),
                "key_encoder_new",
            );
            let mut key_event = ptr::null_mut();
            ok(
                sys::ghostty_key_event_new(ptr::null(), &mut key_event),
                "key_event_new",
            );
            let mut mouse_encoder = ptr::null_mut();
            ok(
                sys::ghostty_mouse_encoder_new(ptr::null(), &mut mouse_encoder),
                "mouse_encoder_new",
            );
            let mut mouse_event = ptr::null_mut();
            ok(
                sys::ghostty_mouse_event_new(ptr::null(), &mut mouse_event),
                "mouse_event_new",
            );
            Self {
                key_encoder,
                key_event,
                mouse_encoder,
                mouse_event,
                option_as_alt: false,
                cell_w: super::CELL_W_PX as f32,
                cell_h: super::CELL_H_PX as f32,
                held: 0,
                last_cell: None,
            }
        }
    }
}

impl Drop for Input {
    fn drop(&mut self) {
        // SAFETY: created in `new`, freed once.
        unsafe {
            sys::ghostty_key_event_free(self.key_event);
            sys::ghostty_key_encoder_free(self.key_encoder);
            sys::ghostty_mouse_event_free(self.mouse_event);
            sys::ghostty_mouse_encoder_free(self.mouse_encoder);
        }
    }
}

impl GhosttyEngine {
    /// macOS: whether Option acts as Alt (sends ESC-prefixed keys) instead
    /// of typing the layout's special characters. Off by default, as in
    /// the system's own text fields.
    pub fn set_option_as_alt(&mut self, on: bool) {
        self.input.option_as_alt = on;
    }

    /// Size of one cell on screen, in the same logical pixels as
    /// [`MouseInput`] positions. May be fractional.
    pub fn set_cell_pixels(&mut self, width: f32, height: f32) {
        self.input.cell_w = width.max(1.0);
        self.input.cell_h = height.max(1.0);
        self.effects.cell_px = (
            self.input.cell_w.round() as u32,
            self.input.cell_h.round() as u32,
        );
    }

    pub fn input_modes(&self) -> InputModes {
        let mut tracking = false;
        let mut kitty_flags: u8 = 0;
        let mut screen: sys::GhosttyTerminalScreen = sys::GHOSTTY_TERMINAL_SCREEN_PRIMARY;
        // SAFETY: valid terminal; out types as documented in terminal.h.
        unsafe {
            self.get(sys::GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING, &mut tracking);
            self.get(
                sys::GHOSTTY_TERMINAL_DATA_KITTY_KEYBOARD_FLAGS,
                &mut kitty_flags,
            );
            self.get(sys::GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &mut screen);
        }
        InputModes {
            mouse_tracking: tracking,
            bracketed_paste: self.mode(MODE_BRACKETED_PASTE),
            focus_events: self.mode(MODE_FOCUS_EVENT),
            alt_screen: screen == sys::GHOSTTY_TERMINAL_SCREEN_ALTERNATE,
            kitty_flags,
        }
    }

    /// Bytes for one key event (often none, e.g. a bare modifier or a
    /// release outside kitty's event reporting).
    pub fn encode_key(&mut self, key: &KeyInput) -> Vec<u8> {
        self.encode_key_raw(
            key_from_hid(key.hid_usage),
            key.action,
            key.mods,
            &key.text,
            key.unshifted,
        )
    }

    /// Text committed by an input method or typed on a soft keyboard.
    /// Newlines become Enter; under kitty "report all keys" each character
    /// goes out as a key event.
    pub fn encode_text(&mut self, text: &str) -> Vec<u8> {
        let report_all = self.input_modes().report_all_keys();
        let mut out = Vec::with_capacity(text.len());
        let mut buf = [0u8; 4];
        for ch in text.chars() {
            if ch == '\n' || ch == '\r' {
                out.extend(self.encode_key_raw(sys::GHOSTTY_KEY_ENTER, KeyAction::Press, 0, "", 0));
            } else if (ch as u32) < 0x20 || ch == '\u{7f}' {
                // A stray control character from an IME: never sent raw.
            } else if report_all {
                let s = ch.encode_utf8(&mut buf);
                out.extend(self.encode_key_raw(
                    sys::GHOSTTY_KEY_UNIDENTIFIED,
                    KeyAction::Press,
                    0,
                    s,
                    ch as u32,
                ));
            } else {
                out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
            }
        }
        out
    }

    fn encode_key_raw(
        &mut self,
        key: sys::GhosttyKey,
        action: KeyAction,
        mods: u16,
        text: &str,
        unshifted: u32,
    ) -> Vec<u8> {
        let text = encoder_text(text);
        // Shift (and, on macOS, Option when it is not Alt) went into
        // producing the text; the encoder must not report it twice.
        let mut consumed = 0;
        if !text.is_empty() {
            consumed |= mods & mods::SHIFT;
            if cfg!(any(target_os = "macos", target_os = "ios")) && !self.input.option_as_alt {
                consumed |= mods & mods::ALT;
            }
        }
        let action = match action {
            KeyAction::Press => sys::GHOSTTY_KEY_ACTION_PRESS,
            KeyAction::Repeat => sys::GHOSTTY_KEY_ACTION_REPEAT,
            KeyAction::Release => sys::GHOSTTY_KEY_ACTION_RELEASE,
        };
        let enc = self.input.key_encoder;
        let ev = self.input.key_event;
        // SAFETY: live handles; `text` outlives the encode call and is
        // detached from the event before returning (the event borrows it).
        unsafe {
            sys::ghostty_key_encoder_setopt_from_terminal(enc, self.term);
            // setopt_from_terminal resets option-as-alt; apply ours after.
            let option_as_alt = if self.input.option_as_alt {
                sys::GHOSTTY_OPTION_AS_ALT_TRUE
            } else {
                sys::GHOSTTY_OPTION_AS_ALT_FALSE
            };
            sys::ghostty_key_encoder_setopt(
                enc,
                sys::GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT,
                (&option_as_alt as *const sys::GhosttyOptionAsAlt).cast::<c_void>(),
            );
            sys::ghostty_key_event_set_action(ev, action);
            sys::ghostty_key_event_set_key(ev, key);
            sys::ghostty_key_event_set_mods(ev, mods);
            sys::ghostty_key_event_set_consumed_mods(ev, consumed);
            sys::ghostty_key_event_set_composing(ev, false);
            sys::ghostty_key_event_set_unshifted_codepoint(ev, unshifted);
            if text.is_empty() {
                sys::ghostty_key_event_set_utf8(ev, ptr::null(), 0);
            } else {
                sys::ghostty_key_event_set_utf8(ev, text.as_ptr().cast::<c_char>(), text.len());
            }
            let out = encode_into(|buf, cap, len| {
                sys::ghostty_key_encoder_encode(enc, ev, buf, cap, len)
            });
            sys::ghostty_key_event_set_utf8(ev, ptr::null(), 0);
            out
        }
    }

    /// Bytes for a pointer event; empty unless the program tracks the mouse.
    pub fn encode_mouse(&mut self, m: &MouseInput) -> Vec<u8> {
        let bit = match m.button {
            MouseButton::None => 0,
            MouseButton::Left => 1,
            MouseButton::Middle => 2,
            MouseButton::Right => 4,
        };
        match m.action {
            MouseAction::Press => self.input.held |= bit,
            MouseAction::Release => self.input.held &= !bit,
            MouseAction::Motion => {}
        }
        // Drags in button-event mode carry the held button.
        let button = match (m.action, m.button) {
            (MouseAction::Motion, MouseButton::None) => match self.input.held {
                0 => None,
                h if h & 1 != 0 => Some(sys::GHOSTTY_MOUSE_BUTTON_LEFT),
                h if h & 2 != 0 => Some(sys::GHOSTTY_MOUSE_BUTTON_MIDDLE),
                _ => Some(sys::GHOSTTY_MOUSE_BUTTON_RIGHT),
            },
            (_, MouseButton::None) => None,
            (_, MouseButton::Left) => Some(sys::GHOSTTY_MOUSE_BUTTON_LEFT),
            (_, MouseButton::Middle) => Some(sys::GHOSTTY_MOUSE_BUTTON_MIDDLE),
            (_, MouseButton::Right) => Some(sys::GHOSTTY_MOUSE_BUTTON_RIGHT),
        };
        let action = match m.action {
            MouseAction::Press => sys::GHOSTTY_MOUSE_ACTION_PRESS,
            MouseAction::Release => sys::GHOSTTY_MOUSE_ACTION_RELEASE,
            MouseAction::Motion => sys::GHOSTTY_MOUSE_ACTION_MOTION,
        };
        // Motion is reported once per cell (per pixel in SGR-pixels mode).
        let cell = (
            (m.x / self.input.cell_w).floor() as i32,
            (m.y / self.input.cell_h).floor() as i32,
        );
        if m.action == MouseAction::Motion
            && self.input.last_cell == Some(cell)
            && !self.mode(MODE_SGR_PIXELS_MOUSE)
        {
            return Vec::new();
        }
        let out = self.encode_mouse_raw(action, button, m.mods, m.x, m.y);
        if !out.is_empty() {
            self.input.last_cell = Some(cell);
        }
        out
    }

    /// Mouse wheel, `lines` notches (positive = up, towards history, as
    /// [`TermEngine::scroll_display`](openward_term::TermEngine::scroll_display)).
    /// `None` means the program does not want it: scroll the scrollback.
    pub fn wheel(&mut self, lines: i32, x: f32, y: f32, mods: u16) -> Option<Vec<u8>> {
        let modes = self.input_modes();
        let steps = lines.unsigned_abs().min(64);
        if modes.mouse_tracking {
            let button = if lines > 0 {
                sys::GHOSTTY_MOUSE_BUTTON_FOUR
            } else {
                sys::GHOSTTY_MOUSE_BUTTON_FIVE
            };
            let mut out = Vec::new();
            for _ in 0..steps {
                out.extend(self.encode_mouse_raw(
                    sys::GHOSTTY_MOUSE_ACTION_PRESS,
                    Some(button),
                    mods,
                    x,
                    y,
                ));
            }
            return Some(out);
        }
        // Alternate scroll (1007): full-screen programs without mouse
        // support (less, man) get arrow keys.
        if modes.alt_screen && self.mode(MODE_ALT_SCROLL) {
            let key = if lines > 0 {
                sys::GHOSTTY_KEY_ARROW_UP
            } else {
                sys::GHOSTTY_KEY_ARROW_DOWN
            };
            let mut out = Vec::new();
            for _ in 0..steps {
                out.extend(self.encode_key_raw(key, KeyAction::Press, 0, "", 0));
            }
            return Some(out);
        }
        None
    }

    fn encode_mouse_raw(
        &mut self,
        action: sys::GhosttyMouseAction,
        button: Option<sys::GhosttyMouseButton>,
        mods: u16,
        x: f32,
        y: f32,
    ) -> Vec<u8> {
        // libghostty-vt wants whole-pixel cells; the UI's are fractional.
        // Map positions onto a grid of rounded cells so the cell under the
        // pointer is exact (pixel reports, mode 1016, are approximate).
        let cw = self.input.cell_w.round().max(1.0);
        let ch = self.input.cell_h.round().max(1.0);
        let position = sys::GhosttyMousePosition {
            x: x / self.input.cell_w * cw,
            y: y / self.input.cell_h * ch,
        };
        let size = sys::GhosttyMouseEncoderSize {
            screen_width: self.size.cols as u32 * cw as u32,
            screen_height: self.size.rows as u32 * ch as u32,
            cell_width: cw as u32,
            cell_height: ch as u32,
            ..sized(|s: &mut sys::GhosttyMouseEncoderSize, n| s.size = n)
        };
        let any_pressed = self.input.held != 0;
        let enc = self.input.mouse_encoder;
        let ev = self.input.mouse_event;
        // SAFETY: live handles; option values match their documented types.
        unsafe {
            sys::ghostty_mouse_encoder_setopt_from_terminal(enc, self.term);
            sys::ghostty_mouse_encoder_setopt(
                enc,
                sys::GHOSTTY_MOUSE_ENCODER_OPT_SIZE,
                (&size as *const sys::GhosttyMouseEncoderSize).cast::<c_void>(),
            );
            sys::ghostty_mouse_encoder_setopt(
                enc,
                sys::GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED,
                (&any_pressed as *const bool).cast::<c_void>(),
            );
            sys::ghostty_mouse_event_set_action(ev, action);
            match button {
                Some(b) => sys::ghostty_mouse_event_set_button(ev, b),
                None => sys::ghostty_mouse_event_clear_button(ev),
            }
            sys::ghostty_mouse_event_set_mods(ev, mods);
            sys::ghostty_mouse_event_set_position(ev, position);
            encode_into(|buf, cap, len| sys::ghostty_mouse_encoder_encode(enc, ev, buf, cap, len))
        }
    }

    /// Clipboard text for the pty: bracketed if the program set mode 2004,
    /// with newlines as CR otherwise, unsafe control bytes replaced.
    pub fn encode_paste(&mut self, text: &str, allow_unsafe: bool) -> Paste {
        unsafe extern "C" fn read(
            userdata: *mut c_void,
            _mime: sys::GhosttyString,
            writer: sys::GhosttyWriter,
        ) -> bool {
            // SAFETY: userdata is the `&[u8]` below, alive for the call.
            let data = unsafe { &*userdata.cast::<&[u8]>() };
            match writer.write {
                Some(write) => unsafe { write(writer.userdata, data.as_ptr(), data.len()) },
                None => false,
            }
        }

        let data: &[u8] = text.as_bytes();
        let mimes = [sys::GhosttyString {
            ptr: b"text/plain".as_ptr(),
            len: b"text/plain".len(),
        }];
        let paste = sys::GhosttyPaste {
            location: sys::GHOSTTY_CLIPBOARD_LOCATION_STANDARD,
            source: sys::GHOSTTY_PASTE_SOURCE_CLIPBOARD,
            mimes: mimes.as_ptr(),
            mimes_len: mimes.len(),
            reader: sys::GhosttyMimeReader {
                read: Some(read),
                userdata: (&data as *const &[u8]).cast_mut().cast::<c_void>(),
            },
            allow_unsafe,
            ..sized(|p: &mut sys::GhosttyPaste, n| p.size = n)
        };
        // The terminal streams the encoded text through write_pty, after
        // whatever replies are already queued there; take only the new part.
        let start = self.effects.host_writes.len();
        let mut written = false;
        // SAFETY: valid terminal; `paste`, `mimes` and `data` outlive the call.
        let result = unsafe { sys::ghostty_terminal_paste(self.term, &paste, &mut written) };
        match result {
            sys::GHOSTTY_SUCCESS => Paste::Bytes(self.effects.host_writes.split_off(start)),
            sys::GHOSTTY_REJECTED => Paste::Unsafe,
            other => {
                debug_assert!(false, "libghostty-vt: paste failed ({other})");
                Paste::Bytes(Vec::new())
            }
        }
    }

    /// Focus report, only if the program asked for them (mode 1004).
    pub fn encode_focus(&mut self, gained: bool) -> Vec<u8> {
        if !self.mode(MODE_FOCUS_EVENT) {
            return Vec::new();
        }
        let event = if gained {
            sys::GHOSTTY_FOCUS_GAINED
        } else {
            sys::GHOSTTY_FOCUS_LOST
        };
        // SAFETY: plain buffer encode, no handles involved.
        unsafe { encode_into(|buf, cap, len| sys::ghostty_focus_encode(event, buf, cap, len)) }
    }

    fn mode(&self, mode: sys::GhosttyMode) -> bool {
        let mut config = sys::GhosttyTerminalModeConfig { mode, value: false };
        // SAFETY: in/out struct with `mode` set, as GHOSTTY_TERMINAL_DATA_MODE expects.
        let result = unsafe { self.get_raw(sys::GHOSTTY_TERMINAL_DATA_MODE, &mut config) };
        result == sys::GHOSTTY_SUCCESS && config.value
    }

    /// # Safety
    /// `T` must be the output type libghostty-vt documents for `data`.
    unsafe fn get<T>(&self, data: sys::GhosttyTerminalData, out: &mut T) {
        ok(unsafe { self.get_raw(data, out) }, "terminal_get");
    }

    /// # Safety
    /// As [`Self::get`].
    unsafe fn get_raw<T>(&self, data: sys::GhosttyTerminalData, out: &mut T) -> sys::GhosttyResult {
        unsafe { sys::ghostty_terminal_get(self.term, data, (out as *mut T).cast::<c_void>()) }
    }
}

/// The text the key encoder may see: no C0 controls or DEL (Ctrl+C arrives
/// from some platforms as "\x03") and no macOS function-key private-use
/// characters. The encoder derives those keys from the key code instead.
fn encoder_text(text: &str) -> &str {
    let unusable =
        |c: char| (c as u32) < 0x20 || c == '\u{7f}' || ('\u{f700}'..='\u{f8ff}').contains(&c);
    if text.chars().any(unusable) { "" } else { text }
}

/// Calls an encoder with a stack buffer, retrying with the size it asks for.
///
/// # Safety
/// `encode` must write at most `cap` bytes to `buf` and set `len`.
unsafe fn encode_into(
    mut encode: impl FnMut(*mut c_char, usize, &mut usize) -> sys::GhosttyResult,
) -> Vec<u8> {
    let mut buf = [0u8; 128];
    let mut len = 0usize;
    match encode(buf.as_mut_ptr().cast(), buf.len(), &mut len) {
        sys::GHOSTTY_SUCCESS => buf[..len].to_vec(),
        sys::GHOSTTY_OUT_OF_SPACE => {
            let mut big = vec![0u8; len];
            let mut written = 0usize;
            ok(
                encode(big.as_mut_ptr().cast(), big.len(), &mut written),
                "encode",
            );
            big.truncate(written);
            big
        }
        other => {
            debug_assert!(false, "libghostty-vt: encode failed ({other})");
            Vec::new()
        }
    }
}

/// USB HID keyboard usage (page 7) to libghostty-vt's key code, which
/// follows the W3C `KeyboardEvent.code` names, as HID does.
pub(crate) fn key_from_hid(usage: u32) -> sys::GhosttyKey {
    if usage & 0xFFFF_0000 != HID_KEYBOARD_PAGE {
        return sys::GHOSTTY_KEY_UNIDENTIFIED;
    }
    let id = usage & 0xFFFF;
    match id {
        0x04..=0x1D => sys::GHOSTTY_KEY_A + (id - 0x04) as sys::GhosttyKey,
        0x1E..=0x26 => sys::GHOSTTY_KEY_DIGIT_1 + (id - 0x1E) as sys::GhosttyKey,
        0x27 => sys::GHOSTTY_KEY_DIGIT_0,
        0x28 => sys::GHOSTTY_KEY_ENTER,
        0x29 => sys::GHOSTTY_KEY_ESCAPE,
        0x2A => sys::GHOSTTY_KEY_BACKSPACE,
        0x2B => sys::GHOSTTY_KEY_TAB,
        0x2C => sys::GHOSTTY_KEY_SPACE,
        0x2D => sys::GHOSTTY_KEY_MINUS,
        0x2E => sys::GHOSTTY_KEY_EQUAL,
        0x2F => sys::GHOSTTY_KEY_BRACKET_LEFT,
        0x30 => sys::GHOSTTY_KEY_BRACKET_RIGHT,
        // 0x32 is the non-US "#~" key, which W3C also calls Backslash.
        0x31 | 0x32 => sys::GHOSTTY_KEY_BACKSLASH,
        0x33 => sys::GHOSTTY_KEY_SEMICOLON,
        0x34 => sys::GHOSTTY_KEY_QUOTE,
        0x35 => sys::GHOSTTY_KEY_BACKQUOTE,
        0x36 => sys::GHOSTTY_KEY_COMMA,
        0x37 => sys::GHOSTTY_KEY_PERIOD,
        0x38 => sys::GHOSTTY_KEY_SLASH,
        0x39 => sys::GHOSTTY_KEY_CAPS_LOCK,
        0x3A..=0x45 => sys::GHOSTTY_KEY_F1 + (id - 0x3A) as sys::GhosttyKey,
        0x46 => sys::GHOSTTY_KEY_PRINT_SCREEN,
        0x47 => sys::GHOSTTY_KEY_SCROLL_LOCK,
        0x48 => sys::GHOSTTY_KEY_PAUSE,
        0x49 => sys::GHOSTTY_KEY_INSERT,
        0x4A => sys::GHOSTTY_KEY_HOME,
        0x4B => sys::GHOSTTY_KEY_PAGE_UP,
        0x4C => sys::GHOSTTY_KEY_DELETE,
        0x4D => sys::GHOSTTY_KEY_END,
        0x4E => sys::GHOSTTY_KEY_PAGE_DOWN,
        0x4F => sys::GHOSTTY_KEY_ARROW_RIGHT,
        0x50 => sys::GHOSTTY_KEY_ARROW_LEFT,
        0x51 => sys::GHOSTTY_KEY_ARROW_DOWN,
        0x52 => sys::GHOSTTY_KEY_ARROW_UP,
        0x53 => sys::GHOSTTY_KEY_NUM_LOCK,
        0x54 => sys::GHOSTTY_KEY_NUMPAD_DIVIDE,
        0x55 => sys::GHOSTTY_KEY_NUMPAD_MULTIPLY,
        0x56 => sys::GHOSTTY_KEY_NUMPAD_SUBTRACT,
        0x57 => sys::GHOSTTY_KEY_NUMPAD_ADD,
        0x58 => sys::GHOSTTY_KEY_NUMPAD_ENTER,
        0x59..=0x61 => sys::GHOSTTY_KEY_NUMPAD_1 + (id - 0x59) as sys::GhosttyKey,
        0x62 => sys::GHOSTTY_KEY_NUMPAD_0,
        0x63 => sys::GHOSTTY_KEY_NUMPAD_DECIMAL,
        0x64 => sys::GHOSTTY_KEY_INTL_BACKSLASH,
        0x65 => sys::GHOSTTY_KEY_CONTEXT_MENU,
        0x67 => sys::GHOSTTY_KEY_NUMPAD_EQUAL,
        0x68..=0x73 => sys::GHOSTTY_KEY_F13 + (id - 0x68) as sys::GhosttyKey,
        0x75 => sys::GHOSTTY_KEY_HELP,
        0x85 => sys::GHOSTTY_KEY_NUMPAD_COMMA,
        0x87 => sys::GHOSTTY_KEY_INTL_RO,
        0x88 => sys::GHOSTTY_KEY_KANA_MODE,
        0x89 => sys::GHOSTTY_KEY_INTL_YEN,
        0x8A => sys::GHOSTTY_KEY_CONVERT,
        0x8B => sys::GHOSTTY_KEY_NON_CONVERT,
        0xE0 => sys::GHOSTTY_KEY_CONTROL_LEFT,
        0xE1 => sys::GHOSTTY_KEY_SHIFT_LEFT,
        0xE2 => sys::GHOSTTY_KEY_ALT_LEFT,
        0xE3 => sys::GHOSTTY_KEY_META_LEFT,
        0xE4 => sys::GHOSTTY_KEY_CONTROL_RIGHT,
        0xE5 => sys::GHOSTTY_KEY_SHIFT_RIGHT,
        0xE6 => sys::GHOSTTY_KEY_ALT_RIGHT,
        0xE7 => sys::GHOSTTY_KEY_META_RIGHT,
        _ => sys::GHOSTTY_KEY_UNIDENTIFIED,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use openward_term::{Size, TermEngine};

    // USB HID usages, as Flutter's PhysicalKeyboardKey reports them.
    const KEY_A: u32 = 0x0007_0004;
    const KEY_C: u32 = 0x0007_0006;
    const KEY_X: u32 = 0x0007_001B;
    const DIGIT_1: u32 = 0x0007_001E;
    const ENTER: u32 = 0x0007_0028;
    const ESCAPE: u32 = 0x0007_0029;
    const BACKSPACE: u32 = 0x0007_002A;
    const TAB: u32 = 0x0007_002B;
    const F1: u32 = 0x0007_003A;
    const F5: u32 = 0x0007_003E;
    const ARROW_UP: u32 = 0x0007_0052;
    const SHIFT_LEFT: u32 = 0x0007_00E1;

    fn engine() -> GhosttyEngine {
        GhosttyEngine::new(Size::new(200, 50), 100)
    }

    fn press(hid_usage: u32, mods: u16, text: &str, unshifted: char) -> KeyInput {
        KeyInput {
            hid_usage,
            action: KeyAction::Press,
            mods,
            text: text.into(),
            unshifted: unshifted as u32,
        }
    }

    fn key(e: &mut GhosttyEngine, k: KeyInput) -> Vec<u8> {
        e.encode_key(&k)
    }

    #[test]
    fn maps_hid_usages_to_ghostty_keys() {
        assert_eq!(key_from_hid(KEY_A), sys::GHOSTTY_KEY_A);
        assert_eq!(key_from_hid(0x0007_001D), sys::GHOSTTY_KEY_Z);
        assert_eq!(key_from_hid(DIGIT_1), sys::GHOSTTY_KEY_DIGIT_1);
        assert_eq!(key_from_hid(0x0007_0026), sys::GHOSTTY_KEY_DIGIT_9);
        assert_eq!(key_from_hid(0x0007_0027), sys::GHOSTTY_KEY_DIGIT_0);
        assert_eq!(key_from_hid(0x0007_0045), sys::GHOSTTY_KEY_F12);
        assert_eq!(key_from_hid(0x0007_0059), sys::GHOSTTY_KEY_NUMPAD_1);
        assert_eq!(key_from_hid(0x0007_0073), sys::GHOSTTY_KEY_F24);
        assert_eq!(key_from_hid(0x0007_00E7), sys::GHOSTTY_KEY_META_RIGHT);
        // Other pages (consumer keys, Flutter's own planes) are unknown.
        assert_eq!(key_from_hid(0x000C_00E9), sys::GHOSTTY_KEY_UNIDENTIFIED);
        assert_eq!(key_from_hid(0x0011_0000_u32), sys::GHOSTTY_KEY_UNIDENTIFIED);
    }

    #[test]
    fn plain_and_special_keys_in_legacy_mode() {
        let mut e = engine();
        assert_eq!(key(&mut e, press(KEY_A, 0, "a", 'a')), b"a");
        assert_eq!(key(&mut e, press(KEY_A, mods::SHIFT, "A", 'a')), b"A");
        assert_eq!(key(&mut e, press(ENTER, 0, "\r", '\0')), b"\r");
        assert_eq!(key(&mut e, press(TAB, 0, "\t", '\0')), b"\t");
        assert_eq!(key(&mut e, press(BACKSPACE, 0, "", '\0')), b"\x7f");
        assert_eq!(key(&mut e, press(ESCAPE, 0, "\x1b", '\0')), b"\x1b");
        assert_eq!(key(&mut e, press(F1, 0, "", '\0')), b"\x1bOP");
        assert_eq!(key(&mut e, press(F5, 0, "", '\0')), b"\x1b[15~");
        // Bare modifiers and releases produce nothing.
        assert!(key(&mut e, press(SHIFT_LEFT, mods::SHIFT, "", '\0')).is_empty());
        let release = KeyInput {
            action: KeyAction::Release,
            ..press(KEY_A, 0, "a", 'a')
        };
        assert!(key(&mut e, release).is_empty());
    }

    #[test]
    fn ctrl_and_alt_combinations() {
        let mut e = engine();
        // macOS hands Flutter "\x03" for Ctrl+C; the key code decides.
        assert_eq!(key(&mut e, press(KEY_C, mods::CTRL, "\x03", 'c')), [0x03]);
        assert_eq!(key(&mut e, press(KEY_C, mods::CTRL, "", 'c')), [0x03]);
        e.set_option_as_alt(true);
        assert_eq!(key(&mut e, press(KEY_X, mods::ALT, "x", 'x')), b"\x1bx");
        assert_eq!(
            key(&mut e, press(ARROW_UP, mods::SHIFT | mods::ALT, "", '\0')),
            b"\x1b[1;4A"
        );
    }

    #[test]
    fn cursor_keys_follow_decckm() {
        let mut e = engine();
        assert_eq!(key(&mut e, press(ARROW_UP, 0, "", '\0')), b"\x1b[A");
        e.feed(b"\x1b[?1h");
        assert_eq!(key(&mut e, press(ARROW_UP, 0, "", '\0')), b"\x1bOA");
        e.feed(b"\x1b[?1l");
        assert_eq!(key(&mut e, press(ARROW_UP, 0, "", '\0')), b"\x1b[A");
    }

    #[test]
    fn kitty_keyboard_protocol_when_the_program_asks() {
        let mut e = engine();
        e.feed(b"\x1b[>1u"); // push: disambiguate escape codes
        assert_eq!(e.input_modes().kitty_flags, 1);
        assert_eq!(key(&mut e, press(ESCAPE, 0, "", '\0')), b"\x1b[27u");
        assert_eq!(
            key(&mut e, press(KEY_C, mods::CTRL, "", 'c')),
            b"\x1b[99;5u"
        );
        // Plain text stays text under "disambiguate".
        assert_eq!(key(&mut e, press(KEY_A, 0, "a", 'a')), b"a");
        assert_eq!(e.encode_text("é"), "é".as_bytes());

        e.feed(b"\x1b[>9u"); // + report all keys as escape codes
        assert!(e.input_modes().report_all_keys());
        assert_eq!(key(&mut e, press(KEY_A, 0, "a", 'a')), b"\x1b[97u");
        e.feed(b"\x1b[<u\x1b[<u"); // pop both
        assert_eq!(e.input_modes().kitty_flags, 0);
        assert_eq!(key(&mut e, press(ESCAPE, 0, "", '\0')), b"\x1b");
    }

    #[test]
    fn committed_text_turns_newlines_into_enter() {
        let mut e = engine();
        assert_eq!(e.encode_text("ls -la\n"), b"ls -la\r");
        assert_eq!(e.encode_text("日本語"), "日本語".as_bytes());
        assert_eq!(e.encode_text("a\x1b[31mb"), b"a[31mb");
    }

    #[test]
    fn mouse_is_reported_only_when_tracked_in_sgr() {
        let mut e = engine();
        e.set_cell_pixels(10.0, 20.0);
        let at = |action, button, col: f32, row: f32| MouseInput {
            action,
            button,
            mods: 0,
            x: col * 10.0 + 2.0,
            y: row * 20.0 + 2.0,
        };
        assert!(
            e.encode_mouse(&at(MouseAction::Press, MouseButton::Left, 2.0, 3.0))
                .is_empty()
        );
        e.encode_mouse(&at(MouseAction::Release, MouseButton::Left, 2.0, 3.0));

        e.feed(b"\x1b[?1000h\x1b[?1006h");
        assert!(e.input_modes().mouse_tracking);
        assert_eq!(
            e.encode_mouse(&at(MouseAction::Press, MouseButton::Left, 2.0, 3.0)),
            b"\x1b[<0;3;4M"
        );
        assert_eq!(
            e.encode_mouse(&at(MouseAction::Release, MouseButton::Left, 2.0, 3.0)),
            b"\x1b[<0;3;4m"
        );
        // Normal tracking (1000) does not report motion.
        assert!(
            e.encode_mouse(&at(MouseAction::Motion, MouseButton::None, 5.0, 3.0))
                .is_empty()
        );
    }

    #[test]
    fn drags_carry_the_held_button_in_button_event_mode() {
        let mut e = engine();
        e.set_cell_pixels(10.0, 20.0);
        e.feed(b"\x1b[?1002h\x1b[?1006h");
        let at = |action, button, col: f32| MouseInput {
            action,
            button,
            mods: 0,
            x: col * 10.0 + 1.0,
            y: 1.0,
        };
        e.encode_mouse(&at(MouseAction::Press, MouseButton::Left, 0.0));
        assert_eq!(
            e.encode_mouse(&at(MouseAction::Motion, MouseButton::None, 1.0)),
            b"\x1b[<32;2;1M"
        );
        // Same cell again: deduplicated.
        assert!(
            e.encode_mouse(&at(MouseAction::Motion, MouseButton::None, 1.2))
                .is_empty()
        );
        e.encode_mouse(&at(MouseAction::Release, MouseButton::Left, 1.0));
        // Without a held button, 1002 drops motion.
        assert!(
            e.encode_mouse(&at(MouseAction::Motion, MouseButton::None, 4.0))
                .is_empty()
        );
    }

    #[test]
    fn fractional_cells_map_to_the_right_column() {
        let mut e = engine();
        e.set_cell_pixels(8.4, 17.3);
        e.feed(b"\x1b[?1000h\x1b[?1006h");
        let m = MouseInput {
            action: MouseAction::Press,
            button: MouseButton::Left,
            mods: 0,
            x: 8.4 * 150.0 + 0.5,
            y: 17.3 * 40.0 + 0.5,
        };
        assert_eq!(e.encode_mouse(&m), b"\x1b[<0;151;41M");
    }

    #[test]
    fn wheel_goes_to_the_program_or_the_scrollback() {
        let mut e = engine();
        e.set_cell_pixels(10.0, 20.0);
        // Primary screen, no tracking: the UI scrolls history.
        assert_eq!(e.wheel(3, 15.0, 25.0, 0), None);
        // Full-screen program without mouse support: arrow keys.
        e.feed(b"\x1b[?1049h\x1b[?1007h");
        assert_eq!(e.wheel(2, 15.0, 25.0, 0), Some(b"\x1b[A\x1b[A".to_vec()));
        assert_eq!(e.wheel(-1, 15.0, 25.0, 0), Some(b"\x1b[B".to_vec()));
        // Mouse tracking: wheel buttons 64/65.
        e.feed(b"\x1b[?1000h\x1b[?1006h");
        assert_eq!(e.wheel(1, 15.0, 25.0, 0), Some(b"\x1b[<64;2;2M".to_vec()));
        assert_eq!(e.wheel(-1, 15.0, 25.0, 0), Some(b"\x1b[<65;2;2M".to_vec()));
    }

    #[test]
    fn paste_follows_bracketed_mode_and_flags_unsafe_text() {
        let mut e = engine();
        assert_eq!(
            e.encode_paste("echo hi", false),
            Paste::Bytes(b"echo hi".to_vec())
        );
        assert_eq!(e.encode_paste("rm -rf x\n", false), Paste::Unsafe);
        assert_eq!(e.encode_paste("a\nb", true), Paste::Bytes(b"a\rb".to_vec()));

        e.feed(b"\x1b[?2004h");
        assert!(e.input_modes().bracketed_paste);
        assert_eq!(
            e.encode_paste("a\nb", false),
            Paste::Bytes(b"\x1b[200~a\nb\x1b[201~".to_vec())
        );
        assert_eq!(e.encode_paste("x\x1b[201~y", false), Paste::Unsafe);
        // Nothing leaks into the host-write queue.
        assert!(e.take_host_writes().is_empty());
    }

    #[test]
    fn focus_reports_only_when_enabled() {
        let mut e = engine();
        assert!(e.encode_focus(true).is_empty());
        e.feed(b"\x1b[?1004h");
        assert_eq!(e.encode_focus(true), b"\x1b[I");
        assert_eq!(e.encode_focus(false), b"\x1b[O");
    }
}
