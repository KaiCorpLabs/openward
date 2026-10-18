//! Vault data types and their CBOR encoding (ARCHITECTURE §4).
//!
//! An item's [`Body`] is what phase 2 encrypts into the `ct` of an envelope
//! (ADR-004), so it has to survive version skew between devices in both
//! directions:
//! - fields are only ever added, never renamed or retyped, and an absent
//!   field means "not set";
//! - fields this version does not know are kept in `extra` and written back
//!   untouched, so an older client never drops what a newer one wrote;
//! - an item of a type this version does not know decodes as
//!   [`Data::Unsupported`] and must be left as it is in storage. A new
//!   variant inside an existing enum is a breaking change: it needs a new
//!   field instead.

mod settings;

use std::collections::BTreeMap;
use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub use settings::{
    Agent, Environment, EnvironmentMark, HostKeyPolicy, IDENTITY_FIELDS, Jump, Proxy, ProxyServer,
    Route, Settings, UseIdentity,
};

/// Fields a newer version wrote that this one does not know.
pub type Extra = BTreeMap<String, ciborium::Value>;

/// UUIDv7: sorts by creation time and needs no coordination between devices.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ItemId(Uuid);

impl ItemId {
    #[allow(clippy::new_without_default)] // a fresh id is not a default value
    pub fn new() -> Self {
        Self(Uuid::now_v7())
    }

    pub fn from_bytes(bytes: [u8; 16]) -> Self {
        Self(Uuid::from_bytes(bytes))
    }

    pub fn as_bytes(&self) -> &[u8; 16] {
        self.0.as_bytes()
    }
}

impl fmt::Display for ItemId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}

impl FromStr for ItemId {
    type Err = uuid::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Uuid::from_str(s).map(Self)
    }
}

/// An item as the vault holds it: identity and revision live outside the
/// body (in the envelope), everything else inside.
#[derive(Clone, Debug, PartialEq)]
pub struct Item {
    pub id: ItemId,
    /// Bumped on every write; updates name the revision they started from.
    pub rev: u64,
    pub body: Body,
}

/// The encodable part of an item. Timestamps go inside so that, once
/// encrypted, the server cannot see when items change.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Body {
    /// Milliseconds since the Unix epoch.
    pub created: i64,
    pub modified: i64,
    #[serde(flatten)]
    pub data: Data,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Data {
    Group(Group),
    Host(Host),
    Identity(Identity),
    KnownHost(KnownHost),
    PortForward(PortForward),
    Snippet(Snippet),
    Workspace(Workspace),
    /// A type from a newer version. Never encoded: the stored bytes stay.
    #[serde(other)]
    Unsupported,
}

impl Data {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Group(_) => "group",
            Self::Host(_) => "host",
            Self::Identity(_) => "identity",
            Self::KnownHost(_) => "known_host",
            Self::PortForward(_) => "port_forward",
            Self::Snippet(_) => "snippet",
            Self::Workspace(_) => "workspace",
            Self::Unsupported => "unsupported",
        }
    }
}

/// A folder of hosts. Its settings apply to everything inside unless a
/// subgroup or the host sets them again.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Group {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent: Option<ItemId>,
    #[serde(default, skip_serializing_if = "Settings::is_empty")]
    pub settings: Settings,
    /// Set when it came from another program's import.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub imported: Option<Imported>,
    #[serde(flatten)]
    pub extra: Extra,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Host {
    pub label: String,
    /// Host name or IP address to connect to.
    pub address: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub group: Option<ItemId>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
    /// Only what this host sets; the rest comes from its groups.
    #[serde(default, skip_serializing_if = "Settings::is_empty")]
    pub settings: Settings,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    /// Where the host came from; `None` when created by hand.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<Source>,
    /// Set when it came from another program's import.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub imported: Option<Imported>,
    /// What the server runs: told when connecting, or chosen by hand.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub system: Option<System>,
    /// Among the favorites, in this place (lower first).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub favorite: Option<u32>,
    #[serde(flatten)]
    pub extra: Extra,
}

