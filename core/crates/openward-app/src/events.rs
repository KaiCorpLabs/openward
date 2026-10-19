//! What a session tells the UI, and the questions it waits on.
//!
//! A connection that needs something from the user (trusting a host key, a
//! passphrase, a password, a 2FA code) sends a [`Prompt`] with an id and
//! waits; the UI answers through [`crate::App::answer`]. Secrets in answers
//! are wiped from memory when dropped.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use tokio::sync::oneshot;
use zeroize::Zeroizing;

/// Where a session's events go (a stream to Dart, a channel in tests).
pub trait EventSink: Send + Sync {
    fn send(&self, event: Event);
}

#[derive(Clone, Debug, PartialEq)]
pub enum Event {
    /// The hops this connection goes through, jump hosts first and the
    /// target last; sent before the first [`Event::Stage`].
    Route {
        hops: Vec<String>,
    },
    /// Connection progress, hop by hop (`hop` counts from 0).
    Stage {
        hop: usize,
        hops: usize,
        label: String,
        stage: Stage,
    },
    Prompt {
        id: u64,
        prompt: Prompt,
    },
    Connected(Connected),
    /// An established connection was lost; it is tried again after
    /// `delay_ms`. The screen stays; [`crate::App::connect`] retries now and
    /// closing the terminal gives up.
    Reconnecting {
        attempt: u32,
        delay_ms: u64,
        reason: Failure,
    },
    /// How a live connection is doing (see [`crate::alive`]).
    Health(Health),
    /// The round trip from here to each jump host, in route order, when
    /// the connection goes through any; None for one that did not answer
    /// in time. Sent with each check, beside [`Event::Health`].
    Hops {
        rtt_ms: Vec<Option<u32>>,
    },
    /// Saved hosts changed under the UI (connecting told their system):
    /// it should read them again. `unknown`: the ones just found not to
    /// tell their system, which do not read `/etc/os-release`.
    HostsChanged {
        unknown: Vec<openward_vault::proto::ItemId>,
    },
    /// The shell of a host with a persistent session: its tmux session,
    /// found again or new, or no tmux on the server (an ordinary shell).
    Persistent {
        session: String,
        state: Persistence,
    },
    /// A local program is running: input goes to it from now on.
    Started {
        program: String,
    },
    /// The program ended, the connection dropped or it never came up.
    Closed {
        exit_code: Option<u32>,
        failure: Option<Failure>,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Health {
    /// The server answered; after `rtt_ms` when it was a question's answer.
    Answered { rtt_ms: Option<u32> },
    /// No answer for `silent_ms` so far: it may come back, or be lost.
    Stalled { silent_ms: u64 },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Persistence {
    /// A new tmux session.
    New,
    /// The session from before the cut, as it was.
    Resumed,
    /// No tmux on the server: an ordinary shell, that a cut ends.
    NoTmux,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stage {
    Connecting,
    Authenticating,
    OpeningShell,
    OpeningSftp,
}

/// What the status bar shows about a live connection.
#[derive(Clone, Debug, PartialEq)]
pub struct Connected {
    /// The target, as the vault has it.
    pub host: String,
    pub port: u16,
    pub kex: String,
    pub post_quantum: bool,
    pub cipher: String,
    pub host_key_algorithm: String,
    /// `SHA256:…` of the target's host key.
    pub fingerprint: String,
    pub trust: Trust,
    pub hops: usize,
    pub connect_ms: f64,
}

/// How the target's host key was trusted.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Trust {
    Known,
    /// Signed by a trusted CA.
    Certified {
        ca: String,
    },
    /// Trusted just now (TOFU) and saved.
    New,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Prompt {
    /// A host seen for the first time. Accepting saves the key.
    HostKey {
        label: String,
        host: String,
        port: u16,
        algorithm: String,
        /// `SHA256:…`, as OpenSSH shows it.
        fingerprint: String,
    },
    Passphrase {
        key: String,
        retry: bool,
    },
    Password {
        user: String,
        host: String,
        retry: bool,
    },
    /// The proxy in front of the first hop wants to log in. With `user`
    /// empty, the answer is the user and then the password; otherwise just
    /// the password. Neither is kept.
    ProxyLogin {
        /// `host:port`.
        proxy: String,
        user: String,
        retry: bool,
    },
    /// Keyboard-interactive (2FA and the like): one answer per question.
    KeyboardInteractive {
        user: String,
        host: String,
        name: String,
        instructions: String,
        questions: Vec<Question>,
        retry: bool,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Question {
    pub text: String,
    /// The answer may be shown while typed (it is not a secret).
    pub echo: bool,
}

pub enum Answer {
    /// Yes to a host key.
    Accept,
    /// One text per question: passphrase, password, or 2FA answers.
    Text(Vec<Zeroizing<String>>),
    Cancel,
}

/// A host key that differs from the one trusted.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChangedKey {
    pub label: String,
    pub host: String,
    pub port: u16,
    pub algorithm: String,
    pub fingerprint: String,
    /// The offered key, OpenSSH format.
    pub key: String,
    /// The keys trusted so far for this host and key type.
    pub previous: Vec<PreviousKey>,
}

/// A key that was trusted for a host before it changed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PreviousKey {
    pub fingerprint: String,
    pub source: KeySource,
}

/// Where a trusted key is written down.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeySource {
    /// OpenWard's vault: trusting the new key replaces it.
    OpenWard,
    /// `~/.ssh/known_hosts`: OpenWard never writes there, so OpenSSH keeps
    /// warning until the user updates it.
    OpenSsh,
}

/// Why a connection did not come up or went away.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Failure {
    /// The host key differs from the one trusted: possibly an attack. The
    /// new key is only trusted by an explicit action
    /// ([`crate::App::trust_host_key`]).
    HostKeyChanged(Box<ChangedKey>),
    /// Unknown key refused: by the user, or by a strict policy.
    HostKeyRejected {
        label: String,
    },
    /// The key is marked `@revoked` in a `known_hosts`.
    HostKeyRevoked {
        label: String,
        fingerprint: String,
    },
    BadCertificate {
        label: String,
        reason: String,
    },
    AuthFailed {
        label: String,
        user: String,
        /// What the server would still accept.
        methods: Vec<String>,
    },
    Cancelled,
    /// The server has no SFTP (a Dropbear without `sftp-server`, a router).
    NoSftp {
        label: String,
    },
    /// Could not reach the host, or the connection broke.
    Network {
        label: String,
        message: String,
    },
    Other(String),
}

impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::HostKeyChanged(c) => {
                write!(f, "{}: host key changed (now {})", c.label, c.fingerprint)
            }
            Self::HostKeyRejected { label } => write!(f, "{label}: host key not trusted"),
            Self::HostKeyRevoked { label, fingerprint } => {
                write!(f, "{label}: host key {fingerprint} is revoked")
            }
            Self::BadCertificate { label, reason } => {
                write!(f, "{label}: bad host certificate ({reason})")
            }
            Self::AuthFailed {
                label,
                user,
                methods,
            } => write!(
                f,
                "{label}: authentication failed for {user} (server accepts {})",
                methods.join(", ")
            ),
            Self::Cancelled => write!(f, "cancelled"),
            Self::NoSftp { label } => write!(f, "{label}: the server has no SFTP"),
            Self::Network { label, message } => write!(f, "{label}: {message}"),
            Self::Other(message) => write!(f, "{message}"),
        }
    }
}

