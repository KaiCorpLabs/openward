//! Terminals and their events as Dart sees them.
//!
//! Events are flat: a kind and the part that goes with it. Answers to
//! prompts come back as [`PromptAnswer`]; their texts are wiped from memory
//! once used.

use std::sync::Arc;

use flutter_rust_bridge::frb;
use openward_app::events::{
    CertProblem, Connected, Health, KeySource, NetCause, Persistence, Question, SerialProblem,
    Stage, Trust,
};
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
    /// How a live connection is doing (`health`).
    Health,
    /// The round trip to each jump host (`hop_rtt_ms`).
    Hops,
    /// Saved hosts changed (connecting told their system): read them
    /// again. `unknown_systems`: the ones just found not to tell their
    /// system, to offer reading `/etc/os-release`.
    HostsChanged,
    /// How the shell of a host with a persistent session started
    /// (`persistent`).
    Persistent,
    /// Mosh was asked for and the session goes over SSH (`mosh_fallback`).
    MoshFallback,
    /// A local program is running (`program`).
    Started,
    Closed,
}

/// Why a session asked to go over Mosh goes over SSH, in tmux.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MoshFallbackKind {
    /// No `mosh-client` on this computer.
    NoClient,
    /// No `mosh-server` on the server.
    NoServer,
    /// The server's UDP did not get through.
    NoUdp,
    /// `mosh-server` did not start; [`MoshFallbackView::said`] is why.
    Other,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MoshFallbackView {
    pub kind: MoshFallbackKind,
    /// What the server said, with `Other`.
    pub said: String,
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
    pub health: Option<HealthView>,
    /// From here to each jump host, in route order; null for one that did
    /// not answer in time.
    pub hop_rtt_ms: Vec<Option<u32>>,
    pub persistent: Option<PersistentView>,
    pub program: Option<String>,
    pub closed: Option<ClosedView>,
    /// Saved hosts (by id) that do not tell their system and do not read
    /// `/etc/os-release`, with `HostsChanged`.
    pub unknown_systems: Vec<String>,
    pub mosh_fallback: Option<MoshFallbackView>,
}

/// An answer from the server (after `rtt_ms`, when it was a question's),
/// or no answer for `silent_ms` so far (`stalled`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HealthView {
    pub stalled: bool,
    pub silent_ms: u64,
    pub rtt_ms: Option<u32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PersistenceKind {
    /// A new tmux session.
    New,
    /// The session from before, as it was.
    Resumed,
    /// No tmux on the server: an ordinary shell.
    NoTmux,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PersistentView {
    /// The tmux session's name (`ow-…`).
    pub session: String,
    pub state: PersistenceKind,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StageKind {
    Connecting,
    Authenticating,
    OpeningShell,
    OpeningSftp,
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
    /// The proxy's password; first its user when `user` is empty.
    ProxyLogin,
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
    /// With [`PromptKind::HostKey`]: the types of the keys already known
    /// for the host. Empty for a new host; otherwise the server did not
    /// offer the key that is known.
    pub known_types: Vec<String>,
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
    /// For Telnet the SSH fields are empty (nothing is encrypted); for a
    /// serial port `host` is the port and `port` 0.
    pub protocol: super::vault::ProtocolKind,
    /// The shell goes over Mosh (SSH only started it).
    pub mosh: bool,
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
    /// Marked `@revoked` in a `known_hosts`.
    HostKeyRevoked,
    BadCertificate,
    AuthFailed,
    Cancelled,
    /// The server has no SFTP.
    NoSftp,
    /// A serial port: [`FailureView::serial`] says what.
    Serial,
    Network,
    Other,
}

/// With [`FailureKind::Serial`]: what went wrong with the port
/// ([`FailureView::host`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SerialKind {
    /// Not there (now).
    Missing,
    /// Another program has it.
    Busy,
    /// Not allowed (on Linux, not in `dialout`).
    Denied,
    /// It does not take these settings; [`FailureView::reason`] says why.
    Settings,
    /// It went while open: the cable was pulled.
    Gone,
    Other,
}

/// macOS: which Option keys act as Alt.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OptionAlt {
    Off,
    Both,
    Left,
    Right,
}

