//! SSH client on `russh`: generic transport, authentication, host trust and
//! the server-initiated channels (remote forwards, agent forwarding).
//!
//! Shaped like the future `core/crates/openward-ssh`: the transport is any
//! byte stream (TCP, ProxyCommand, or a `direct-tcpip` channel of another
//! session), so jumps and proxies compose without special cases.

use std::borrow::Cow;
use std::collections::{HashMap, VecDeque};
use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::Context;
use russh::client::{self, AuthResult, KeyboardInteractiveAuthResponse};
use russh::keys::agent::AgentIdentity;
use russh::keys::agent::client::AgentClient;
use russh::keys::agent::client::AgentStream;
use russh::keys::{
    Algorithm, Certificate, EcdsaCurve, PrivateKey, PrivateKeyWithHashAlg, PublicKey,
    PublicKeyOrCertificate,
};
use russh::{Channel, ChannelMsg, MethodKind, Pty};
use tokio::io::AsyncWriteExt;
use tokio::process::{Child, Command};

use crate::known_hosts::{KnownHosts, Verdict};
#[cfg(feature = "test-auth")]
use crate::totp;

#[derive(Clone, Debug)]
pub struct Target {
    pub host: String,
    pub port: u16,
}

impl Target {
    pub fn new(host: &str, port: u16) -> Self {
        Self {
            host: host.to_owned(),
            port,
        }
    }
}

/// How the bytes reach the target.
pub enum Hop<'a> {
    Tcp,
    /// A command whose stdin/stdout carry the connection (`nc host port`,
    /// `cloudflared access ssh`, `aws ssm …`). Desktop only.
    ProxyCommand(String),
    /// A `direct-tcpip` channel through an authenticated session (jump host).
    Via(&'a Session),
    /// An HTTP or SOCKS5 proxy. Fails with [`crate::proxy::ProxyAuthRequired`]
    /// when the proxy wants a password it was not given.
    Proxy(crate::proxy::Proxy),
}

/// One way to authenticate, its secrets at hand (spikes and tests).
#[cfg(feature = "test-auth")]
#[derive(Clone, Debug)]
pub enum Auth {
    Password(String),
    Key {
        path: PathBuf,
        passphrase: Option<String>,
    },
    /// An OpenSSH user certificate and its private key.
    Cert {
        key: PathBuf,
        cert: PathBuf,
    },
    /// Every identity of an ssh-agent (`SSH_AUTH_SOCK`).
    Agent {
        socket: PathBuf,
    },
    /// Answers prompts by their text: the password, then a TOTP code.
    KeyboardInteractive {
        password: String,
        totp_secret: Option<String>,
    },
}

/// A host key `known_hosts` does not vouch for: unknown, changed, or a
/// certificate that does not check out.
#[derive(Clone, Debug)]
pub struct HostKeyQuery {
    pub host: String,
    pub port: u16,
    pub key: PublicKey,
    pub verdict: Verdict,
    /// The types of the keys known for the host (with [`Verdict::OtherType`]).
    pub known_types: Vec<String>,
}

/// Decides on a [`HostKeyQuery`]: true to go on. It may take its time, to
/// ask the user.
pub type HostKeyHook =
    Arc<dyn Fn(HostKeyQuery) -> Pin<Box<dyn Future<Output = bool> + Send>> + Send + Sync>;

#[derive(Clone)]
pub struct Options {
    pub user: String,
    pub known_hosts: Arc<Mutex<KnownHosts>>,
    /// Ask servers for host certificates (only useful with a trusted CA).
    pub host_certificates: bool,
    /// Accept `ssh-rsa` host key signatures, made with SHA-1, for servers
    /// older than OpenSSH 7.2 that sign no other way. OpenSSH stopped
    /// accepting them in 8.8.
    pub legacy_host_keys: bool,
    /// How long the server has to answer: to set up the connection (up to
    /// the host key, without the time spent asking the user about it), and
    /// then each step of authentication. `None` waits for ever.
    pub connect_timeout: Option<Duration>,
    pub keepalive: Option<Duration>,
    /// Local agent that forwarded agent requests are relayed to.
    pub agent_forward: Option<PathBuf>,
    /// Asked about plain host keys that are not trusted. Without it they
    /// are refused (or learned, if `known_hosts` learns).
    pub on_untrusted: Option<HostKeyHook>,
}

/// What was negotiated and how the host was trusted.
#[derive(Clone, Debug, Default)]
pub struct Info {
    pub kex: String,
    pub cipher: String,
    pub mac: String,
    pub host_key: String,
    /// `SHA256:…` of the host key (of the key a certificate certifies).
    pub host_key_fingerprint: String,
    pub verdict: Option<Verdict>,
    /// From opening the transport to authenticated.
    pub connect_ms: f64,
    /// What the server said it runs, before anything else
    /// (`SSH-2.0-OpenSSH_9.2p1 Debian-2+deb12u3`).
    pub server_id: String,
}

impl Info {
    pub fn post_quantum(&self) -> bool {
        self.kex.starts_with("mlkem") || self.kex.starts_with("sntrup")
    }
}

struct Shared {
    info: Info,
    /// Remote forward port on the server → local address it leads to, and
    /// how many connections are going through it.
    remote_forwards: HashMap<u32, (String, u16, Arc<AtomicU32>)>,
    started: Instant,
    /// The user is being asked about the host key: not the server's time.
    asking: bool,
    /// Time spent asking so far, still to add to the opening's limit.
    asked: Duration,
}

/// The server did not answer in time.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NoAnswer(pub Duration);

impl std::fmt::Display for NoAnswer {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "no answer for {} s", self.0.as_secs())
    }
}

impl std::error::Error for NoAnswer {}

/// What a ProxyCommand wrote before it went (its last lines of stderr):
/// why it failed, likely. The context of the error it failed with.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProxyCommandSaid(pub Vec<String>);

impl std::fmt::Display for ProxyCommandSaid {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "ProxyCommand: {}", self.0.join(" · "))
    }
}

/// An agent may wait for its user (a touch, an approval): longer than a
/// server's answer.
const AGENT_TIMEOUT: Duration = Duration::from_secs(120);

/// Opens a connection within `limit`, not counting the time spent asking
/// the user about the host key.
async fn within_limit<T>(
    fut: impl Future<Output = anyhow::Result<T>>,
    limit: Option<Duration>,
    shared: &Mutex<Shared>,
) -> anyhow::Result<T> {
    let Some(limit) = limit else {
        return fut.await;
    };
    tokio::pin!(fut);
    let mut deadline = tokio::time::Instant::now() + limit;
    loop {
        tokio::select! {
            out = &mut fut => return out,
            () = tokio::time::sleep_until(deadline) => {
                let mut s = shared.lock().unwrap();
                if s.asking {
                    deadline += Duration::from_secs(1);
                    continue;
                }
                let asked = std::mem::take(&mut s.asked);
                if asked.is_zero() {
                    return Err(NoAnswer(limit).into());
                }
                deadline += asked;
            }
        }
    }
}

