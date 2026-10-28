//! A terminal: the engine's state, the program behind it (a remote shell or
//! a local one), and the input and frames the UI exchanges with it.
//!
//! The UI pulls damage frames with [`Terminal::poll`], once per refresh
//! while there is something to draw: the waker ([`Terminal::set_waker`])
//! tells it when there is again, so an idle terminal asks for no frames.
//! It sends input with the other methods; output from the program feeds
//! the engine from a background thread or task. The engine outlives the
//! connection, so a reconnect continues on the same screen.

pub use openward_ghostty::OptionAsAlt;
use std::io::Read;
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread;

use openward_ghostty::{
    GhosttyEngine, KeyAction, KeyInput, Link, MouseAction, MouseButton, MouseInput, Paste,
    SearchState, SelectedRow,
};
use openward_pty::{Pty, Spawn};
use openward_ssh::russh::ChannelMsg;
use openward_ssh::russh::client::Msg;
pub use openward_term::CursorShape;
use openward_term::{FrameEncoder, Size, TermEngine};
use tokio::io::AsyncWriteExt;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;

use crate::alive::Activity;
use crate::events::{Event, EventSink, Failure};
use crate::logs::{self, End};

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
    /// DECKPAM: so do the keypad's.
    pub keypad_application: bool,
    /// What the program set for itself over the theme (OSC 10, 11, 12);
    /// its palette changes come painted in the frame.
    pub program_foreground: Option<[u8; 3]>,
    pub program_background: Option<[u8; 3]>,
    pub program_cursor: Option<[u8; 3]>,
    pub alt_screen: bool,
    pub title: String,
    /// The selected range of each visible row that has one; empty without
    /// a selection.
    pub selection: Vec<SelectedRow>,
    /// A BEL arrived since the last poll.
    pub bell: bool,
    pub cursor_blinks: bool,
    /// The find bar's search and its matches on screen, while it is open.
    pub search: Option<SearchState>,
}

/// Called when the screen changes after the UI last looked.
pub type Waker = Arc<dyn Fn() + Send + Sync>;

/// A terminal's session log, as its pane shows it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LogState {
    pub id: String,
    /// What comes out is recorded (not only the entry).
    pub recording: bool,
    pub paused: bool,
    /// Writing failed, and why: nothing more is recorded.
    pub failed: Option<String>,
}

struct State {
    engine: GhosttyEngine,
    enc: FrameEncoder,
    dirty: bool,
    /// The waker was called and the UI has not polled since: one call per
    /// look, however much output comes in between.
    notified: bool,
    waker: Option<Waker>,
    /// The session log of the connection going on, if one is kept.
    log: Option<Arc<logs::Session>>,
}

impl State {
    /// Something to draw: tells the UI, once until it looks.
    fn touch(&mut self) {
        self.dirty = true;
        if !self.notified {
            self.notified = true;
            if let Some(wake) = &self.waker {
                wake();
            }
        }
    }
}

enum Io {
    /// Not connected (yet, or any more): input goes nowhere.
    None,
    Pty(Arc<Pty>),
    Ssh(mpsc::Sender<SshCmd>),
}

/// Chunks of output waiting for the parse thread.
const PARSE_QUEUE: usize = 64;

/// Input, resizes and the terminal's answers waiting for the server. A
/// server that stops reading (no window) holds them back; past this many,
/// typing goes nowhere and the parse waits, rather than piling up.
const SEND_QUEUE: usize = 256;

pub(crate) enum SshCmd {
    Data(Vec<u8>),
    Resize(u16, u16),
}