/// With [`FailureKind::BadCertificate`]: what is wrong with it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CertKind {
    NotHost,
    NoAuthority,
    Untrusted,
    OutOfDate,
    NotForHost,
}

/// With [`FailureKind::Network`]: what kind of trouble.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NetKind {
    Refused,
    NotFound,
    Unreachable,
    /// It did not answer for [`FailureView::seconds`] (0: the system gave
    /// up on its own).
    Silent,
    Lost,
    /// The ProxyCommand failed; [`FailureView::reason`] is what it wrote.
    ProxyCommand,
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
    pub cert: Option<CertKind>,
    pub net: Option<NetKind>,
    pub serial: Option<SerialKind>,
    pub seconds: u32,
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

pub(crate) fn failure_view(f: Failure) -> FailureView {
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
        Failure::HostKeyRevoked { label, fingerprint } => FailureView {
            kind: Some(FailureKind::HostKeyRevoked),
            label,
            fingerprint,
            ..v
        },
        Failure::BadCertificate { label, problem } => FailureView {
            kind: Some(FailureKind::BadCertificate),
            label,
            reason: problem.to_string(),
            cert: Some(match problem {
                CertProblem::NotHost => CertKind::NotHost,
                CertProblem::NoAuthority => CertKind::NoAuthority,
                CertProblem::Untrusted => CertKind::Untrusted,
                CertProblem::OutOfDate => CertKind::OutOfDate,
                CertProblem::NotForHost => CertKind::NotForHost,
            }),
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
        Failure::NoSftp { label } => FailureView {
            kind: Some(FailureKind::NoSftp),
            label,
            ..v
        },
        Failure::Network {
            label,
            message,
            cause,
        } => {
            let mut reason = message;
            let (net, seconds) = match cause {
                NetCause::Refused => (NetKind::Refused, 0),
                NetCause::NotFound => (NetKind::NotFound, 0),
                NetCause::Unreachable => (NetKind::Unreachable, 0),
                NetCause::Silent(s) => (NetKind::Silent, s),
                NetCause::Lost => (NetKind::Lost, 0),
                NetCause::ProxyCommand(said) => {
                    reason = said.join(" · ");
                    (NetKind::ProxyCommand, 0)
                }
                NetCause::Other => (NetKind::Other, 0),
            };
            FailureView {
                kind: Some(FailureKind::Network),
                label,
                reason,
                net: Some(net),
                seconds,
                ..v
            }
        }
        Failure::Serial { port, problem } => {
            let (serial, reason) = match problem {
                SerialProblem::Missing => (SerialKind::Missing, String::new()),
                SerialProblem::Busy => (SerialKind::Busy, String::new()),
                SerialProblem::Denied => (SerialKind::Denied, String::new()),
                SerialProblem::Settings(why) => (SerialKind::Settings, why),
                SerialProblem::Gone => (SerialKind::Gone, String::new()),
                SerialProblem::Other(why) => (SerialKind::Other, why),
            };
            FailureView {
                kind: Some(FailureKind::Serial),
                label: port.clone(),
                host: port,
                reason,
                serial: Some(serial),
                ..v
            }
        }
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
            known_types,
        } => PromptView {
            kind: Some(PromptKind::HostKey),
            label,
            host,
            port,
            algorithm,
            fingerprint,
            known_types,
            ..v
        },
        Prompt::Passphrase { key, retry } => PromptView {
            kind: Some(PromptKind::Passphrase),
            key,
            retry,
            ..v
        },
        Prompt::ProxyLogin { proxy, user, retry } => PromptView {
            kind: Some(PromptKind::ProxyLogin),
            host: proxy,
            user,
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
        health: None,
        hop_rtt_ms: Vec::new(),
        persistent: None,
        program: None,
        closed: None,
        unknown_systems: Vec::new(),
        mosh_fallback: None,
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
                    Stage::OpeningSftp => StageKind::OpeningSftp,
                },
            });
        }
        Event::Prompt { id, prompt } => {
            v.kind = SessionEventKind::Prompt;
            v.prompt = Some(prompt_view(id, prompt));
        }
        Event::Connected(Connected {
            protocol,
            mosh,
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
                protocol: super::vault::ProtocolKind::of(protocol),
                mosh,
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
        Event::Health(h) => {
            v.kind = SessionEventKind::Health;
            v.health = Some(match h {
                Health::Answered { rtt_ms } => HealthView {
                    stalled: false,
                    silent_ms: 0,
                    rtt_ms,
                },
                Health::Stalled { silent_ms } => HealthView {
                    stalled: true,
                    silent_ms,
                    rtt_ms: None,
                },
            });
        }
        Event::Hops { rtt_ms } => {
            v.kind = SessionEventKind::Hops;
            v.hop_rtt_ms = rtt_ms;
        }
        Event::HostsChanged { unknown } => {
            v.kind = SessionEventKind::HostsChanged;
            v.unknown_systems = unknown.iter().map(ToString::to_string).collect();
        }
        Event::Persistent { session, state } => {
            v.kind = SessionEventKind::Persistent;
            v.persistent = Some(PersistentView {
                session,
                state: match state {
                    Persistence::New => PersistenceKind::New,
                    Persistence::Resumed => PersistenceKind::Resumed,
                    Persistence::NoTmux => PersistenceKind::NoTmux,
                },
            });
        }
        Event::MoshFallback { reason } => {
            use openward_app::events::MoshFallback;
            v.kind = SessionEventKind::MoshFallback;
            let (kind, said) = match reason {
                MoshFallback::NoClient => (MoshFallbackKind::NoClient, String::new()),
                MoshFallback::NoServer => (MoshFallbackKind::NoServer, String::new()),
                MoshFallback::NoUdp => (MoshFallbackKind::NoUdp, String::new()),
                MoshFallback::Other(said) => (MoshFallbackKind::Other, said),
            };
            v.mosh_fallback = Some(MoshFallbackView { kind, said });
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

/// One visible row's selected columns, both inclusive.
pub struct SelectedRange {
    pub row: u16,
    pub start: u16,
    pub end: u16,
}

/// A search match's part on one visible row; columns inclusive.
pub struct SearchHitView {
    pub row: u16,
    pub start: u16,
    pub end: u16,
    /// The match the find bar points at.
    pub selected: bool,
}

/// The find bar's search: "selected of total", and what to highlight.
pub struct SearchView {
    pub total: u32,
    /// 1-based from the newest match; none before the first step.
    pub selected: Option<u32>,
    pub hits: Vec<SearchHitView>,
    /// Still going through the history: more matches may come.
    pub searching: bool,
}

/// A link on screen (OSC 8, or a URL in the text); columns inclusive.
pub struct LinkView {
    pub url: String,
    /// What the screen shows of it (an OSC 8 link's text may differ).
    pub text: String,
    pub row: u16,
    pub start: u16,
    pub end: u16,
}

/// A cell of the screen.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CellPos {
    pub row: u16,
    pub col: u16,
}

/// The screen from where typing began up to the cursor, and what follows
/// the cursor on its row (a suggestion the shell shows, or the rest of a
/// line being edited).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TypedLine {
    pub text: String,
    pub after: String,
}

/// The cursor's shape, when the program does not choose one.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CursorStyle {
    Block,
    Bar,
    Underline,
}

