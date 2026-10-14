//! SSH client on `russh`: generic transport, authentication, host trust and
//! the server-initiated channels (remote forwards, agent forwarding).
//!
//! Shaped like the future `core/crates/openward-ssh`: the transport is any
//! byte stream (TCP, ProxyCommand, or a `direct-tcpip` channel of another
//! session), so jumps and proxies compose without special cases.

use std::borrow::Cow;
use std::collections::HashMap;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context, bail};
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
}

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
}

impl Info {
    pub fn post_quantum(&self) -> bool {
        self.kex.starts_with("mlkem") || self.kex.starts_with("sntrup")
    }
}

struct Shared {
    info: Info,
    /// Remote forward port on the server → local address it leads to.
    remote_forwards: HashMap<u32, (String, u16)>,
    started: Instant,
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
        let mut verdict =
            self.known_hosts
                .lock()
                .unwrap()
                .check(&self.target.host, self.target.port, offered);
        let key = match offered {
            PublicKeyOrCertificate::PublicKey { key, .. } => key.clone(),
            PublicKeyOrCertificate::Certificate(cert) => PublicKey::from(cert.public_key().clone()),
        };
        self.shared.lock().unwrap().info.host_key_fingerprint =
            key.fingerprint(russh::keys::HashAlg::Sha256).to_string();
        if let (false, Some(hook), PublicKeyOrCertificate::PublicKey { key, .. }) =
            (verdict.trusted(), &self.on_untrusted, offered)
        {
            let query = HostKeyQuery {
                host: self.target.host.clone(),
                port: self.target.port,
                key: key.clone(),
                verdict: verdict.clone(),
            };
            if hook(query).await {
                verdict = Verdict::Learned;
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
        _session: &mut client::Session,
    ) -> Result<(), Self::Error> {
        let mut shared = self.shared.lock().unwrap();
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
        let Some((host, port)) = local else {
            // Not ours: dropping the reply rejects the channel.
            return Ok(());
        };
        reply.accept().await;
        tokio::spawn(async move {
            if let Ok(mut socket) = tokio::net::TcpStream::connect((host.as_str(), port)).await {
                let mut stream = channel.into_stream();
                let _ = tokio::io::copy_bidirectional(&mut stream, &mut socket).await;
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

/// ProxyCommand runs through the platform shell, as OpenSSH does.
fn shell_command(command: &str) -> Command {
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
    c
}

pub struct Session {
    pub handle: client::Handle<Handler>,
    shared: Arc<Mutex<Shared>>,
    /// The ProxyCommand process, killed with the session.
    _proxy: Option<Child>,
}

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

/// Opens the transport and checks the host key; the session still has to
/// authenticate (the `auth_*` methods) before it can open channels.
pub async fn open(target: &Target, hop: Hop<'_>, opts: &Options) -> anyhow::Result<Session> {
    let started = Instant::now();
    let mut config = client::Config {
        // Terminal traffic is many tiny writes: Nagle would hold keystrokes.
        nodelay: true,
        keepalive_interval: opts.keepalive,
        keepalive_max: 3,
        ..Default::default()
    };
    if opts.host_certificates {
        config.preferred.host_key_certificates = Cow::Borrowed(CERT_ALGORITHMS);
    }
    let config = Arc::new(config);
    let shared = Arc::new(Mutex::new(Shared {
        info: Info::default(),
        remote_forwards: HashMap::new(),
        started,
    }));
    let handler = Handler {
        target: target.clone(),
        known_hosts: Arc::clone(&opts.known_hosts),
        agent_forward: opts.agent_forward.clone(),
        on_untrusted: opts.on_untrusted.clone(),
        shared: Arc::clone(&shared),
    };

    let mut proxy = None;
    let result = match hop {
        Hop::Tcp => client::connect(config, (target.host.as_str(), target.port), handler).await,
        Hop::ProxyCommand(command) => {
            let mut child = shell_command(&command)
                .stdin(std::process::Stdio::piped())
                .stdout(std::process::Stdio::piped())
                .kill_on_drop(true)
                .spawn()
                .with_context(|| format!("ProxyCommand {command}"))?;
            let stream = tokio::io::join(
                child.stdout.take().context("ProxyCommand stdout")?,
                child.stdin.take().context("ProxyCommand stdin")?,
            );
            proxy = Some(child);
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
    };
    let handle = match result {
        Ok(handle) => handle,
        Err(e) => {
            // A refused host key surfaces as a generic error: say why.
            if let Some(v) = shared.lock().unwrap().info.verdict.clone()
                && !v.trusted()
            {
                return Err(UntrustedHost(v).into());
            }
            return Err(e);
        }
    };
    Ok(Session {
        handle,
        shared,
        _proxy: proxy,
    })
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

/// Opens and authenticates with one method whose secrets are all at hand.
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
                            bail!("keyboard-interactive: too many rounds");
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
        bail!("authentication failed ({})", auth_name(auth));
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
    match russh::keys::load_secret_key(path, passphrase) {
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

    /// The `none` method: lets in servers without authentication and
    /// otherwise lists the methods they accept.
    pub async fn auth_none(&mut self, user: &str) -> anyhow::Result<Outcome> {
        let r = self.handle.authenticate_none(user).await?;
        Ok(self.done(r.into()))
    }

    pub async fn auth_password(&mut self, user: &str, password: &str) -> anyhow::Result<Outcome> {
        let r = self.handle.authenticate_password(user, password).await?;
        Ok(self.done(r.into()))
    }

    pub async fn auth_key(&mut self, user: &str, key: Arc<PrivateKey>) -> anyhow::Result<Outcome> {
        // RSA: the strongest of rsa-sha2-512/256 the server announced.
        let hash = if key.algorithm().is_rsa() {
            self.handle.best_supported_rsa_hash().await?.flatten()
        } else {
            None
        };
        let r = self
            .handle
            .authenticate_publickey(user, PrivateKeyWithHashAlg::new(key, hash))
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
        let r = self
            .handle
            .authenticate_openssh_cert(user, key, cert)
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
        let hash = if key.algorithm().is_rsa() {
            self.handle.best_supported_rsa_hash().await?.flatten()
        } else {
            None
        };
        let r = self
            .handle
            .authenticate_publickey_with(user, key, hash, &mut agent.client)
            .await?;
        Ok(self.done(r.into()))
    }

    pub async fn kbd_start(&mut self, user: &str) -> anyhow::Result<Kbd> {
        let r = self
            .handle
            .authenticate_keyboard_interactive_start(user, None)
            .await?;
        Ok(self.kbd_done(r.into()))
    }

    pub async fn kbd_respond(&mut self, answers: Vec<String>) -> anyhow::Result<Kbd> {
        let r = self
            .handle
            .authenticate_keyboard_interactive_respond(answers)
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

    /// Runs a command, optionally with agent forwarding and environment.
    pub async fn exec_with(
        &self,
        command: &str,
        agent_forward: bool,
        env: &[(&str, &str)],
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
                ChannelMsg::Data { data } => out.stdout.extend_from_slice(&data),
                ChannelMsg::ExitStatus { exit_status } => out.status = Some(exit_status),
                ChannelMsg::Close => break,
                _ => {}
            }
        }
        Ok(out)
    }

    pub async fn exec(&self, command: &str) -> anyhow::Result<Output> {
        self.exec_with(command, false, &[]).await
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
        // ECHO on and the usual cooked mode; the server fills in the rest.
        channel
            .request_pty(true, term, cols, rows, 0, 0, &[(Pty::ECHO, 1)])
            .await?;
        channel.request_shell(true).await?;
        Ok(channel)
    }

    /// Asks the server to listen on `127.0.0.1:0` and relay connections to
    /// `local`. Returns the port the server picked.
    pub async fn remote_forward(&self, local: (&str, u16)) -> anyhow::Result<u32> {
        let port = self.handle.tcpip_forward("127.0.0.1", 0).await?;
        self.shared
            .lock()
            .unwrap()
            .remote_forwards
            .insert(port, (local.0.to_owned(), local.1));
        Ok(port)
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