pub struct Handler {
    target: Target,
    known_hosts: Arc<Mutex<KnownHosts>>,
    agent_forward: Option<PathBuf>,
    on_untrusted: Option<HostKeyHook>,
    shared: Arc<Mutex<Shared>>,
}

impl client::Handler for Handler {
    type Error = anyhow::Error;

    async fn check_server_key(
        &mut self,
        offered: &PublicKeyOrCertificate,
    ) -> Result<bool, Self::Error> {
        let key = match offered {
            PublicKeyOrCertificate::PublicKey { key, .. } => key.clone(),
            PublicKeyOrCertificate::Certificate(cert) => PublicKey::from(cert.public_key().clone()),
        };
        let (host, port) = (&self.target.host, self.target.port);
        let (mut verdict, plain, known_types) = {
            let mut known = self.known_hosts.lock().unwrap();
            let verdict = known.check(host, port, offered);
            // As OpenSSH: a certificate that does not hold up falls back to
            // its plain key.
            let plain = match (&verdict, offered) {
                (Verdict::BadCertificate(_), PublicKeyOrCertificate::Certificate(_)) => {
                    let plain = PublicKeyOrCertificate::PublicKey {
                        key: key.clone(),
                        hash_alg: None,
                    };
                    Some(known.check(host, port, &plain))
                }
                _ => None,
            };
            let types = known.algorithms(host, port);
            let types = types.iter().map(ToString::to_string).collect();
            (verdict, plain, types)
        };
        self.shared.lock().unwrap().info.host_key_fingerprint =
            key.fingerprint(russh::keys::HashAlg::Sha256).to_string();
        // The key's own verdict: the plain key's, after a bad certificate.
        let own = plain.clone().unwrap_or_else(|| verdict.clone());
        if own.trusted() {
            verdict = own.clone();
        }
        let plain_key =
            plain.is_some() || matches!(offered, PublicKeyOrCertificate::PublicKey { .. });
        if let (false, Some(hook), true) = (own.trusted(), &self.on_untrusted, plain_key) {
            let query = HostKeyQuery {
                host: host.clone(),
                port,
                key,
                verdict: own.clone(),
                known_types,
            };
            let asked = Instant::now();
            self.shared.lock().unwrap().asking = true;
            let accepted = hook(query).await;
            let mut shared = self.shared.lock().unwrap();
            shared.asking = false;
            shared.asked += asked.elapsed();
            drop(shared);
            if accepted {
                verdict = Verdict::Learned;
            } else if own == Verdict::Changed {
                // A changed key outweighs the certificate's fault.
                verdict = own;
            }
        }
        let trusted = verdict.trusted();
        self.shared.lock().unwrap().info.verdict = Some(verdict);
        Ok(trusted)
    }

    async fn kex_done(
        &mut self,
        _shared_secret: Option<&[u8]>,
        names: &russh::Names,
        session: &mut client::Session,
    ) -> Result<(), Self::Error> {
        let mut shared = self.shared.lock().unwrap();
        shared.info.server_id = String::from_utf8_lossy(session.remote_sshid())
            .trim()
            .to_owned();
        shared.info.kex = names.kex.as_ref().to_owned();
        shared.info.cipher = names.cipher.as_ref().to_owned();
        shared.info.mac = names.client_mac.as_ref().to_owned();
        shared.info.host_key = names.key.to_string();
        Ok(())
    }

    async fn server_channel_open_forwarded_tcpip(
        &mut self,
        channel: Channel<client::Msg>,
        _connected_address: &str,
        connected_port: u32,
        _originator_address: &str,
        _originator_port: u32,
        reply: client::ChannelOpenHandle,
        _session: &mut client::Session,
    ) -> Result<(), Self::Error> {
        let local = self
            .shared
            .lock()
            .unwrap()
            .remote_forwards
            .get(&connected_port)
            .cloned();
        let Some((host, port, active)) = local else {
            // Not ours: dropping the reply rejects the channel.
            return Ok(());
        };
        reply.accept().await;
        tokio::spawn(async move {
            if let Ok(mut socket) = tokio::net::TcpStream::connect((host.as_str(), port)).await {
                active.fetch_add(1, Ordering::Relaxed);
                let mut stream = channel.into_stream();
                let _ = tokio::io::copy_bidirectional(&mut stream, &mut socket).await;
                active.fetch_sub(1, Ordering::Relaxed);
            }
        });
        Ok(())
    }

    async fn server_channel_open_agent_forward(
        &mut self,
        channel: Channel<client::Msg>,
        reply: client::ChannelOpenHandle,
        _session: &mut client::Session,
    ) -> Result<(), Self::Error> {
        let Some(socket) = self.agent_forward.clone() else {
            return Ok(()); // agent forwarding not offered: reject
        };
        reply.accept().await;
        tokio::spawn(async move {
            if let Ok(mut agent) = connect_agent(&socket).await {
                let mut stream = channel.into_stream();
                let _ = tokio::io::copy_bidirectional(&mut stream, &mut agent).await;
            }
        });
        Ok(())
    }
}

/// The local ssh-agent: a Unix socket, or a named pipe on Windows
/// (`\\.\pipe\openssh-ssh-agent`).
#[cfg(unix)]
async fn connect_agent(path: &std::path::Path) -> std::io::Result<tokio::net::UnixStream> {
    tokio::net::UnixStream::connect(path).await
}

#[cfg(windows)]
async fn connect_agent(
    path: &std::path::Path,
) -> std::io::Result<tokio::net::windows::named_pipe::NamedPipeClient> {
    tokio::net::windows::named_pipe::ClientOptions::new().open(path)
}

/// ProxyCommand runs through the platform shell, as OpenSSH does, with
/// the `PATH` of a terminal.
async fn shell_command(command: &str) -> Command {
    let mut c = if cfg!(windows) {
        let mut c = Command::new("cmd");
        c.arg("/C");
        c
    } else {
        let mut c = Command::new("sh");
        c.arg("-c");
        c
    };
    c.arg(command);
    if let Some(login) = login_path().await {
        let own = std::env::var_os("PATH").unwrap_or_default();
        if let Some(path) = merge_paths(login, &own) {
            c.env("PATH", path);
        }
    }
    c
}