/// Damage since the last poll, and how input should be routed.
pub struct TermFrame {
    /// Damage frame v1 (`openward-term`, frame.rs).
    pub frame: Vec<u8>,
    pub mouse_tracking: bool,
    pub bracketed_paste: bool,
    pub report_all_keys: bool,
    pub keypad_application: bool,
    /// `0xRRGGBB` the program set for itself over the theme (OSC 10, 11,
    /// 12); its palette changes come painted in the frame.
    pub program_foreground: Option<u32>,
    pub program_background: Option<u32>,
    pub program_cursor: Option<u32>,
    pub alt_screen: bool,
    pub title: String,
    /// The selection as it stands now (empty: none), to paint over the
    /// screen.
    pub selection: Vec<SelectedRange>,
    /// A BEL arrived since the last frame.
    pub bell: bool,
    pub cursor_blinks: bool,
    /// While the find bar is open.
    pub search: Option<SearchView>,
}

/// A terminal tab: a remote shell, or a local one.
#[frb(opaque)]
pub struct TerminalSession {
    pub(crate) term: Arc<Terminal>,
}

/// What a hidden tab reads instead of the screen.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TermMeta {
    pub title: String,
    /// A BEL arrived since the last look.
    pub bell: bool,
}

impl TerminalSession {
    /// An event each time there is something new to draw that has not
    /// been polled: the UI polls while it has events, and asks for no
    /// frames while nothing changes.
    pub fn watch(&self, wakes: StreamSink<bool>) {
        self.term.set_waker(Arc::new(move || {
            let _ = wakes.add(true);
        }));
    }

