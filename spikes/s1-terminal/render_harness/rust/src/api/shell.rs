//! Interactive session for spike S1.5: keyboard, IME, paste and mouse into
//! a real program, encoded by libghostty-vt.
//!
//! Two backends:
//! - a shell on a local pty (desktop; Android has /system/bin/sh), and
//! - a key log, which prints the bytes each input produced. It works on
//!   every platform (iOS has no local shell) and is how the manual input
//!   checklist verifies the encoding.

use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread;

use flutter_rust_bridge::frb;
use ghostty_engine::{
    GhosttyEngine, KeyAction, KeyInput, MouseAction, MouseButton, MouseInput, Paste,
};
use openward_term::{FrameEncoder, Size, TermEngine};
use portable_pty::{Child, CommandBuilder, MasterPty, PtySize, native_pty_system};

use super::term::now_micros;

/// The key log backend's program name for [`create_shell`].
pub const KEY_LOG: &str = "keylog";

#[derive(Clone, Copy, Debug)]
pub enum KeyKind {
    Down,
    Repeat,
    Up,
}

#[derive(Clone, Copy, Debug)]
pub enum PointerAction {
    Down,
    Up,
    Move,
}

#[derive(Clone, Copy, Debug)]
pub enum PointerButton {
    None,
    Left,
    Middle,
    Right,
}

/// Damage since the previous poll, plus what the UI needs to route input.
pub struct ShellFrame {
    /// Damage frame v1 (`openward-term` frame.rs).
    pub frame: Vec<u8>,
    /// The program tracks the mouse: clicks and wheel go to it.
    pub mouse_tracking: bool,
    pub bracketed_paste: bool,
    /// Kitty "report all keys": printable keys go through [`ShellSession::key`].
    pub report_all_keys: bool,
    pub alt_screen: bool,
    pub title: String,
    pub exited: bool,
    /// When the input this frame first echoes was sent (`now_micros`
    /// clock), for key-to-paint latency; 0 if none.
    pub input_micros: u64,
}

struct ShellState {
    engine: GhosttyEngine,
    enc: FrameEncoder,
    dirty: bool,
    /// First input sent since the program last produced output.
    awaiting_echo: Option<u64>,
    /// Input whose echo has arrived but not been painted yet.
    echoed: Option<u64>,
}

enum Sink {
    Pty(Box<dyn Write + Send>),
    KeyLog,
}

#[frb(opaque)]
pub struct ShellSession {
    state: Arc<Mutex<ShellState>>,
    sink: Arc<Mutex<Sink>>,
    exited: Arc<AtomicBool>,
    // Mutex: the opaque type must be Sync, MasterPty is only Send.
    master: Option<Mutex<Box<dyn MasterPty + Send>>>,
    child: Option<Box<dyn Child + Send + Sync>>,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// Starts `program` ("" for the user's login shell, [`KEY_LOG`] for the key
/// log) on a `cols`×`rows` terminal.
pub fn create_shell(
    program: String,
    cols: u16,
    rows: u16,
    scrollback: u32,
) -> anyhow::Result<ShellSession> {
    let state = Arc::new(Mutex::new(ShellState {
        engine: GhosttyEngine::new(Size::new(cols, rows), scrollback as usize),
        enc: FrameEncoder::new(),
        dirty: true,
        awaiting_echo: None,
        echoed: None,
    }));
    let exited = Arc::new(AtomicBool::new(false));
    if program == KEY_LOG {
        lock(&state).engine.feed(KEY_LOG_BANNER.as_bytes());
        return Ok(ShellSession {
            state,
            sink: Arc::new(Mutex::new(Sink::KeyLog)),
            exited,
            master: None,
            child: None,
        });
    }

    let pair = native_pty_system().openpty(PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    })?;
    let program = if program.is_empty() {
        std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".into())
    } else {
        program
    };
    let mut cmd = CommandBuilder::new(&program);
    cmd.arg("-l");
    cmd.env("TERM", "xterm-256color");
    cmd.env("COLORTERM", "truecolor");
    cmd.env("TERM_PROGRAM", "openward-s1");
    // Apps started from Finder or the IDE often have no locale.
    if std::env::var_os("LANG").is_none() {
        cmd.env("LANG", "en_US.UTF-8");
    }
    if let Some(home) = std::env::var_os("HOME") {
        cmd.cwd(home);
    }
    let child = pair.slave.spawn_command(cmd)?;
    drop(pair.slave);
    let mut reader = pair.master.try_clone_reader()?;
    let sink = Arc::new(Mutex::new(Sink::Pty(pair.master.take_writer()?)));