/// The `PATH` of the user's login shell, asked once. An app opened from
/// the Finder gets launchd's (`/usr/bin:/bin:…`), without Homebrew's or
/// the user's own folders, where `cloudflared` or `aws` live.
async fn login_path() -> Option<&'static std::ffi::OsStr> {
    static PATH: tokio::sync::OnceCell<Option<std::ffi::OsString>> =
        tokio::sync::OnceCell::const_new();
    if cfg!(windows) {
        return None;
    }
    PATH.get_or_init(|| async {
        const MARK: &str = "__openward_path__";
        let shell = std::env::var_os("SHELL")?;
        // Between marks: a profile may print things of its own.
        let ask = Command::new(shell)
            .args(["-l", "-c", &format!("printf '{MARK}%s{MARK}' \"$PATH\"")])
            .stdin(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .kill_on_drop(true)
            .output();
        let out = tokio::time::timeout(Duration::from_secs(3), ask)
            .await
            .ok()?
            .ok()?;
        let text = String::from_utf8(out.stdout).ok()?;
        let path = text.split(MARK).nth(1)?;
        (!path.is_empty()).then(|| path.into())
    })
    .await
    .as_deref()
}

/// Where a program on this computer is (`mosh-client`): in the login
/// shell's `PATH`, the app's own, or the usual places of package managers
/// that an app opened from the Finder does not see.
pub async fn find_program(name: &str) -> Option<PathBuf> {
    let own = std::env::var_os("PATH").unwrap_or_default();
    let path = match login_path().await {
        Some(login) => merge_paths(login, &own).unwrap_or(own),
        None => own,
    };
    let mut dirs: Vec<PathBuf> = std::env::split_paths(&path).collect();
    for extra in [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/snap/bin",
        "/run/current-system/sw/bin",
    ] {
        dirs.push(PathBuf::from(extra));
    }
    if let Some(home) = std::env::var_os("HOME") {
        dirs.push(PathBuf::from(home).join(".nix-profile/bin"));
    }
    let file = if cfg!(windows) {
        format!("{name}.exe")
    } else {
        name.to_owned()
    };
    dirs.into_iter()
        .map(|d| d.join(&file))
        .find(|p| p.is_file())
}

/// The login shell's folders, then the app's own that it lacks.
fn merge_paths(login: &std::ffi::OsStr, own: &std::ffi::OsStr) -> Option<std::ffi::OsString> {
    let mut dirs: Vec<PathBuf> = std::env::split_paths(login).collect();
    for dir in std::env::split_paths(own) {
        if !dirs.contains(&dir) {
            dirs.push(dir);
        }
    }
    std::env::join_paths(dirs).ok()
}

/// Keeps the last lines a ProxyCommand writes to stderr, to tell why it
/// failed; the rest is read and let go, so that it never blocks.
async fn last_lines(stderr: tokio::process::ChildStderr, said: Arc<Mutex<VecDeque<String>>>) {
    use tokio::io::AsyncBufReadExt;
    let mut lines = tokio::io::BufReader::new(stderr).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let mut said = said.lock().unwrap();
        if said.len() == 3 {
            said.pop_front();
        }
        said.push_back(line.chars().take(300).collect());
    }
}

pub struct Session {
    pub handle: client::Handle<Handler>,
    shared: Arc<Mutex<Shared>>,
    /// How long the server has for each step of authentication.
    limit: Option<Duration>,
    /// Methods tried, `none` aside.
    attempts: u32,
    /// The ProxyCommand process, killed with the session.
    _proxy: Option<Child>,
}

/// The most of a command's output [`Session::exec_short`] keeps.
pub const EXEC_OUTPUT: usize = 64 * 1024;

/// A terminal's modes, as OpenSSH sends its own: the usual control keys
/// (erase is DEL, what ⌫ sends), cooked mode, and UTF-8, so that ⌫ after
/// an «ñ» takes the whole character. The server keeps its own for the rest.
const PTY_MODES: &[(Pty, u32)] = &[
    (Pty::VINTR, 0x03),
    (Pty::VQUIT, 0x1c),
    (Pty::VERASE, 0x7f),
    (Pty::VKILL, 0x15),
    (Pty::VEOF, 0x04),
    (Pty::VSUSP, 0x1a),
    (Pty::VREPRINT, 0x12),
    (Pty::VWERASE, 0x17),
    (Pty::VLNEXT, 0x16),
    (Pty::ICRNL, 1),
    (Pty::IUTF8, 1),
    (Pty::ISIG, 1),
    (Pty::ICANON, 1),
    (Pty::IEXTEN, 1),
    (Pty::ECHO, 1),
    (Pty::ECHOE, 1),
    (Pty::ECHOK, 1),
    (Pty::ECHOCTL, 1),
    (Pty::ECHOKE, 1),
    (Pty::OPOST, 1),
    (Pty::ONLCR, 1),
    (Pty::CS8, 1),
    (Pty::TTY_OP_ISPEED, 38400),
    (Pty::TTY_OP_OSPEED, 38400),
];

/// Host key algorithms whose certificate variants we ask for.
const CERT_ALGORITHMS: &[Algorithm] = &[
    Algorithm::Ed25519,
    Algorithm::Ecdsa {
        curve: EcdsaCurve::NistP256,
    },
    Algorithm::Rsa {
        hash: Some(russh::keys::HashAlg::Sha512),
    },
];

/// The host key types to ask for, best first: those of the keys already
/// known for the host go ahead, as OpenSSH does, so that a host known by
/// its ECDSA key is checked against that key and not taken for a new host
/// when it also has an Ed25519 one. `ssh-rsa` with SHA-1 only if `legacy`.
fn host_key_order(known: &[Algorithm], legacy: bool) -> Vec<Algorithm> {
    let same_type = |a: &Algorithm, b: &Algorithm| match (a, b) {
        // One RSA key signs with any of the hashes.
        (Algorithm::Rsa { .. }, Algorithm::Rsa { .. }) => true,
        _ => a == b,
    };
    let (first, rest): (Vec<Algorithm>, Vec<Algorithm>) = russh::Preferred::DEFAULT
        .key
        .iter()
        .filter(|a| legacy || !matches!(a, Algorithm::Rsa { hash: None }))
        .cloned()
        .partition(|a| known.iter().any(|k| same_type(k, a)));
    first.into_iter().chain(rest).collect()
}