    /// Compresses the history, in steps that let output in between: for a
    /// terminal that has been quiet for a while. Off the UI thread.
    pub fn compress_history(&self) {
        self.term.compress_history();
    }

    /// The title and the bell, leaving the screen's damage for later: for
    /// a tab that is not on view.
    #[frb(sync)]
    pub fn poll_meta(&self) -> TermMeta {
        let (title, bell) = self.term.poll_meta();
        TermMeta { title, bell }
    }

    /// What changed since the last call, or nothing; once per refresh.
    #[frb(sync)]
    pub fn poll(&self) -> Option<TermFrame> {
        self.term.poll().map(|f| TermFrame {
            frame: f.frame,
            mouse_tracking: f.mouse_tracking,
            bracketed_paste: f.bracketed_paste,
            report_all_keys: f.report_all_keys,
            keypad_application: f.keypad_application,
            program_foreground: f.program_foreground.map(packed),
            program_background: f.program_background.map(packed),
            program_cursor: f.program_cursor.map(packed),
            alt_screen: f.alt_screen,
            title: f.title,
            selection: f
                .selection
                .into_iter()
                .map(|r| SelectedRange {
                    row: r.row,
                    start: r.start,
                    end: r.end,
                })
                .collect(),
            bell: f.bell,
            cursor_blinks: f.cursor_blinks,
            search: f.search.map(|s| SearchView {
                searching: s.searching,
                total: s.total as u32,
                selected: s.selected.map(|i| i as u32),
                hits: s
                    .hits
                    .into_iter()
                    .map(|h| SearchHitView {
                        row: h.row,
                        start: h.start,
                        end: h.end,
                        selected: h.selected,
                    })
                    .collect(),
            }),
        })
    }

    /// Looks for `needle` through the screen and the history (ASCII letters
    /// in any case); an empty needle ends the search. Matches come with the
    /// next frames.
    #[frb(sync)]
    pub fn search(&self, needle: String) {
        self.term.search(&needle);
    }

    /// The next match towards older output (`older`), or towards newer;
    /// scrolls to it.
    #[frb(sync)]
    pub fn search_step(&self, older: bool) {
        self.term.search_step(older);
    }

    #[frb(sync)]
    pub fn end_search(&self) {
        self.term.end_search();
    }

    /// The link under a point, in the logical pixels of [`Self::pointer`].
    #[frb(sync)]
    pub fn link_at(&self, x: f32, y: f32) -> Option<LinkView> {
        self.term.link_at(x, y).map(|l| LinkView {
            url: l.url,
            text: l.text,
            row: l.row,
            start: l.start,
            end: l.end,
        })
    }

    /// The cursor until a program sets its own, and whether it blinks.
    #[frb(sync)]
    pub fn set_cursor(&self, style: CursorStyle, blink: bool) {
        self.term.set_cursor(
            match style {
                CursorStyle::Block => terminal::CursorShape::Block,
                CursorStyle::Bar => terminal::CursorShape::Beam,
                CursorStyle::Underline => terminal::CursorShape::Underline,
            },
            blink,
        );
    }

    /// Selection with the mouse, in the logical pixels of [`Self::pointer`]:
    /// press, drag (`rectangle` for a block) and release. Two and three
    /// quick presses select a word and a line.
    #[frb(sync)]
    pub fn select_press(&self, x: f32, y: f32) {
        self.term.select_press(x, y);
    }

    #[frb(sync)]
    pub fn select_drag(&self, x: f32, y: f32, rectangle: bool) {
        self.term.select_drag(x, y, rectangle);
    }

    #[frb(sync)]
    pub fn select_release(&self, x: f32, y: f32) {
        self.term.select_release(x, y);
    }

    #[frb(sync)]
    pub fn select_all(&self) {
        self.term.select_all();
    }