/// Questions waiting for an answer, across every session.
#[derive(Default)]
pub(crate) struct Prompts {
    next: AtomicU64,
    pending: Mutex<HashMap<u64, oneshot::Sender<Answer>>>,
}

/// Forgets a question whose asker went away (its session was closed).
struct Forget<'a>(&'a Prompts, u64);

impl Drop for Forget<'_> {
    fn drop(&mut self) {
        self.0.lock().remove(&self.1);
    }
}

impl Prompts {
    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<u64, oneshot::Sender<Answer>>> {
        self.pending.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Sends `prompt` and waits; no answer counts as a cancel.
    pub async fn ask(&self, sink: &Arc<dyn EventSink>, prompt: Prompt) -> Answer {
        let id = self.next.fetch_add(1, Ordering::Relaxed) + 1;
        let (tx, rx) = oneshot::channel();
        self.lock().insert(id, tx);
        let _forget = Forget(self, id);
        sink.send(Event::Prompt { id, prompt });
        rx.await.unwrap_or(Answer::Cancel)
    }

    /// False if nothing waits on `id` any more.
    pub fn answer(&self, id: u64, answer: Answer) -> bool {
        match self.lock().remove(&id) {
            Some(tx) => tx.send(answer).is_ok(),
            None => false,
        }
    }
}
