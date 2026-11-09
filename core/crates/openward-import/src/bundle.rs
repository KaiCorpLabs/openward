//! What an importer read from another program, before anything is in the
//! vault: groups, hosts, identities and the rest, each with that program's
//! own id, and what could not come along.
//!
//! References between them (a host's group, a jump through another host,
//! an identity's key) use those ids too. The app turns a bundle into vault
//! items, leaving alone what an earlier import already brought.

use std::fmt;

use openward_proto::{ForwardKind, Marker, Settings};
use zeroize::Zeroizing;

/// The programs there is an importer for.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Program {
    Termius,
    Putty,
    Kitty,
    MobaXterm,
    Tabby,
    SecureCrt,
    /// A spreadsheet of hosts (Termius's import template among them).
    Csv,
}

impl Program {
    /// The id kept in the vault's `imported.from`.
    pub fn id(self) -> &'static str {
        match self {
            Self::Termius => "termius",
            Self::Putty => "putty",
            Self::Kitty => "kitty",
            Self::MobaXterm => "mobaxterm",
            Self::Tabby => "tabby",
            Self::SecureCrt => "securecrt",
            Self::Csv => "csv",
        }
    }

    pub fn from_id(id: &str) -> Option<Self> {
        [
            Self::Termius,
            Self::Putty,
            Self::Kitty,
            Self::MobaXterm,
            Self::Tabby,
            Self::SecureCrt,
            Self::Csv,
        ]
        .into_iter()
        .find(|p| p.id() == id)
    }

    /// The name people know it by: also the group imports go into.
    pub fn name(self) -> &'static str {
        match self {
            Self::Termius => "Termius",
            Self::Putty => "PuTTY",
            Self::Kitty => "KiTTY",
            Self::MobaXterm => "MobaXterm",
            Self::Tabby => "Tabby",
            Self::SecureCrt => "SecureCRT",
            Self::Csv => "CSV",
        }
    }
}

impl fmt::Display for Program {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Bundle {
    pub groups: Vec<Group>,
    pub hosts: Vec<Host>,
    pub identities: Vec<Identity>,
    /// Private keys the program keeps inside itself.
    pub keys: Vec<StoredKey>,
    pub tunnels: Vec<Tunnel>,
    pub snippets: Vec<Snippet>,
    pub known_hosts: Vec<KnownHost>,
    pub warnings: Vec<Warning>,
    /// Saved passwords and key passphrases, never imported.
    pub passwords: usize,
    pub passphrases: usize,
}

/// A folder, inside its parent or at the top.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Group {
    pub id: String,
    pub name: String,
    pub parent: Option<String>,
    /// Without keys or identity: those go in `keys` and `identity`.
    pub settings: Settings,
    pub identity: Option<String>,
    pub keys: Vec<KeyRef>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Host {
    pub id: String,
    pub label: String,
    pub address: String,
    pub group: Option<String>,
    /// Without keys, identity or jumps: those go in their own fields.
    pub settings: Settings,
    pub identity: Option<String>,
    pub keys: Vec<KeyRef>,
    /// Through these, first to last.
    pub jumps: Vec<JumpRef>,
    pub tags: Vec<String>,
    pub notes: Option<String>,
    /// Why it cannot be imported (`telnet`, `serial`…); shown, not
    /// brought.
    pub unsupported: Option<String>,
}

/// A named login that several hosts or groups use.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Identity {
    pub id: String,
    pub label: String,
    pub user: Option<String>,
    pub keys: Vec<KeyRef>,
}

/// A private key, by where it is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum KeyRef {
    /// A file, as the program has it (`~` and OpenSSH tokens allowed).
    Path(String),
    /// One of the bundle's [`StoredKey`]s, by id.
    Stored(String),
}

/// A private key kept inside the other program. The vault never holds it:
/// the app looks for the same key in `~/.ssh`, or saves it there if asked.
/// Its secrets are wiped from memory when it goes.
#[derive(Clone, PartialEq, Eq)]
pub struct StoredKey {
    pub id: String,
    pub label: String,
    /// In whatever text format the program kept it (OpenSSH, PEM, PPK).
    pub private_key: Zeroizing<String>,
    pub passphrase: Option<Zeroizing<String>>,
}

