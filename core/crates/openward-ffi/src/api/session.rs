//! Terminals and their events as Dart sees them.
//!
//! Events are flat: a kind and the part that goes with it. Answers to
//! prompts come back as [`PromptAnswer`]; their texts are wiped from memory
//! once used.

use std::sync::Arc;

use flutter_rust_bridge::frb;
use openward_app::events::{Connected, KeySource, Question, Stage, Trust};
use openward_app::terminal::{self, Terminal};
use openward_app::{Answer, Event, EventSink, Failure, Prompt};
use zeroize::Zeroizing;

use crate::frb_generated::StreamSink;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SessionEventKind {
    /// The hops of the connection (`route`), before the first stage.
    Route,
    Stage,
    Prompt,
    Connected,
    /// The connection was lost and is tried again (`reconnecting`).
    Reconnecting,
    /// A local program is running (`program`).
    Started,
    Closed,
}

/// One event; the field named by `kind` is set.
#[derive(Clone, Debug, PartialEq)]
pub struct SessionEvent {
    pub kind: SessionEventKind,
    pub route: Vec<String>,
    pub stage: Option<StageView>,
    pub prompt: Option<PromptView>,
    pub connected: Option<ConnectedView>,
    pub reconnecting: Option<ReconnectingView>,
    pub program: Option<String>,
    pub closed: Option<ClosedView>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StageKind {
    Connecting,
    Authenticating,
    OpeningShell,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StageView {
    /// From 0; `hops` in total, the target last.
    pub hop: u32,
    pub hops: u32,
    pub label: String,
    pub stage: StageKind,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PromptKind {
    /// First connection to a host: show the fingerprint, accept or not.
    HostKey,
    Passphrase,
    Password,
    /// One answer per question, in order.
    KeyboardInteractive,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct QuestionView {
    pub text: String,
    /// Not a secret: the answer may show while typed.
    pub echo: bool,
}

/// A question; answer it with `OpenWard.answer(id, …)`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PromptView {
    pub id: u64,
    pub kind: Option<PromptKind>,
    pub label: String,
    pub host: String,
    pub port: u16,
    pub user: String,
    pub algorithm: String,
    pub fingerprint: String,
    /// The key file a passphrase is for.
    pub key: String,
    pub name: String,
    pub instructions: String,
    pub questions: Vec<QuestionView>,
    /// The previous answer was wrong.
    pub retry: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrustKind {
    Known,
    Certified,
    New,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReconnectingView {
    /// From 1.
    pub attempt: u32,
    pub delay_ms: u64,
    /// Why the connection went away.
    pub reason: FailureView,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ConnectedView {
    pub host: String,
    pub port: u16,
    pub kex: String,
    pub post_quantum: bool,
    pub cipher: String,
    pub host_key_algorithm: String,
    /// `SHA256:…` of the host key.
    pub fingerprint: String,
    pub trust: TrustKind,
    /// The CA's fingerprint, when certified.
    pub ca: String,
    pub hops: u32,
    pub connect_ms: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FailureKind {
    HostKeyChanged,
    HostKeyRejected,
    BadCertificate,
    AuthFailed,
    Cancelled,
    Network,
    Other,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct FailureView {
    pub kind: Option<FailureKind>,
    /// In English, for logs; the UI words its own message from the fields.
    pub message: String,
    pub label: String,
    pub host: String,
    pub port: u16,
    pub user: String,
    pub algorithm: String,
    pub fingerprint: String,
    /// The new host key, OpenSSH format, for `trust_host_key`.
    pub key: String,
    pub methods: Vec<String>,
    pub reason: String,
    /// With [`FailureKind::HostKeyChanged`]: what was trusted before.
    pub previous: Vec<PreviousKeyView>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeySourceKind {
    /// OpenWard's own list: trusting the new key replaces it.
    OpenWard,
    /// `~/.ssh/known_hosts`, which OpenWard does not write.
    OpenSsh,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PreviousKeyView {
    pub fingerprint: String,
    pub source: KeySourceKind,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClosedView {
    pub exit_code: Option<u32>,
    /// `None`: the program ended normally.
    pub failure: Option<FailureView>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AnswerKind {
    Accept,
    Text,
    Cancel,
}

pub struct PromptAnswer {
    pub kind: AnswerKind,
    /// With [`AnswerKind::Text`]: one per question.
    pub texts: Vec<String>,
}

impl PromptAnswer {
    pub(crate) fn into_answer(self) -> Answer {
        match self.kind {
            AnswerKind::Accept => Answer::Accept,
            AnswerKind::Cancel => Answer::Cancel,
            // Moved, not copied: the strings are wiped when dropped.
            AnswerKind::Text => Answer::Text(self.texts.into_iter().map(Zeroizing::new).collect()),
        }
    }
}

fn failure_view(f: Failure) -> FailureView {
    let message = f.to_string();
    let v = FailureView {
        message,
        ..FailureView::default()
    };
    match f {
        Failure::HostKeyChanged(c) => FailureView {
            kind: Some(FailureKind::HostKeyChanged),
            label: c.label,
            host: c.host,
            port: c.port,
            algorithm: c.algorithm,
            fingerprint: c.fingerprint,
            key: c.key,
            previous: c
                .previous
                .into_iter()
                .map(|p| PreviousKeyView {
                    fingerprint: p.fingerprint,
                    source: match p.source {
                        KeySource::OpenWard => KeySourceKind::OpenWard,
                        KeySource::OpenSsh => KeySourceKind::OpenSsh,
                    },
                })
                .collect(),
            ..v
        },
        Failure::HostKeyRejected { label } => FailureView {
            kind: Some(FailureKind::HostKeyRejected),
            label,
            ..v
        },
        Failure::BadCertificate { label, reason } => FailureView {
            kind: Some(FailureKind::BadCertificate),
            label,
            reason,
            ..v
        },
        Failure::AuthFailed {
            label,
            user,
            methods,
        } => FailureView {
            kind: Some(FailureKind::AuthFailed),
            label,
            user,
            methods,
            ..v
        },
        Failure::Cancelled => FailureView {
            kind: Some(FailureKind::Cancelled),
            ..v
        },
        Failure::Network { label, message } => FailureView {
            kind: Some(FailureKind::Network),
            label,
            reason: message,
            ..v
        },
        Failure::Other(reason) => FailureView {
            kind: Some(FailureKind::Other),
            reason,
            ..v
        },
    }
}

fn prompt_view(id: u64, p: Prompt) -> PromptView {
    let v = PromptView {
        id,
        ..PromptView::default()
    };
    match p {
        Prompt::HostKey {
            label,
            host,
            port,
            algorithm,
            fingerprint,
        } => PromptView {
            kind: Some(PromptKind::HostKey),
            label,
            host,
            port,
            algorithm,
            fingerprint,
            ..v
        },
        Prompt::Passphrase { key, retry } => PromptView {
            kind: Some(PromptKind::Passphrase),
            key,
            retry,
            ..v
        },
        Prompt::Password { user, host, retry } => PromptView {
            kind: Some(PromptKind::Password),
            user,
            host,
            retry,
            ..v
        },
        Prompt::KeyboardInteractive {
            user,
            host,
            name,
            instructions,
            questions,
            retry,
        } => PromptView {
            kind: Some(PromptKind::KeyboardInteractive),
            user,
            host,
            name,
            instructions,
            questions: questions
                .into_iter()
                .map(|Question { text, echo }| QuestionView { text, echo })
                .collect(),
            retry,
            ..v
        },
    }
}

pub(crate) fn event_view(e: Event) -> SessionEvent {
    let mut v = SessionEvent {
        kind: SessionEventKind::Stage,
        route: Vec::new(),
        stage: None,
        prompt: None,
        connected: None,
        reconnecting: None,
        program: None,
        closed: None,
    };
    match e {
        Event::Route { hops } => {
            v.kind = SessionEventKind::Route;
            v.route = hops;
        }
        Event::Reconnecting {
            attempt,
            delay_ms,
            reason,
        } => {
            v.kind = SessionEventKind::Reconnecting;
            v.reconnecting = Some(ReconnectingView {
                attempt,
                delay_ms,
                reason: failure_view(reason),
            });
        }
        Event::Stage {
            hop,
            hops,
            label,
            stage,
        } => {
            v.stage = Some(StageView {
                hop: hop as u32,
                hops: hops as u32,
                label,
                stage: match stage {
                    Stage::Connecting => StageKind::Connecting,
                    Stage::Authenticating => StageKind::Authenticating,
                    Stage::OpeningShell => StageKind::OpeningShell,
                },
            });
        }
        Event::Prompt { id, prompt } => {
            v.kind = SessionEventKind::Prompt;
            v.prompt = Some(prompt_view(id, prompt));
        }
        Event::Connected(Connected {
            host,
            port,
            kex,
            post_quantum,
            cipher,
            host_key_algorithm,
            fingerprint,
            trust,
            hops,
            connect_ms,
        }) => {
            v.kind = SessionEventKind::Connected;
            let (trust, ca) = match trust {
                Trust::Known => (TrustKind::Known, String::new()),
                Trust::Certified { ca } => (TrustKind::Certified, ca),
                Trust::New => (TrustKind::New, String::new()),
            };
            v.connected = Some(ConnectedView {
                host,
                port,
                kex,
                post_quantum,
                cipher,
                host_key_algorithm,
                fingerprint,
                trust,
                ca,
                hops: hops as u32,
                connect_ms,
            });
        }
        Event::Started { program } => {
            v.kind = SessionEventKind::Started;
            v.program = Some(program);
        }
        Event::Closed { exit_code, failure } => {
            v.kind = SessionEventKind::Closed;
            v.closed = Some(ClosedView {
                exit_code,
                failure: failure.map(failure_view),
            });
        }
    }
    v
}

/// Events of one terminal, to a Dart stream.
pub(crate) struct DartSink(pub StreamSink<SessionEvent>);

impl EventSink for DartSink {
    fn send(&self, event: Event) {
        // The stream is gone once Dart stops listening: nothing to do.
        let _ = self.0.add(event_view(event));
    }
}

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

/// Damage since the last poll, and how input should be routed.
pub struct TermFrame {
    /// Damage frame v1 (`openward-term`, frame.rs).
    pub frame: Vec<u8>,
    pub mouse_tracking: bool,
    pub bracketed_paste: bool,
    pub report_all_keys: bool,
    pub alt_screen: bool,
    pub title: String,
}

/// A terminal tab: a remote shell, or a local one.
#[frb(opaque)]
pub struct TerminalSession {
    pub(crate) term: Arc<Terminal>,
}

impl TerminalSession {
    /// What changed since the last call, or nothing; once per refresh.
    #[frb(sync)]
    pub fn poll(&self) -> Option<TermFrame> {
        self.term.poll().map(|f| TermFrame {
            frame: f.frame,
            mouse_tracking: f.mouse_tracking,
            bracketed_paste: f.bracketed_paste,
            report_all_keys: f.report_all_keys,
            alt_screen: f.alt_screen,
            title: f.title,
        })
    }

    /// A key; returns whether it produced any bytes.
    #[frb(sync)]
    pub fn key(
        &self,
        hid_usage: u32,
        kind: KeyKind,
        mods: u16,
        text: String,
        unshifted: u32,
    ) -> bool {
        let kind = match kind {
            KeyKind::Down => terminal::KeyKind::Down,
            KeyKind::Repeat => terminal::KeyKind::Repeat,
            KeyKind::Up => terminal::KeyKind::Up,
        };
        self.term.key(hid_usage, kind, mods, text, unshifted)
    }

    /// Text from an input method or soft keyboard.
    #[frb(sync)]
    pub fn text(&self, text: String) {
        self.term.text(&text);
    }

    /// False, sending nothing, if the text could run commands: confirm and
    /// call again with `allow_unsafe`.
    #[frb(sync)]
    pub fn paste(&self, text: String, allow_unsafe: bool) -> bool {
        self.term.paste(&text, allow_unsafe)
    }

    #[frb(sync)]
    pub fn pointer(&self, action: PointerAction, button: PointerButton, mods: u16, x: f32, y: f32) {
        let action = match action {
            PointerAction::Down => terminal::PointerAction::Down,
            PointerAction::Up => terminal::PointerAction::Up,
            PointerAction::Move => terminal::PointerAction::Move,
        };
        let button = match button {
            PointerButton::None => terminal::PointerButton::None,
            PointerButton::Left => terminal::PointerButton::Left,
            PointerButton::Middle => terminal::PointerButton::Middle,
            PointerButton::Right => terminal::PointerButton::Right,
        };
        self.term.pointer(action, button, mods, x, y);
    }

    /// `lines` notches, positive up.
    #[frb(sync)]
    pub fn wheel(&self, lines: i32, x: f32, y: f32, mods: u16) {
        self.term.wheel(lines, x, y, mods);
    }

    #[frb(sync)]
    pub fn focus(&self, gained: bool) {
        self.term.focus(gained);
    }

    #[frb(sync)]
    pub fn resize(&self, cols: u16, rows: u16) {
        self.term.resize(cols, rows);
    }

    #[frb(sync)]
    pub fn set_cell_pixels(&self, width: f32, height: f32) {
        self.term.set_cell_pixels(width, height);
    }

    #[frb(sync)]
    pub fn set_option_as_alt(&self, enabled: bool) {
        self.term.set_option_as_alt(enabled);
    }

    #[frb(sync)]
    pub fn screen_text(&self) -> String {
        self.term.screen_text()
    }

    /// The next poll returns the whole screen: after the UI dropped its
    /// cached rows (new font, theme or pixel density).
    #[frb(sync)]
    pub fn redraw(&self) {
        self.term.redraw();
    }

    /// Ends the connection or program; the screen stays until dropped.
    #[frb(sync)]
    pub fn close(&self) {
        self.term.close();
    }
}
