//! SSH client on `russh`: generic transport, authentication, host trust and
//! the server-initiated channels (remote forwards, agent forwarding).
//!
//! Shaped like the future `core/crates/openward-ssh`: the transport is any
//! byte stream (TCP, ProxyCommand, or a `direct-tcpip` channel of another
//! session), so jumps and proxies compose without special cases.

use std::borrow::Cow;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context, bail};
use russh::client::{self, KeyboardInteractiveAuthResponse};
use russh::keys::agent::AgentIdentity;
use russh::keys::agent::client::AgentClient;
use russh::keys::{Algorithm, EcdsaCurve, PrivateKeyWithHashAlg, PublicKeyOrCertificate};
use russh::{Channel, ChannelMsg, Pty};
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

#[derive(Clone)]
pub struct Options {
    pub user: String,
    pub known_hosts: Arc<Mutex<KnownHosts>>,
    /// Ask servers for host certificates (only useful with a trusted CA).
    pub host_certificates: bool,
    pub keepalive: Option<Duration>,
    /// Local agent that forwarded agent requests are relayed to.
    pub agent_forward: Option<PathBuf>,
}

/// What was negotiated and how the host was trusted.
#[derive(Clone, Debug, Default)]
pub struct Info {
    pub kex: String,
    pub cipher: String,
    pub mac: String,
    pub host_key: String,
    pub verdict: Option<Verdict>,
    /// From opening the transport to authenticated.
    pub connect_ms: f64,
}

impl Info {
    pub fn post_quantum(&self) -> bool {
        self.kex.starts_with("mlkem") || self.kex.starts_with("sntrup")
    }
}

#[derive(Default)]
struct Shared {
    info: Info,
    /// Remote forward port on the server → local address it leads to.
    remote_forwards: HashMap<u32, (String, u16)>,
}

pub struct Handler {
    target: Target,
    known_hosts: Arc<Mutex<KnownHosts>>,
    agent_forward: Option<PathBuf>,
    shared: Arc<Mutex<Shared>>,
}

impl client::Handler for Handler {
    type Error = anyhow::Error;

    async fn check_server_key(
        &mut self,
        offered: &PublicKeyOrCertificate,
    ) -> Result<bool, Self::Error> {
        let verdict =
            self.known_hosts
                .lock()
                .unwrap()
                .check(&self.target.host, self.target.port, offered);
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

pub async fn connect(
    target: &Target,
    hop: Hop<'_>,
    auth: &Auth,
    opts: &Options,
) -> anyhow::Result<Session> {
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
    let shared = Arc::new(Mutex::new(Shared::default()));
    let handler = Handler {
        target: target.clone(),
        known_hosts: Arc::clone(&opts.known_hosts),
        agent_forward: opts.agent_forward.clone(),
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
    let mut handle = match result {
        Ok(handle) => handle,
        Err(e) => {
            // A refused host key surfaces as a generic error: say why.
            if let Some(v) = shared.lock().unwrap().info.verdict.clone()
                && !v.trusted()
            {
                bail!("host key not trusted: {v:?}");
            }
            return Err(e);
        }
    };
    authenticate(&mut handle, &opts.user, auth).await?;
    shared.lock().unwrap().info.connect_ms = started.elapsed().as_secs_f64() * 1e3;
    Ok(Session {
        handle,
        shared,
        _proxy: proxy,
    })
}

async fn authenticate(
    handle: &mut client::Handle<Handler>,
    user: &str,
    auth: &Auth,
) -> anyhow::Result<()> {
    let ok = match auth {
        Auth::Password(password) => handle
            .authenticate_password(user, password)
            .await?
            .success(),
        Auth::Key { path, passphrase } => {
            let key = russh::keys::load_secret_key(path, passphrase.as_deref())
                .with_context(|| format!("loading {}", path.display()))?;
            // RSA: the strongest of rsa-sha2-512/256 the server announced.
            let hash = if key.algorithm().is_rsa() {
                handle.best_supported_rsa_hash().await?.flatten()
            } else {
                None
            };
            handle
                .authenticate_publickey(user, PrivateKeyWithHashAlg::new(Arc::new(key), hash))
                .await?
                .success()
        }
        Auth::Cert { key, cert } => {
            let key = russh::keys::load_secret_key(key, None)?;
            let cert = russh::keys::load_openssh_certificate(cert)?;
            handle
                .authenticate_openssh_cert(user, Arc::new(key), cert)
                .await?
                .success()
        }
        Auth::Agent { socket } => {
            let mut agent = AgentClient::connect(connect_agent(socket).await?);
            let mut ok = false;
            for identity in agent.request_identities().await? {
                let AgentIdentity::PublicKey { key, .. } = identity else {
                    continue;
                };
                let hash = if key.algorithm().is_rsa() {
                    handle.best_supported_rsa_hash().await?.flatten()
                } else {
                    None
                };
                if handle
                    .authenticate_publickey_with(user, key, hash, &mut agent)
                    .await?
                    .success()
                {
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
            let mut reply = handle
                .authenticate_keyboard_interactive_start(user, None)
                .await?;
            let mut rounds = 0;
            loop {
                match reply {
                    KeyboardInteractiveAuthResponse::Success => break true,
                    KeyboardInteractiveAuthResponse::Failure { .. } => break false,
                    KeyboardInteractiveAuthResponse::InfoRequest { prompts, .. } => {
                        rounds += 1;
                        if rounds > 5 {
                            bail!("keyboard-interactive: too many rounds");
                        }
                        let mut answers = Vec::with_capacity(prompts.len());
                        for p in &prompts {
                            let text = p.prompt.to_lowercase();
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
                        reply = handle
                            .authenticate_keyboard_interactive_respond(answers)
                            .await?;
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
        let channel = self.handle.channel_open_session().await?;
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
