//! What a session tells the UI, and the questions it waits on.
//!
//! A connection that needs something from the user (trusting a host key, a
//! passphrase, a password, a 2FA code) sends a [`Prompt`] with an id and
//! waits; the UI answers through [`crate::App::answer`]. Secrets in answers
//! are wiped from memory when dropped.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

pub use openward_ssh::known_hosts::CertProblem;
pub use openward_vault::proto::Protocol;
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
    /// Mosh was asked for and could not be: the session goes on over SSH
    /// (in tmux, to come back to it), for this reason.
    MoshFallback {
        reason: MoshFallback,
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
    /// Waiting for the security key of `label`'s key file to be touched.
    TouchKey,
    OpeningShell,
    OpeningSftp,
}

/// What the status bar shows about a live connection.
#[derive(Clone, Debug, PartialEq)]
pub struct Connected {
    /// SSH, Telnet (nothing encrypted: the SSH fields are empty) or a
    /// serial port (`host` is the port, `port` 0).
    pub protocol: Protocol,
    /// The shell goes over Mosh: SSH only started it (its fields are those
    /// of that SSH connection).
    pub mosh: bool,
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
    /// A host seen for the first time, or one known only by keys of other
    /// types. Accepting saves the key.
    HostKey {
        label: String,
        host: String,
        port: u16,
        algorithm: String,
        /// `SHA256:…`, as OpenSSH shows it.
        fingerprint: String,
        /// The types of the keys already known for the host: empty for a
        /// new host. Otherwise the server did not offer the key that is
        /// known, which may be someone else answering.
        known_types: Vec<String>,
    },
    Passphrase {
        key: String,
        retry: bool,
    },
    /// The PIN of the security key that holds `key` (a key made with
    /// `verify-required`). Not kept.
    SecurityKeyPin {
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
    /// Canonical OpenSSH text to revoke this exact key when rotating.
    pub key: String,
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
        problem: CertProblem,
    },
    AuthFailed {
        label: String,
        user: String,
        /// What the server would still accept.
        methods: Vec<String>,
        /// A certificate that went with one of the keys had run out, and
        /// was not offered: likely why (its path).
        expired_certificate: Option<String>,
        /// A security key's file was among the keys and its key did not
        /// sign: why (not plugged in, not touched…).
        security_key: Option<SecurityKeyProblem>,
    },
    Cancelled,
    /// The server has no SFTP (a Dropbear without `sftp-server`, a router).
    NoSftp {
        label: String,
    },
    /// A serial port that did not open, or went (the cable was pulled).
    Serial {
        port: String,
        problem: SerialProblem,
    },
    /// Could not reach the host, or the connection broke.
    Network {
        label: String,
        /// In English, for logs and «Detalles».
        message: String,
        /// What it was, for the UI to say it in its words.
        cause: NetCause,
    },
    Other(String),
}

/// Why a security key did not sign or make a key.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SecurityKeyProblem {
    /// None is plugged in.
    NoKey,
    /// More than one: which is not clear.
    TooManyKeys,
    /// Its PIN is needed (and was not given).
    PinRequired,
    WrongPin,
    /// Too many wrong PINs.
    Locked,
    NotTouched,
    /// The key plugged in is not the one this file is for.
    NotThisKey,
    /// The system does not let OpenWard talk to it (Windows, without
    /// administrator rights: use the agent of Windows' OpenSSH).
    NoAccess,
    Other,
}

impl SecurityKeyProblem {
    pub fn of(e: &openward_fido::FidoError) -> Self {
        use openward_fido::FidoError as F;
        match e {
            F::NoKey => Self::NoKey,
            F::TooManyKeys => Self::TooManyKeys,
            F::PinRequired => Self::PinRequired,
            F::WrongPin => Self::WrongPin,
            F::Locked => Self::Locked,
            F::NotTouched => Self::NotTouched,
            F::NotThisKey => Self::NotThisKey,
            F::NoAccess => Self::NoAccess,
            F::Other(_) => Self::Other,
        }
    }
}