    let (state2, sink2, exited2) = (Arc::clone(&state), Arc::clone(&sink), Arc::clone(&exited));
    thread::Builder::new()
        .name("s1-pty-reader".into())
        .spawn(move || {
            let mut buf = vec![0u8; 64 * 1024];
            loop {
                let n = match reader.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => n,
                };
                let replies = {
                    let mut s = lock(&state2);
                    s.engine.feed(&buf[..n]);
                    s.dirty = true;
                    if let Some(t) = s.awaiting_echo.take() {
                        s.echoed.get_or_insert(t);
                    }
                    s.engine.take_host_writes()
                };
                // Replies to the program's queries (DA, DSR, ...).
                if !replies.is_empty() {
                    write_sink(&sink2, &replies);
                }
            }
            exited2.store(true, Ordering::SeqCst);
            lock(&state2).dirty = true;
        })?;

    Ok(ShellSession {
        state,
        sink,
        exited,
        master: Some(Mutex::new(pair.master)),
        child: Some(child),
    })
}

/// `now_micros`, never 0 (0 means "no input" in [`ShellFrame`]).
fn input_time() -> u64 {
    now_micros().max(1)
}

fn write_sink(sink: &Mutex<Sink>, bytes: &[u8]) {
    if let Sink::Pty(w) = &mut *lock(sink) {
        // A dead child is reported by the reader thread; nothing to do here.
        let _ = w.write_all(bytes).and_then(|_| w.flush());
    }
}

const KEY_LOG_BANNER: &str = "\x1b[1mOpenWard S1.5 · registro de teclas\x1b[0m\r\n\
\x1b[2mCada entrada muestra los bytes que enviaría al programa. \
␛ = ESC, ^X = control.\x1b[0m\r\n\r\n";

/// One input chunk as a readable line: printable text as is, ESC as ␛,
/// other control bytes in caret notation.
fn describe(bytes: &[u8]) -> String {
    let mut out = String::from("\x1b[36m→\x1b[0m ");
    for chunk in bytes.utf8_chunks() {
        for c in chunk.valid().chars() {
            match c {
                '\x1b' => out.push_str("\x1b[33m␛\x1b[0m"),
                '\x7f' => out.push_str("\x1b[33m^?\x1b[0m"),
                c if (c as u32) < 0x20 => {
                    out.push_str("\x1b[33m^");
                    out.push(char::from(b'@' + c as u8));
                    out.push_str("\x1b[0m");
                }
                c => out.push(c),
            }
        }
        for b in chunk.invalid() {
            out.push_str(&format!("\x1b[31m\\x{b:02x}\x1b[0m"));
        }
    }
    out.push_str(&format!("  \x1b[2m({} B)\x1b[0m\r\n", bytes.len()));
    out
}

impl ShellSession {
    fn send(&self, bytes: Vec<u8>) -> bool {
        if bytes.is_empty() {
            return false;
        }
        match &mut *lock(&self.sink) {
            Sink::Pty(w) => {
                {
                    let mut s = lock(&self.state);
                    s.engine.scroll_to_bottom();
                    s.awaiting_echo.get_or_insert(input_time());
                }
                let _ = w.write_all(&bytes).and_then(|_| w.flush());
            }
            Sink::KeyLog => {
                let mut s = lock(&self.state);
                s.engine.scroll_to_bottom();
                s.echoed.get_or_insert(input_time());
                s.engine.feed(describe(&bytes).as_bytes());
                s.engine.take_host_writes();
                s.dirty = true;
            }
        }
        true
    }

    /// Everything that changed since the last call, or `None` if nothing did.
    #[frb(sync)]
    pub fn poll(&self) -> Option<ShellFrame> {
        let mut s = lock(&self.state);
        if !s.dirty {
            return None;
        }
        s.dirty = false;
        let ShellState {
            engine,
            enc,
            echoed,
            ..
        } = &mut *s;
        engine.encode_damage(enc);
        let modes = engine.input_modes();
        Some(ShellFrame {
            frame: enc.bytes().to_vec(),
            mouse_tracking: modes.mouse_tracking,
            bracketed_paste: modes.bracketed_paste,
            report_all_keys: modes.report_all_keys(),
            alt_screen: modes.alt_screen,
            title: engine.title().unwrap_or_default(),
            exited: self.exited.load(Ordering::SeqCst),
            input_micros: echoed.take().unwrap_or(0),
        })
    }

    /// A key event; returns whether it produced any bytes.
    #[frb(sync)]
    pub fn key(
        &self,
        hid_usage: u32,
        kind: KeyKind,
        mods: u16,
        text: String,
        unshifted: u32,
    ) -> bool {
        let key = KeyInput {
            hid_usage,
            action: match kind {
                KeyKind::Down => KeyAction::Press,
                KeyKind::Repeat => KeyAction::Repeat,
                KeyKind::Up => KeyAction::Release,
            },
            mods,
            text,
            unshifted,
        };
        let bytes = lock(&self.state).engine.encode_key(&key);
        self.send(bytes)
    }

    /// Text committed by an IME or a soft keyboard.
    #[frb(sync)]
    pub fn text(&self, text: String) {
        let bytes = lock(&self.state).engine.encode_text(&text);
        self.send(bytes);
    }

    /// Pastes `text`. Returns false, sending nothing, when it could run
    /// commands; ask the user and call again with `allow_unsafe`.
    #[frb(sync)]
    pub fn paste(&self, text: String, allow_unsafe: bool) -> bool {
        let result = lock(&self.state).engine.encode_paste(&text, allow_unsafe);
        match result {
            Paste::Bytes(bytes) => {
                self.send(bytes);
                true
            }
            Paste::Unsafe => false,
        }
    }