/// Opens the transport and checks the host key; the session still has to
/// authenticate (the `auth_*` methods) before it can open channels.
pub async fn open(target: &Target, hop: Hop<'_>, opts: &Options) -> anyhow::Result<Session> {
    let started = Instant::now();
    let mut config = client::Config {
        // Terminal traffic is many tiny writes: Nagle would hold keystrokes.
        nodelay: true,
        keepalive_interval: opts.keepalive,
        keepalive_max: 3,
        // What a server may send before we ask for more. russh's 2 MiB,
        // reopened by halves, caps a download at ~1 MiB per round trip
        // (about 20 MiB/s at 50 ms); SFTP needs far more in flight.
        window_size: 16 << 20,
        ..Default::default()
    };
    if opts.host_certificates {
        config.preferred.host_key_certificates = Cow::Borrowed(CERT_ALGORITHMS);
    }
    let known = opts
        .known_hosts
        .lock()
        .unwrap()
        .algorithms(&target.host, target.port);
    config.preferred.key = Cow::Owned(host_key_order(&known, opts.legacy_host_keys));
    let config = Arc::new(config);
    let shared = Arc::new(Mutex::new(Shared {
        info: Info::default(),
        remote_forwards: HashMap::new(),
        started,
        asking: false,
        asked: Duration::ZERO,
    }));
    let handler = Handler {
        target: target.clone(),
        known_hosts: Arc::clone(&opts.known_hosts),
        agent_forward: opts.agent_forward.clone(),
        on_untrusted: opts.on_untrusted.clone(),
        shared: Arc::clone(&shared),
    };

    let mut proxy = None;
    let said = Arc::new(Mutex::new(VecDeque::new()));
    let mut reading = None;
    let opening = async {
        match hop {
            Hop::Tcp => client::connect(config, (target.host.as_str(), target.port), handler).await,
            Hop::ProxyCommand(command) => {
                let mut child = shell_command(&command)
                    .await
                    .stdin(std::process::Stdio::piped())
                    .stdout(std::process::Stdio::piped())
                    .stderr(std::process::Stdio::piped())
                    .kill_on_drop(true)
                    .spawn()
                    .with_context(|| format!("ProxyCommand {command}"))?;
                if let Some(stderr) = child.stderr.take() {
                    reading = Some(tokio::spawn(last_lines(stderr, Arc::clone(&said))));
                }
                let stream = tokio::io::join(
                    child.stdout.take().context("ProxyCommand stdout")?,
                    child.stdin.take().context("ProxyCommand stdin")?,
                );
                proxy = Some(child);
                client::connect_stream(config, stream, handler).await
            }
            Hop::Proxy(p) => {
                let stream = crate::proxy::connect(&p, &target.host, target.port).await?;
                client::connect_stream(config, stream, handler).await
            }
            Hop::Via(jump) => {
                let channel = jump
                    .handle
                    .channel_open_direct_tcpip(
                        target.host.as_str(),
                        u32::from(target.port),
                        "127.0.0.1",
                        0,
                    )
                    .await
                    .context("direct-tcpip through the jump host")?;
                client::connect_stream(config, channel.into_stream(), handler).await
            }
        }
    };
    let result = within_limit(opening, opts.connect_timeout, &shared).await;
    let handle = match result {
        Ok(handle) => handle,
        Err(e) => {
            // A refused host key surfaces as a generic error: say why.
            if let Some(v) = shared.lock().unwrap().info.verdict.clone()
                && !v.trusted()
            {
                return Err(UntrustedHost(v).into());
            }
            // What the ProxyCommand said before it went: why, likely.
            if let Some(reading) = reading {
                let _ = tokio::time::timeout(Duration::from_millis(500), reading).await;
            }
            let said = said.lock().unwrap();
            if !said.is_empty() {
                return Err(e.context(ProxyCommandSaid(said.iter().cloned().collect())));
            }
            return Err(e);
        }
    };
    Ok(Session {
        handle,
        shared,
        limit: opts.connect_timeout,
        attempts: 0,
        _proxy: proxy,
    })
}

/// A plain byte stream, both ways.
pub trait Duplex: tokio::io::AsyncRead + tokio::io::AsyncWrite + Send + Unpin {}

impl<T: tokio::io::AsyncRead + tokio::io::AsyncWrite + Send + Unpin> Duplex for T {}

/// A connection that is not SSH (Telnet) to `target`, the way an SSH one
/// would go: straight, through a proxy or a ProxyCommand, or out of a
/// jump host. A ProxyCommand's program lives as long as the stream.
pub struct Stream {
    io: Box<dyn Duplex>,
    _proxy: Option<Child>,
}

impl tokio::io::AsyncRead for Stream {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        Pin::new(&mut self.io).poll_read(cx, buf)
    }
}

impl tokio::io::AsyncWrite for Stream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        Pin::new(&mut self.io).poll_write(cx, buf)
    }

    fn poll_flush(
        mut self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        Pin::new(&mut self.io).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        Pin::new(&mut self.io).poll_shutdown(cx)
    }
}

/// Opens a [`Stream`] within `limit`.
pub async fn open_stream(
    target: &Target,
    hop: Hop<'_>,
    limit: Option<Duration>,
) -> anyhow::Result<Stream> {
    let opening = async {
        Ok(match hop {
            Hop::Tcp => {
                let tcp = tokio::net::TcpStream::connect((target.host.as_str(), target.port))
                    .await
                    .with_context(|| format!("connecting to {}:{}", target.host, target.port))?;
                let _ = tcp.set_nodelay(true);
                Stream {
                    io: Box::new(tcp),
                    _proxy: None,
                }
            }
            Hop::ProxyCommand(command) => {
                let mut child = shell_command(&command)
                    .await
                    .stdin(std::process::Stdio::piped())
                    .stdout(std::process::Stdio::piped())
                    .stderr(std::process::Stdio::null())
                    .kill_on_drop(true)
                    .spawn()
                    .with_context(|| format!("ProxyCommand {command}"))?;
                let io = tokio::io::join(
                    child.stdout.take().context("ProxyCommand stdout")?,
                    child.stdin.take().context("ProxyCommand stdin")?,
                );
                Stream {
                    io: Box::new(io),
                    _proxy: Some(child),
                }
            }
            Hop::Proxy(p) => Stream {
                io: Box::new(crate::proxy::connect(&p, &target.host, target.port).await?),
                _proxy: None,
            },
            Hop::Via(jump) => {
                let channel = jump
                    .handle
                    .channel_open_direct_tcpip(
                        target.host.as_str(),
                        u32::from(target.port),
                        "127.0.0.1",
                        0,
                    )
                    .await
                    .context("direct-tcpip through the jump host")?;
                Stream {
                    io: Box::new(channel.into_stream()),
                    _proxy: None,
                }
            }
        })
    };
    match limit {
        Some(limit) => tokio::time::timeout(limit, opening)
            .await
            .map_err(|_| anyhow::Error::new(NoAnswer(limit)))?,
        None => opening.await,
    }
}

/// The host key was refused; the error carries the verdict.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UntrustedHost(pub Verdict);

impl std::fmt::Display for UntrustedHost {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "host key not trusted: {:?}", self.0)
    }
}

impl std::error::Error for UntrustedHost {}

/// The server has no SFTP subsystem.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NoSftp;

impl std::fmt::Display for NoSftp {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "the server has no SFTP subsystem")
    }
}