/// Why a session asked to go over Mosh goes over SSH instead.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MoshFallback {
    /// `mosh-client` is not installed on this computer.
    NoClient,
    /// The server has no `mosh-server` (where it was looked for).
    NoServer,
    /// The server's UDP did not get through (a firewall, a NAT, a jump).
    NoUdp,
    /// `mosh-server` did not start: what it said.
    Other(String),
}

/// What went wrong with a serial port.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SerialProblem {
    /// There is no such port (now): unplugged, or another name.
    Missing,
    /// Another program (or tab) has it open.
    Busy,
    /// This user may not open it (on Linux, not in `dialout`).
    Denied,
    /// The port does not take these settings.
    Settings(String),
    /// It went while open: the cable or the adapter was pulled.
    Gone,
    Other(String),
}

impl SerialProblem {
    pub fn of(e: &openward_serial::OpenError) -> Self {
        use openward_serial::OpenError as E;
        match e {
            E::Missing(_) => Self::Missing,
            E::Busy(_) => Self::Busy,
            E::Denied(_) => Self::Denied,
            E::Settings(_, why) => Self::Settings(why.clone()),
            E::Other(_, why) => Self::Other(why.clone()),
        }
    }
}

/// What kind of network trouble a [`Failure::Network`] is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NetCause {
    /// Nothing listens there: the connection was refused.
    Refused,
    /// Its name does not resolve.
    NotFound,
    /// No route to it: off, on another network, or (macOS) without the
    /// Local Network permission.
    Unreachable,
    /// It did not answer in time: for so many seconds, or (0) the system
    /// gave up on its own.
    Silent(u32),
    /// The connection went away.
    Lost,
    /// The ProxyCommand failed, and wrote these lines before it went.
    ProxyCommand(Vec<String>),
    Other,
}

impl NetCause {
    /// What `e` says went wrong: by the error's type where it has one; a
    /// name that does not resolve only says so in words.
    pub fn of(e: &anyhow::Error) -> Self {
        use openward_ssh::russh::Error as Ssh;
        // Its words say more than the error it went with.
        if let Some(said) = e.downcast_ref::<openward_ssh::client::ProxyCommandSaid>() {
            return Self::ProxyCommand(said.0.clone());
        }
        for cause in e.chain() {
            if let Some(silent) = cause.downcast_ref::<openward_ssh::client::NoAnswer>() {
                return Self::Silent(silent.0.as_secs() as u32);
            }
            let io = cause.downcast_ref::<std::io::Error>();
            // russh's own is transparent: its io error is not in the chain.
            let io = io.or(match cause.downcast_ref::<Ssh>() {
                Some(Ssh::IO(io)) => Some(io),
                _ => None,
            });
            if let Some(kind) = io.and_then(Self::of_io) {
                return kind;
            }
            match cause.downcast_ref::<Ssh>() {
                Some(Ssh::Disconnect | Ssh::HUP | Ssh::SendError | Ssh::RecvError) => {
                    return Self::Lost;
                }
                Some(
                    Ssh::ConnectionTimeout
                    | Ssh::KeepaliveTimeout
                    | Ssh::InactivityTimeout
                    | Ssh::Elapsed(_),
                ) => return Self::Silent(0),
                _ => {}
            }
        }
        let text = format!("{e:#}").to_lowercase();
        let says = |words: &[&str]| words.iter().any(|w| text.contains(w));
        if says(&[
            "failed to lookup address",
            "nodename nor servname",
            "name or service not known",
            "no such host",
        ]) {
            Self::NotFound
        } else if says(&["no route to host", "host is unreachable"]) {
            Self::Unreachable
        } else {
            Self::Other
        }
    }

    fn of_io(io: &std::io::Error) -> Option<Self> {
        use std::io::ErrorKind as K;
        Some(match io.kind() {
            K::ConnectionRefused => Self::Refused,
            K::TimedOut => Self::Silent(0),
            K::HostUnreachable | K::NetworkUnreachable => Self::Unreachable,
            K::ConnectionReset
            | K::ConnectionAborted
            | K::BrokenPipe
            | K::UnexpectedEof
            | K::NotConnected => Self::Lost,
            _ => return None,
        })
    }
}

