//! Identities as Dart sees them: what each sets, its keys as this machine
//! has them, and who uses it.

use std::collections::{HashMap, HashSet};
use std::time::UNIX_EPOCH;

use flutter_rust_bridge::frb;
use openward_app::keys::{KeyInfo, KeyState, key_info};
use openward_app::vault::proto::{Agent, Data, Identity, ItemId, UseIdentity};
use openward_app::vault::{Origin, Vault};

use super::app::OpenWard;
use super::vault::VaultError;
use super::vault::{AgentKind, id};

/// What an identity sets. Its user and keys apply to the hosts that use
/// it unless a host sets its own.
#[frb(non_opaque)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IdentitySpec {
    pub label: String,
    pub user: Option<String>,
    /// Tried in this order.
    #[frb(default = "const []")]
    pub identity_files: Vec<String>,
    #[frb(default = "const []")]
    pub certificate_files: Vec<String>,
    /// Offer only these keys, not every key in the agent.
    #[frb(default = "false")]
    pub identities_only: bool,
    #[frb(default = "AgentKind.system")]
    pub agent: AgentKind,
    /// With [`AgentKind::Socket`].
    #[frb(default = "")]
    pub agent_socket: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyStateKind {
    Found,
    /// Not on this machine.
    Missing,
    /// Its `.pub` is missing: its type is unknown.
    NoPublicHalf,
    /// The path names `%h`, `%r`…: one file per host.
    PerHost,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CertView {
    pub path: String,
    /// `<key>-cert.pub`, found without being listed.
    pub implicit: bool,
    /// Milliseconds since the epoch; `None`: valid forever.
    pub valid_before_ms: Option<i64>,
    pub expired: bool,
    pub principals: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeyView {
    pub path: String,
    pub state: KeyStateKind,
    pub algorithm: Option<String>,
    pub fingerprint: Option<String>,
    pub comment: Option<String>,
    pub certificate: Option<CertView>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IdentityView {
    pub id: String,
    pub rev: u64,
    pub spec: IdentitySpec,
    pub keys: Vec<KeyView>,
    /// Groups and hosts that choose it themselves, by name.
    pub groups: Vec<String>,
    pub hosts: Vec<String>,
    /// Their ids, for the "use on…" dialog.
    pub chooser_ids: Vec<String>,
    /// Hosts that end up with it, through a group or themselves.
    pub host_count: u32,
}

/// A group or host in the "use on…" dialog, with what choosing the
/// identity for the ticked ones would do.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IdentityUseRow {
    pub id: String,
    pub is_group: bool,
    pub label: String,
    /// A host's group, or a group's parent.
    pub group_label: Option<String>,
    /// It is ticked: it chooses the identity itself.
    pub chooses: bool,
    /// Hosts inside a group, subgroups included.
    pub host_count: u32,
    /// The identity it has now (a host) or chooses now (a group), by name.
    pub now: Option<String>,
    /// `now` is this identity.
    pub now_is_this: bool,
    /// For a host, the group that gives it `now`.
    pub now_from_group: Option<String>,
    /// A group chooses "none" now.
    pub now_none: bool,
    /// For a host: it ends up with the identity.
    pub after: bool,
    /// For a host that ends up with it through a group: that group.
    pub after_from_group: Option<String>,
    /// For a host: the user it sets itself, which beats the identity's.
    pub own_user: Option<String>,
}

fn spec_of(i: &Identity) -> IdentitySpec {
    let s = &i.settings;
    let (agent, agent_socket) = match &s.agent {
        None | Some(Agent::System) => (AgentKind::System, String::new()),
        Some(Agent::Off) => (AgentKind::Off, String::new()),
        Some(Agent::Socket(p)) => (AgentKind::Socket, p.clone()),
    };
    IdentitySpec {
        label: i.label.clone(),
        user: s.user.clone(),
        identity_files: s.identity_files.clone().unwrap_or_default(),
        certificate_files: s.certificate_files.clone().unwrap_or_default(),
        identities_only: s.identities_only.unwrap_or(false),
        agent,
        agent_socket,
    }
}

/// Writes `spec` over `i`, keeping what OpenWard does not know.
fn apply(spec: &IdentitySpec, i: &mut Identity) {
    let list = |files: &[String]| {
        let files: Vec<String> = files
            .iter()
            .map(|f| f.trim().to_owned())
            .filter(|f| !f.is_empty())
            .collect();
        Some(files).filter(|f| !f.is_empty())
    };
    i.label = spec.label.trim().to_owned();
    let s = &mut i.settings;
    s.user = spec
        .user
        .as_deref()
        .map(str::trim)
        .filter(|u| !u.is_empty())
        .map(str::to_owned);
    s.identity_files = list(&spec.identity_files);
    s.certificate_files = list(&spec.certificate_files);
    s.identities_only = Some(spec.identities_only);
    s.agent = Some(match spec.agent {
        AgentKind::Off => Agent::Off,
        AgentKind::System => Agent::System,
        AgentKind::Socket => Agent::Socket(spec.agent_socket.trim().to_owned()),
    });
}

fn key_view(path: &str, k: KeyInfo) -> KeyView {
    KeyView {
        path: path.to_owned(),
        state: match k.state {
            KeyState::Found => KeyStateKind::Found,
            KeyState::Missing => KeyStateKind::Missing,
            KeyState::NoPublicHalf => KeyStateKind::NoPublicHalf,
            KeyState::PerHost => KeyStateKind::PerHost,
        },
        algorithm: k.algorithm,
        fingerprint: k.fingerprint,
        comment: k.comment,
        certificate: k.certificate.map(|c| CertView {
            path: c.path,
            implicit: c.implicit,
            valid_before_ms: c.valid_before.map(|t| {
                t.duration_since(UNIX_EPOCH)
                    .map_or(0, |d| d.as_millis() as i64)
            }),
            expired: c.expired,
            principals: c.principals,
        }),
    }
}

fn label_of(vault: &Vault, id: ItemId) -> String {
    match vault.get(id).map(|i| &i.body.data) {
        Some(Data::Host(h)) => h.label.clone(),
        Some(Data::Group(g)) => g.name.clone(),
        Some(Data::Identity(i)) => i.label.clone(),
        _ => String::new(),
    }
}

/// The hosts inside each group, subgroups included.
fn hosts_per_group(vault: &Vault) -> HashMap<ItemId, u32> {
    let mut counts = HashMap::new();
    for (_, h) in vault.hosts() {
        let mut next = h.group;
        let mut seen = HashSet::new();
        while let Some(gid) = next.filter(|g| seen.insert(*g)) {
            *counts.entry(gid).or_insert(0) += 1;
            next = vault.group(gid).ok().and_then(|g| g.parent);
        }
    }
    counts
}

impl OpenWard {
    fn identity_view(&self, vault: &Vault, iid: ItemId, i: &Identity) -> IdentityView {
        let spec = spec_of(i);
        let mut groups = Vec::new();
        let mut hosts = Vec::new();
        let choosers = vault.identity_choosers(iid);
        for &chooser in &choosers {
            match vault.get(chooser).map(|i| &i.body.data) {
                Some(Data::Group(g)) => groups.push(g.name.clone()),
                Some(Data::Host(h)) => hosts.push(h.label.clone()),
                _ => {}
            }
        }
        groups.sort_by_key(|g| g.to_lowercase());
        hosts.sort_by_key(|h| h.to_lowercase());
        IdentityView {
            id: iid.to_string(),
            rev: vault.get(iid).map_or(0, |i| i.rev),
            keys: Vec::new(),
            spec,
            groups,
            hosts,
            chooser_ids: choosers.iter().map(ItemId::to_string).collect(),
            host_count: vault.identity_hosts(iid).len() as u32,
        }
    }

    fn inspect_identity(&self, mut view: IdentityView) -> IdentityView {
        view.keys = view
            .spec
            .identity_files
            .iter()
            .map(|p| {
                key_view(
                    p,
                    key_info(self.app.local(), p, &view.spec.certificate_files),
                )
            })
            .collect();
        view
    }

    /// Every identity, by name.
    pub fn identities(&self) -> Vec<IdentityView> {
        let views: Vec<_> = {
            let vault = self.app.vault();
            vault
                .identities()
                .into_iter()
                .map(|(iid, i)| self.identity_view(&vault, iid, i))
                .collect()
        };
        views
            .into_iter()
            .map(|view| self.inspect_identity(view))
            .collect()
    }

    pub fn identity(&self, id: String) -> Result<IdentityView, VaultError> {
        let iid = super::vault::id(&id)?;
        let view = {
            let vault = self.app.vault();
            let i = vault.identity(iid)?;
            self.identity_view(&vault, iid, i)
        };
        Ok(self.inspect_identity(view))
    }

    pub fn create_identity(&self, spec: IdentitySpec) -> Result<String, VaultError> {
        let mut i = Identity::default();
        apply(&spec, &mut i);
        Ok(self.app.vault().create(Data::Identity(i))?.to_string())
    }

    /// Returns the new revision. Fails if it changed since `rev`.
    pub fn update_identity(
        &self,
        id: String,
        rev: u64,
        spec: IdentitySpec,
    ) -> Result<u64, VaultError> {
        let iid = super::vault::id(&id)?;
        let mut vault = self.app.vault();
        let mut i = vault.identity(iid)?.clone();
        apply(&spec, &mut i);
        Ok(vault.update(iid, rev, Data::Identity(i))?)
    }

    /// What the key at `path` is on this machine, and which of
    /// `certificate_files` (or `<key>-cert.pub`) goes with it.
    pub fn key_info(&self, path: String, certificate_files: Vec<String>) -> KeyView {
        key_view(&path, key_info(self.app.local(), &path, &certificate_files))
    }

    /// Groups (by name) and hosts (by label) for the "use on…" dialog, as
    /// they would be if exactly `choosers` chose `identity_id`.
    #[frb(sync)]
    pub fn identity_use(
        &self,
        identity_id: String,
        choosers: Vec<String>,
    ) -> Result<Vec<IdentityUseRow>, VaultError> {
        let iid = id(&identity_id)?;
        let choosers: HashSet<ItemId> = choosers.iter().map(|c| id(c)).collect::<Result<_, _>>()?;
        let vault = self.app.vault();
        vault.identity(iid)?;
        let counts = hosts_per_group(&vault);
        let group_label = |g: Option<ItemId>| g.map(|g| label_of(&vault, g));
        let mut rows = Vec::new();
        for (gid, g) in vault.groups() {
            let (now, now_none) = match g.settings.identity {
                Some(UseIdentity::Id(other)) => (Some(other), false),
                Some(UseIdentity::None) => (None, true),
                None => (None, false),
            };
            rows.push(IdentityUseRow {
                id: gid.to_string(),
                is_group: true,
                label: g.name.clone(),
                group_label: group_label(g.parent),
                chooses: choosers.contains(&gid),
                host_count: counts.get(&gid).copied().unwrap_or(0),
                now: now.map(|n| label_of(&vault, n)),
                now_is_this: now == Some(iid),
                now_from_group: None,
                now_none,
                after: false,
                after_from_group: None,
                own_user: None,
            });
        }
        let current: HashMap<ItemId, Option<Origin>> = vault
            .hosts()
            .into_iter()
            .map(|(hid, _)| {
                (
                    hid,
                    vault.effective(hid).ok().and_then(|e| e.origin("identity")),
                )
            })
            .collect();
        let preview = vault.identity_use_preview(iid, &choosers);
        for u in preview {
            let Ok(h) = vault.host(u.host) else { continue };
            let from = |o: Option<Origin>| match o {
                Some(Origin::Group(g)) => Some(label_of(&vault, g)),
                _ => None,
            };
            rows.push(IdentityUseRow {
                id: u.host.to_string(),
                is_group: false,
                label: h.label.clone(),
                group_label: group_label(h.group),
                chooses: choosers.contains(&u.host),
                host_count: 0,
                now: u.before.map(|b| label_of(&vault, b)),
                now_is_this: u.before == Some(iid),
                now_from_group: u.before.and(from(current.get(&u.host).copied().flatten())),
                now_none: false,
                after: u.after == Some(iid),
                after_from_group: (u.after == Some(iid)).then(|| from(u.by)).flatten(),
                own_user: h.settings.user.clone(),
            });
        }
        Ok(rows)
    }

    /// Makes exactly `choosers` (hosts and groups) choose `identity_id`;
    /// those that chose it and are left out go back to inheriting one.
    /// Returns how many changed.
    pub fn use_identity(
        &self,
        identity_id: String,
        choosers: Vec<String>,
    ) -> Result<u32, VaultError> {
        let iid = id(&identity_id)?;
        let choosers: HashSet<ItemId> = choosers.iter().map(|c| id(c)).collect::<Result<_, _>>()?;
        Ok(self.app.vault().use_identity(iid, &choosers)? as u32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_identity_round_trips_through_its_spec() {
        let spec = IdentitySpec {
            label: "deploy".into(),
            user: Some("deploy".into()),
            identity_files: vec!["~/.ssh/deploy".into(), "~/.ssh/old".into()],
            certificate_files: vec!["~/.ssh/deploy-cert.pub".into()],
            identities_only: true,
            agent: AgentKind::Socket,
            agent_socket: "~/.1password/agent.sock".into(),
        };
        let mut i = Identity::default();
        apply(&spec, &mut i);
        assert_eq!(spec_of(&i), spec);
        // Blank entries are dropped; no keys is no setting.
        let mut blank = spec.clone();
        blank.user = Some(" ".into());
        blank.identity_files = vec![" ".into()];
        apply(&blank, &mut i);
        assert_eq!(
            (i.settings.user.as_ref(), i.settings.identity_files.as_ref()),
            (None, None)
        );
    }
}