pub struct Terminal {
    state: Arc<Mutex<State>>,
    io: Arc<Mutex<Io>>,
    /// The connection task; aborting it drops the SSH sessions.
    task: Mutex<Option<JoinHandle<()>>>,
    /// When input went out and output came in, for the connection's
    /// watcher.
    activity: Arc<Activity>,
    /// Run when the terminal is closed on purpose: ending a persistent
    /// session on the server.
    closer: Mutex<Option<Box<dyn FnOnce() + Send>>>,
    /// The tmux session of a persistent shell: the same for every
    /// connection of this terminal, so that reconnecting finds it again.
    tmux: Mutex<Option<String>>,
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
                notified: false,
                waker: None,
                log: None,
            })),
            io: Arc::new(Mutex::new(Io::None)),
            task: Mutex::new(None),
            activity: Arc::default(),
            closer: Mutex::new(None),
            tmux: Mutex::new(None),
        })
    }

    /// The name of this terminal's tmux session, made the first time.
    pub(crate) fn tmux_name(&self, make: impl FnOnce() -> String) -> String {
        lock(&self.tmux).get_or_insert_with(make).clone()
    }

    pub fn size(&self) -> Size {
        lock(&self.state).engine.size()
    }

    /// Called (from any thread) when there is something to draw that the
    /// UI has not polled yet. The UI polls, and stops asking for frames
    /// while nothing changes.
    pub fn set_waker(&self, wake: Waker) {
        let mut s = lock(&self.state);
        s.waker = Some(wake);
        s.notified = false;
        if s.dirty {
            s.touch();
        }
    }

    /// Output from the program; replies to its queries go straight back.
    fn output(state: &Mutex<State>, bytes: &[u8]) -> Vec<u8> {
        let mut s = lock(state);
        s.engine.feed(bytes);
        if let Some(log) = &s.log {
            log.output(bytes);
        }
        s.touch();
        s.engine.take_host_writes()
    }

    /// Output that no program sent: a recording played back. Replies to
    /// its queries go nowhere.
    pub(crate) fn feed(&self, bytes: &[u8]) {
        Self::output(&self.state, bytes);
    }

    /// A blank screen of this size, with no history, as a new terminal
    /// starts: where a recording plays again from the start.
    pub(crate) fn reset(&self, cols: u16, rows: u16) {
        Self::output(&self.state, b"\x1bc");
        let mut s = lock(&self.state);
        s.engine.clear_history();
        if s.engine.size() != Size::new(cols, rows) {
            s.engine.resize(Size::new(cols, rows));
        }
        s.engine.redraw();
        s.touch();
    }

    /// Starts keeping the session log of a connection that is up; one that
    /// was kept before ends.
    pub(crate) fn attach_log(&self, log: Arc<logs::Session>) {
        let old = lock(&self.state).log.replace(log);
        if let Some(old) = old {
            old.finish(End::Closed);
        }
    }

    /// Ends the session log, if one is kept, saying how.
    pub(crate) fn end_log(&self, end: End) {
        // Outside the lock: finishing waits for the last write.
        let log = lock(&self.state).log.take();
        if let Some(log) = log {
            log.finish(end);
        }
    }

    /// Stops feeding `log`, if it is the one kept, without ending it.
    pub(crate) fn release_log(&self, log: &Arc<logs::Session>) {
        let mut s = lock(&self.state);
        if s.log.as_ref().is_some_and(|kept| Arc::ptr_eq(kept, log)) {
            s.log = None;
        }
    }

    fn log(&self) -> Option<Arc<logs::Session>> {
        lock(&self.state).log.clone()
    }

    /// A command ran (the UI saw it at Enter): a marker in the recording.
    pub fn log_command(&self, command: &str) {
        if let Some(log) = self.log() {
            log.command(command);
        }
    }

    /// Stops keeping what comes out in the recording, or starts again.
    /// False if there is no recording, or it already was so.
    pub fn pause_log(&self, paused: bool) -> bool {
        self.log().is_some_and(|log| log.pause(paused))
    }

    /// The session log kept now, if any.
    pub fn log_state(&self) -> Option<LogState> {
        self.log().map(|log| LogState {
            id: log.id(),
            recording: log.recording(),
            paused: log.paused(),
            failed: log.failed(),
        })
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
                lock(&state).touch();
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
            activity: Arc::clone(&self.activity),
        }
    }

    /// What closing the terminal on purpose also does (replacing the last).
    pub(crate) fn set_closer(&self, closer: impl FnOnce() + Send + 'static) {
        *lock(&self.closer) = Some(Box::new(closer));
    }

    /// A line of OpenWard's own on the screen, as if output (`\r\n` and
    /// escape sequences included): never sent to the program.
    pub fn note(&self, text: &str) {
        Self::output(&self.state, text.as_bytes());
    }

    pub(crate) fn set_task(&self, task: JoinHandle<()>) {
        if let Some(old) = lock(&self.task).replace(task) {
            old.abort();
        }
    }

    /// Ends the connection or the local program for good, a persistent
    /// session on the server too. The screen stays.
    pub fn close(&self) {
        self.end_log(End::Closed);
        if let Some(closer) = lock(&self.closer).take() {
            closer();
        }
        self.detach();
    }

    /// Drops the connection or the local program, leaving a persistent
    /// session on the server to be found again: what reconnecting does.
    pub(crate) fn detach(&self) {
        lock(&self.closer).take();
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
        {
            // Typing goes back to the live screen and drops the selection,
            // as in Ghostty.
            let mut s = lock(&self.state);
            s.engine.scroll_to_bottom();
            if s.engine.has_selection() {
                s.engine.clear_selection();
                s.touch();
            }
        }
        match &*lock(&self.io) {
            Io::Pty(pty) => pty.write(&bytes).is_ok(),
            Io::Ssh(tx) => tx.try_send(SshCmd::Data(bytes)).is_ok(),
            Io::None => false,
        }
    }

    /// Everything that changed since the last call, or `None` if nothing did.
    pub fn poll(&self) -> Option<Frame> {
        let mut s = lock(&self.state);
        s.notified = false;
        if !s.dirty {
            return None;
        }
        s.dirty = false;
        let State { engine, enc, .. } = &mut *s;
        engine.encode_damage(enc);
        let modes = engine.input_modes();
        let search = engine.search_state();
        // A search still going through the history goes on with the next
        // frame: the UI keeps polling while there is something to draw.
        s.dirty = search.as_ref().is_some_and(|st| st.searching);
        let State { engine, enc, .. } = &mut *s;
        Some(Frame {
            frame: enc.bytes().to_vec(),
            mouse_tracking: modes.mouse_tracking,
            bracketed_paste: modes.bracketed_paste,
            report_all_keys: modes.report_all_keys(),
            keypad_application: modes.keypad_application,
            program_foreground: engine.program_colors().foreground,
            program_background: engine.program_colors().background,
            program_cursor: engine.program_colors().cursor,
            alt_screen: modes.alt_screen,
            title: engine.title().unwrap_or_default(),
            selection: engine.selected_rows(),
            bell: engine.take_bell(),
            cursor_blinks: engine.cursor_blinks(),
            search,
        })
    }

    /// Compresses the history a step at a time, letting output and the UI
    /// in between: for a terminal that has been quiet for a while.
    pub fn compress_history(&self) {
        while lock(&self.state).engine.compress_step() {}
    }

    /// The title and whether a bell rang, without the screen: what a
    /// hidden tab needs. The damage stays for when it shows.
    pub fn poll_meta(&self) -> (String, bool) {
        let mut s = lock(&self.state);
        s.notified = false;
        (s.engine.title().unwrap_or_default(), s.engine.take_bell())
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
                s.touch();
            }
        }
    }

    /// Scrolls the history, whatever the program wants of the wheel: for
    /// a selection dragged past an edge, which is not the program's.
    pub fn scroll_history(&self, lines: i32) {
        let mut s = lock(&self.state);
        s.engine.scroll_display(lines);
        s.touch();
    }

    /// Forgets what scrolled above the screen; the program is not told.
    pub fn clear_history(&self) {
        let mut s = lock(&self.state);
        s.engine.clear_history();
        s.touch();
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
            if let Some(log) = &s.log {
                log.resize(cols, rows);
            }
            s.touch();
        }
        match &*lock(&self.io) {
            Io::Pty(pty) => {
                let _ = pty.resize(cols, rows);
            }
            Io::Ssh(tx) => {
                let _ = tx.try_send(SshCmd::Resize(cols, rows));
            }
            Io::None => {}
        }
    }

    /// Cell size in the logical pixels pointer positions use.
    pub fn set_cell_pixels(&self, width: f32, height: f32) {
        lock(&self.state).engine.set_cell_pixels(width, height);
    }

    /// macOS: Option sends Alt (ESC-prefixed) instead of typing symbols.
    pub fn set_option_as_alt(&self, which: OptionAsAlt) {
        lock(&self.state).engine.set_option_as_alt(which);
    }

    pub fn screen_text(&self) -> String {
        lock(&self.state).engine.screen_text()
    }

    /// The cursor's cell (row, column) while the live screen is on view.
    pub fn cursor_cell(&self) -> Option<(u16, u16)> {
        lock(&self.state).engine.cursor_cell()
    }

    /// What was typed at a prompt that began at `start`, and what follows
    /// the cursor on its row.
    pub fn typed_since(&self, start: (u16, u16)) -> Option<(String, String)> {
        lock(&self.state).engine.typed_since(start)
    }

    fn select(&self, change: impl FnOnce(&mut GhosttyEngine)) {
        let mut s = lock(&self.state);
        change(&mut s.engine);
        s.touch();
    }

    /// Selection with the mouse, in logical pixels: press, drag (a block
    /// with `rectangle`) and release. Two and three quick presses select a
    /// word and a line.
    pub fn select_press(&self, x: f32, y: f32) {
        self.select(|e| e.select_press(x, y));
    }

    pub fn select_drag(&self, x: f32, y: f32, rectangle: bool) {
        self.select(|e| e.select_drag(x, y, rectangle));
    }

    pub fn select_release(&self, x: f32, y: f32) {
        self.select(|e| e.select_release(x, y));
    }

    pub fn select_all(&self) {
        self.select(GhosttyEngine::select_all);
    }

    pub fn clear_selection(&self) {
        self.select(GhosttyEngine::clear_selection);
    }

    /// The selected text, for the clipboard.
    pub fn selection_text(&self) -> Option<String> {
        lock(&self.state).engine.selection_text()
    }

    /// Looks for `needle` through the screen and the history; an empty one
    /// ends the search. The matches come with the next frames.
    pub fn search(&self, needle: &str) {
        let mut s = lock(&self.state);
        s.engine.search(needle);
        s.touch();
    }

    /// The next match towards older output, or towards newer.
    pub fn search_step(&self, older: bool) {
        let mut s = lock(&self.state);
        s.engine.search_step(older);
        s.touch();
    }

    pub fn end_search(&self) {
        let mut s = lock(&self.state);
        s.engine.end_search();
        s.touch();
    }

    /// The link under a point, in the logical pixels of [`Terminal::pointer`].
    pub fn link_at(&self, x: f32, y: f32) -> Option<Link> {
        lock(&self.state).engine.link_at(x, y)
    }

    /// The cursor until a program sets its own.
    pub fn set_cursor(&self, shape: CursorShape, blink: bool) {
        let mut s = lock(&self.state);
        s.engine.set_cursor_defaults(shape, blink);
        s.touch();
    }

    /// See [`GhosttyEngine::set_theme`]; the screen is sent again, for the
    /// UI to paint it in the new colors.
    pub fn set_theme(
        &self,
        dark: bool,
        foreground: [u8; 3],
        background: [u8; 3],
        cursor: [u8; 3],
        palette: &[[u8; 3]; 256],
    ) {
        let mut s = lock(&self.state);
        s.engine
            .set_theme(dark, foreground, background, cursor, palette);
        s.engine.redraw();
        s.touch();
    }

    /// The next [`Terminal::poll`] returns the whole screen.
    pub fn redraw(&self) {
        let mut s = lock(&self.state);
        s.engine.redraw();
        s.touch();
    }
}

