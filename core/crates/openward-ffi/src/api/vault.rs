//! Hosts and groups as Dart sees them: plain values, ids as strings.
//!
//! Editing goes through specs that carry only the fields OpenWard knows;
//! updates apply them over the stored item, so fields written by a newer
//! version survive (openward-proto).

use std::str::FromStr;

use flutter_rust_bridge::frb;
use openward_app::vault::Origin;
use openward_app::vault::proto::{
    Agent, HostKeyPolicy, ItemId, Jump, Proxy, ProxyServer, Route, Settings,
};

pub(crate) fn id(text: &str) -> anyhow::Result<ItemId> {
    ItemId::from_str(text).map_err(|e| anyhow::anyhow!("bad id {text:?}: {e}"))
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
    pub agent_forward: Option<bool>,
    pub term: Option<String>,
    pub env: Option<Vec<EnvVar>>,
    pub host_key_policy: Option<KeyPolicy>,
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
                        Jump::Address { host, user, port } => JumpSpec {
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
        Self {
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
            agent_forward: s.agent_forward,
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
        s.route = match self.route {
            None => None,
            Some(RouteKind::Direct) => Some(Route::Direct),
            Some(RouteKind::Command) => Some(Route::Command(self.proxy_command.clone())),
            Some(RouteKind::Jump) => Some(Route::Jump(
                self.jumps
                    .iter()
                    .map(|j| match (&j.host_id, &j.address) {
                        (Some(hid), _) => Ok(Jump::Host(id(hid)?)),
                        (None, Some(address)) => Ok(Jump::Address {
                            host: address.clone(),
                            user: j.user.clone(),
                            port: j.port,
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
            })
        };
        s.proxy = match self.proxy {
            None => None,
            Some(ProxyKind::Off) => Some(Proxy::None),
            Some(ProxyKind::Http) => Some(Proxy::Http(server()?)),
            Some(ProxyKind::Socks5) => Some(Proxy::Socks5(server()?)),
        };
        s.keepalive_secs = self.keepalive_secs;
        s.agent_forward = self.agent_forward;
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
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GroupView {
    pub id: String,
    pub name: String,
    pub parent_id: Option<String>,
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
    Host,
}

/// Where an effective setting comes from.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FieldOrigin {
    /// A field of [`SettingsSpec`] (`agent` covers `agent_socket`, `route`
    /// covers `jumps` and `proxy_command`).
    pub field: String,
    pub origin: OriginKind,
    pub group_id: Option<String>,
}

pub(crate) fn origin(field: &str, o: Option<Origin>) -> FieldOrigin {
    let (origin, group_id) = match o {
        None => (OriginKind::Unset, None),
        Some(Origin::Default) => (OriginKind::Default, None),
        Some(Origin::Host) => (OriginKind::Host, None),
        Some(Origin::Group(g)) => (OriginKind::Group, Some(g.to_string())),
    };
    FieldOrigin {
        field: field.to_owned(),
        origin,
        group_id,
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KnownHostView {
    pub id: String,
    pub hosts: String,
    pub algorithm: String,
    pub key: String,
    pub cert_authority: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ImportWarningKind {
    Unsupported,
    Match,
    BadValue,
    Stricter,
    IncludeTooDeep,
    Unreadable,
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
                },
            ])),
            env: Some([("LANG".to_owned(), "C".to_owned())].into()),
            host_key_policy: Some(HostKeyPolicy::Strict),
            ..Settings::default()
        };
        let spec = SettingsSpec::from_settings(&settings);
        let mut back = Settings::default();
        spec.apply(&mut back).unwrap();
        assert_eq!(back, settings);
    }
}