    #[frb(sync)]
    pub fn pointer(&self, action: PointerAction, button: PointerButton, mods: u16, x: f32, y: f32) {
        let m = MouseInput {
            action: match action {
                PointerAction::Down => MouseAction::Press,
                PointerAction::Up => MouseAction::Release,
                PointerAction::Move => MouseAction::Motion,
            },
            button: match button {
                PointerButton::None => MouseButton::None,
                PointerButton::Left => MouseButton::Left,
                PointerButton::Middle => MouseButton::Middle,
                PointerButton::Right => MouseButton::Right,
            },
            mods,
            x,
            y,
        };
        let bytes = lock(&self.state).engine.encode_mouse(&m);
        self.send(bytes);
    }

    /// Wheel or touch scroll, `lines` notches (positive = up). Goes to the
    /// program if it wants it, otherwise scrolls the history.
    #[frb(sync)]
    pub fn wheel(&self, lines: i32, x: f32, y: f32, mods: u16) {
        let mut s = lock(&self.state);
        match s.engine.wheel(lines, x, y, mods) {
            Some(bytes) => {
                drop(s);
                self.send(bytes);
            }
            None => {
                s.engine.scroll_display(lines);
                s.dirty = true;
            }
        }
    }

    #[frb(sync)]
    pub fn focus(&self, gained: bool) {
        let bytes = lock(&self.state).engine.encode_focus(gained);
        self.send(bytes);
    }

    #[frb(sync)]
    pub fn resize(&self, cols: u16, rows: u16) {
        {
            let mut s = lock(&self.state);
            if s.engine.size() == Size::new(cols, rows) {
                return;
            }
            s.engine.resize(Size::new(cols, rows));
            s.dirty = true;
        }
        if let Some(master) = &self.master {
            let _ = lock(master).resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            });
        }
    }

    /// Cell size in the logical pixels pointer positions use.
    #[frb(sync)]
    pub fn set_cell_pixels(&self, width: f32, height: f32) {
        lock(&self.state).engine.set_cell_pixels(width, height);
    }

    /// macOS: Option sends Alt (ESC-prefixed) instead of typing symbols.
    #[frb(sync)]
    pub fn set_option_as_alt(&self, enabled: bool) {
        lock(&self.state).engine.set_option_as_alt(enabled);
    }

    /// Feeds `bytes` as if the program had written them; the key log uses
    /// it to switch input modes (DECCKM, kitty flags, mouse, paste).
    #[frb(sync)]
    pub fn inject(&self, bytes: Vec<u8>) {
        let mut s = lock(&self.state);
        s.engine.feed(&bytes);
        s.engine.take_host_writes();
        s.dirty = true;
    }

    #[frb(sync)]
    pub fn screen_text(&self) -> String {
        lock(&self.state).engine.screen_text()
    }
}

impl Drop for ShellSession {
    fn drop(&mut self) {
        if let Some(child) = &mut self.child {
            let _ = child.kill();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn describes_control_bytes_readably() {
        let s = describe(b"\x1b[A\x03a\x7f");
        assert!(s.contains("␛\x1b[0m[A"));
        assert!(s.contains("^C"));
        assert!(s.contains("^?"));
        assert!(s.contains("(6 B)"));
    }

    #[test]
    fn key_log_shows_encoded_keys() {
        let s = create_shell(KEY_LOG.into(), 80, 24, 100).unwrap();
        // Arrow up, then again with DECCKM set.
        assert!(s.key(0x0007_0052, KeyKind::Down, 0, String::new(), 0));
        s.inject(b"\x1b[?1h".to_vec());
        assert!(s.key(0x0007_0052, KeyKind::Down, 0, String::new(), 0));
        let text = s.screen_text();
        assert!(text.contains("→ ␛[A"), "{text}");
        assert!(text.contains("→ ␛OA"), "{text}");
        let frame = s.poll().expect("dirty after input");
        assert!(frame.input_micros > 0);
        assert!(s.poll().is_none());
    }

    #[test]
    fn unsafe_paste_needs_confirmation() {
        let s = create_shell(KEY_LOG.into(), 80, 24, 100).unwrap();
        assert!(!s.paste("rm -rf /tmp/x\n".into(), false));
        assert!(s.paste("rm -rf /tmp/x\n".into(), true));
        assert!(s.screen_text().contains("→ rm -rf /tmp/x^M"));
    }

    #[cfg(unix)]
    #[test]
    fn a_real_shell_echoes_what_is_typed() {
        let s = create_shell("/bin/sh".into(), 80, 24, 100).unwrap();
        s.text("echo s1-$((40+2))\n".into());
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while !s.screen_text().contains("s1-42") {
            assert!(std::time::Instant::now() < deadline, "{}", s.screen_text());
            thread::sleep(std::time::Duration::from_millis(20));
        }
    }
}