    #[frb(sync)]
    pub fn clear_selection(&self) {
        self.term.clear_selection();
    }

    /// The selected text, for the clipboard; `None` without a selection.
    #[frb(sync)]
    pub fn selection_text(&self) -> Option<String> {
        self.term.selection_text()
    }

    /// The UI theme, which programs ask for to pick their colors: its
    /// default colors and its 256. Colors are `0xRRGGBB`.
    #[frb(sync)]
    pub fn set_theme(
        &self,
        dark: bool,
        foreground: u32,
        background: u32,
        cursor: u32,
        palette: Vec<u32>,
    ) {
        let rgb = |c: u32| [(c >> 16) as u8, (c >> 8) as u8, c as u8];
        let mut colors = [[0u8; 3]; 256];
        for (i, c) in palette.iter().take(256).enumerate() {
            colors[i] = rgb(*c);
        }
        self.term
            .set_theme(dark, rgb(foreground), rgb(background), rgb(cursor), &colors);
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

    /// Scrolls the history only (a selection dragged past an edge): the
    /// program hears nothing.
    #[frb(sync)]
    pub fn scroll_history(&self, lines: i32) {
        self.term.scroll_history(lines);
    }

    #[frb(sync)]
    pub fn focus(&self, gained: bool) {
        self.term.focus(gained);
    }

    /// Forgets the history above the screen; the program is not told.
    #[frb(sync)]
    pub fn clear_history(&self) {
        self.term.clear_history();
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
    pub fn set_option_as_alt(&self, which: OptionAlt) {
        self.term.set_option_as_alt(match which {
            OptionAlt::Off => terminal::OptionAsAlt::Off,
            OptionAlt::Both => terminal::OptionAsAlt::Both,
            OptionAlt::Left => terminal::OptionAsAlt::Left,
            OptionAlt::Right => terminal::OptionAsAlt::Right,
        });
    }

    #[frb(sync)]
    pub fn screen_text(&self) -> String {
        self.term.screen_text()
    }

    /// A line of OpenWard's own on the screen (escape sequences allowed),
    /// never sent to the program: where a new shell starts after a cut.
    #[frb(sync)]
    pub fn note(&self, text: String) {
        self.term.note(&text);
    }

    /// The cursor's cell while the live screen is on view: where a prompt
    /// begins, read when typing starts.
    #[frb(sync)]
    pub fn cursor_cell(&self) -> Option<CellPos> {
        self.term
            .cursor_cell()
            .map(|(row, col)| CellPos { row, col })
    }

    /// What was typed since `start` (see [`Self::cursor_cell`]): for the
    /// command history.
    #[frb(sync)]
    pub fn typed_since(&self, start: CellPos) -> Option<TypedLine> {
        self.term
            .typed_since((start.row, start.col))
            .map(|(text, after)| TypedLine { text, after })
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

    /// Sends a break down a serial port (a router's ROM monitor waits for
    /// one); false if this is not a serial port.
    #[frb(sync)]
    pub fn send_break(&self) -> bool {
        self.term.send_break()
    }

    /// A command ran (the UI saw it at Enter): a marker in the session's
    /// recording, to jump to it.
    #[frb(sync)]
    pub fn log_command(&self, command: String) {
        self.term.log_command(&command);
    }

    /// Stops recording what comes out, or starts again. False when there
    /// is no recording, or it already was so.
    #[frb(sync)]
    pub fn pause_log(&self, paused: bool) -> bool {
        self.term.pause_log(paused)
    }

    /// The session log kept now, if any.
    #[frb(sync)]
    pub fn log_state(&self) -> Option<LogStateView> {
        self.term.log_state().map(|s| LogStateView {
            id: s.id,
            recording: s.recording,
            paused: s.paused,
            failed: s.failed,
        })
    }
}

/// A terminal's session log, as its pane shows it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LogStateView {
    pub id: String,
    /// What comes out is recorded, not only the entry.
    pub recording: bool,
    pub paused: bool,
    /// Writing failed (in English, for «Detalles»): nothing more is kept.
    pub failed: Option<String>,
}

/// `0xRRGGBB`.
fn packed([r, g, b]: [u8; 3]) -> u32 {
    (r as u32) << 16 | (g as u32) << 8 | b as u32
}
