//! Connection settings that groups and hosts set partially and inherit.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::{Extra, ItemId};

/// The fields an identity sets; the rest are a host's or a group's.
pub const IDENTITY_FIELDS: &[&str] = &[
    "user",
    "identity_files",
    "certificate_files",
    "identities_only",
    "agent",
];

/// Declares the settings once: the struct, its field names and the overlay
/// that inheritance is built on.
macro_rules! settings {
    ($( $(#[doc = $doc:literal])* $name:ident: $ty:ty, )*) => {
        /// Every field is optional: `None` means "inherit".
        #[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
        pub struct Settings {
            $(
                $(#[doc = $doc])*
                #[serde(default, skip_serializing_if = "Option::is_none")]
                pub $name: Option<$ty>,
            )*
            #[serde(flatten)]
            pub extra: Extra,
        }

        impl Settings {
            /// Field names, as encoded and as [`Settings::overlay`] reports them.
            pub const FIELDS: &[&str] = &[$(stringify!($name)),*];

            pub fn is_empty(&self) -> bool {
                $(self.$name.is_none() &&)* self.extra.is_empty()
            }

            /// Copies what `layer` sets over `self` and calls `set` with the
            /// name of each field it took. Unknown fields are not inherited.
            pub fn overlay(&mut self, layer: &Settings, mut set: impl FnMut(&'static str)) {
                $(
                    if let Some(value) = &layer.$name {
                        self.$name = Some(value.clone());
                        set(stringify!($name));
                    }
                )*
            }
        }
    };
}

settings! {
    /// Login name.
    user: String,
    port: u16,
    /// Private keys by path, tried in order. OpenSSH tokens (`~`, `%d`,
    /// `%h`, `%r`, `%u`) are expanded when connecting.
    identity_files: Vec<String>,
    /// Certificates by path, paired with the identity files.
    certificate_files: Vec<String>,
    /// Offer only the identity files, not every key in the agent.
    identities_only: bool,
    agent: Agent,
    /// How to reach the host.
    route: Route,
    /// A proxy in front of the first hop (not with a `ProxyCommand`).
    proxy: Proxy,
    /// Seconds between keepalives; 0 turns them off.
    keepalive_secs: u32,
    /// Seconds the server has to set up the connection and to answer each
    /// step of logging in (OpenSSH's `ConnectTimeout`).
    connect_timeout_secs: u32,
    /// Forward the agent to the server.
    agent_forward: bool,
    /// Run the shell inside tmux on the server, to find it as it was after
    /// a connection that came back.
    persistent_session: bool,
    /// `TERM` for the remote shell.
    term: String,
    /// Variables sent with the session (`SetEnv`).
    env: BTreeMap<String, String>,
    host_key_policy: HostKeyPolicy,
    /// OpenSSH `known_hosts` files trusted as well, in place of
    /// `~/.ssh/known_hosts` and `known_hosts2` (`UserKnownHostsFile`).
    /// Expanded like an identity file.
    known_hosts_files: Vec<String>,
    /// The system's, in place of `/etc/ssh/ssh_known_hosts` and
    /// `ssh_known_hosts2` (`GlobalKnownHostsFile`).
    global_known_hosts_files: Vec<String>,
    /// Accept host keys signed with `ssh-rsa` (SHA-1), for servers older
    /// than OpenSSH 7.2 that sign no other way. Off by default, as in
    /// OpenSSH since 8.8.
    legacy_host_keys: bool,
    /// The identity whose user, keys and agent apply (below the host's
    /// own settings).
    identity: UseIdentity,
    /// A color and a short name ("prod") on the host's tabs and terminals,
    /// so as not to mistake one server for another.
    environment: Environment,
    /// Read `/etc/os-release` after connecting, to tell the system better
    /// than the server's banner does. It runs a command on the server.
    read_os_release: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Agent {
    /// Do not use an agent.
    Off,
    /// The system agent: `SSH_AUTH_SOCK`, or OpenSSH's pipe on Windows.
    System,
    /// Another agent's socket, such as a password manager's. Expanded like
    /// an identity file.
    Socket(String),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Route {
    /// A TCP connection to the address.
    Direct,
    /// Through these hosts, first to last (`ProxyJump`).
    Jump(Vec<Jump>),
    /// Through a command's stdin and stdout (`ProxyCommand`). OpenSSH tokens
    /// (`%h`, `%p`, `%r`, `%n`) are expanded when connecting.
    Command(String),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Jump {
    /// A saved host, with its own settings.
    Host(ItemId),
    /// A bare `[user@]host[:port]`.
    Address {
        host: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        user: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        port: Option<u16>,
    },
}

/// An HTTP or SOCKS proxy that the connection to the first hop goes
/// through. Its password is never stored: it is asked for when needed.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Proxy {
    /// No proxy, even if a group sets one.
    None,
    /// `CONNECT` through an HTTP proxy.
    Http(ProxyServer),
    Socks5(ProxyServer),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProxyServer {
    pub host: String,
    pub port: u16,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub user: Option<String>,
}

/// Which identity a group or host uses.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UseIdentity {
    /// None, even if a group sets one.
    None,
    Id(ItemId),
}

/// How a group or host is marked.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Environment {
    /// None, even if a group sets one.
    None,
    Mark(EnvironmentMark),
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct EnvironmentMark {
    /// What it is called ("Producción").
    pub name: String,
    /// On tabs and in the sidebar ("prod").
    pub short: String,
    /// A color of the palette by name (`red`, `orange`, `yellow`, `green`,
    /// `blue`, `violet`, `pink`, `gray`): each theme draws it its way.
    pub color: String,
}

/// What to do with a host key that is not known yet. A key that changed is
/// refused under every policy until the user trusts the new one.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HostKeyPolicy {
    /// Show the fingerprint and let the user decide.
    Ask,
    /// Trust it on first use without asking (`accept-new`).
    AcceptNew,
    /// Refuse it: only known keys and certified hosts get in.
    Strict,
}