impl std::error::Error for NoSftp {}

/// Opens and authenticates with one method whose secrets are all at hand.
#[cfg(feature = "test-auth")]
pub async fn connect(
    target: &Target,
    hop: Hop<'_>,
    auth: &Auth,
    opts: &Options,
) -> anyhow::Result<Session> {
    let mut session = open(target, hop, opts).await?;
    authenticate(&mut session, &opts.user, auth).await?;
    Ok(session)
}

#[cfg(feature = "test-auth")]
async fn authenticate(session: &mut Session, user: &str, auth: &Auth) -> anyhow::Result<()> {
    let ok = match auth {
        Auth::Password(password) => session.auth_password(user, password).await?.success(),
        Auth::Key { path, passphrase } => {
            let key = load_key(path, passphrase.as_deref())?;
            session.auth_key(user, Arc::new(key)).await?.success()
        }
        Auth::Cert { key, cert } => {
            let key = load_key(key, None)?;
            let cert = russh::keys::load_openssh_certificate(cert)?;
            session
                .auth_cert(user, Arc::new(key), cert)
                .await?
                .success()
        }
        Auth::Agent { socket } => {
            let mut agent = Agent::connect(socket).await?;
            let mut ok = false;
            for key in agent.keys().await? {
                if session.auth_agent(user, &mut agent, key).await?.success() {
                    ok = true;
                    break;
                }
            }
            ok
        }
        Auth::KeyboardInteractive {
            password,
            totp_secret,
        } => {
            let mut step = session.kbd_start(user).await?;
            let mut rounds = 0;
            loop {
                match step {
                    Kbd::Done(outcome) => break outcome.success(),
                    Kbd::Questions { prompts, .. } => {
                        rounds += 1;
                        if rounds > 5 {
                            anyhow::bail!("keyboard-interactive: too many rounds");
                        }
                        let mut answers = Vec::with_capacity(prompts.len());
                        for (prompt, _echo) in &prompts {
                            let text = prompt.to_lowercase();
                            answers.push(if text.contains("password") {
                                password.clone()
                            } else if text.contains("verification") || text.contains("code") {
                                let secret = totp_secret.as_deref().context(
                                    "server asked for a code and there is no TOTP secret",
                                )?;
                                let now = std::time::SystemTime::now()
                                    .duration_since(std::time::UNIX_EPOCH)?
                                    .as_secs();
                                totp::code(secret, now)?
                            } else {
                                String::new()
                            });
                        }
                        step = session.kbd_respond(answers).await?;
                    }
                }
            }
        }
    };
    if !ok {
        anyhow::bail!("authentication failed ({})", auth_name(auth));
    }
    Ok(())
}

/// Why a private key could not be loaded.
#[derive(Debug, thiserror::Error)]
pub enum KeyError {
    #[error("the key is protected by a passphrase")]
    Encrypted,
    #[error("wrong passphrase")]
    WrongPassphrase,
    #[error("{0}")]
    Unreadable(String),
}

/// Loads a private key, decrypting it with `passphrase` if it is protected.
pub fn load_key(path: &Path, passphrase: Option<&str>) -> Result<PrivateKey, KeyError> {
    match crate::keyfile::load_secret_key(path, passphrase) {
        Ok(key) => Ok(key),
        Err(russh::keys::Error::KeyIsEncrypted) => Err(KeyError::Encrypted),
        // Without a passphrase an encrypted key says so; with one, a
        // failure to decode means it was wrong.
        Err(russh::keys::Error::IO(e)) => {
            Err(KeyError::Unreadable(format!("{}: {e}", path.display())))
        }
        Err(_) if passphrase.is_some() => Err(KeyError::WrongPassphrase),
        Err(e) => Err(KeyError::Unreadable(format!("{}: {e}", path.display()))),
    }
}

/// What the server said to an authentication attempt.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Outcome {
    Success,
    /// Not (yet) in. `partial` means the method was accepted but the server
    /// wants another one too.
    Continue {
        methods: Vec<MethodKind>,
        partial: bool,
    },
}

impl Outcome {
    pub fn success(&self) -> bool {
        matches!(self, Self::Success)
    }
}

impl From<AuthResult> for Outcome {
    fn from(r: AuthResult) -> Self {
        match r {
            AuthResult::Success => Self::Success,
            AuthResult::Failure {
                remaining_methods,
                partial_success,
            } => Self::Continue {
                methods: remaining_methods.to_vec(),
                partial: partial_success,
            },
        }
    }
}

/// A step of keyboard-interactive authentication.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Kbd {
    Done(Outcome),
    /// Answer each prompt (text, and whether the answer may be shown) with
    /// [`Session::kbd_respond`]. A round can have no prompts at all.
    Questions {
        name: String,
        instructions: String,
        prompts: Vec<(String, bool)>,
    },
}

impl From<KeyboardInteractiveAuthResponse> for Kbd {
    fn from(r: KeyboardInteractiveAuthResponse) -> Self {
        match r {
            KeyboardInteractiveAuthResponse::Success => Self::Done(Outcome::Success),
            KeyboardInteractiveAuthResponse::Failure {
                remaining_methods,
                partial_success,
            } => Self::Done(Outcome::Continue {
                methods: remaining_methods.to_vec(),
                partial: partial_success,
            }),
            KeyboardInteractiveAuthResponse::InfoRequest {
                name,
                instructions,
                prompts,
            } => Self::Questions {
                name,
                instructions,
                prompts: prompts.into_iter().map(|p| (p.prompt, p.echo)).collect(),
            },
        }
    }
}

/// The agent did not sign: another key or method may still do.
#[derive(Debug)]
pub enum AgentRefused {
    /// It said no (a denied confirmation, a locked agent).
    Refused(String),
    /// It did not answer in time (a key not touched): not to be asked
    /// again, its answer may still come.
    Silent(Duration),
}

impl std::fmt::Display for AgentRefused {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Refused(reason) => write!(f, "the agent did not sign: {reason}"),
            Self::Silent(limit) => write!(f, "the agent did not sign: {}", NoAnswer(*limit)),
        }
    }
}

impl std::error::Error for AgentRefused {}

/// The agent as russh's signer. Waiting for a signature, russh hears
/// nothing else: when the agent does not sign, the request is left unsent
/// and `refused` says why, so that the session takes the next one.
struct Signing<'a> {
    client: &'a mut AgentClient<Box<dyn AgentStream + Send + Unpin>>,
    limit: Option<Duration>,
    refused: Option<tokio::sync::oneshot::Sender<AgentRefused>>,
}