/// A terminal's state and input side, for the task that feeds it.
pub(crate) struct Pipe {
    state: Arc<Mutex<State>>,
    io: Arc<Mutex<Io>>,
    activity: Arc<Activity>,
}

impl Pipe {
    pub(crate) fn size(&self) -> Size {
        lock(&self.state).engine.size()
    }

    pub(crate) fn activity(&self) -> Arc<Activity> {
        Arc::clone(&self.activity)
    }

    /// Pumps an open shell channel until it closes; returns its exit code,
    /// or the failure if the connection broke.
    /// Wires input to an open shell channel at once, then returns what
    /// pumps it until it closes: its exit code, or the failure if the
    /// connection broke. Input sent after this call reaches the shell.
    pub(crate) fn pump_ssh(
        &self,
        channel: openward_ssh::russh::Channel<Msg>,
        label: &str,
    ) -> impl Future<Output = (Option<u32>, Option<Failure>)> + Send + 'static {
        let (tx, rx) = mpsc::channel::<SshCmd>(SEND_QUEUE);
        *lock(&self.io) = Io::Ssh(tx.clone());
        let (state, io, activity, label) = (
            Arc::clone(&self.state),
            Arc::clone(&self.io),
            Arc::clone(&self.activity),
            label.to_owned(),
        );
        async move { Self::pump(channel, tx, rx, state, io, activity, label).await }
    }

    async fn pump(
        channel: openward_ssh::russh::Channel<Msg>,
        tx: mpsc::Sender<SshCmd>,
        mut rx: mpsc::Receiver<SshCmd>,
        state: Arc<Mutex<State>>,
        io: Arc<Mutex<Io>>,
        activity: Arc<Activity>,
        label: String,
    ) -> (Option<u32>, Option<Failure>) {
        let (mut read, write) = channel.split();
        let typed = Arc::clone(&activity);
        let writer = async move {
            let mut w = write.make_writer();
            while let Some(cmd) = rx.recv().await {
                match cmd {
                    SshCmd::Data(bytes) => {
                        typed.sent();
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
        // The engine parses on a thread of its own: a flood of output in one
        // tab would otherwise hold the runtime's few threads, which every
        // connection's keepalives, transfers and tunnels share. The channel
        // is bounded, so a slow parse still slows the server down.
        let (feed, mut parsed) = mpsc::channel::<Vec<u8>>(PARSE_QUEUE);
        let parser_state = Arc::clone(&state);
        let replies = tx.clone();
        let parser = thread::Builder::new()
            .name("openward-parse".into())
            .spawn(move || {
                while let Some(data) = parsed.blocking_recv() {
                    let out = Terminal::output(&parser_state, &data);
                    if !out.is_empty() {
                        // Its own thread: waiting here holds the parse back.
                        let _ = replies.blocking_send(SshCmd::Data(out));
                    }
                }
            });
        let mut feed = parser.is_ok().then_some(feed);
        let reader_state = Arc::clone(&state);
        let reader = async move {
            let mut exit = None;
            let mut ended = false;
            while let Some(msg) = read.wait().await {
                match msg {
                    ChannelMsg::Data { data } | ChannelMsg::ExtendedData { data, .. } => {
                        activity.received();
                        let parsed = match &feed {
                            Some(f) => f.send(data.to_vec()).await.is_ok(),
                            None => false,
                        };
                        if !parsed {
                            // No parse thread: here, as before.
                            feed = None;
                            let out = Terminal::output(&reader_state, &data);
                            if !out.is_empty() {
                                let _ = tx.send(SshCmd::Data(out)).await;
                            }
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
                *lock(&io) = Io::None;
                r
            },
            writer
        );
        lock(&state).touch();
        let failure = (!ended).then(|| Failure::lost(label));
        (exit, failure)
    }
}

impl Drop for Terminal {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// A server that reads nothing holds input back up to a point; past
    /// it, typing goes nowhere instead of piling up.
    #[test]
    fn input_for_a_server_that_reads_nothing_is_bounded() {
        let term = Terminal::new(40, 4, 100);
        let (tx, _rx) = mpsc::channel(SEND_QUEUE);
        *lock(&term.io) = Io::Ssh(tx);
        for _ in 0..SEND_QUEUE {
            assert!(term.send(b"x".to_vec()));
        }
        assert!(!term.send(b"x".to_vec()));
    }

    /// The UI hears of new output once until it looks, and nothing while
    /// nothing changes: an idle terminal costs no frames.
    #[test]
    fn the_waker_calls_once_per_look() {
        let term = Terminal::new(40, 4, 100);
        let calls = Arc::new(AtomicUsize::new(0));
        let counted = Arc::clone(&calls);
        term.set_waker(Arc::new(move || {
            counted.fetch_add(1, Ordering::Relaxed);
        }));
        // The first screen is there to draw.
        assert_eq!(calls.load(Ordering::Relaxed), 1);
        assert!(term.poll().is_some());
        assert!(term.poll().is_none());
        assert_eq!(calls.load(Ordering::Relaxed), 1);

        term.note("one");
        term.note("two");
        assert_eq!(calls.load(Ordering::Relaxed), 2, "once until it looks");
        // A hidden tab reads the title only: the damage stays, and it is
        // told of the next output.
        let _ = term.poll_meta();
        term.note("three");
        assert_eq!(calls.load(Ordering::Relaxed), 3);
        assert!(term.poll().is_some());
        assert!(term.poll().is_none());
        assert_eq!(calls.load(Ordering::Relaxed), 3);
    }
}
