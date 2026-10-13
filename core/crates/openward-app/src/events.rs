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
pub enum Stage {
    Connecting,
    Authenticating,
    OpeningShell,
}

/// What the status bar shows about a live connection.
#[derive(Clone, Debug, PartialEq)]
pub struct Connected {
    pub kex: String,
    pub post_quantum: bool,
    pub cipher: String,
    pub host_key_algorithm: String,
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

/// Why a connection did not come up or went away.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Failure {
    /// The host key differs from the one trusted: possibly an attack. The
    /// new key is only trusted by an explicit action
    /// ([`crate::App::trust_host_key`]).
    HostKeyChanged {
        label: String,
        host: String,
        port: u16,
        algorithm: String,
        fingerprint: String,
        /// The offered key, OpenSSH format.
        key: String,
    },
    /// Unknown key refused: by the user, or by a strict policy.
    HostKeyRejected {
        label: String,
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
            Self::HostKeyChanged {
                label, fingerprint, ..
            } => write!(f, "{label}: host key changed (now {fingerprint})"),
            Self::HostKeyRejected { label } => write!(f, "{label}: host key not trusted"),
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
