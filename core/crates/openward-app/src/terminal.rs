//! A terminal: the engine's state, the program behind it (a remote shell or
//! a local one), and the input and frames the UI exchanges with it.
//!
//! The UI pulls damage frames once per refresh with [`Terminal::poll`] and
//! sends input with the other methods; output from the program feeds the
//! engine from a background thread or task. The engine outlives the
//! connection, so a reconnect continues on the same screen.

use std::io::Read;
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread;

use openward_ghostty::{
    GhosttyEngine, KeyAction, KeyInput, MouseAction, MouseButton, MouseInput, Paste,
};
use openward_pty::{Pty, Spawn};
use openward_ssh::russh::ChannelMsg;
use openward_ssh::russh::client::Msg;
use openward_term::{FrameEncoder, Size, TermEngine};
use tokio::io::AsyncWriteExt;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;

use crate::events::{Event, EventSink, Failure};

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

/// Damage since the previous poll, and what the UI needs to route input.
pub struct Frame {
    /// Damage frame v1 (`openward-term`, frame.rs).
    pub frame: Vec<u8>,
    /// The program follows the mouse: clicks and wheel go to it.
    pub mouse_tracking: bool,
    pub bracketed_paste: bool,
    /// Kitty "report all keys": printable keys go through [`Terminal::key`].
    pub report_all_keys: bool,
    pub alt_screen: bool,
    pub title: String,
}

struct State {
    engine: GhosttyEngine,
    enc: FrameEncoder,
    dirty: bool,
}

enum Io {
    /// Not connected (yet, or any more): input goes nowhere.
    None,
    Pty(Arc<Pty>),
    Ssh(mpsc::UnboundedSender<SshCmd>),
}

pub(crate) enum SshCmd {
    Data(Vec<u8>),
    Resize(u16, u16),
}

pub struct Terminal {
    state: Arc<Mutex<State>>,
    io: Arc<Mutex<Io>>,
    /// The connection task; aborting it drops the SSH sessions.
    task: Mutex<Option<JoinHandle<()>>>,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

impl Terminal {
    pub fn new(cols: u16, rows: u16, scrollback: usize) -> Arc<Self> {
        Arc::new(Self {
            state: Arc::new(Mutex::new(State {
                engine: GhosttyEngine::new(Size::new(cols, rows), scrollback),
                enc: FrameEncoder::new(),
                dirty: true,
            })),
            io: Arc::new(Mutex::new(Io::None)),
            task: Mutex::new(None),
        })
    }

    pub fn size(&self) -> Size {
        lock(&self.state).engine.size()
    }

    /// Output from the program; replies to its queries go straight back.
    fn output(state: &Mutex<State>, bytes: &[u8]) -> Vec<u8> {
        let mut s = lock(state);
        s.engine.feed(bytes);
        s.dirty = true;
        s.engine.take_host_writes()
    }

    /// Starts a local program and pipes it in.
    pub(crate) fn attach_pty(
        self: &Arc<Self>,
        spawn: Spawn,
        sink: Arc<dyn EventSink>,
    ) -> anyhow::Result<()> {
        let (pty, mut reader) = Pty::spawn(&spawn)?;
        let pty = Arc::new(pty);
        *lock(&self.io) = Io::Pty(Arc::clone(&pty));
        sink.send(Event::Started {
            program: spawn
                .program
                .clone()
                .unwrap_or_else(openward_pty::default_shell),
        });
        let state = Arc::clone(&self.state);
        thread::Builder::new()
            .name("openward-pty".into())
            .spawn(move || {
                let mut buf = vec![0u8; 64 * 1024];
                loop {
                    let n = match reader.read(&mut buf) {
                        Ok(0) | Err(_) => break,
                        Ok(n) => n,
                    };
                    let replies = Self::output(&state, &buf[..n]);
                    if !replies.is_empty() {
                        let _ = pty.write(&replies);
                    }
                }
                lock(&state).dirty = true;
                // EOF can come a moment before the program is reaped.
                let mut exit_code = pty.exit_code();
                for _ in 0..50 {
                    if exit_code.is_some() {
                        break;
                    }
                    thread::sleep(std::time::Duration::from_millis(20));
                    exit_code = pty.exit_code();
                }
                sink.send(Event::Closed {
                    exit_code,
                    failure: None,
                });
            })?;
        Ok(())
    }

    /// What a connection task needs to feed this terminal, without
    /// keeping the terminal itself alive: dropping it ends the task.
    pub(crate) fn pipe(&self) -> Pipe {
        Pipe {
            state: Arc::clone(&self.state),
            io: Arc::clone(&self.io),
        }
    }

    pub(crate) fn set_task(&self, task: JoinHandle<()>) {
        if let Some(old) = lock(&self.task).replace(task) {
            old.abort();
        }
    }

    /// Ends the connection or the local program. The screen stays.
    pub fn close(&self) {
        if let Some(task) = lock(&self.task).take() {
            task.abort();
        }
        if let Io::Pty(pty) = std::mem::replace(&mut *lock(&self.io), Io::None) {
            pty.kill();
        }
    }

    fn send(&self, bytes: Vec<u8>) -> bool {
        if bytes.is_empty() {
            return false;
        }
        lock(&self.state).engine.scroll_to_bottom();
        match &*lock(&self.io) {
            Io::Pty(pty) => pty.write(&bytes).is_ok(),
            Io::Ssh(tx) => tx.send(SshCmd::Data(bytes)).is_ok(),
            Io::None => false,
        }
    }

