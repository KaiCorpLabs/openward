//! The local vault: items in SQLite, an in-memory index, and settings
//! inheritance (ARCHITECTURE §4).
//!
//! Phase 1 stores item bodies unencrypted (envelope version 0), so the alpha
//! keeps nothing secret here: keys are referenced by path and passwords are
//! asked for on each connection. Phase 2 encrypts the same bodies into the
//! same column (ADR-004).
//!
//! Every item is loaded at open and served from memory; writes go to SQLite
//! first and then to the index.

mod inherit;
mod store;

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use openward_proto::{
    Body, Data, ForwardKind, Group, Host, IDENTITY_FIELDS, Identity, Item, ItemId, Jump, KnownHost,
    PortForward, Route, Settings, UseIdentity,
};

pub use inherit::{Effective, Origin, defaults};
pub use openward_proto as proto;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("storage: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("storage: {0}")]
    Io(#[from] std::io::Error),
    #[error("the vault was written by a newer version (format {0})")]
    NewerFormat(i64),
    #[error("item {0} not found")]
    NotFound(ItemId),
    #[error("item {id} is a {found}, not a {expected}")]
    WrongType {
        id: ItemId,
        expected: &'static str,
        found: &'static str,
    },
    #[error("item {id} changed since revision {expected} (now {current})")]
    Conflict {
        id: ItemId,
        expected: u64,
        current: u64,
    },
    #[error("a group cannot be inside itself")]
    Cycle,
    #[error("item {0} is used as a jump host by other hosts")]
    InUse(ItemId, Vec<ItemId>),
    #[error("{0}")]
    Invalid(&'static str),
}

pub type Result<T> = std::result::Result<T, Error>;

pub struct Vault {
    store: store::Store,
    items: HashMap<ItemId, Item>,
    /// Rows this version cannot read: a newer item type or a newer
    /// envelope. They stay in storage untouched.
    unreadable: usize,
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64)
}

impl Vault {
    /// Opens the vault at `path`, creating it if needed. On Unix a new file
    /// is readable by its owner only.
    pub fn open(path: &Path) -> Result<Self> {
        Self::load(store::Store::open(path)?)
    }

    pub fn open_in_memory() -> Result<Self> {
        Self::load(store::Store::open_in_memory()?)
    }

    fn load(store: store::Store) -> Result<Self> {
        let mut items = HashMap::new();
        let mut unreadable = 0;
        for (id, rev, envelope) in store.rows()? {
            match openward_proto::envelope::open(&envelope) {
                Ok(body) if body.data != Data::Unsupported => {
                    items.insert(id, Item { id, rev, body });
                }
                _ => unreadable += 1,
            }
        }
        Ok(Self {
            store,
            items,
            unreadable,
        })
    }

    pub fn id(&self) -> ItemId {
        self.store.vault_id
    }

    pub fn unreadable(&self) -> usize {
        self.unreadable
    }

    pub fn get(&self, id: ItemId) -> Option<&Item> {
        self.items.get(&id)
    }

    pub fn items(&self) -> impl Iterator<Item = &Item> {
        self.items.values()
    }

    pub fn host(&self, id: ItemId) -> Result<&Host> {
        match &self.item(id)?.body.data {
            Data::Host(h) => Ok(h),
            other => Err(wrong_type(id, "host", other)),
        }
    }

    pub fn group(&self, id: ItemId) -> Result<&Group> {
        match &self.item(id)?.body.data {
            Data::Group(g) => Ok(g),
            other => Err(wrong_type(id, "group", other)),
        }
    }

    /// Hosts sorted by label.
    pub fn hosts(&self) -> Vec<(ItemId, &Host)> {
        let mut hosts: Vec<_> = self
            .items
            .values()
            .filter_map(|i| match &i.body.data {
                Data::Host(h) => Some((i.id, h)),
                _ => None,
            })
            .collect();
        hosts.sort_by_cached_key(|(id, h)| (h.label.to_lowercase(), *id));
        hosts
    }

    /// Groups sorted by name.
    pub fn groups(&self) -> Vec<(ItemId, &Group)> {
        let mut groups: Vec<_> = self
            .items
            .values()
            .filter_map(|i| match &i.body.data {
                Data::Group(g) => Some((i.id, g)),
                _ => None,
            })
            .collect();
        groups.sort_by_cached_key(|(id, g)| (g.name.to_lowercase(), *id));
        groups
    }

    pub fn identity(&self, id: ItemId) -> Result<&Identity> {
        match &self.item(id)?.body.data {
            Data::Identity(i) => Ok(i),
            other => Err(wrong_type(id, "identity", other)),
        }
    }

    /// Identities sorted by label.
    pub fn identities(&self) -> Vec<(ItemId, &Identity)> {
        let mut identities: Vec<_> = self
            .items
            .values()
            .filter_map(|i| match &i.body.data {
                Data::Identity(identity) => Some((i.id, identity)),
                _ => None,
            })
            .collect();
        identities.sort_by_cached_key(|(id, i)| (i.label.to_lowercase(), *id));
        identities
    }

    /// Saved tunnels sorted by label.
    pub fn port_forward(&self, id: ItemId) -> Result<&PortForward> {
        match &self.item(id)?.body.data {
            Data::PortForward(f) => Ok(f),
            other => Err(wrong_type(id, "port_forward", other)),
        }
    }

    pub fn port_forwards(&self) -> Vec<(ItemId, &PortForward)> {
        let mut forwards: Vec<_> = self
            .items
            .values()
            .filter_map(|i| match &i.body.data {
                Data::PortForward(f) => Some((i.id, f)),
                _ => None,
            })
            .collect();
        forwards.sort_by_cached_key(|(id, f)| (f.label.to_lowercase(), *id));
        forwards
    }

    pub fn known_hosts(&self) -> Vec<(ItemId, &KnownHost)> {
        let mut known: Vec<_> = self
            .items
            .values()
            .filter_map(|i| match &i.body.data {
                Data::KnownHost(k) => Some((i.id, k)),
                _ => None,
            })
            .collect();
        known.sort_by_key(|(id, _)| *id);
        known
    }

    /// Adds an item and returns its id.
    pub fn create(&mut self, data: Data) -> Result<ItemId> {
        let id = ItemId::new();
        self.create_all(vec![(id, data)])?;
        Ok(id)
    }

    /// Adds several items in one transaction, with ids chosen by the caller
    /// so they can refer to each other (an import, say). All or nothing.
    pub fn create_all(&mut self, items: Vec<(ItemId, Data)>) -> Result<()> {
        let incoming: HashMap<ItemId, &Data> = items.iter().map(|(id, d)| (*id, d)).collect();
        if incoming.len() != items.len() || items.iter().any(|(id, _)| self.items.contains_key(id))
        {
            return Err(Error::Invalid("duplicate item id"));
        }
        for (id, data) in &items {
            self.validate(*id, data, &incoming)?;
        }
        let now = now_ms();
        let new: Vec<Item> = items
            .into_iter()
            .map(|(id, data)| Item {
                id,
                rev: 1,
                body: Body {
                    created: now,
                    modified: now,
                    data,
                },
            })
            .collect();
        self.store.write(&new, &[])?;
        for item in new {
            self.items.insert(item.id, item);
        }
        Ok(())
    }

    /// Replaces an item's data. `rev` is the revision the change was made
    /// from; if the item moved on since, nothing is written.
    pub fn update(&mut self, id: ItemId, rev: u64, data: Data) -> Result<u64> {
        let current = self.item(id)?;
        if current.rev != rev {
            return Err(Error::Conflict {
                id,
                expected: rev,
                current: current.rev,
            });
        }
        if current.body.data.kind() != data.kind() {
            return Err(wrong_type(id, current.body.data.kind(), &data));
        }
        self.validate(id, &data, &HashMap::new())?;
        let mut item = current.clone();
        item.rev += 1;
        item.body.modified = now_ms();
        item.body.data = data;
        self.store.write(std::slice::from_ref(&item), &[])?;
        let rev = item.rev;
        self.items.insert(id, item);
        Ok(rev)
    }

    /// Deletes an item. What was inside a deleted group moves up to that
    /// group's parent. A host that other hosts jump through cannot be
    /// deleted until they stop using it; its tunnels go with it. The hosts
    /// and groups that used a deleted identity go back to inheriting one.
    pub fn delete(&mut self, id: ItemId) -> Result<()> {
        let mut moved = Vec::new();
        let mut gone = vec![id];
        match &self.item(id)?.body.data {
            Data::Group(group) => {
                let parent = group.parent;
                let now = now_ms();
                for item in self.items.values() {
                    let mut item = item.clone();
                    let slot = match &mut item.body.data {
                        Data::Group(g) => &mut g.parent,
                        Data::Host(h) => &mut h.group,
                        _ => continue,
                    };
                    if *slot == Some(id) {
                        *slot = parent;
                        item.rev += 1;
                        item.body.modified = now;
                        moved.push(item);
                    }
                }
            }
            Data::Identity(_) => {
                let now = now_ms();
                for item in self.items.values() {
                    let mut item = item.clone();
                    let settings = match &mut item.body.data {
                        Data::Group(g) => &mut g.settings,
                        Data::Host(h) => &mut h.settings,
                        _ => continue,
                    };
                    if settings.identity == Some(UseIdentity::Id(id)) {
                        settings.identity = None;
                        item.rev += 1;
                        item.body.modified = now;
                        moved.push(item);
                    }
                }
            }
            Data::Host(_) => {
                let users = self.jump_users(id);
                if !users.is_empty() {
                    return Err(Error::InUse(id, users));
                }
                gone.extend(
                    self.port_forwards()
                        .into_iter()
                        .filter(|(_, f)| f.host == id)
                        .map(|(fid, _)| fid),
                );
            }
            _ => {}
        }
        self.store.write(&moved, &gone)?;
        for g in &gone {
            self.items.remove(g);
        }
        for item in moved {
            self.items.insert(item.id, item);
        }
        Ok(())
    }

    /// Hosts and groups whose route jumps through `host`.
    pub fn jump_users(&self, host: ItemId) -> Vec<ItemId> {
        let mut users: Vec<ItemId> = self
            .items
            .values()
            .filter(|i| {
                let settings = match &i.body.data {
                    Data::Host(h) => &h.settings,
                    Data::Group(g) => &g.settings,
                    _ => return false,
                };
                matches!(&settings.route, Some(Route::Jump(jumps))
                    if jumps.contains(&Jump::Host(host)))
            })
            .map(|i| i.id)
            .collect();
        users.sort();
        users
    }

    /// The settings a connection to `host` uses, and where each came from.
    pub fn effective(&self, host: ItemId) -> Result<Effective> {
        let h = self.host(host)?;
        self.resolve(h.group, &h.settings)
    }

    /// What a host in `group` (or at the top level) gets before its own
    /// settings, as an editor shows it: the defaults, the groups' and the
    /// identity's. `identity` is the editor's choice, if it makes one.
    pub fn inherited(
        &self,
        group: Option<ItemId>,
        identity: Option<UseIdentity>,
    ) -> Result<Effective> {
        let own = Settings {
            identity,
            ..Settings::default()
        };
        self.resolve(group, &own)
    }

    fn resolve(&self, group: Option<ItemId>, own: &Settings) -> Result<Effective> {
        let mut chain = Vec::new();
        let mut next = group;
        while let Some(gid) = next {
            if chain.iter().any(|(id, _)| *id == gid) {
                return Err(Error::Cycle);
            }
            let g = self.group(gid)?;
            chain.push((gid, &g.settings));
            next = g.parent;
        }
        // The nearest choice wins: the host's own, then the groups' from
        // the inside out. One deleted meanwhile (another device) is none.
        let chosen = own
            .identity
            .or_else(|| chain.iter().find_map(|(_, s)| s.identity));
        let identity = match chosen {
            Some(UseIdentity::Id(iid)) => self.identity(iid).ok().map(|i| (iid, &i.settings)),
            _ => None,
        };
        Ok(Effective::resolve(chain.into_iter().rev(), identity, own))
    }

    /// The identity `host` ends up with and who chose it (the host, or a
    /// group), with `changes` applied over what each item sets itself.
    fn identity_choice(
        &self,
        host: ItemId,
        changes: &HashMap<ItemId, Option<UseIdentity>>,
    ) -> (Option<ItemId>, Option<Origin>) {
        let own = |id: ItemId, settings: &Settings| match changes.get(&id) {
            Some(change) => *change,
            None => settings.identity,
        };
        let Ok(h) = self.host(host) else {
            return (None, None);
        };
        let mut found = own(host, &h.settings).map(|c| (c, Origin::Host));
        let mut next = h.group;
        let mut seen = HashSet::new();
        while found.is_none()
            && let Some(gid) = next.filter(|g| seen.insert(*g))
        {
            let Ok(g) = self.group(gid) else { break };
            found = own(gid, &g.settings).map(|c| (c, Origin::Group(gid)));
            next = g.parent;
        }
        match found {
            Some((UseIdentity::Id(iid), origin)) if self.identity(iid).is_ok() => {
                (Some(iid), Some(origin))
            }
            Some((_, origin)) => (None, Some(origin)),
            None => (None, None),
        }
    }

    /// Hosts and groups that choose `identity` themselves.
    pub fn identity_choosers(&self, identity: ItemId) -> Vec<ItemId> {
        let mut users: Vec<ItemId> = self
            .items
            .values()
            .filter(|i| {
                let settings = match &i.body.data {
                    Data::Host(h) => &h.settings,
                    Data::Group(g) => &g.settings,
                    _ => return false,
                };
                settings.identity == Some(UseIdentity::Id(identity))
            })
            .map(|i| i.id)
            .collect();
        users.sort();
        users
    }

    /// Hosts that end up with `identity`, sorted by label.
    pub fn identity_hosts(&self, identity: ItemId) -> Vec<ItemId> {
        self.hosts()
            .into_iter()
            .map(|(id, _)| id)
            .filter(|&id| self.identity_choice(id, &HashMap::new()).0 == Some(identity))
            .collect()
    }

    /// What making exactly `choosers` (hosts and groups) choose `identity`
    /// would do to each host: the identity it has now and the one it would
    /// have, and who would choose that one. Hosts sorted by label.
    pub fn identity_use_preview(
        &self,
        identity: ItemId,
        choosers: &HashSet<ItemId>,
    ) -> Vec<IdentityUse> {
        let changes = self.identity_changes(identity, choosers);
        self.hosts()
            .into_iter()
            .map(|(id, _)| {
                let (before, _) = self.identity_choice(id, &HashMap::new());
                let (after, by) = self.identity_choice(id, &changes);
                IdentityUse {
                    host: id,
                    before,
                    after,
                    by,
                }
            })
            .collect()
    }

    /// Makes exactly `choosers` (hosts and groups) choose `identity`: they
    /// choose it, and those that chose it and are not in `choosers` go
    /// back to inheriting one. One write; returns how many items changed.
    pub fn use_identity(&mut self, identity: ItemId, choosers: &HashSet<ItemId>) -> Result<usize> {
        self.identity(identity)?;
        for id in choosers {
            match self.item(*id)?.body.data {
                Data::Host(_) | Data::Group(_) => {}
                ref other => return Err(wrong_type(*id, "host", other)),
            }
        }
        let now = now_ms();
        let mut changed = Vec::new();
        for (id, choice) in self.identity_changes(identity, choosers) {
            let mut item = self.item(id)?.clone();
            match &mut item.body.data {
                Data::Host(h) => h.settings.identity = choice,
                Data::Group(g) => g.settings.identity = choice,
                _ => continue,
            }
            item.rev += 1;
            item.body.modified = now;
            changed.push(item);
        }
        self.store.write(&changed, &[])?;
        let count = changed.len();
        for item in changed {
            self.items.insert(item.id, item);
        }
        Ok(count)
    }

    /// The `identity` setting each item would get from [`Self::use_identity`].
    fn identity_changes(
        &self,
        identity: ItemId,
        choosers: &HashSet<ItemId>,
    ) -> HashMap<ItemId, Option<UseIdentity>> {
        let mut changes = HashMap::new();
        for item in self.items.values() {
            let current = match &item.body.data {
                Data::Host(h) => h.settings.identity,
                Data::Group(g) => g.settings.identity,
                _ => continue,
            };
            let chooses = current == Some(UseIdentity::Id(identity));
            match (choosers.contains(&item.id), chooses) {
                (true, false) => {
                    changes.insert(item.id, Some(UseIdentity::Id(identity)));
                }
                (false, true) => {
                    changes.insert(item.id, None);
                }
                _ => {}
            }
        }
        changes
    }

    /// Hosts matching every word of `query` (case-insensitive) in their
    /// label, address, user, tags or group names; sorted by label.
    pub fn search(&self, query: &str) -> Vec<ItemId> {
        let words: Vec<String> = query.split_whitespace().map(str::to_lowercase).collect();
        self.hosts()
            .into_iter()
            .filter(|(_, h)| {
                let mut text = vec![h.label.to_lowercase(), h.address.to_lowercase()];
                text.extend(h.settings.user.iter().map(|u| u.to_lowercase()));
                text.extend(h.tags.iter().map(|t| t.to_lowercase()));
                let mut next = h.group;
                let mut seen = HashSet::new();
                while let Some(gid) = next.filter(|g| seen.insert(*g)) {
                    let Ok(g) = self.group(gid) else { break };
                    text.push(g.name.to_lowercase());
                    next = g.parent;
                }
                words.iter().all(|w| text.iter().any(|t| t.contains(w)))
            })
            .map(|(id, _)| id)
            .collect()
    }

    /// Every tag in use and how many hosts carry it.
    pub fn tags(&self) -> BTreeMap<String, usize> {
        let mut tags = BTreeMap::new();
        for (_, h) in self.hosts() {
            for t in &h.tags {
                *tags.entry(t.clone()).or_insert(0) += 1;
            }
        }
        tags
    }

    /// The trusted keys as `known_hosts` text, for `openward-ssh`.
    pub fn known_hosts_text(&self) -> String {
        let mut text = String::new();
        for (_, k) in self.known_hosts() {
            text.push_str(&k.to_line());
            text.push('\n');
        }
        text
    }

    /// Trusts `key` (OpenSSH format) for `host:port`, replacing the keys of
    /// the same algorithm trusted for exactly that host before: what
    /// accepting a new key after TOFU, or a change, does.
    pub fn trust_host_key(&mut self, host: &str, port: u16, key: &str) -> Result<ItemId> {
        let hosts = host_spec(host, port);
        let algorithm = key.split_whitespace().next().unwrap_or_default();
        if algorithm.is_empty() || key.split_whitespace().count() < 2 {
            return Err(Error::Invalid("not an OpenSSH public key"));
        }
        let replaced: Vec<ItemId> = self
            .known_hosts()
            .into_iter()
            .filter(|(_, k)| {
                k.marker.is_none()
                    && k.hosts == hosts
                    && k.key.split_whitespace().next() == Some(algorithm)
            })
            .map(|(id, _)| id)
            .collect();
        let id = ItemId::new();
        let now = now_ms();
        let item = Item {
            id,
            rev: 1,
            body: Body {
                created: now,
                modified: now,
                data: Data::KnownHost(KnownHost {
                    hosts,
                    key: key.split_whitespace().take(2).collect::<Vec<_>>().join(" "),
                    ..KnownHost::default()
                }),
            },
        };
        self.store.write(std::slice::from_ref(&item), &replaced)?;
        for old in replaced {
            self.items.remove(&old);
        }
        self.items.insert(id, item);
        Ok(id)
    }

    fn item(&self, id: ItemId) -> Result<&Item> {
        self.items.get(&id).ok_or(Error::NotFound(id))
    }

    /// Checks `data` as the new content of `id`, with `incoming` items
    /// about to be created alongside it.
    fn validate(&self, id: ItemId, data: &Data, incoming: &HashMap<ItemId, &Data>) -> Result<()> {
        let kind_of = |other: ItemId| -> Option<&'static str> {
            incoming
                .get(&other)
                .map(|d| d.kind())
                .or_else(|| self.items.get(&other).map(|i| i.body.data.kind()))
        };
        let expect = |other: ItemId, expected: &'static str| match kind_of(other) {
            None => Err(Error::NotFound(other)),
            Some(found) if found != expected => Err(Error::WrongType {
                id: other,
                expected,
                found,
            }),
            Some(_) => Ok(()),
        };
        let check_identity = |settings: &Settings| -> Result<()> {
            match settings.identity {
                Some(UseIdentity::Id(identity)) => expect(identity, "identity"),
                _ => Ok(()),
            }
        };
        let check_route = |settings: &Settings| -> Result<()> {
            if let Some(Route::Jump(jumps)) = &settings.route {
                for jump in jumps {
                    if let Jump::Host(target) = jump {
                        if *target == id {
                            return Err(Error::Invalid("a host cannot jump through itself"));
                        }
                        expect(*target, "host")?;
                    }
                }
            }
            Ok(())
        };
        match data {
            Data::Host(h) => {
                if h.label.trim().is_empty() || h.address.trim().is_empty() {
                    return Err(Error::Invalid("a host needs a label and an address"));
                }
                if let Some(g) = h.group {
                    expect(g, "group")?;
                }
                check_identity(&h.settings)?;
                check_route(&h.settings)
            }
            Data::Group(g) => {
                if g.name.trim().is_empty() {
                    return Err(Error::Invalid("a group needs a name"));
                }
                // Walk up from the new parent; reaching `id` means a loop.
                let mut next = g.parent;
                let mut steps = 0;
                while let Some(parent) = next {
                    if parent == id || steps > incoming.len() + self.items.len() {
                        return Err(Error::Cycle);
                    }
                    expect(parent, "group")?;
                    next = match incoming.get(&parent) {
                        Some(Data::Group(p)) => p.parent,
                        _ => match self.items.get(&parent).map(|i| &i.body.data) {
                            Some(Data::Group(p)) => p.parent,
                            _ => None,
                        },
                    };
                    steps += 1;
                }
                check_identity(&g.settings)?;
                check_route(&g.settings)
            }
            Data::Identity(i) => {
                if i.label.trim().is_empty() {
                    return Err(Error::Invalid("an identity needs a name"));
                }
                let mut set = Vec::new();
                Settings::default().overlay(&i.settings, |f| set.push(f));
                if set.iter().any(|f| !IDENTITY_FIELDS.contains(f)) {
                    return Err(Error::Invalid(
                        "an identity sets only a user, keys, certificates and an agent",
                    ));
                }
                Ok(())
            }
            Data::KnownHost(k) => {
                if k.hosts.trim().is_empty() || k.key.split_whitespace().count() < 2 {
                    return Err(Error::Invalid("a known host needs patterns and a key"));
                }
                Ok(())
            }
            Data::PortForward(f) => {
                if f.label.trim().is_empty() {
                    return Err(Error::Invalid("a tunnel needs a name"));
                }
                if f.listen_port == 0 {
                    return Err(Error::Invalid("a tunnel needs a port to listen on"));
                }
                let dest = f.dest_host.as_deref().is_some_and(|h| !h.trim().is_empty())
                    && f.dest_port.is_some_and(|p| p > 0);
                match (f.kind, dest) {
                    (ForwardKind::Dynamic, _) => {}
                    (_, false) => return Err(Error::Invalid("a tunnel needs a destination")),
                    _ => {}
                }
                expect(f.host, "host")
            }
            Data::Unsupported => Err(Error::Invalid("unsupported items cannot be written")),
        }
    }
}

/// What [`Vault::identity_use_preview`] says of a host.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IdentityUse {
    pub host: ItemId,
    pub before: Option<ItemId>,
    pub after: Option<ItemId>,
    /// Who would choose `after`: the host, or one of its groups. `None`
    /// when nothing chooses.
    pub by: Option<Origin>,
}

fn wrong_type(id: ItemId, expected: &'static str, found: &Data) -> Error {
    Error::WrongType {
        id,
        expected,
        found: found.kind(),
    }
}

/// `host` or `[host]:port`, as OpenSSH writes host names.
fn host_spec(host: &str, port: u16) -> String {
    if port == 22 {
        host.to_owned()
    } else {
        format!("[{host}]:{port}")
    }
}

#[cfg(test)]
mod tests;