/// The system a server runs, for its monogram in the sidebar.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct System {
    /// `deb`, `ubu`, `fed`, `rhel`, `alp`, `arch`, `bsd`, `mac`, `win`, or
    /// `?` when it could not be told.
    pub code: String,
    /// What to call it ("Debian 12"); empty when unknown.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    pub source: SystemSource,
    /// What it was told from: the server's banner, or os-release's
    /// `PRETTY_NAME`.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub evidence: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SystemSource {
    /// The banner the server sends before anything else.
    Banner,
    /// `/etc/os-release`, when the host asks for it to be read.
    OsRelease,
    /// Chosen by hand: connecting leaves it as it is.
    Manual,
}

/// A login with a name ("deploy in production"): a user, keys and an
/// agent that hosts and groups use by id. In inheritance it comes right
/// below what a host sets itself: defaults ← groups ← identity ← host.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Identity {
    pub label: String,
    /// Only the fields in [`IDENTITY_FIELDS`]. Like everything in the
    /// vault in phase 1, no secrets: keys go by path.
    #[serde(default, skip_serializing_if = "Settings::is_empty")]
    pub settings: Settings,
    /// Set when it came from another program's import.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub imported: Option<Imported>,
    #[serde(flatten)]
    pub extra: Extra,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Source {
    /// A `Host` alias of an imported `~/.ssh/config`.
    SshConfig { alias: String },
}

/// What another program called an item: the program (`termius`, `putty`,
/// `kitty`, `mobaxterm`, `tabby`, `securecrt`) and its own id for it, so
/// importing again leaves what came before alone. A field and not a
/// [`Source`] variant, which would break older versions' decoding.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Imported {
    pub from: String,
    pub id: String,
}

/// A saved tunnel: a port forward over the connection to a host.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct PortForward {
    pub label: String,
    /// The host whose connection it goes over.
    pub host: ItemId,
    pub kind: ForwardKind,
    /// The port listened on: on this machine (local, dynamic) or on the
    /// server (remote).
    pub listen_port: u16,
    /// Where to listen; `None` is loopback only. `0.0.0.0` (or `*`) lets
    /// the local network in.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub listen_address: Option<String>,
    /// Where connections go: seen from the server for a local forward,
    /// from this machine for a remote one. `None` for a dynamic forward.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dest_host: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dest_port: Option<u16>,
    /// Opened whenever a terminal or a browser connects to the host.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub autostart: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<Source>,
    /// Set when it came from another program's import.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub imported: Option<Imported>,
    #[serde(flatten)]
    pub extra: Extra,
}

/// A saved command to send to a terminal. What it writes between `{{` and
/// `}}` is asked for when it runs (or filled in from the session).
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Snippet {
    pub label: String,
    /// One or more lines, sent as if typed.
    pub script: String,
    /// Values offered for some of its variables.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub defaults: BTreeMap<String, String>,
    /// Leave it typed without pressing Enter.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub type_only: bool,
    /// Set when it came from another program's import.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub imported: Option<Imported>,
    #[serde(flatten)]
    pub extra: Extra,
}

/// Tabs and panes saved to open again together. What they connect to is
/// named, never what they showed.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Workspace {
    pub name: String,
    pub tabs: Vec<WorkspaceTab>,
    /// The tab in front, by index.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub active: u32,
    #[serde(flatten)]
    pub extra: Extra,
}

fn is_zero(n: &u32) -> bool {
    *n == 0
}

/// A tab of a workspace: terminals laid out in panes, or a file browser.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct WorkspaceTab {
    /// The name the user gave the tab.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// Terminals: one pane, or splits of them.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub panes: Option<PaneLayout>,
    /// Files: an SFTP browser on this target.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sftp: Option<Target>,
    #[serde(flatten)]
    pub extra: Extra,
}