impl fmt::Debug for StoredKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("StoredKey")
            .field("id", &self.id)
            .field("label", &self.label)
            .finish_non_exhaustive()
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum JumpRef {
    /// Another host of the bundle, by id.
    Host(String),
    Address {
        host: String,
        user: Option<String>,
        port: Option<u16>,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Tunnel {
    /// The host it goes over, by id.
    pub host: String,
    pub label: String,
    pub kind: ForwardKind,
    pub listen_address: Option<String>,
    pub listen_port: u16,
    pub dest_host: Option<String>,
    pub dest_port: Option<u16>,
    pub autostart: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Snippet {
    pub id: String,
    pub label: String,
    pub script: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KnownHost {
    pub id: String,
    pub hosts: String,
    pub key: String,
    pub marker: Option<Marker>,
    pub comment: Option<String>,
}

/// Something that did not come along as it was. `subject` is what it is
/// about (a host's label), when it is about one thing.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Warning {
    pub subject: Option<String>,
    pub kind: WarningKind,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WarningKind {
    /// Mosh: it comes in as SSH.
    Mosh,
    /// A command run on connect, which OpenWard does not do yet.
    StartupCommand,
    /// A `ProxyCommand`, left out: it would run a program on this computer
    /// on the word of another program's file. The text is the command, for
    /// the user to set it by hand if they trust it.
    ProxyCommand(String),
    /// The agent forwarded to the server, left out: that server could sign
    /// with your keys while you are connected, on the word of another
    /// program's file. See [`Bundle::hold_back`].
    AgentForward,
    /// A tunnel that listened at this address, open to other computers: it
    /// comes in listening on loopback. See [`Bundle::hold_back`].
    OpenTunnel(String),
    /// Something OpenWard does not have; the rest of the item came in.
    Unsupported(Missing),
    /// A value that made no sense (`port`, `70000`); left out.
    BadValue { field: String, value: String },
    /// Items shared from a team, encrypted with a key this computer does
    /// not have.
    Shared { count: usize },
    /// Termius's host chains, whose format is not known: the hosts come
    /// in without those jumps.
    HostChain,
    /// Part of the data could not be read: so many items; `why` in
    /// English, for logs.
    Unreadable { count: usize, why: String },
}

/// What OpenWard does not have, of an item that came in without it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Missing {
    X11,
    Socks4Proxy,
    TelnetProxy,
    /// A proxy of another type, as the program names it.
    Proxy(String),
    /// A proxy without its address or its port.
    IncompleteProxy,
    HardwareKey,
    /// A key kept in Tabby's vault.
    TabbyVaultKey,
    SecureCrtGlobalKey,
    /// A password MobaXterm keeps.
    MobaCredential,
    /// A jump through a profile that is not SSH.
    JumpNotSsh,
    /// A jump through a session that is not there, by its name.
    JumpThrough(String),
    /// SecureCRT's firewall, by its name.
    Firewall(String),
}

/// Whether two ids of the same program name the same item. Termius's ids
/// are `id:…|local:…` alternatives (its server's id, this computer's):
/// any shared alternative is a match.
pub fn same_item(program: Program, a: &str, b: &str) -> bool {
    if program != Program::Termius {
        return a == b;
    }
    a.split('|').any(|x| b.split('|').any(|y| x == y))
}

impl Warning {
    pub fn about(subject: impl Into<String>, kind: WarningKind) -> Self {
        Self {
            subject: Some(subject.into()),
            kind,
        }
    }

    pub fn general(kind: WarningKind) -> Self {
        Self {
            subject: None,
            kind,
        }
    }
}

impl Bundle {
    /// Leaves out what another program's file could turn against you, and
    /// says so, as with a `ProxyCommand`: the agent forwarded to a server
    /// (whoever runs it signs with your keys while you are connected) and
    /// tunnels open to the network (anyone there goes through them). The
    /// file's word is not enough for either; whoever trusts it sets them
    /// by hand. An agent turned off on purpose stays off.
    pub fn hold_back(&mut self) {
        let mut said = Vec::new();
        for g in &mut self.groups {
            if g.settings.agent_forward == Some(true) {
                g.settings.agent_forward = None;
                said.push(Warning::about(&g.name, WarningKind::AgentForward));
            }
        }
        for h in &mut self.hosts {
            if h.settings.agent_forward == Some(true) {
                h.settings.agent_forward = None;
                // One that does not come in needs no word.
                if h.unsupported.is_none() {
                    said.push(Warning::about(&h.label, WarningKind::AgentForward));
                }
            }
        }
        for t in &mut self.tunnels {
            let Some(address) = t.listen_address.take_if(|a| !loopback(a)) else {
                continue;
            };
            let name = if t.label.trim().is_empty() {
                let host = self.hosts.iter().find(|h| h.id == t.host);
                let host = host.map_or(t.host.as_str(), |h| h.label.as_str());
                format!("{host} :{}", t.listen_port)
            } else {
                t.label.clone()
            };
            said.push(Warning::about(name, WarningKind::OpenTunnel(address)));
        }
        self.warnings.extend(said);
    }
}

/// Whether a tunnel listening at `address` is for this computer alone, as
/// the tunnels read it: no address, `localhost` or a loopback one.
fn loopback(address: &str) -> bool {
    let a = address.trim().trim_start_matches('[').trim_end_matches(']');
    a.is_empty()
        || a.eq_ignore_ascii_case("localhost")
        || a.parse::<std::net::IpAddr>()
            .is_ok_and(|ip| ip.is_loopback())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn host(id: &str, forward: Option<bool>) -> Host {
        let mut h = Host {
            id: id.into(),
            label: id.into(),
            address: format!("{id}.example.com"),
            ..Host::default()
        };
        h.settings.agent_forward = forward;
        h
    }

    fn tunnel(label: &str, listen: Option<&str>) -> Tunnel {
        Tunnel {
            host: "web".into(),
            label: label.into(),
            kind: ForwardKind::Local,
            listen_address: listen.map(Into::into),
            listen_port: 8080,
            dest_host: Some("db".into()),
            dest_port: Some(5432),
            autostart: true,
        }
    }

    /// AM-8: a file that points a host at a server with your agent, or
    /// opens a tunnel to the network, brings neither.
    #[test]
    fn the_agent_and_open_tunnels_are_held_back_and_said() {
        let mut group = Group {
            id: "g".into(),
            name: "Producción".into(),
            ..Group::default()
        };
        group.settings.agent_forward = Some(true);
        let mut telnet = host("switch", Some(true));
        telnet.unsupported = Some("telnet".into());
        let mut b = Bundle {
            groups: vec![group],
            hosts: vec![
                host("web", Some(true)),
                host("off", Some(false)),
                host("plain", None),
                telnet,
            ],
            tunnels: vec![
                tunnel("abierto", Some("0.0.0.0")),
                tunnel("", Some("*")),
                tunnel("v6", Some("[::]")),
                tunnel("local", Some("127.0.0.1")),
                tunnel("local6", Some("[::1]")),
                tunnel("nombre", Some("localhost")),
                tunnel("vacío", Some(" ")),
                tunnel("ninguno", None),
            ],
            ..Bundle::default()
        };
        b.hold_back();

        assert_eq!(b.groups[0].settings.agent_forward, None);
        let forwards: Vec<_> = b.hosts.iter().map(|h| h.settings.agent_forward).collect();
        assert_eq!(forwards, [None, Some(false), None, None]);
        let open: Vec<_> = b
            .tunnels
            .iter()
            .map(|t| t.listen_address.as_deref())
            .collect();
        assert_eq!(
            open,
            [
                None,
                None,
                None,
                Some("127.0.0.1"),
                Some("[::1]"),
                Some("localhost"),
                Some(" "),
                None
            ]
        );
        assert_eq!(
            b.warnings,
            [
                Warning::about("Producción", WarningKind::AgentForward),
                Warning::about("web", WarningKind::AgentForward),
                Warning::about("abierto", WarningKind::OpenTunnel("0.0.0.0".into())),
                Warning::about("web :8080", WarningKind::OpenTunnel("*".into())),
                Warning::about("v6", WarningKind::OpenTunnel("[::]".into())),
            ]
        );
    }
}
