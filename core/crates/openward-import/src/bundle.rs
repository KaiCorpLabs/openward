//! What an importer read from another program, before anything is in the
//! vault: groups, hosts, identities and the rest, each with that program's
//! own id, and what could not come along.
//!
//! References between them (a host's group, a jump through another host,
//! an identity's key) use those ids too. The app turns a bundle into vault
//! items, leaving alone what an earlier import already brought.

use std::fmt;

use openward_proto::{ForwardKind, Marker, Settings};

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
#[derive(Clone, PartialEq, Eq)]
pub struct StoredKey {
    pub id: String,
    pub label: String,
    /// In whatever text format the program kept it (OpenSSH, PEM, PPK).
    pub private_key: String,
    pub passphrase: Option<String>,
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
    /// Something OpenWard does not have, named in the program's terms
    /// (`X11 forwarding`, `a telnet proxy`); the rest of the item came in.
    Unsupported(String),
    /// A value that made no sense (`port`, `70000`); left out.
    BadValue { field: String, value: String },
    /// Items shared from a team, encrypted with a key this computer does
    /// not have.
    Shared { count: usize },
    /// Termius's host chains, whose format is not known: the hosts come
    /// in without those jumps.
    HostChain,
    /// Part of the file or data could not be read.
    Unreadable(String),
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