/// A pane (`target`), a split in two (`split`), or a pane that asks what
/// to open (neither).
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct PaneLayout {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<Target>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub split: Option<Box<PaneSplit>>,
    /// Had the keyboard.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub active: bool,
    #[serde(flatten)]
    pub extra: Extra,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct PaneSplit {
    /// One above the other; otherwise side by side.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub vertical: bool,
    /// The first part's share of the space.
    pub ratio: f64,
    pub first: PaneLayout,
    pub second: PaneLayout,
    #[serde(flatten)]
    pub extra: Extra,
}

/// What a pane or tab connects to: a saved host, an address, or (neither)
/// a shell on this computer.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Target {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub host: Option<ItemId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub address: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub user: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub port: Option<u16>,
    #[serde(flatten)]
    pub extra: Extra,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ForwardKind {
    /// `-L`: a port here that reaches a service the server sees.
    Local,
    /// `-R`: a port on the server that reaches a service here.
    Remote,
    /// `-D`: a SOCKS5 proxy here whose connections leave from the server.
    Dynamic,
}

/// A trusted host key, in the terms of an OpenSSH `known_hosts` line.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct KnownHost {
    /// Comma-separated patterns as OpenSSH writes them: `host`,
    /// `[host]:port`, wildcards and `!` negation.
    pub hosts: String,
    /// Public key in OpenSSH format: `ssh-ed25519 AAAA…`.
    pub key: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub marker: Option<Marker>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub comment: Option<String>,
    /// Set when it came from another program's import.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub imported: Option<Imported>,
    #[serde(flatten)]
    pub extra: Extra,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Marker {
    /// The key is a CA that signs host certificates.
    CertAuthority,
    /// The key must be refused.
    Revoked,
}

impl KnownHost {
    /// The entry as a `known_hosts` line.
    pub fn to_line(&self) -> String {
        let mut line = String::new();
        match self.marker {
            Some(Marker::CertAuthority) => line.push_str("@cert-authority "),
            Some(Marker::Revoked) => line.push_str("@revoked "),
            None => {}
        }
        line.push_str(&self.hosts);
        line.push(' ');
        line.push_str(&self.key);
        if let Some(comment) = &self.comment {
            line.push(' ');
            line.push_str(comment);
        }
        line
    }
}

#[derive(Debug, thiserror::Error)]
pub enum DecodeError {
    #[error("invalid CBOR: {0}")]
    Cbor(String),
    #[error("unknown envelope version {0}")]
    Version(u64),
}

impl Body {
    pub fn to_cbor(&self) -> Vec<u8> {
        assert!(
            !matches!(self.data, Data::Unsupported),
            "an unsupported item is kept as stored, never encoded"
        );
        let mut out = Vec::new();
        ciborium::into_writer(self, &mut out).expect("writing to a Vec cannot fail");
        out
    }

    pub fn from_cbor(bytes: &[u8]) -> Result<Self, DecodeError> {
        ciborium::from_reader(bytes).map_err(|e| DecodeError::Cbor(e.to_string()))
    }
}

/// How an item's body is stored. Version 0 is the plaintext of phase 1;
/// phase 2 adds the encrypted envelope as version 1 in the same column, so
/// rows can move over one at a time.
pub mod envelope {
    use super::{Body, DecodeError};
    use ciborium::Value;
    use serde::{Deserialize, Serialize};

    #[derive(Serialize, Deserialize)]
    struct Plain {
        v: u64,
        body: Value,
    }

    /// Wraps the body without encrypting it (phase 1).
    pub fn seal_plain(body: &Body) -> Vec<u8> {
        let plain = Plain {
            v: 0,
            body: Value::Bytes(body.to_cbor()),
        };
        let mut out = Vec::new();
        ciborium::into_writer(&plain, &mut out).expect("writing to a Vec cannot fail");
        out
    }

    pub fn open(bytes: &[u8]) -> Result<Body, DecodeError> {
        let plain: Plain =
            ciborium::from_reader(bytes).map_err(|e| DecodeError::Cbor(e.to_string()))?;
        match (plain.v, plain.body) {
            (0, Value::Bytes(body)) => Body::from_cbor(&body),
            (0, _) => Err(DecodeError::Cbor("body is not a byte string".into())),
            (v, _) => Err(DecodeError::Version(v)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ciborium::Value;

    fn host() -> Body {
        Body {
            created: 1,
            modified: 2,
            data: Data::Host(Host {
                label: "web".into(),
                address: "web.example.com".into(),
                tags: vec!["prod".into()],
                settings: Settings {
                    port: Some(2222),
                    route: Some(Route::Jump(vec![Jump::Address {
                        host: "bastion".into(),
                        user: Some("ops".into()),
                        port: None,
                    }])),
                    ..Settings::default()
                },
                ..Host::default()
            }),
        }
    }

    #[test]
    fn a_body_round_trips_through_the_envelope() {
        let body = host();
        assert_eq!(envelope::open(&envelope::seal_plain(&body)).unwrap(), body);
    }

    #[test]
    fn the_encoding_is_a_flat_map_tagged_by_type() {
        let value: Value = ciborium::from_reader(&host().to_cbor()[..]).unwrap();
        let keys: Vec<String> = value
            .as_map()
            .unwrap()
            .iter()
            .map(|(k, _)| k.as_text().unwrap().to_owned())
            .collect();
        assert_eq!(
            keys,
            [
                "created", "modified", "type", "label", "address", "tags", "settings"
            ]
        );
    }

    #[test]
    fn tunnels_and_proxies_round_trip() {
        let tunnel = Body {
            created: 1,
            modified: 2,
            data: Data::PortForward(PortForward {
                label: "Postgres".into(),
                host: ItemId::new(),
                kind: ForwardKind::Local,
                listen_port: 5433,
                listen_address: None,
                dest_host: Some("10.0.4.21".into()),
                dest_port: Some(5432),
                autostart: true,
                source: None,
                imported: None,
                extra: Extra::new(),
            }),
        };
        assert_eq!(Body::from_cbor(&tunnel.to_cbor()).unwrap(), tunnel);
        let mut group = host();
        if let Data::Host(h) = &mut group.data {
            h.settings.proxy = Some(Proxy::Socks5(ProxyServer {
                host: "proxy.example".into(),
                port: 1080,
                user: Some("ana".into()),
            }));
        }
        assert_eq!(Body::from_cbor(&group.to_cbor()).unwrap(), group);
    }

    #[test]
    fn snippets_round_trip() {
        let snippet = Body {
            created: 1,
            modified: 2,
            data: Data::Snippet(Snippet {
                label: "Reiniciar".into(),
                script: "sudo systemctl restart {{servicio}}".into(),
                defaults: [("servicio".to_owned(), "nginx".to_owned())].into(),
                type_only: true,
                imported: Some(Imported {
                    from: "termius".into(),
                    id: "42".into(),
                }),
                extra: Extra::new(),
            }),
        };
        assert_eq!(Body::from_cbor(&snippet.to_cbor()).unwrap(), snippet);
    }

    #[test]
    fn workspaces_round_trip() {
        let pane = |target: Target| PaneLayout {
            target: Some(target),
            ..PaneLayout::default()
        };
        let host = ItemId::new();
        let mut extra = Extra::new();
        extra.insert("zoom".into(), Value::Integer(2.into()));
        let workspace = Body {
            created: 1,
            modified: 2,
            data: Data::Workspace(Workspace {
                name: "Producción".into(),
                tabs: vec![
                    WorkspaceTab {
                        title: Some("web".into()),
                        panes: Some(PaneLayout {
                            split: Some(Box::new(PaneSplit {
                                vertical: true,
                                ratio: 0.25,
                                first: pane(Target {
                                    host: Some(host),
                                    ..Target::default()
                                }),
                                second: PaneLayout {
                                    active: true,
                                    extra,
                                    ..pane(Target::default())
                                },
                                extra: Extra::new(),
                            })),
                            ..PaneLayout::default()
                        }),
                        ..WorkspaceTab::default()
                    },
                    WorkspaceTab {
                        sftp: Some(Target {
                            address: Some("10.0.0.5".into()),
                            user: Some("deploy".into()),
                            port: Some(2222),
                            ..Target::default()
                        }),
                        ..WorkspaceTab::default()
                    },
                ],
                active: 1,
                extra: Extra::new(),
            }),
        };
        assert_eq!(Body::from_cbor(&workspace.to_cbor()).unwrap(), workspace);
    }

    #[test]
    fn identities_and_their_use_round_trip() {
        let identity = Body {
            created: 1,
            modified: 2,
            data: Data::Identity(Identity {
                label: "deploy en producción".into(),
                settings: Settings {
                    user: Some("deploy".into()),
                    identity_files: Some(vec!["~/.ssh/deploy_ed25519".into()]),
                    agent: Some(Agent::System),
                    ..Settings::default()
                },
                imported: None,
                extra: Extra::new(),
            }),
        };
        assert_eq!(Body::from_cbor(&identity.to_cbor()).unwrap(), identity);
        for choice in [UseIdentity::None, UseIdentity::Id(ItemId::new())] {
            let mut body = host();
            if let Data::Host(h) = &mut body.data {
                h.settings.identity = Some(choice);
            }
            assert_eq!(Body::from_cbor(&body.to_cbor()).unwrap(), body);
        }
    }

    /// What a newer version wrote survives a read and a write by this one.
    #[test]
    fn unknown_fields_are_kept() {
        let mut value: Value = ciborium::from_reader(&host().to_cbor()[..]).unwrap();
        let map = value.as_map_mut().unwrap();
        map.push((Value::Text("color".into()), Value::Text("teal".into())));
        for (k, v) in map.iter_mut() {
            if k.as_text() == Some("settings") {
                v.as_map_mut()
                    .unwrap()
                    .push((Value::Text("x11".into()), Value::Bool(true)));
            }
        }
        let mut bytes = Vec::new();
        ciborium::into_writer(&value, &mut bytes).unwrap();

        let mut body = Body::from_cbor(&bytes).unwrap();
        let Data::Host(h) = &mut body.data else {
            panic!("not a host")
        };
        assert_eq!(h.extra["color"], Value::Text("teal".into()));
        h.label = "web-1".into();
        let again = Body::from_cbor(&body.to_cbor()).unwrap();
        let Data::Host(h) = again.data else {
            panic!("not a host")
        };
        assert_eq!(h.label, "web-1");
        assert_eq!(h.extra["color"], Value::Text("teal".into()));
        assert_eq!(h.settings.extra["x11"], Value::Bool(true));
    }

    #[test]
    fn an_unknown_type_decodes_as_unsupported() {
        let value = Value::Map(vec![
            (Value::Text("created".into()), Value::Integer(1.into())),
            (Value::Text("modified".into()), Value::Integer(1.into())),
            (
                Value::Text("type".into()),
                Value::Text("ai_provider".into()),
            ),
            (Value::Text("script".into()), Value::Text("uptime".into())),
        ]);
        let mut bytes = Vec::new();
        ciborium::into_writer(&value, &mut bytes).unwrap();
        assert_eq!(Body::from_cbor(&bytes).unwrap().data, Data::Unsupported);
    }

    #[test]
    fn known_host_lines() {
        let entry = KnownHost {
            hosts: "[git.example.com]:2222".into(),
            key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA".into(),
            marker: Some(Marker::CertAuthority),
            comment: Some("ops CA".into()),
            ..KnownHost::default()
        };
        assert_eq!(
            entry.to_line(),
            "@cert-authority [git.example.com]:2222 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA ops CA"
        );
    }
}