impl Failure {
    /// The network failed `label`, as `e` says.
    pub fn network(label: String, e: &anyhow::Error) -> Self {
        Self::Network {
            label,
            message: format!("{e:#}"),
            cause: NetCause::of(e),
        }
    }

    /// The connection to `label` went away.
    pub fn lost(label: String) -> Self {
        Self::Network {
            label,
            message: "connection lost".into(),
            cause: NetCause::Lost,
        }
    }

    /// `label` stopped answering for `silent`.
    pub fn silent(label: String, silent: std::time::Duration) -> Self {
        Self::Network {
            label,
            message: crate::no_answer(silent),
            cause: NetCause::Silent(silent.as_secs() as u32),
        }
    }
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
            Self::BadCertificate { label, problem } => {
                write!(f, "{label}: bad host certificate ({problem})")
            }
            Self::AuthFailed {
                label,
                user,
                methods,
                ..
            } => write!(
                f,
                "{label}: authentication failed for {user} (server accepts {})",
                methods.join(", ")
            ),
            Self::Cancelled => write!(f, "cancelled"),
            Self::NoSftp { label } => write!(f, "{label}: the server has no SFTP"),
            Self::Serial { port, problem } => match problem {
                SerialProblem::Missing => write!(f, "{port}: no such serial port"),
                SerialProblem::Busy => write!(f, "{port} is in use by another program"),
                SerialProblem::Denied => write!(f, "not allowed to open {port}"),
                SerialProblem::Settings(why) => write!(f, "{port}: {why}"),
                SerialProblem::Gone => write!(f, "{port} went away"),
                SerialProblem::Other(why) => write!(f, "{port}: {why}"),
            },
            Self::Network { label, message, .. } => write!(f, "{label}: {message}"),
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

#[cfg(test)]
mod tests {
    use std::io;
    use std::time::Duration;

    use anyhow::{Context, anyhow};

    use super::NetCause;

    fn io(kind: io::ErrorKind) -> anyhow::Error {
        anyhow::Error::new(io::Error::from(kind)).context("connecting to db.example:22")
    }

    #[test]
    fn network_trouble_goes_by_type() {
        assert_eq!(
            NetCause::of(&io(io::ErrorKind::ConnectionRefused)),
            NetCause::Refused
        );
        assert_eq!(
            NetCause::of(&io(io::ErrorKind::TimedOut)),
            NetCause::Silent(0)
        );
        assert_eq!(
            NetCause::of(&io(io::ErrorKind::HostUnreachable)),
            NetCause::Unreachable
        );
        assert_eq!(
            NetCause::of(&io(io::ErrorKind::ConnectionReset)),
            NetCause::Lost
        );
        let silent: anyhow::Error = openward_ssh::client::NoAnswer(Duration::from_secs(7)).into();
        assert_eq!(
            NetCause::of(&silent.context("handshake")),
            NetCause::Silent(7)
        );
        let gone: anyhow::Error = openward_ssh::russh::Error::Disconnect.into();
        assert_eq!(NetCause::of(&gone), NetCause::Lost);
        // russh's own error hides the io one from the chain.
        let refused =
            openward_ssh::russh::Error::IO(io::Error::from(io::ErrorKind::ConnectionRefused));
        let refused = anyhow::Error::new(refused).context("connecting to db.example:22");
        assert_eq!(NetCause::of(&refused), NetCause::Refused);
        let said = openward_ssh::client::ProxyCommandSaid(vec!["command not found".into()]);
        let failed = io(io::ErrorKind::UnexpectedEof)
            .context(said)
            .context("hop db");
        assert_eq!(
            NetCause::of(&failed),
            NetCause::ProxyCommand(vec!["command not found".into()])
        );
    }

    #[test]
    fn a_name_that_does_not_resolve_is_not_found() {
        // What the resolver says, on macOS and on Linux.
        for words in [
            "failed to lookup address information: nodename nor servname provided, or not known",
            "failed to lookup address information: Name or service not known",
        ] {
            let e = Err::<(), _>(anyhow!("{words}"))
                .context("db.example")
                .unwrap_err();
            assert_eq!(NetCause::of(&e), NetCause::NotFound);
        }
        assert_eq!(NetCause::of(&anyhow!("something else")), NetCause::Other);
    }
}
