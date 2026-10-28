//! Settings inheritance: defaults ← this device's defaults ← root group ←
//! … ← group ← identity ← host. The identity is the one the host or its
//! nearest group chooses.

use std::collections::BTreeMap;

use openward_proto::{Agent, Environment, HostKeyPolicy, ItemId, Route, Settings};

/// Where an effective setting came from, for the UI to show.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Origin {
    Default,
    Group(ItemId),
    Identity(ItemId),
    Host,
}

/// The settings a connection uses, complete, with the origin of each.
#[derive(Clone, Debug, PartialEq)]
pub struct Effective {
    pub settings: Settings,
    /// The identity in use, if any (and it exists).
    pub identity: Option<ItemId>,
    origins: BTreeMap<&'static str, Origin>,
}

/// What a host gets when nothing sets a field. `user`, `identity_files`,
/// `certificate_files` and `env` have no default: the connection falls back
/// to the local user name and the usual key files, as OpenSSH does.
pub fn defaults() -> Settings {
    Settings {
        port: Some(22),
        identities_only: Some(false),
        agent: Some(Agent::System),
        route: Some(Route::Direct),
        keepalive_secs: Some(10),
        connect_timeout_secs: Some(15),
        agent_forward: Some(false),
        persistent_session: Some(false),
        term: Some("xterm-256color".into()),
        host_key_policy: Some(HostKeyPolicy::Ask),
        legacy_host_keys: Some(false),
        environment: Some(Environment::None),
        read_os_release: Some(false),
        session_log: Some(false),
        ..Settings::default()
    }
}

impl Effective {
    /// Overlays this device's defaults, `groups` (root first), the
    /// identity and then the host on the defaults.
    pub(crate) fn resolve<'a>(
        device: &Settings,
        groups: impl Iterator<Item = (ItemId, &'a Settings)>,
        identity: Option<(ItemId, &Settings)>,
        host: &Settings,
    ) -> Self {
        let mut settings = Settings::default();
        let mut origins = BTreeMap::new();
        settings.overlay(&defaults(), |f| {
            origins.insert(f, Origin::Default);
        });
        settings.overlay(device, |f| {
            origins.insert(f, Origin::Default);
        });
        for (id, layer) in groups {
            settings.overlay(layer, |f| {
                origins.insert(f, Origin::Group(id));
            });
        }
        if let Some((id, layer)) = identity {
            settings.overlay(layer, |f| {
                origins.insert(f, Origin::Identity(id));
            });
        }
        settings.overlay(host, |f| {
            origins.insert(f, Origin::Host);
        });
        Self {
            settings,
            identity: identity.map(|(id, _)| id),
            origins,
        }
    }

    /// Where `field` (one of [`Settings::FIELDS`]) came from; `None` if
    /// nothing sets it, defaults included.
    pub fn origin(&self, field: &str) -> Option<Origin> {
        self.origins.get(field).copied()
    }
}
