//! Hosts and groups as Dart sees them: plain values, ids as strings.
//!
//! Editing goes through specs that carry only the fields OpenWard knows;
//! updates apply them over the stored item, so fields written by a newer
//! version survive (openward-proto).

use std::str::FromStr;

use flutter_rust_bridge::frb;
use openward_app::vault::Origin;
use openward_app::vault::proto::{
    Agent, Backspace, Environment, EnvironmentMark, FlowControl, HostKeyPolicy, ItemId, Jump,
    Parity, Protocol, Proxy, ProxyServer, Route, SerialLine, Settings, System, SystemSource,
    UseIdentity,
};

/// What went wrong with a change to the vault, for the app to say it in
/// its own words.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VaultErrorKind {
    /// It changed meanwhile (connecting learned the system, another
    /// window): read it again.
    Conflict,
    /// It is gone.
    NotFound,
    /// Other hosts jump through it.
    InUse,
    /// A group inside itself.
    Cycle,
    /// What was asked does not hold together (a field missing, a wrong id).
    Invalid,
    /// Written by a newer version of OpenWard.
    NewerFormat,
    /// Another OpenWard has it open.
    OpenElsewhere,
    /// A file that was shown changed before the change (`known_hosts`).
    FileChanged,
    /// The disk would not take it.
    Storage,
    Other,
}

/// What went wrong with a change to the vault; thrown in Dart.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VaultError {
    pub kind: VaultErrorKind,
    /// In English, for «Detalles» and for the logs.
    pub message: String,
}

impl From<anyhow::Error> for VaultError {
    fn from(e: anyhow::Error) -> Self {
        use openward_app::vault::Error as E;
        let kind = if let Some(v) = e.downcast_ref::<E>() {
            match v {
                E::Conflict { .. } => VaultErrorKind::Conflict,
                E::NotFound(_) | E::WrongType { .. } => VaultErrorKind::NotFound,
                E::InUse(..) => VaultErrorKind::InUse,
                E::Cycle => VaultErrorKind::Cycle,
                E::Invalid(_) => VaultErrorKind::Invalid,
                E::NewerFormat(_) => VaultErrorKind::NewerFormat,
                E::OpenElsewhere => VaultErrorKind::OpenElsewhere,
                E::Sql(_) | E::Io(_) => VaultErrorKind::Storage,
            }
        } else if let Some(f) = e.downcast_ref::<openward_app::known::ForgetError>() {
            match f {
                openward_app::known::ForgetError::Changed(_) => VaultErrorKind::FileChanged,
                openward_app::known::ForgetError::Io(_) => VaultErrorKind::Storage,
            }
        } else {
            VaultErrorKind::Other
        };
        Self {
            kind,
            message: format!("{e:#}"),
        }
    }
}

impl From<openward_app::vault::Error> for VaultError {
    fn from(e: openward_app::vault::Error) -> Self {
        anyhow::Error::from(e).into()
    }
}

/// An import that went wrong: in the vault, or saving a key to disk.
impl From<openward_app::programs::Error> for VaultError {
    fn from(e: openward_app::programs::Error) -> Self {
        match e {
            openward_app::programs::Error::Vault(v) => v.into(),
            key => Self {
                kind: VaultErrorKind::Storage,
                message: key.to_string(),
            },
        }
    }
}

/// A plan that cannot run: what the vault says (a host that is gone), or
/// settings that do not hold together (jumps in a loop, a ProxyCommand
/// that would run what a name says).
impl From<openward_app::plan::PlanError> for VaultError {
    fn from(e: openward_app::plan::PlanError) -> Self {
        match e {
            openward_app::plan::PlanError::Vault(v) => v.into(),
            other => Self {
                kind: VaultErrorKind::Invalid,
                message: other.to_string(),
            },
        }
    }
}

pub(crate) fn id(text: &str) -> anyhow::Result<ItemId> {
    ItemId::from_str(text).map_err(|e| {
        anyhow::Error::new(openward_app::vault::Error::Invalid("not an item id"))
            .context(format!("bad id {text:?}: {e}"))
    })
}

pub(crate) fn opt_id(text: &Option<String>) -> anyhow::Result<Option<ItemId>> {
    text.as_deref().map(id).transpose()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AgentKind {
    Off,
    System,
    Socket,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RouteKind {
    Direct,
    Jump,
    Command,
}

/// A proxy in front of the first hop; `Off` overrides one inherited.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProxyKind {
    Off,
    Http,
    Socks5,
}

/// How a host is reached.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProtocolKind {
    Ssh,
    /// Unencrypted.
    Telnet,
    /// A serial port of this computer: the host's address is the port.
    Serial,
}

/// What the Backspace key sends.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BackspaceKind {
    /// `^?`, as systems of today expect.
    Delete,
    /// `^H`, for old systems and some network gear.
    ControlH,
}