impl russh::Signer for Signing<'_> {
    type Error = russh::AgentAuthError;

    async fn auth_sign(
        &mut self,
        key: &AgentIdentity,
        hash_alg: Option<russh::keys::HashAlg>,
        to_sign: Vec<u8>,
    ) -> Result<Vec<u8>, Self::Error> {
        let sign = self.client.sign_request(key, hash_alg, to_sign.clone());
        let refused = |e: russh::keys::Error| AgentRefused::Refused(e.to_string());
        let signed = match self.limit {
            Some(limit) => match tokio::time::timeout(limit, sign).await {
                Ok(signed) => signed.map_err(refused),
                Err(_) => Err(AgentRefused::Silent(limit)),
            },
            None => sign.await.map_err(refused),
        };
        match signed {
            Ok(signed) => Ok(signed),
            Err(reason) => {
                if let Some(refused) = self.refused.take() {
                    let _ = refused.send(reason);
                }
                // Unchanged: russh sends nothing.
                Ok(to_sign)
            }
        }
    }
}

/// What signs with a key whose secret is elsewhere (a security key): it
/// gets the data to sign and gives SSH's signature, blocking meanwhile
/// (a touch).
pub type SignFn = Arc<dyn Fn(&[u8]) -> anyhow::Result<Vec<u8>> + Send + Sync>;

/// A key signed with by a [`SignFn`]; why it failed goes to `failed`.
struct ExternalSigning {
    sign: SignFn,
    failed: Option<tokio::sync::oneshot::Sender<anyhow::Error>>,
}

impl russh::Signer for ExternalSigning {
    type Error = russh::AgentAuthError;

    async fn auth_sign(
        &mut self,
        _key: &AgentIdentity,
        _hash_alg: Option<russh::keys::HashAlg>,
        mut to_sign: Vec<u8>,
    ) -> Result<Vec<u8>, Self::Error> {
        let sign = Arc::clone(&self.sign);
        let data = to_sign.clone();
        let signed = tokio::task::spawn_blocking(move || sign(&data))
            .await
            .map_err(anyhow::Error::from)
            .and_then(|r| r);
        match signed {
            Ok(blob) => {
                to_sign.extend((blob.len() as u32).to_be_bytes());
                to_sign.extend(blob);
                Ok(to_sign)
            }
            Err(reason) => {
                if let Some(failed) = self.failed.take() {
                    let _ = failed.send(reason);
                }
                // Unchanged: russh sends nothing.
                Ok(to_sign)
            }
        }
    }
}

/// A local ssh-agent.
pub struct Agent {
    client: AgentClient<Box<dyn AgentStream + Send + Unpin>>,
}

impl Agent {
    pub async fn connect(socket: &Path) -> anyhow::Result<Self> {
        let stream = connect_agent(socket)
            .await
            .with_context(|| format!("agent at {}", socket.display()))?;
        Ok(Self {
            client: AgentClient::connect(stream).dynamic(),
        })
    }

    /// The agent's plain keys (its certificates are not offered yet).
    pub async fn keys(&mut self) -> anyhow::Result<Vec<PublicKey>> {
        Ok(self
            .client
            .request_identities()
            .await?
            .into_iter()
            .filter_map(|identity| match identity {
                AgentIdentity::PublicKey { key, .. } => Some(key),
                _ => None,
            })
            .collect())
    }
}

#[cfg(feature = "test-auth")]
pub fn auth_name(auth: &Auth) -> &'static str {
    match auth {
        Auth::Password(_) => "password",
        Auth::Key { .. } => "publickey",
        Auth::Cert { .. } => "certificate",
        Auth::Agent { .. } => "agent",
        Auth::KeyboardInteractive { .. } => "keyboard-interactive",
    }
}

/// Output of a command run with `exec`.
pub struct Output {
    pub stdout: Vec<u8>,
    pub status: Option<u32>,
}

impl Output {
    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.stdout).trim().to_owned()
    }
}

impl Session {
    pub fn info(&self) -> Info {
        self.shared.lock().unwrap().info.clone()
    }

    fn done(&self, outcome: Outcome) -> Outcome {
        if outcome.success() {
            let mut shared = self.shared.lock().unwrap();
            shared.info.connect_ms = shared.started.elapsed().as_secs_f64() * 1e3;
        }
        outcome
    }

    /// The server's answer to a step of authentication, within the limit.
    async fn answer<T, E: Into<anyhow::Error>>(
        limit: Option<Duration>,
        step: impl Future<Output = Result<T, E>>,
    ) -> anyhow::Result<T> {
        match limit {
            Some(limit) => tokio::time::timeout(limit, step)
                .await
                .map_err(|_| NoAnswer(limit))?
                .map_err(Into::into),
            None => step.await.map_err(Into::into),
        }
    }

    /// The `none` method: lets in servers without authentication and
    /// otherwise lists the methods they accept.
    pub async fn auth_none(&mut self, user: &str) -> anyhow::Result<Outcome> {
        let r = Self::answer(self.limit, self.handle.authenticate_none(user)).await?;
        Ok(self.done(r.into()))
    }

    pub async fn auth_password(&mut self, user: &str, password: &str) -> anyhow::Result<Outcome> {
        self.attempts += 1;
        let r = Self::answer(
            self.limit,
            self.handle.authenticate_password(user, password),
        )
        .await?;
        Ok(self.done(r.into()))
    }

    pub async fn auth_key(&mut self, user: &str, key: Arc<PrivateKey>) -> anyhow::Result<Outcome> {
        self.attempts += 1;
        // RSA: the strongest of rsa-sha2-512/256 the server announced.
        let hash = if key.algorithm().is_rsa() {
            self.handle.best_supported_rsa_hash().await?.flatten()
        } else {
            None
        };
        let r = Self::answer(
            self.limit,
            self.handle
                .authenticate_publickey(user, PrivateKeyWithHashAlg::new(key, hash)),
        )
        .await?;
        Ok(self.done(r.into()))
    }

    /// An OpenSSH user certificate and its private key.
    pub async fn auth_cert(
        &mut self,
        user: &str,
        key: Arc<PrivateKey>,
        cert: Certificate,
    ) -> anyhow::Result<Outcome> {
        self.attempts += 1;
        let r = Self::answer(
            self.limit,
            self.handle.authenticate_openssh_cert(user, key, cert),
        )
        .await?;
        Ok(self.done(r.into()))
    }

    /// One of the agent's keys; the agent signs.
    pub async fn auth_agent(
        &mut self,
        user: &str,
        agent: &mut Agent,
        key: PublicKey,
    ) -> anyhow::Result<Outcome> {
        self.attempts += 1;
        let hash = if key.algorithm().is_rsa() {
            self.handle.best_supported_rsa_hash().await?.flatten()
        } else {
            None
        };
        let (refused, refusal) = tokio::sync::oneshot::channel();
        let mut signing = Signing {
            client: &mut agent.client,
            limit: self.limit.map(|_| AGENT_TIMEOUT),
            refused: Some(refused),
        };
        let step = async {
            tokio::select! {
                r = self.handle.authenticate_publickey_with(user, key, hash, &mut signing) => {
                    r.map_err(anyhow::Error::from)
                }
                Ok(reason) = refusal => Err(reason.into()),
            }
        };
        // The agent's time, then the server's.
        let r = Self::answer(self.limit.map(|l| AGENT_TIMEOUT + l), step).await?;
        Ok(self.done(r.into()))
    }