    /// Everything that changed since the last call, or `None` if nothing did.
    pub fn poll(&self) -> Option<Frame> {
        let mut s = lock(&self.state);
        if !s.dirty {
            return None;
        }
        s.dirty = false;
        let State { engine, enc, .. } = &mut *s;
        engine.encode_damage(enc);
        let modes = engine.input_modes();
        Some(Frame {
            frame: enc.bytes().to_vec(),
            mouse_tracking: modes.mouse_tracking,
            bracketed_paste: modes.bracketed_paste,
            report_all_keys: modes.report_all_keys(),
            alt_screen: modes.alt_screen,
            title: engine.title().unwrap_or_default(),
        })
    }

    /// A key event; returns whether it produced any bytes.
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

    /// Text committed by an input method or a soft keyboard.
    pub fn text(&self, text: &str) {
        let bytes = lock(&self.state).engine.encode_text(text);
        self.send(bytes);
    }

    /// Pastes `text`. Returns false, sending nothing, when it could run
    /// commands: ask the user and call again with `allow_unsafe`.
    pub fn paste(&self, text: &str, allow_unsafe: bool) -> bool {
        let result = lock(&self.state).engine.encode_paste(text, allow_unsafe);
        match result {
            Paste::Bytes(bytes) => {
                self.send(bytes);
                true
            }
            Paste::Unsafe => false,
        }
    }

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

    pub fn focus(&self, gained: bool) {
        let bytes = lock(&self.state).engine.encode_focus(gained);
        self.send(bytes);
    }

    pub fn resize(&self, cols: u16, rows: u16) {
        {
            let mut s = lock(&self.state);
            if s.engine.size() == Size::new(cols, rows) {
                return;
            }
            s.engine.resize(Size::new(cols, rows));
            s.dirty = true;
        }
        match &*lock(&self.io) {
            Io::Pty(pty) => {
                let _ = pty.resize(cols, rows);
            }
            Io::Ssh(tx) => {
                let _ = tx.send(SshCmd::Resize(cols, rows));
            }
            Io::None => {}
        }
    }

    /// Cell size in the logical pixels pointer positions use.
    pub fn set_cell_pixels(&self, width: f32, height: f32) {
        lock(&self.state).engine.set_cell_pixels(width, height);
    }

    /// macOS: Option sends Alt (ESC-prefixed) instead of typing symbols.
    pub fn set_option_as_alt(&self, enabled: bool) {
        lock(&self.state).engine.set_option_as_alt(enabled);
    }

    pub fn screen_text(&self) -> String {
        lock(&self.state).engine.screen_text()
    }
}

/// A terminal's state and input side, for the task that feeds it.
pub(crate) struct Pipe {
    state: Arc<Mutex<State>>,
    io: Arc<Mutex<Io>>,
}

impl Pipe {
    pub(crate) fn size(&self) -> Size {
        lock(&self.state).engine.size()
    }

    /// Pumps an open shell channel until it closes; returns its exit code,
    /// or the failure if the connection broke.
    pub(crate) async fn pump_ssh(
        &self,
        channel: openward_ssh::russh::Channel<Msg>,
        label: &str,
    ) -> (Option<u32>, Option<Failure>) {
        let (tx, mut rx) = mpsc::unbounded_channel::<SshCmd>();
        *lock(&self.io) = Io::Ssh(tx.clone());
        let (mut read, write) = channel.split();
        let writer = async move {
            let mut w = write.make_writer();
            while let Some(cmd) = rx.recv().await {
                match cmd {
                    SshCmd::Data(bytes) => {
                        if w.write_all(&bytes).await.is_err() || w.flush().await.is_err() {
                            break;
                        }
                    }
                    SshCmd::Resize(c, r) => {
                        let _ = write.window_change(u32::from(c), u32::from(r), 0, 0).await;
                    }
                }
            }
        };
        let state = Arc::clone(&self.state);
        let reader = async move {
            let mut exit = None;
            let mut ended = false;
            while let Some(msg) = read.wait().await {
                match msg {
                    ChannelMsg::Data { data } | ChannelMsg::ExtendedData { data, .. } => {
                        let replies = Terminal::output(&state, &data);
                        if !replies.is_empty() {
                            let _ = tx.send(SshCmd::Data(replies));
                        }
                    }
                    ChannelMsg::ExitStatus { exit_status } => {
                        exit = Some(exit_status);
                        ended = true;
                    }
                    ChannelMsg::ExitSignal { .. } | ChannelMsg::Eof => ended = true,
                    ChannelMsg::Close => {
                        ended = true;
                        break;
                    }
                    _ => {}
                }
            }
            (exit, ended)
        };
        // The writer ends when the reader drops the last sender.
        let ((exit, ended), ()) = tokio::join!(
            async {
                let r = reader.await;
                *lock(&self.io) = Io::None;
                r
            },
            writer
        );
        lock(&self.state).dirty = true;
        let failure = (!ended).then(|| Failure::Network {
            label: label.to_owned(),
            message: "connection lost".into(),
        });
        (exit, failure)
    }
}

impl Drop for Terminal {
    fn drop(&mut self) {
        self.close();
    }
}