impl BackspaceKind {
    pub(crate) fn of(b: Backspace) -> Self {
        match b {
            Backspace::Delete => Self::Delete,
            Backspace::ControlH => Self::ControlH,
        }
    }

    pub(crate) fn proto(self) -> Backspace {
        match self {
            Self::Delete => Backspace::Delete,
            Self::ControlH => Backspace::ControlH,
        }
    }
}

impl ProtocolKind {
    pub(crate) fn of(p: Protocol) -> Self {
        match p {
            Protocol::Ssh => Self::Ssh,
            Protocol::Telnet => Self::Telnet,
            Protocol::Serial => Self::Serial,
        }
    }

    pub(crate) fn proto(self) -> Protocol {
        match self {
            Self::Ssh => Protocol::Ssh,
            Self::Telnet => Protocol::Telnet,
            Self::Serial => Protocol::Serial,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ParityKind {
    None,
    Odd,
    Even,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FlowKind {
    None,
    /// XON/XOFF.
    Software,
    /// RTS/CTS.
    Hardware,
}

/// A serial port's settings.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SerialLineSpec {
    pub baud: u32,
    /// 5 to 8.
    pub data_bits: u8,
    pub parity: ParityKind,
    /// 1 or 2.
    pub stop_bits: u8,
    pub flow: FlowKind,
}

impl SerialLineSpec {
    pub(crate) fn of(l: &SerialLine) -> Self {
        Self {
            baud: l.baud,
            data_bits: l.data_bits,
            parity: match l.parity {
                Parity::None => ParityKind::None,
                Parity::Odd => ParityKind::Odd,
                Parity::Even => ParityKind::Even,
            },
            stop_bits: l.stop_bits,
            flow: match l.flow {
                FlowControl::None => FlowKind::None,
                FlowControl::Software => FlowKind::Software,
                FlowControl::Hardware => FlowKind::Hardware,
            },
        }
    }

    /// As the vault keeps it, with what a newer version wrote in `old`.
    pub(crate) fn line(&self, old: Option<&SerialLine>) -> SerialLine {
        SerialLine {
            baud: self.baud,
            data_bits: self.data_bits,
            parity: match self.parity {
                ParityKind::None => Parity::None,
                ParityKind::Odd => Parity::Odd,
                ParityKind::Even => Parity::Even,
            },
            stop_bits: self.stop_bits,
            flow: match self.flow {
                FlowKind::None => FlowControl::None,
                FlowKind::Software => FlowControl::Software,
                FlowKind::Hardware => FlowControl::Hardware,
            },
            extra: old.map(|o| o.extra.clone()).unwrap_or_default(),
        }
    }
}

/// How a group or host is marked; `None` overrides a mark inherited.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EnvironmentKind {
    None,
    /// The one in `environment_name`, `environment_short` and
    /// `environment_color`.
    Mark,
}

/// A mark: «Producción», «prod» and a color of the palette by name.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EnvironmentView {
    pub name: String,
    pub short: String,
    pub color: String,
}

impl EnvironmentView {
    pub(crate) fn of(e: &Option<Environment>) -> Option<Self> {
        match e {
            Some(Environment::Mark(m)) => Some(Self {
                name: m.name.clone(),
                short: m.short.clone(),
                color: m.color.clone(),
            }),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SystemKind {
    /// Told from the server's banner.
    Banner,
    /// Read from `/etc/os-release`.
    OsRelease,
    /// Chosen by hand.
    Manual,
}

/// What a server runs.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SystemView {
    /// `deb`, `ubu`, `fed`, `mint`… (four letters at most, the app knows
    /// their logos), `lnx` for an unknown Linux, or `?`.
    pub code: String,
    /// «Debian 12»; empty when unknown.
    pub name: String,
    pub kind: SystemKind,
    /// The banner or the `PRETTY_NAME` it was told from.
    pub evidence: String,
}

impl SystemView {
    pub(crate) fn of(s: &System) -> Self {
        Self {
            code: s.code.clone(),
            name: s.name.clone(),
            kind: match s.source {
                SystemSource::Banner => SystemKind::Banner,
                SystemSource::OsRelease => SystemKind::OsRelease,
                SystemSource::Manual => SystemKind::Manual,
            },
            evidence: s.evidence.clone(),
        }
    }
}

/// Which identity applies; `None` overrides one inherited.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum IdentityChoice {
    None,
    /// The one in `identity_id`.
    Use,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyPolicy {
    Ask,
    AcceptNew,
    Strict,
}

/// One jump: a saved host (`host_id`) or a bare `address`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct JumpSpec {
    pub host_id: Option<String>,
    pub address: Option<String>,
    pub user: Option<String>,
    pub port: Option<u16>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EnvVar {
    pub name: String,
    pub value: String,
}

/// Settings a group or host sets; `None` inherits.
// `frb` on the struct lets it read the `#[frb(default)]` of the fields.
#[frb(non_opaque)]
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SettingsSpec {
    pub user: Option<String>,
    pub port: Option<u16>,
    pub identity_files: Option<Vec<String>>,
    pub certificate_files: Option<Vec<String>>,
    pub identities_only: Option<bool>,
    pub agent: Option<AgentKind>,
    /// With [`AgentKind::Socket`].
    #[frb(default = "")]
    pub agent_socket: String,
    pub route: Option<RouteKind>,
    /// With [`RouteKind::Jump`], first to last.
    #[frb(default = "const []")]
    pub jumps: Vec<JumpSpec>,
    /// With [`RouteKind::Command`].
    #[frb(default = "")]
    pub proxy_command: String,
    pub proxy: Option<ProxyKind>,
    /// With an HTTP or SOCKS5 proxy.
    #[frb(default = "")]
    pub proxy_host: String,
    #[frb(default = "0")]
    pub proxy_port: u16,
    /// Optional; the password is asked for when connecting.
    #[frb(default = "")]
    pub proxy_user: String,
    pub keepalive_secs: Option<u32>,
    /// Seconds the server has to answer while connecting.
    #[frb(default = "null")]
    pub connect_timeout_secs: Option<u32>,
    pub agent_forward: Option<bool>,
    /// The shell inside tmux on the server, to come back to it.
    #[frb(default = "null")]
    pub persistent_session: Option<bool>,
    pub term: Option<String>,
    pub env: Option<Vec<EnvVar>>,
    pub host_key_policy: Option<KeyPolicy>,
    /// Accept `ssh-rsa` host keys signed with SHA-1 (old servers).
    #[frb(default = "null")]
    pub legacy_host_keys: Option<bool>,
    pub identity: Option<IdentityChoice>,
    /// With [`IdentityChoice::Use`].
    #[frb(default = "")]
    pub identity_id: String,
    #[frb(default = "null")]
    pub environment: Option<EnvironmentKind>,
    /// With [`EnvironmentKind::Mark`].
    #[frb(default = "")]
    pub environment_name: String,
    #[frb(default = "")]
    pub environment_short: String,
    #[frb(default = "")]
    pub environment_color: String,
    /// Read `/etc/os-release` after connecting (it runs a command).
    #[frb(default = "null")]
    pub read_os_release: Option<bool>,
    /// Record what comes out on the screen in the session log.
    #[frb(default = "null")]
    pub session_log: Option<bool>,
    /// SSH, Telnet or a serial port.
    #[frb(default = "null")]
    pub protocol: Option<ProtocolKind>,
    /// With a serial port.
    #[frb(default = "null")]
    pub serial: Option<SerialLineSpec>,
    /// The shell over Mosh (SSH only).
    #[frb(default = "null")]
    pub mosh: Option<bool>,
    /// What starts `mosh-server`, when it is not on the server's `PATH`.
    #[frb(default = "null")]
    pub mosh_server: Option<String>,
    /// The host's character set, as `encoding_rs` names it (`utf-8`,
    /// `iso-8859-1`, `cp437`…).
    #[frb(default = "null")]
    pub encoding: Option<String>,
    #[frb(default = "null")]
    pub backspace: Option<BackspaceKind>,
    /// The terminal's colors: a scheme's name.
    #[frb(default = "null")]
    pub terminal_scheme: Option<String>,
    /// A snippet's id, typed in each new shell; empty here for none, over
    /// a group's.
    #[frb(default = "null")]
    pub startup_snippet: Option<String>,
}

/// The `identity` setting of a spec.
pub(crate) fn identity_choice(
    choice: Option<IdentityChoice>,
    identity_id: &str,
) -> anyhow::Result<Option<UseIdentity>> {
    Ok(match choice {
        None => None,
        Some(IdentityChoice::None) => Some(UseIdentity::None),
        Some(IdentityChoice::Use) => Some(UseIdentity::Id(id(identity_id)?)),
    })
}

impl SettingsSpec {
    pub(crate) fn from_settings(s: &Settings) -> Self {
        let (agent, agent_socket) = match &s.agent {
            None => (None, String::new()),
            Some(Agent::Off) => (Some(AgentKind::Off), String::new()),
            Some(Agent::System) => (Some(AgentKind::System), String::new()),
            Some(Agent::Socket(p)) => (Some(AgentKind::Socket), p.clone()),
        };
        let (route, jumps, proxy_command) = match &s.route {
            None => (None, Vec::new(), String::new()),
            Some(Route::Direct) => (Some(RouteKind::Direct), Vec::new(), String::new()),
            Some(Route::Command(c)) => (Some(RouteKind::Command), Vec::new(), c.clone()),
            Some(Route::Jump(jumps)) => (
                Some(RouteKind::Jump),
                jumps
                    .iter()
                    .map(|j| match j {
                        Jump::Host(id) => JumpSpec {
                            host_id: Some(id.to_string()),
                            ..JumpSpec::default()
                        },
                        Jump::Address {
                            host, user, port, ..
                        } => JumpSpec {
                            host_id: None,
                            address: Some(host.clone()),
                            user: user.clone(),
                            port: *port,
                        },
                    })
                    .collect(),
                String::new(),
            ),
        };
        let (proxy, server) = match &s.proxy {
            None => (None, None),
            Some(Proxy::None) => (Some(ProxyKind::Off), None),
            Some(Proxy::Http(server)) => (Some(ProxyKind::Http), Some(server)),
            Some(Proxy::Socks5(server)) => (Some(ProxyKind::Socks5), Some(server)),
        };
        let (identity, identity_id) = match s.identity {
            None => (None, String::new()),
            Some(UseIdentity::None) => (Some(IdentityChoice::None), String::new()),
            Some(UseIdentity::Id(i)) => (Some(IdentityChoice::Use), i.to_string()),
        };
        let (environment, mark) = match &s.environment {
            None => (None, None),
            Some(Environment::None) => (Some(EnvironmentKind::None), None),
            Some(Environment::Mark(m)) => (Some(EnvironmentKind::Mark), Some(m)),
        };
        Self {
            identity,
            identity_id,
            environment,
            environment_name: mark.map(|m| m.name.clone()).unwrap_or_default(),
            environment_short: mark.map(|m| m.short.clone()).unwrap_or_default(),
            environment_color: mark.map(|m| m.color.clone()).unwrap_or_default(),
            read_os_release: s.read_os_release,
            session_log: s.session_log,
            protocol: s.protocol.map(ProtocolKind::of),
            serial: s.serial.as_ref().map(SerialLineSpec::of),
            mosh: s.mosh,
            mosh_server: s.mosh_server.clone(),
            encoding: s.encoding.clone(),
            backspace: s.backspace.map(BackspaceKind::of),
            terminal_scheme: s.terminal_scheme.clone(),
            startup_snippet: s.startup_snippet.clone(),
            legacy_host_keys: s.legacy_host_keys,
            proxy,
            proxy_host: server.map(|s| s.host.clone()).unwrap_or_default(),
            proxy_port: server.map_or(0, |s| s.port),
            proxy_user: server.and_then(|s| s.user.clone()).unwrap_or_default(),
            user: s.user.clone(),
            port: s.port,
            identity_files: s.identity_files.clone(),
            certificate_files: s.certificate_files.clone(),
            identities_only: s.identities_only,
            agent,
            agent_socket,
            route,
            jumps,
            proxy_command,
            keepalive_secs: s.keepalive_secs,
            connect_timeout_secs: s.connect_timeout_secs,
            agent_forward: s.agent_forward,
            persistent_session: s.persistent_session,
            term: s.term.clone(),
            env: s.env.as_ref().map(|env| {
                env.iter()
                    .map(|(name, value)| EnvVar {
                        name: name.clone(),
                        value: value.clone(),
                    })
                    .collect()
            }),
            host_key_policy: s.host_key_policy.map(|p| match p {
                HostKeyPolicy::Ask => KeyPolicy::Ask,
                HostKeyPolicy::AcceptNew => KeyPolicy::AcceptNew,
                HostKeyPolicy::Strict => KeyPolicy::Strict,
            }),
        }
    }

    /// Writes these fields over `s`, keeping what OpenWard does not know.
    pub(crate) fn apply(&self, s: &mut Settings) -> anyhow::Result<()> {
        s.user = self.user.clone().filter(|u| !u.is_empty());
        s.port = self.port;
        s.identity_files = self.identity_files.clone();
        s.certificate_files = self.certificate_files.clone();
        s.identities_only = self.identities_only;
        s.agent = self.agent.map(|a| match a {
            AgentKind::Off => Agent::Off,
            AgentKind::System => Agent::System,
            AgentKind::Socket => Agent::Socket(self.agent_socket.clone()),
        });
        // What a newer version wrote inside them stays: in a jump to the
        // same address, in the proxy server and in the mark.
        let jump_extra = |host: &str| match &s.route {
            Some(Route::Jump(jumps)) => jumps.iter().find_map(|j| match j {
                Jump::Address { host: h, extra, .. } if h == host => Some(extra.clone()),
                _ => None,
            }),
            _ => None,
        };
        let jump_extras: Vec<_> = self
            .jumps
            .iter()
            .map(|j| {
                j.address
                    .as_deref()
                    .and_then(jump_extra)
                    .unwrap_or_default()
            })
            .collect();
        let proxy_extra = match &s.proxy {
            Some(Proxy::Http(p) | Proxy::Socks5(p)) => p.extra.clone(),
            _ => Default::default(),
        };
        let mark_extra = match &s.environment {
            Some(Environment::Mark(m)) => m.extra.clone(),
            _ => Default::default(),
        };
        s.route = match self.route {
            None => None,
            Some(RouteKind::Direct) => Some(Route::Direct),
            Some(RouteKind::Command) => Some(Route::Command(self.proxy_command.clone())),
            Some(RouteKind::Jump) => Some(Route::Jump(
                self.jumps
                    .iter()
                    .zip(jump_extras)
                    .map(|(j, extra)| match (&j.host_id, &j.address) {
                        (Some(hid), _) => Ok(Jump::Host(id(hid)?)),
                        (None, Some(address)) => Ok(Jump::Address {
                            host: address.clone(),
                            user: j.user.clone(),
                            port: j.port,
                            extra,
                        }),
                        (None, None) => Err(anyhow::anyhow!("a jump needs a host or an address")),
                    })
                    .collect::<anyhow::Result<_>>()?,
            )),
        };
        let server = || {
            let host = self.proxy_host.trim();
            if host.is_empty() || self.proxy_port == 0 {
                anyhow::bail!("a proxy needs a host and a port");
            }
            Ok(ProxyServer {
                host: host.to_owned(),
                port: self.proxy_port,
                user: Some(self.proxy_user.trim().to_owned()).filter(|u| !u.is_empty()),
                extra: proxy_extra.clone(),
            })
        };
        s.proxy = match self.proxy {
            None => None,
            Some(ProxyKind::Off) => Some(Proxy::None),
            Some(ProxyKind::Http) => Some(Proxy::Http(server()?)),
            Some(ProxyKind::Socks5) => Some(Proxy::Socks5(server()?)),
        };
        s.keepalive_secs = self.keepalive_secs;
        s.connect_timeout_secs = self.connect_timeout_secs;
        s.agent_forward = self.agent_forward;
        s.persistent_session = self.persistent_session;
        s.term = self.term.clone().filter(|t| !t.is_empty());
        s.env = self.env.as_ref().map(|env| {
            env.iter()
                .map(|v| (v.name.clone(), v.value.clone()))
                .collect()
        });
        s.host_key_policy = self.host_key_policy.map(|p| match p {
            KeyPolicy::Ask => HostKeyPolicy::Ask,
            KeyPolicy::AcceptNew => HostKeyPolicy::AcceptNew,
            KeyPolicy::Strict => HostKeyPolicy::Strict,
        });
        s.identity = identity_choice(self.identity, &self.identity_id)?;
        s.environment = match self.environment {
            None => None,
            Some(EnvironmentKind::None) => Some(Environment::None),
            Some(EnvironmentKind::Mark) => {
                let name = self.environment_name.trim();
                if name.is_empty() {
                    anyhow::bail!("an environment needs a name");
                }
                let short = self.environment_short.trim();
                Some(Environment::Mark(EnvironmentMark {
                    name: name.to_owned(),
                    short: if short.is_empty() { name } else { short }.to_owned(),
                    color: self.environment_color.trim().to_owned(),
                    extra: mark_extra,
                }))
            }
        };
        s.read_os_release = self.read_os_release;
        s.session_log = self.session_log;
        s.legacy_host_keys = self.legacy_host_keys;
        s.protocol = self.protocol.map(ProtocolKind::proto);
        s.serial = self.serial.map(|l| l.line(s.serial.as_ref()));
        s.mosh = self.mosh;
        s.mosh_server = self.mosh_server.clone().filter(|m| !m.trim().is_empty());
        s.encoding = self
            .encoding
            .as_deref()
            .map(str::trim)
            .filter(|e| !e.is_empty())
            .map(str::to_lowercase);
        s.backspace = self.backspace.map(BackspaceKind::proto);
        // Empty here is the app's own colors, over a group's scheme.
        s.terminal_scheme = self.terminal_scheme.as_deref().map(|t| t.trim().to_owned());
        s.startup_snippet = self.startup_snippet.as_deref().map(|t| t.trim().to_owned());
        Ok(())
    }
}

/// A row of the host list.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HostView {
    pub id: String,
    pub label: String,
    pub address: String,
    pub group_id: Option<String>,
    pub tags: Vec<String>,
    /// Effective user and port, for `user@address:port`.
    pub user: String,
    pub port: u16,
    /// The `~/.ssh/config` alias it was imported from.
    pub imported_alias: Option<String>,
    /// Its mark, its own or its groups'.
    pub environment: Option<EnvironmentView>,
    pub system: Option<SystemView>,
    /// Its place among the favorites (lower first), if it is one.
    pub favorite: Option<u32>,
    /// How it is reached, its own or its groups'.
    pub protocol: ProtocolKind,
    /// With a serial port: its settings.
    pub serial: Option<SerialLineSpec>,
    /// Its terminal's scheme, its own or its groups'; empty for the app's.
    pub terminal_scheme: String,
    /// The snippet typed in each new shell, its own or its groups'; empty
    /// for none.
    pub startup_snippet: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GroupView {
    pub id: String,
    pub name: String,
    pub parent_id: Option<String>,
    /// Its mark, its own or its parents'.
    pub environment: Option<EnvironmentView>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TagCount {
    pub tag: String,
    pub hosts: u32,
}

#[frb(non_opaque)]
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct HostSpec {
    pub label: String,
    pub address: String,
    pub group_id: Option<String>,
    #[frb(default = "const []")]
    pub tags: Vec<String>,
    pub notes: Option<String>,
    #[frb(default = "const SettingsSpec()")]
    pub settings: SettingsSpec,
    /// Among the favorites; a new one goes last.
    #[frb(default = "false")]
    pub favorite: bool,
    /// The system's code, chosen by hand; null leaves it to what
    /// connecting tells.
    #[frb(default = "null")]
    pub system_code: Option<String>,
}

/// Three ways: what an editor changed from what it read (`base`) goes over
/// what is there now (`theirs`); a field both changed, each its own way,
/// is a conflict (`None`).
fn pick<T: PartialEq>(base: &T, mine: T, theirs: T) -> Option<T> {
    if mine == *base || mine == theirs {
        Some(theirs)
    } else if theirs == *base {
        Some(mine)
    } else {
        None
    }
}

impl SettingsSpec {
    /// [`pick`] field by field; those that go together (an agent and its
    /// socket, a route and its jumps, a proxy and its server, an identity
    /// and its id, a mark and its name) as one.
    pub(crate) fn merge(base: &Self, mine: Self, theirs: Self) -> Option<Self> {
        let b = base.clone();
        let (agent, agent_socket) = pick(
            &(b.agent, b.agent_socket),
            (mine.agent, mine.agent_socket),
            (theirs.agent, theirs.agent_socket),
        )?;
        let (route, jumps, proxy_command) = pick(
            &(b.route, b.jumps, b.proxy_command),
            (mine.route, mine.jumps, mine.proxy_command),
            (theirs.route, theirs.jumps, theirs.proxy_command),
        )?;
        let (proxy, proxy_host, proxy_port, proxy_user) = pick(
            &(b.proxy, b.proxy_host, b.proxy_port, b.proxy_user),
            (
                mine.proxy,
                mine.proxy_host,
                mine.proxy_port,
                mine.proxy_user,
            ),
            (
                theirs.proxy,
                theirs.proxy_host,
                theirs.proxy_port,
                theirs.proxy_user,
            ),
        )?;
        let (identity, identity_id) = pick(
            &(b.identity, b.identity_id),
            (mine.identity, mine.identity_id),
            (theirs.identity, theirs.identity_id),
        )?;
        let (environment, environment_name, environment_short, environment_color) = pick(
            &(
                b.environment,
                b.environment_name,
                b.environment_short,
                b.environment_color,
            ),
            (
                mine.environment,
                mine.environment_name,
                mine.environment_short,
                mine.environment_color,
            ),
            (
                theirs.environment,
                theirs.environment_name,
                theirs.environment_short,
                theirs.environment_color,
            ),
        )?;
        Some(Self {
            user: pick(&base.user, mine.user, theirs.user)?,
            port: pick(&base.port, mine.port, theirs.port)?,
            identity_files: pick(
                &base.identity_files,
                mine.identity_files,
                theirs.identity_files,
            )?,
            certificate_files: pick(
                &base.certificate_files,
                mine.certificate_files,
                theirs.certificate_files,
            )?,
            identities_only: pick(
                &base.identities_only,
                mine.identities_only,
                theirs.identities_only,
            )?,
            agent,
            agent_socket,
            route,
            jumps,
            proxy_command,
            proxy,
            proxy_host,
            proxy_port,
            proxy_user,
            keepalive_secs: pick(
                &base.keepalive_secs,
                mine.keepalive_secs,
                theirs.keepalive_secs,
            )?,
            connect_timeout_secs: pick(
                &base.connect_timeout_secs,
                mine.connect_timeout_secs,
                theirs.connect_timeout_secs,
            )?,
            agent_forward: pick(
                &base.agent_forward,
                mine.agent_forward,
                theirs.agent_forward,
            )?,
            persistent_session: pick(
                &base.persistent_session,
                mine.persistent_session,
                theirs.persistent_session,
            )?,
            term: pick(&base.term, mine.term, theirs.term)?,
            env: pick(&base.env, mine.env, theirs.env)?,
            host_key_policy: pick(
                &base.host_key_policy,
                mine.host_key_policy,
                theirs.host_key_policy,
            )?,
            legacy_host_keys: pick(
                &base.legacy_host_keys,
                mine.legacy_host_keys,
                theirs.legacy_host_keys,
            )?,
            identity,
            identity_id,
            environment,
            environment_name,
            environment_short,
            environment_color,
            read_os_release: pick(
                &base.read_os_release,
                mine.read_os_release,
                theirs.read_os_release,
            )?,
            session_log: pick(&base.session_log, mine.session_log, theirs.session_log)?,
            protocol: pick(&base.protocol, mine.protocol, theirs.protocol)?,
            serial: pick(&base.serial, mine.serial, theirs.serial)?,
            mosh: pick(&base.mosh, mine.mosh, theirs.mosh)?,
            mosh_server: pick(&base.mosh_server, mine.mosh_server, theirs.mosh_server)?,
            encoding: pick(&base.encoding, mine.encoding, theirs.encoding)?,
            backspace: pick(&base.backspace, mine.backspace, theirs.backspace)?,
            terminal_scheme: pick(
                &base.terminal_scheme,
                mine.terminal_scheme,
                theirs.terminal_scheme,
            )?,
            startup_snippet: pick(
                &base.startup_snippet,
                mine.startup_snippet,
                theirs.startup_snippet,
            )?,
        })
    }
}

impl HostSpec {
    /// [`pick`] field by field, and the settings by [`SettingsSpec::merge`].
    pub(crate) fn merge(base: &Self, mine: Self, theirs: Self) -> Option<Self> {
        Some(Self {
            label: pick(&base.label, mine.label, theirs.label)?,
            address: pick(&base.address, mine.address, theirs.address)?,
            group_id: pick(&base.group_id, mine.group_id, theirs.group_id)?,
            tags: pick(&base.tags, mine.tags, theirs.tags)?,
            notes: pick(&base.notes, mine.notes, theirs.notes)?,
            settings: SettingsSpec::merge(&base.settings, mine.settings, theirs.settings)?,
            favorite: pick(&base.favorite, mine.favorite, theirs.favorite)?,
            system_code: pick(&base.system_code, mine.system_code, theirs.system_code)?,
        })
    }
}

#[frb(non_opaque)]
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct GroupSpec {
    pub name: String,
    pub parent_id: Option<String>,
    #[frb(default = "const SettingsSpec()")]
    pub settings: SettingsSpec,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OriginKind {
    /// Nothing sets it; the connection decides (local user, default keys).
    Unset,
    Default,
    Group,
    /// The identity in `identity_id`.
    Identity,
    Host,
}

/// Where an effective setting comes from.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FieldOrigin {
    /// A field of [`SettingsSpec`] (`agent` covers `agent_socket`, `route`
    /// covers `jumps` and `proxy_command`, `identity` covers
    /// `identity_id`).
    pub field: String,
    pub origin: OriginKind,
    pub group_id: Option<String>,
    pub identity_id: Option<String>,
}

pub(crate) fn origin(field: &str, o: Option<Origin>) -> FieldOrigin {
    let (origin, group_id, identity_id) = match o {
        None => (OriginKind::Unset, None, None),
        Some(Origin::Default) => (OriginKind::Default, None, None),
        Some(Origin::Host) => (OriginKind::Host, None, None),
        Some(Origin::Group(g)) => (OriginKind::Group, Some(g.to_string()), None),
        Some(Origin::Identity(i)) => (OriginKind::Identity, None, Some(i.to_string())),
    };
    FieldOrigin {
        field: field.to_owned(),
        origin,
        group_id,
        identity_id,
    }
}

/// A host to edit: what it sets itself, what it ends up with, and why.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HostDetail {
    pub id: String,
    /// Pass back to `update_host`.
    pub rev: u64,
    pub spec: HostSpec,
    pub effective: SettingsSpec,
    pub origins: Vec<FieldOrigin>,
    /// What connecting told (or what was chosen), for the editor.
    pub system: Option<SystemView>,
}

/// What a host or group placed in a group gets before its own settings.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InheritedView {
    pub effective: SettingsSpec,
    pub origins: Vec<FieldOrigin>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GroupDetail {
    pub id: String,
    pub rev: u64,
    pub spec: GroupSpec,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ImportWarningKind {
    Unsupported,
    Match,
    BadValue,
    Stricter,
    IncludeTooDeep,
    /// A file that could not be read; `subject` says why, in English.
    Unreadable,
    /// A file without permission to read it.
    Denied,
    JumpLossy,
}

/// Something that did not carry over; the UI words it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ImportWarning {
    pub kind: ImportWarningKind,
    pub file: String,
    pub line: u32,
    /// The keyword, the alias, or the error.
    pub subject: String,
    /// The value, or the jump.
    pub detail: String,
}

/// One alias as an import would bring it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ImportPreview {
    pub alias: String,
    pub address: String,
    pub user: Option<String>,
    pub port: Option<u16>,
    /// What it jumps through, in order: aliases of the same file, or
    /// addresses. Importing it brings those aliases along.
    pub jumps: Vec<String>,
    /// Imported before: importing again leaves it as it is.
    pub existing: bool,
    /// Tunnels (its forwards) it would bring that are not in OpenWard yet.
    pub tunnels: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ImportReport {
    pub group_id: String,
    pub created: u32,
    pub skipped: u32,
    pub tunnels: u32,
    pub warnings: Vec<ImportWarning>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_round_trip_through_the_spec() {
        let settings = Settings {
            user: Some("ops".into()),
            agent: Some(Agent::Socket("~/agent.sock".into())),
            route: Some(Route::Jump(vec![
                Jump::Host(ItemId::new()),
                Jump::Address {
                    host: "10.0.0.1".into(),
                    user: None,
                    port: Some(2222),
                    extra: Default::default(),
                },
            ])),
            env: Some([("LANG".to_owned(), "C".to_owned())].into()),
            host_key_policy: Some(HostKeyPolicy::Strict),
            identity: Some(UseIdentity::Id(ItemId::new())),
            environment: Some(Environment::Mark(EnvironmentMark {
                name: "Producción".into(),
                short: "prod".into(),
                color: "red".into(),
                extra: Default::default(),
            })),
            read_os_release: Some(true),
            session_log: Some(true),
            ..Settings::default()
        };
        let spec = SettingsSpec::from_settings(&settings);
        let mut back = Settings::default();
        spec.apply(&mut back).unwrap();
        assert_eq!(back, settings);
    }

    /// An edit over a host that changed meanwhile: what each side changed
    /// stays; the same field changed both ways is a conflict.
    #[test]
    fn edits_merge_three_ways() {
        let base = HostSpec {
            label: "web".into(),
            address: "web.example.com".into(),
            settings: SettingsSpec {
                port: Some(22),
                ..SettingsSpec::default()
            },
            ..HostSpec::default()
        };
        let mut mine = base.clone();
        mine.label = "web-1".into();
        mine.settings.user = Some("ops".into());
        let mut theirs = base.clone();
        theirs.favorite = true;
        theirs.settings.port = Some(2222);
        let merged = HostSpec::merge(&base, mine.clone(), theirs.clone()).unwrap();
        assert_eq!(merged.label, "web-1");
        assert_eq!(merged.settings.user.as_deref(), Some("ops"));
        assert_eq!(merged.settings.port, Some(2222));
        assert!(merged.favorite);

        theirs.label = "web-2".into();
        assert_eq!(
            HostSpec::merge(&base, mine, theirs),
            None,
            "both renamed it"
        );
        // A route and its jumps go as one.
        let mut mine = base.clone();
        mine.settings.route = Some(RouteKind::Command);
        mine.settings.proxy_command = "nc %h %p".into();
        let mut theirs = base.clone();
        theirs.settings.proxy_command = "ssh -W %h:%p bastion".into();
        assert_eq!(HostSpec::merge(&base, mine, theirs), None);
    }

    /// The core's errors reach the app by kind, with their text for
    /// «Detalles», through the context they gathered on the way.
    #[test]
    fn vault_errors_go_by_kind() {
        use openward_app::vault::Error as E;
        let kind = |e: anyhow::Error| VaultError::from(e).kind;
        let conflict = E::Conflict {
            id: ItemId::new(),
            expected: 1,
            current: 2,
        };
        assert_eq!(kind(conflict.into()), VaultErrorKind::Conflict);
        let cycle = anyhow::Error::new(E::Cycle).context("saving the group");
        let e = VaultError::from(cycle);
        assert_eq!(e.kind, VaultErrorKind::Cycle);
        assert_eq!(
            e.message,
            "saving the group: a group cannot be inside itself"
        );
        assert_eq!(
            VaultError::from(id("nope").unwrap_err()).kind,
            VaultErrorKind::Invalid
        );
        assert_eq!(
            kind(E::InUse(ItemId::new(), vec![]).into()),
            VaultErrorKind::InUse
        );
        assert_eq!(kind(anyhow::anyhow!("other")), VaultErrorKind::Other);
    }

    /// Saving from the editor keeps what a newer version wrote inside a
    /// jump, the proxy server and the mark: the editor only knows the rest.
    #[test]
    fn saving_keeps_what_a_newer_version_wrote_inside() {
        let future = || {
            let mut extra = openward_app::vault::proto::Extra::new();
            extra.insert("future".into(), true.into());
            extra
        };
        let mut settings = Settings {
            route: Some(Route::Jump(vec![Jump::Address {
                host: "bastion".into(),
                user: None,
                port: None,
                extra: future(),
            }])),
            proxy: Some(Proxy::Socks5(ProxyServer {
                host: "proxy".into(),
                port: 1080,
                user: None,
                extra: future(),
            })),
            environment: Some(Environment::Mark(EnvironmentMark {
                name: "Producción".into(),
                short: "prod".into(),
                color: "red".into(),
                extra: future(),
            })),
            ..Settings::default()
        };
        let mut spec = SettingsSpec::from_settings(&settings);
        spec.environment_color = "orange".into();
        spec.proxy_port = 1081;
        spec.apply(&mut settings).unwrap();
        let Some(Route::Jump(jumps)) = &settings.route else {
            panic!("no jumps")
        };
        assert!(matches!(&jumps[0], Jump::Address { extra, .. } if *extra == future()));
        let Some(Proxy::Socks5(proxy)) = &settings.proxy else {
            panic!("no proxy")
        };
        assert_eq!((proxy.port, &proxy.extra), (1081, &future()));
        let Some(Environment::Mark(mark)) = &settings.environment else {
            panic!("no mark")
        };
        assert_eq!((mark.color.as_str(), &mark.extra), ("orange", &future()));
    }
}