    /// A key whose secret is elsewhere (a security key): `sign` signs, and
    /// may take a while (it waits for a touch). Why it could not sign is
    /// this call's error.
    pub async fn auth_signed(
        &mut self,
        user: &str,
        key: PublicKey,
        sign: SignFn,
    ) -> anyhow::Result<Outcome> {
        self.attempts += 1;
        let (failed, failure) = tokio::sync::oneshot::channel();
        let mut signing = ExternalSigning {
            sign,
            failed: Some(failed),
        };
        let step = async {
            tokio::select! {
                r = self.handle.authenticate_publickey_with(user, key, None, &mut signing) => {
                    r.map_err(anyhow::Error::from)
                }
                Ok(reason) = failure => Err(reason),
            }
        };
        // The touch's time, then the server's.
        let r = Self::answer(self.limit.map(|l| AGENT_TIMEOUT + l), step).await?;
        Ok(self.done(r.into()))
    }

    pub async fn kbd_start(&mut self, user: &str) -> anyhow::Result<Kbd> {
        self.attempts += 1;
        let r = Self::answer(
            self.limit,
            self.handle
                .authenticate_keyboard_interactive_start(user, None),
        )
        .await?;
        Ok(self.kbd_done(r.into()))
    }

    pub async fn kbd_respond(&mut self, answers: Vec<String>) -> anyhow::Result<Kbd> {
        let r = Self::answer(
            self.limit,
            self.handle
                .authenticate_keyboard_interactive_respond(answers),
        )
        .await?;
        Ok(self.kbd_done(r.into()))
    }

    fn kbd_done(&self, step: Kbd) -> Kbd {
        match step {
            Kbd::Done(outcome) => Kbd::Done(self.done(outcome)),
            questions => questions,
        }
    }

    pub fn is_closed(&self) -> bool {
        self.handle.is_closed()
    }

    /// The server hung up once a method was tried: it gave up on us
    /// (`MaxAuthTries`), which trying again would not change.
    pub fn gave_up(&self) -> bool {
        self.attempts > 0 && self.is_closed()
    }

    /// Runs a command, optionally with agent forwarding and environment.
    pub async fn exec_with(
        &self,
        command: &str,
        agent_forward: bool,
        env: &[(&str, &str)],
    ) -> anyhow::Result<Output> {
        self.run(command, agent_forward, env, usize::MAX).await
    }

    pub async fn exec(&self, command: &str) -> anyhow::Result<Output> {
        self.exec_with(command, false, &[]).await
    }

    /// A command whose answer is short (a name, a yes or no): at most
    /// [`EXEC_OUTPUT`] of it is kept, whatever the server sends, and past
    /// that the command is let go.
    pub async fn exec_short(&self, command: &str) -> anyhow::Result<Output> {
        self.run(command, false, &[], EXEC_OUTPUT).await
    }

    /// A short command whose answer is complete as soon as `done` says so
    /// (a line it waits for), even if something it left running keeps the
    /// channel open: what came until then, its status if it ended.
    pub async fn exec_until(
        &self,
        command: &str,
        done: impl Fn(&str) -> bool,
    ) -> anyhow::Result<Output> {
        let mut channel = self.handle.channel_open_session().await?;
        channel.exec(true, command).await?;
        let mut out = Output {
            stdout: Vec::new(),
            status: None,
        };
        while let Some(msg) = channel.wait().await {
            match msg {
                ChannelMsg::Data { data } | ChannelMsg::ExtendedData { data, .. } => {
                    let room = EXEC_OUTPUT - out.stdout.len();
                    out.stdout.extend_from_slice(&data[..data.len().min(room)]);
                    if data.len() > room || done(&String::from_utf8_lossy(&out.stdout)) {
                        break;
                    }
                }
                ChannelMsg::ExitStatus { exit_status } => out.status = Some(exit_status),
                ChannelMsg::Close => break,
                _ => {}
            }
        }
        Ok(out)
    }

    async fn run(
        &self,
        command: &str,
        agent_forward: bool,
        env: &[(&str, &str)],
        max: usize,
    ) -> anyhow::Result<Output> {
        let mut channel = self.handle.channel_open_session().await?;
        if agent_forward {
            channel.agent_forward(false).await?;
        }
        for (k, v) in env {
            channel.set_env(true, *k, *v).await?;
        }
        channel.exec(true, command).await?;
        let mut out = Output {
            stdout: Vec::new(),
            status: None,
        };
        while let Some(msg) = channel.wait().await {
            match msg {
                ChannelMsg::Data { data } => {
                    let room = max - out.stdout.len();
                    out.stdout.extend_from_slice(&data[..data.len().min(room)]);
                    if data.len() > room {
                        // Enough: the rest is not read (the channel closes).
                        break;
                    }
                }
                ChannelMsg::ExitStatus { exit_status } => out.status = Some(exit_status),
                ChannelMsg::Close => break,
                _ => {}
            }
        }
        Ok(out)
    }

    /// An interactive shell on a PTY.
    pub async fn shell(
        &self,
        term: &str,
        cols: u32,
        rows: u32,
    ) -> anyhow::Result<Channel<client::Msg>> {
        self.shell_with(term, cols, rows, &[], false).await
    }

    /// A shell with environment variables (servers accept only those their
    /// `AcceptEnv` lists, silently dropping the rest) and, optionally, the
    /// agent forwarded.
    pub async fn shell_with(
        &self,
        term: &str,
        cols: u32,
        rows: u32,
        env: &[(String, String)],
        agent_forward: bool,
    ) -> anyhow::Result<Channel<client::Msg>> {
        let channel = self.handle.channel_open_session().await?;
        if agent_forward {
            channel.agent_forward(false).await?;
        }
        for (k, v) in env {
            channel.set_env(false, k.as_str(), v.as_str()).await?;
        }
        channel
            .request_pty(true, term, cols, rows, 0, 0, PTY_MODES)
            .await?;
        channel.request_shell(true).await?;
        Ok(channel)
    }

    /// As [`Session::shell_with`], running `command` on the PTY instead of
    /// the login shell (tmux, for a session that survives a cut).
    pub async fn command_with(
        &self,
        command: &str,
        term: &str,
        cols: u32,
        rows: u32,
        env: &[(String, String)],
        agent_forward: bool,
    ) -> anyhow::Result<Channel<client::Msg>> {
        let channel = self.handle.channel_open_session().await?;
        if agent_forward {
            channel.agent_forward(false).await?;
        }
        for (k, v) in env {
            channel.set_env(false, k.as_str(), v.as_str()).await?;
        }
        channel
            .request_pty(true, term, cols, rows, 0, 0, PTY_MODES)
            .await?;
        channel.exec(true, command).await?;
        Ok(channel)
    }

    /// Asks the server for an answer (`keepalive@openssh.com`) and waits
    /// for it. Returns false when the connection is gone.
    pub async fn ping(&self) -> bool {
        self.handle.send_ping().await.is_ok() && !self.handle.is_closed()
    }

    /// A channel running the server's SFTP subsystem, as a byte stream for
    /// an SFTP client. Fails with [`NoSftp`] when the server has none (a
    /// Dropbear without `sftp-server`, a router).
    pub async fn sftp(&self) -> anyhow::Result<russh::ChannelStream<client::Msg>> {
        let mut channel = self.handle.channel_open_session().await?;
        channel.request_subsystem(true, "sftp").await?;
        loop {
            match channel.wait().await {
                Some(ChannelMsg::Success) => return Ok(channel.into_stream()),
                Some(ChannelMsg::Failure) | Some(ChannelMsg::Close) | None => {
                    return Err(NoSftp.into());
                }
                Some(_) => {}
            }
        }
    }

    /// Asks the server to listen on `127.0.0.1:0` and relay connections to
    /// `local`. Returns the port the server picked.
    pub async fn remote_forward(&self, local: (&str, u16)) -> anyhow::Result<u32> {
        self.remote_forward_on("127.0.0.1", 0, local, Arc::default())
            .await
    }

    /// Asks the server to listen on `address:port` (0: it picks) and relay
    /// connections to `local`, counting them in `active`. Returns the port.
    /// Fails if the server will not: the port is taken, or it does not
    /// allow forwarding.
    pub async fn remote_forward_on(
        &self,
        address: &str,
        port: u32,
        local: (&str, u16),
        active: Arc<AtomicU32>,
    ) -> anyhow::Result<u32> {
        let got = self.handle.tcpip_forward(address, port).await?;
        // With a fixed port the server answers 0: the port is the one asked.
        let got = if port == 0 { got } else { port };
        self.shared
            .lock()
            .unwrap()
            .remote_forwards
            .insert(got, (local.0.to_owned(), local.1, active));
        Ok(got)
    }

    /// Stops a remote forward.
    pub async fn cancel_remote_forward(&self, address: &str, port: u32) {
        self.shared.lock().unwrap().remote_forwards.remove(&port);
        let _ = self.handle.cancel_tcpip_forward(address, port).await;
    }

    pub async fn disconnect(&self) {
        let _ = self
            .handle
            .disconnect(russh::Disconnect::ByApplication, "", "en")
            .await;
    }
}

/// Writes all of `data` to a channel.
pub async fn send(channel: &Channel<client::Msg>, data: &[u8]) -> anyhow::Result<()> {
    let mut writer = channel.make_writer();
    writer.write_all(data).await?;
    writer.flush().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The limit is the server's time: what goes asking the user about the
    /// host key is added to it.
    #[tokio::test(start_paused = true)]
    async fn time_asking_the_user_does_not_count() {
        let shared = Mutex::new(Shared {
            info: Info::default(),
            remote_forwards: HashMap::new(),
            started: Instant::now(),
            asking: false,
            asked: Duration::from_secs(2),
        });
        let limit = Some(Duration::from_secs(2));
        let answer_at = |secs| async move {
            tokio::time::sleep(Duration::from_secs(secs)).await;
            anyhow::Ok(())
        };
        // At 3 s, but 2 of them were the user's.
        assert!(within_limit(answer_at(3), limit, &shared).await.is_ok());
        // Without asking, 2 s is all it has.
        let err = within_limit(answer_at(3), limit, &shared)
            .await
            .unwrap_err();
        assert_eq!(
            err.downcast_ref::<NoAnswer>(),
            Some(&NoAnswer(Duration::from_secs(2)))
        );
        assert_eq!(err.to_string(), "no answer for 2 s");
    }

    /// A ProxyCommand that fails says why in the error, not just that the
    /// connection went.
    #[cfg(unix)]
    #[tokio::test]
    async fn a_failing_proxy_command_is_heard() {
        let opts = Options {
            user: "demo".into(),
            known_hosts: Arc::new(Mutex::new(KnownHosts::parse(
                "",
                crate::known_hosts::Unknown::Reject,
            ))),
            host_certificates: false,
            legacy_host_keys: false,
            connect_timeout: Some(Duration::from_secs(10)),
            keepalive: None,
            agent_forward: None,
            on_untrusted: None,
        };
        let command = "echo 'starting' >&2; echo 'cloudflared: command not found' >&2; exit 127";
        let err = open(
            &Target::new("db.internal", 22),
            Hop::ProxyCommand(command.into()),
            &opts,
        )
        .await
        .err()
        .expect("no server behind it");
        let message = format!("{err:#}");
        assert!(
            message.starts_with("ProxyCommand: starting · cloudflared: command not found"),
            "{message}"
        );
        assert_eq!(
            err.downcast_ref::<ProxyCommandSaid>().map(|s| s.0.len()),
            Some(2)
        );
    }

    #[test]
    fn the_login_shell_s_folders_go_first() {
        let path = merge_paths(
            "/opt/homebrew/bin:/usr/bin".as_ref(),
            "/usr/bin:/bin:/usr/sbin".as_ref(),
        )
        .unwrap();
        assert_eq!(path, "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin");
    }

    #[test]
    fn known_key_types_go_first_and_sha1_only_when_allowed() {
        let p256 = Algorithm::Ecdsa {
            curve: EcdsaCurve::NistP256,
        };
        let sha1 = Algorithm::Rsa { hash: None };
        let fresh = host_key_order(&[], false);
        assert_eq!(fresh[0], Algorithm::Ed25519);
        assert!(!fresh.contains(&sha1));
        assert!(host_key_order(&[], true).contains(&sha1));

        let ecdsa = host_key_order(std::slice::from_ref(&p256), false);
        assert_eq!(ecdsa[0], p256);
        assert_eq!(ecdsa.len(), fresh.len());

        // A known RSA key: its SHA-2 signatures first, SHA-1 still not.
        let rsa = host_key_order(std::slice::from_ref(&sha1), false);
        assert!(matches!(rsa[0], Algorithm::Rsa { hash: Some(_) }));
        assert!(matches!(rsa[1], Algorithm::Rsa { hash: Some(_) }));
        assert!(!rsa.contains(&sha1));
    }
}
