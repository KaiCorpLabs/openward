//! Importing from other programs (Termius, PuTTY, MobaXterm, Tabby,
//! SecureCRT): what [`openward_import`] read, as vault items.
//!
//! Everything goes into one top-level group named after the program, with
//! the program's own folders inside. Items keep the program's id
//! (`imported`), so a second import leaves what came before alone, with
//! the user's changes, and brings only what is new.
//!
//! Keys the other program keeps inside itself never enter the vault: the
//! same key is looked for in `~/.ssh` (by its public half), or written
//! there when the user asks, readable only by them. Passwords are never
//! imported.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};

use openward_import::bundle::{self, Bundle, JumpRef, KeyRef, Program, Warning};
use openward_ssh::keyfile::{self, decode_secret_key};
use openward_ssh::russh::keys::HashAlg;
use openward_ssh::russh::keys::ssh_key::PublicKey;
use openward_vault::Vault;
use openward_vault::proto::{
    Data, Group, Host, Identity, Imported, ItemId, Jump, KnownHost, PortForward, Route, Settings,
    Snippet, UseIdentity,
};
use zeroize::Zeroizing;

use crate::keys::algorithm;
use crate::local::Local;

/// The top-level group's own `imported.id`.
const TOP: &str = "*";

/// What was read from a program, held between the preview and the import.
#[derive(Clone, Debug)]
pub struct Read {
    pub program: Program,
    pub bundle: Bundle,
    pub keys: Vec<KeyMatch>,
}

/// A key kept inside the other program, and what this computer has.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeyMatch {
    pub id: String,
    pub label: String,
    /// `Ed25519`, `RSA 3072`…, when the key could be read.
    pub algorithm: Option<String>,
    pub fingerprint: Option<String>,
    /// The same key in `~/.ssh`, as `~/.ssh/…`.
    pub found: Option<String>,
    /// Where it would be saved, as `~/.ssh/…`: a name not taken yet.
    pub save_as: String,
    /// Hosts and identities that use it.
    pub used_by: usize,
}

/// Reads what `bundle` refers to on this computer: its stored keys.
pub fn read(program: Program, bundle: Bundle, local: &Local) -> Read {
    let mine = ssh_dir_keys(&local.ssh_dir);
    let mut taken = HashSet::new();
    let keys = bundle
        .keys
        .iter()
        .map(|k| {
            let public = public_key(&k.private_key, k.passphrase.as_ref().map(|p| p.as_str()));
            let found = public.as_ref().and_then(|p| {
                mine.iter()
                    .find(|(_, q)| q.key_data() == p.key_data())
                    .map(|(path, _)| tilde(local, path))
            });
            let used_by = bundle
                .hosts
                .iter()
                .map(|h| &h.keys)
                .chain(bundle.identities.iter().map(|i| &i.keys))
                .chain(bundle.groups.iter().map(|g| &g.keys))
                .filter(|keys| keys.contains(&KeyRef::Stored(k.id.clone())))
                .count();
            KeyMatch {
                id: k.id.clone(),
                label: k.label.clone(),
                algorithm: public.as_ref().map(|p| algorithm(p.key_data())),
                fingerprint: public
                    .as_ref()
                    .map(|p| p.fingerprint(HashAlg::Sha256).to_string()),
                found,
                save_as: tilde(
                    local,
                    &free_name(&local.ssh_dir, program, &k.label, &mut taken),
                ),
                used_by,
            }
        })
        .collect();
    Read {
        program,
        bundle,
        keys,
    }
}

/// The public half of a key in any format the other program kept:
/// OpenSSH (readable without the passphrase), PEM, PKCS#8 or PuTTY's.
fn public_key(private: &str, passphrase: Option<&str>) -> Option<PublicKey> {
    if let Ok(k) = keyfile::from_openssh(private) {
        return Some(k.public_key().clone());
    }
    decode_secret_key(private, passphrase)
        .ok()
        .map(|k| k.public_key().clone())
}

/// The public keys in `~/.ssh`, by the private key's path: from each
/// `.pub`, or from OpenSSH private keys without one.
fn ssh_dir_keys(dir: &Path) -> Vec<(PathBuf, PublicKey)> {
    let mut out = Vec::new();
    let Ok(entries) = fs::read_dir(dir) else {
        return out;
    };
    let mut files: Vec<PathBuf> = entries.flatten().map(|e| e.path()).collect();
    files.sort();
    for f in &files {
        let small = fs::metadata(f).is_ok_and(|m| m.is_file() && m.len() < 64 * 1024);
        if !small {
            continue;
        }
        let name = f.file_name().unwrap_or_default().to_string_lossy();
        if let Some(stem) = name.strip_suffix(".pub") {
            if name.ends_with("-cert.pub") {
                continue;
            }
            if let Ok(k) = PublicKey::read_openssh_file(f) {
                out.push((f.with_file_name(stem), k));
            }
        } else if !files
            .iter()
            .any(|g| g.file_name() == Some(format!("{name}.pub").as_ref()))
            && let Ok(text) = fs::read_to_string(f)
            && text.starts_with("-----BEGIN OPENSSH PRIVATE KEY-----")
            && let Ok(k) = keyfile::from_openssh(&text)
        {
            out.push((f.clone(), k.public_key().clone()));
        }
    }
    out
}

/// `~/.ssh/<program>-<label>`, made safe for a file name and not taken.
fn free_name(dir: &Path, program: Program, label: &str, taken: &mut HashSet<PathBuf>) -> PathBuf {
    let safe: String = label
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect();
    let safe = safe.trim_matches('-');
    let base = if safe.is_empty() {
        program.id().to_owned()
    } else {
        format!("{}-{safe}", program.id())
    };
    let mut n = 1;
    loop {
        let name = if n == 1 {
            base.clone()
        } else {
            format!("{base}-{n}")
        };
        let path = dir.join(&name);
        let pub_path = dir.join(format!("{name}.pub"));
        if !path.exists() && !pub_path.exists() && taken.insert(path.clone()) {
            return path;
        }
        n += 1;
    }
}

fn tilde(local: &Local, path: &Path) -> String {
    match path.strip_prefix(&local.home) {
        Ok(rest) => format!("~/{}", rest.to_string_lossy().replace('\\', "/")),
        Err(_) => path.to_string_lossy().into_owned(),
    }
}

/// One group or host of the preview, in the program's order.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PreviewItem {
    pub id: String,
    pub is_group: bool,
    pub label: String,
    /// `user@address`, for hosts.
    pub address: String,
    pub parent: Option<String>,
    /// Imported before: it stays as it is.
    pub existing: bool,
    /// Why it cannot come (`telnet`…).
    pub unsupported: Option<String>,
    /// Labels it jumps through.
    pub jumps: Vec<String>,
    /// New tunnels it would bring.
    pub tunnels: usize,
    pub tags: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Preview {
    pub program: Program,
    /// The top-level group an earlier import made, by its name now.
    pub group: Option<String>,
    pub items: Vec<PreviewItem>,
    /// Named identities, and how many are new.
    pub identities: usize,
    pub new_identities: usize,
    pub new_tunnels: usize,
    pub new_snippets: usize,
    pub new_known_hosts: usize,
    pub keys: Vec<KeyMatch>,
    pub warnings: Vec<Warning>,
    pub passwords: usize,
    pub passphrases: usize,
}

/// Items of `program` already in the vault, by type and program id.
struct Existing {
    program: Program,
    groups: Vec<(String, ItemId)>,
    hosts: Vec<(String, ItemId)>,
    identities: Vec<(String, ItemId)>,
    snippets: Vec<String>,
    tunnels: HashSet<String>,
    known: HashSet<(String, String)>,
    known_ids: Vec<String>,
    top: Option<ItemId>,
}

impl Existing {
    fn new(vault: &Vault, program: Program) -> Self {
        let from = program.id();
        let mine =
            |i: &Option<Imported>| i.as_ref().filter(|i| i.from == from).map(|i| i.id.clone());
        let mut groups = Vec::new();
        let mut top = None;
        for (id, g) in vault.groups() {
            match mine(&g.imported) {
                Some(key) if key == TOP => top = Some(id),
                Some(key) => groups.push((key, id)),
                None => {}
            }
        }
        Self {
            program,
            groups,
            hosts: vault
                .hosts()
                .into_iter()
                .filter_map(|(id, h)| mine(&h.imported).map(|k| (k, id)))
                .collect(),
            identities: vault
                .identities()
                .into_iter()
                .filter_map(|(id, i)| mine(&i.imported).map(|k| (k, id)))
                .collect(),
            snippets: vault
                .snippets()
                .into_iter()
                .filter_map(|(_, s)| mine(&s.imported))
                .collect(),
            tunnels: vault
                .port_forwards()
                .into_iter()
                .filter_map(|(_, f)| mine(&f.imported))
                .collect(),
            known: vault
                .known_hosts()
                .into_iter()
                .map(|(_, k)| (k.hosts.clone(), k.key.clone()))
                .collect(),
            known_ids: vault
                .known_hosts()
                .into_iter()
                .filter_map(|(_, k)| mine(&k.imported))
                .collect(),
            top,
        }
    }

    fn find(&self, list: &[(String, ItemId)], id: &str) -> Option<ItemId> {
        list.iter()
            .find(|(k, _)| bundle::same_item(self.program, k, id))
            .map(|(_, v)| *v)
    }

    fn group(&self, id: &str) -> Option<ItemId> {
        self.find(&self.groups, id)
    }

    fn host(&self, id: &str) -> Option<ItemId> {
        self.find(&self.hosts, id)
    }

    fn identity(&self, id: &str) -> Option<ItemId> {
        self.find(&self.identities, id)
    }

    fn snippet(&self, id: &str) -> bool {
        self.snippets
            .iter()
            .any(|k| bundle::same_item(self.program, k, id))
    }

    fn known_host(&self, k: &bundle::KnownHost) -> bool {
        self.known.contains(&(k.hosts.clone(), k.key.clone()))
            || self
                .known_ids
                .iter()
                .any(|x| bundle::same_item(self.program, x, &k.id))
    }
}

/// A tunnel's `imported.id`: its host's, kind and port.
fn tunnel_id(t: &bundle::Tunnel) -> String {
    format!("{}#{:?}#{}", t.host, t.kind, t.listen_port)
}

pub fn preview(vault: &Vault, read: &Read) -> Preview {
    let b = &read.bundle;
    let have = Existing::new(vault, read.program);
    let labels: HashMap<&str, &str> = b
        .hosts
        .iter()
        .map(|h| (h.id.as_str(), h.label.as_str()))
        .collect();
    let mut items = Vec::new();
    // Groups first, parents before children, then hosts.
    for g in ordered_groups(&b.groups) {
        items.push(PreviewItem {
            id: g.id.clone(),
            is_group: true,
            label: g.name.clone(),
            address: String::new(),
            parent: g.parent.clone(),
            existing: have.group(&g.id).is_some(),
            unsupported: None,
            jumps: Vec::new(),
            tunnels: 0,
            tags: Vec::new(),
        });
    }
    for h in &b.hosts {
        let user = h.settings.user.clone().or_else(|| {
            h.identity
                .as_ref()
                .and_then(|i| b.identities.iter().find(|x| &x.id == i))
                .and_then(|i| i.user.clone())
        });
        items.push(PreviewItem {
            id: h.id.clone(),
            is_group: false,
            label: h.label.clone(),
            address: match user {
                Some(u) => format!("{u}@{}", h.address),
                None => h.address.clone(),
            },
            parent: h.group.clone(),
            existing: have.host(&h.id).is_some(),
            unsupported: h.unsupported.clone(),
            jumps: h
                .jumps
                .iter()
                .map(|j| match j {
                    JumpRef::Host(id) => labels.get(id.as_str()).copied().unwrap_or(id).to_owned(),
                    JumpRef::Address { host, .. } => host.clone(),
                })
                .collect(),
            tunnels: b
                .tunnels
                .iter()
                .filter(|t| t.host == h.id && !have.tunnels.contains(&tunnel_id(t)))
                .count(),
            tags: h.tags.clone(),
        });
    }
    Preview {
        program: read.program,
        group: have
            .top
            .and_then(|id| vault.group(id).ok())
            .map(|g| g.name.clone()),
        items,
        identities: b.identities.len(),
        new_identities: b
            .identities
            .iter()
            .filter(|i| have.identity(&i.id).is_none())
            .count(),
        new_tunnels: b
            .tunnels
            .iter()
            .filter(|t| !have.tunnels.contains(&tunnel_id(t)))
            .count(),
        new_snippets: b.snippets.iter().filter(|s| !have.snippet(&s.id)).count(),
        new_known_hosts: b.known_hosts.iter().filter(|k| !have.known_host(k)).count(),
        keys: read.keys.clone(),
        warnings: b.warnings.clone(),
        passwords: b.passwords,
        passphrases: b.passphrases,
    }
}

/// Parents before their children, otherwise in the program's order.
fn ordered_groups(groups: &[bundle::Group]) -> Vec<&bundle::Group> {
    let mut out: Vec<&bundle::Group> = Vec::new();
    let mut placed: HashSet<&str> = HashSet::new();
    let ids: HashSet<&str> = groups.iter().map(|g| g.id.as_str()).collect();
    while out.len() < groups.len() {
        let before = out.len();
        for g in groups {
            if placed.contains(g.id.as_str()) {
                continue;
            }
            let ready = match &g.parent {
                Some(p) => placed.contains(p.as_str()) || !ids.contains(p.as_str()),
                None => true,
            };
            if ready {
                placed.insert(&g.id);
                out.push(g);
            }
        }
        if out.len() == before {
            // A cycle: the rest as they come.
            out.extend(groups.iter().filter(|g| !placed.contains(g.id.as_str())));
            break;
        }
    }
    out
}

/// What the user picked in the preview.
#[derive(Clone, Debug, Default)]
pub struct Choice {
    /// Hosts to bring, by the program's id; the hosts they jump through
    /// come along.
    pub hosts: Vec<String>,
    /// The top-level group's name, if it is created now.
    pub group_name: String,
    /// Stored keys to write to `~/.ssh`, by id.
    pub save_keys: Vec<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Report {
    pub group: Option<ItemId>,
    pub hosts: usize,
    pub groups: usize,
    pub identities: usize,
    pub tunnels: usize,
    pub snippets: usize,
    pub known_hosts: usize,
    /// Imported before, left as they were.
    pub skipped: usize,
    /// Keys written to `~/.ssh`, as `~/.ssh/…`.
    pub saved_keys: Vec<String>,
    /// Identities and hosts left without the key they had, by label.
    pub without_key: Vec<String>,
    pub warnings: Vec<Warning>,
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Vault(#[from] openward_vault::Error),
    #[error("saving a key to {path}: {error}")]
    Key { path: String, error: std::io::Error },
}

pub fn apply(
    vault: &mut Vault,
    local: &Local,
    read: &Read,
    choice: &Choice,
) -> Result<Report, Error> {
    let b = &read.bundle;
    let program = read.program;
    let have = Existing::new(vault, program);
    let imported = |id: &str| {
        Some(Imported {
            from: program.id().to_owned(),
            id: id.to_owned(),
            extra: Default::default(),
        })
    };
    let mut report = Report {
        warnings: b.warnings.clone(),
        ..Report::default()
    };

    // The hosts picked, and the ones they jump through, all the way.
    let by_id: HashMap<&str, &bundle::Host> = b.hosts.iter().map(|h| (h.id.as_str(), h)).collect();
    let mut chosen: BTreeSet<&str> = choice
        .hosts
        .iter()
        .filter_map(|id| by_id.get(id.as_str()).map(|h| h.id.as_str()))
        .collect();
    let mut queue: Vec<&str> = chosen.iter().copied().collect();
    while let Some(id) = queue.pop() {
        for j in &by_id[id].jumps {
            if let JumpRef::Host(t) = j
                && let Some(h) = by_id.get(t.as_str())
                && chosen.insert(h.id.as_str())
            {
                queue.push(h.id.as_str());
            }
        }
    }
    chosen.retain(|id| by_id[id].unsupported.is_none());

    // Keys: the same in ~/.ssh, or saved there if asked. Written aside
    // now and put in place once the vault has what uses them: a vault that
    // fails leaves no keys behind.
    let mut key_paths: HashMap<&str, String> = HashMap::new();
    let mut staged = Vec::new();
    for m in &read.keys {
        if let Some(found) = &m.found {
            key_paths.insert(&m.id, found.clone());
        } else if choice.save_keys.contains(&m.id)
            && let Some(stored) = b.keys.iter().find(|k| k.id == m.id)
        {
            let key = stage_key(local, &m.save_as, stored)?;
            key_paths.insert(&m.id, key.shown.clone());
            staged.push(key);
        }
    }
    let files = |keys: &[KeyRef], label: &str, without: &mut Vec<String>| -> Vec<String> {
        let mut out = Vec::new();
        for k in keys {
            match k {
                KeyRef::Path(p) => out.push(p.clone()),
                KeyRef::Stored(id) => match key_paths.get(id.as_str()) {
                    Some(p) => out.push(p.clone()),
                    None => without.push(label.to_owned()),
                },
            }
        }
        out
    };

    let mut items: Vec<(ItemId, Data)> = Vec::new();
    // The top-level group, reused when an earlier import made it.
    let top = match have.top {
        Some(id) => id,
        None => {
            let id = ItemId::new();
            let name = choice.group_name.trim();
            items.push((
                id,
                Data::Group(Group {
                    name: if name.is_empty() {
                        program.name().to_owned()
                    } else {
                        name.to_owned()
                    },
                    imported: imported(TOP),
                    ..Group::default()
                }),
            ));
            report.groups += 1;
            id
        }
    };
    report.group = Some(top);

    // Identities the chosen hosts (or their groups) use.
    let groups_of: HashMap<&str, &bundle::Group> =
        b.groups.iter().map(|g| (g.id.as_str(), g)).collect();
    let mut needed_groups: BTreeSet<&str> = BTreeSet::new();
    for id in &chosen {
        let mut g = by_id[id].group.as_deref();
        while let Some(gid) = g {
            if !needed_groups.insert(gid) {
                break;
            }
            g = groups_of.get(gid).and_then(|x| x.parent.as_deref());
        }
    }
    let mut identity_ids: HashMap<&str, ItemId> = HashMap::new();
    let wanted: BTreeSet<&str> = chosen
        .iter()
        .filter_map(|id| by_id[id].identity.as_deref())
        .chain(
            needed_groups
                .iter()
                .filter_map(|g| groups_of.get(g).and_then(|g| g.identity.as_deref())),
        )
        .collect();
    for i in b
        .identities
        .iter()
        .filter(|i| wanted.contains(i.id.as_str()))
    {
        if let Some(old) = have.identity(&i.id) {
            identity_ids.insert(&i.id, old);
            continue;
        }
        let id = ItemId::new();
        identity_ids.insert(&i.id, id);
        let keys = files(&i.keys, &i.label, &mut report.without_key);
        items.push((
            id,
            Data::Identity(Identity {
                label: i.label.clone(),
                settings: Settings {
                    user: i.user.clone(),
                    identity_files: (!keys.is_empty()).then_some(keys),
                    ..Settings::default()
                },
                imported: imported(&i.id),
                ..Identity::default()
            }),
        ));
        report.identities += 1;
    }
    let use_identity = |id: &Option<String>| {
        id.as_deref()
            .and_then(|i| identity_ids.get(i))
            .map(|i| UseIdentity::Id(*i))
    };

    // Groups, parents first, inside the top group.
    let mut group_ids: HashMap<&str, ItemId> = HashMap::new();
    for g in ordered_groups(&b.groups) {
        if !needed_groups.contains(g.id.as_str()) {
            continue;
        }
        if let Some(old) = have.group(&g.id) {
            group_ids.insert(&g.id, old);
            continue;
        }
        let id = ItemId::new();
        group_ids.insert(&g.id, id);
        let mut settings = g.settings.clone();
        let keys = files(&g.keys, &g.name, &mut report.without_key);
        if !keys.is_empty() {
            settings.identity_files = Some(keys);
        }
        settings.identity = use_identity(&g.identity);
        items.push((
            id,
            Data::Group(Group {
                name: g.name.clone(),
                parent: Some(
                    g.parent
                        .as_deref()
                        .and_then(|p| group_ids.get(p).copied())
                        .unwrap_or(top),
                ),
                settings,
                imported: imported(&g.id),
                ..Group::default()
            }),
        ));
        report.groups += 1;
    }

    // Hosts: new ids first, so jumps can point at any of them.
    let mut host_ids: HashMap<&str, ItemId> = HashMap::new();
    for h in &b.hosts {
        if let Some(old) = have.host(&h.id) {
            host_ids.insert(&h.id, old);
        } else if chosen.contains(h.id.as_str()) {
            host_ids.insert(&h.id, ItemId::new());
        }
    }
    for h in b.hosts.iter().filter(|h| chosen.contains(h.id.as_str())) {
        if have.host(&h.id).is_some() {
            report.skipped += 1;
            continue;
        }
        let mut settings = h.settings.clone();
        let keys = files(&h.keys, &h.label, &mut report.without_key);
        if !keys.is_empty() {
            settings.identity_files = Some(keys);
        }
        settings.identity = use_identity(&h.identity);
        if !h.jumps.is_empty() && !matches!(settings.route, Some(Route::Command(_))) {
            settings.route = Some(Route::Jump(
                h.jumps
                    .iter()
                    .map(|j| match j {
                        JumpRef::Host(t) => match host_ids.get(t.as_str()) {
                            Some(id) => Jump::Host(*id),
                            None => Jump::Address {
                                host: by_id
                                    .get(t.as_str())
                                    .map_or(t.clone(), |x| x.address.clone()),
                                user: None,
                                port: None,
                                extra: Default::default(),
                            },
                        },
                        JumpRef::Address { host, user, port } => Jump::Address {
                            host: host.clone(),
                            user: user.clone(),
                            port: *port,
                            extra: Default::default(),
                        },
                    })
                    .collect(),
            ));
        }
        items.push((
            host_ids[h.id.as_str()],
            Data::Host(Host {
                label: h.label.clone(),
                address: h.address.clone(),
                group: Some(
                    h.group
                        .as_deref()
                        .and_then(|g| group_ids.get(g).copied())
                        .unwrap_or(top),
                ),
                tags: h.tags.clone(),
                settings,
                notes: h.notes.clone(),
                imported: imported(&h.id),
                ..Default::default()
            }),
        ));
        report.hosts += 1;
    }

    // Tunnels of the hosts brought now or before, once each.
    for t in &b.tunnels {
        let key = tunnel_id(t);
        let Some(host) = host_ids.get(t.host.as_str()) else {
            continue;
        };
        if have.tunnels.contains(&key) || !chosen.contains(t.host.as_str()) {
            continue;
        }
        let mut t = t.clone();
        let host_name = by_id
            .get(t.host.as_str())
            .map_or(t.host.as_str(), |h| h.label.as_str())
            .to_owned();
        for warning in t.hold_back(&host_name) {
            if !report.warnings.contains(&warning) {
                report.warnings.push(warning);
            }
        }
        let label = if t.label.is_empty() {
            format!("{:?} {}", t.kind, t.listen_port)
        } else {
            t.label.clone()
        };
        items.push((
            ItemId::new(),
            Data::PortForward(PortForward {
                label,
                host: *host,
                kind: t.kind,
                listen_port: t.listen_port,
                listen_address: t.listen_address.clone(),
                dest_host: t.dest_host.clone(),
                dest_port: t.dest_port,
                autostart: t.autostart,
                source: None,
                imported: imported(&key),
                extra: Default::default(),
            }),
        ));
        report.tunnels += 1;
    }

    for s in b.snippets.iter().filter(|s| !have.snippet(&s.id)) {
        items.push((
            ItemId::new(),
            Data::Snippet(Snippet {
                label: s.label.clone(),
                script: s.script.clone(),
                imported: imported(&s.id),
                ..Snippet::default()
            }),
        ));
        report.snippets += 1;
    }
    for k in b.known_hosts.iter().filter(|k| !have.known_host(k)) {
        // The key's own comment (`… user@host`) and line breaks go; what
        // is still not one known_hosts line is left out.
        let mut key = k.key.split_whitespace();
        let known = KnownHost {
            hosts: k.hosts.trim().to_owned(),
            key: [key.next(), key.next()]
                .into_iter()
                .flatten()
                .collect::<Vec<_>>()
                .join(" "),
            marker: k.marker,
            comment: k
                .comment
                .as_deref()
                .map(|c| {
                    c.split(char::is_control)
                        .collect::<Vec<_>>()
                        .join(" ")
                        .trim()
                        .to_owned()
                })
                .filter(|c| !c.is_empty()),
            imported: imported(&k.id),
            ..KnownHost::default()
        };
        if !known.is_well_formed() {
            continue;
        }
        items.push((ItemId::new(), Data::KnownHost(known)));
        report.known_hosts += 1;
    }
    report.without_key.sort();
    report.without_key.dedup();
    if !items.is_empty() {
        vault.create_all(items)?;
    }
    for key in staged {
        report.saved_keys.push(key.place()?);
    }
    Ok(report)
}

/// A stored key written to `~/.ssh` as the other program kept it,
/// readable only by the user, with its `.pub` when it can be read. Until
/// [`place`](Self::place)d it is under a hidden temporary name, synced to
/// disk; dropped before that, it is deleted.
struct StagedKey {
    shown: String,
    files: Vec<(PathBuf, PathBuf)>,
}

fn stage_key(local: &Local, shown: &str, key: &bundle::StoredKey) -> Result<StagedKey, Error> {
    let path = match shown.strip_prefix("~/") {
        Some(rest) => local.home.join(rest),
        None => PathBuf::from(shown),
    };
    let fail = |error| Error::Key {
        path: shown.to_owned(),
        error,
    };
    if let Some(dir) = path.parent() {
        create_private_dir(dir).map_err(fail)?;
    }
    let mut staged = StagedKey {
        shown: shown.to_owned(),
        files: Vec::new(),
    };
    let mut text = Zeroizing::new(key.private_key.replace("\r\n", "\n"));
    if !text.ends_with('\n') {
        text.push('\n');
    }
    let tmp = write_aside(&path, text.as_bytes(), 0o600).map_err(fail)?;
    staged.files.push((tmp, path.clone()));
    if let Some(public) = public_key(
        &key.private_key,
        key.passphrase.as_ref().map(|p| p.as_str()),
    ) && let Ok(line) = crate::keychain::public_key_line(&public)
    {
        let mut pub_path = path.into_os_string();
        pub_path.push(".pub");
        let pub_path = PathBuf::from(pub_path);
        // A missing `.pub` only means the type is shown later as unknown.
        if let Ok(tmp) = write_aside(&pub_path, format!("{line}\n").as_bytes(), 0o644) {
            staged.files.push((tmp, pub_path));
        }
    }
    Ok(staged)
}

impl StagedKey {
    /// Gives the files their names, never replacing one: the key as
    /// `~/.ssh/…`.
    fn place(mut self) -> Result<String, Error> {
        let files = std::mem::take(&mut self.files);
        for (i, (tmp, path)) in files.iter().enumerate() {
            let placed = fs::hard_link(tmp, path).and_then(|()| fs::remove_file(tmp));
            if let Err(error) = placed {
                for (tmp, _) in &files[i..] {
                    let _ = fs::remove_file(tmp);
                }
                // Only the key itself counts; its `.pub` is a nicety.
                if i == 0 {
                    return Err(Error::Key {
                        path: self.shown.clone(),
                        error,
                    });
                }
                break;
            }
        }
        if let Some(dir) = files.first().and_then(|(_, p)| p.parent()) {
            sync_dir(dir);
        }
        Ok(std::mem::take(&mut self.shown))
    }
}

impl Drop for StagedKey {
    fn drop(&mut self) {
        for (tmp, _) in &self.files {
            let _ = fs::remove_file(tmp);
        }
    }
}

fn create_private_dir(dir: &Path) -> std::io::Result<()> {
    if dir.is_dir() {
        return Ok(());
    }
    let mut b = fs::DirBuilder::new();
    b.recursive(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        b.mode(0o700);
    }
    b.create(dir)
}

/// Writes `bytes` next to `path`, under a hidden name of its own created
/// with `mode`, and syncs it; the name it got.
fn write_aside(path: &Path, bytes: &[u8], mode: u32) -> std::io::Result<PathBuf> {
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    let tmp = path.with_file_name(format!(".{name}.openward-{}", std::process::id()));
    let mut o = fs::OpenOptions::new();
    o.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        o.mode(mode);
    }
    #[cfg(not(unix))]
    let _ = mode;
    let mut file = o.open(&tmp)?;
    let written = file.write_all(bytes).and_then(|()| file.sync_all());
    if let Err(e) = written {
        drop(file);
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    Ok(tmp)
}

/// Makes a new name in `dir` last through a power cut, where the system
/// lets a folder be synced.
fn sync_dir(dir: &Path) {
    #[cfg(unix)]
    if let Ok(d) = fs::File::open(dir) {
        let _ = d.sync_all();
    }
    #[cfg(not(unix))]
    let _ = dir;
}

#[cfg(test)]
mod tests {
    use super::*;
    use openward_import::bundle::{StoredKey, Tunnel};
    use openward_ssh::russh::keys::ssh_key::private::Ed25519Keypair;
    use openward_ssh::russh::keys::ssh_key::{LineEnding, PrivateKey};
    use openward_vault::proto::ForwardKind;

    fn local(dir: &Path) -> Local {
        Local {
            home: dir.to_owned(),
            user: "ana".into(),
            ssh_dir: dir.join(".ssh"),
            system_ssh_dir: dir.join("etc-ssh"),
            agent: None,
        }
    }

    /// A real key, made from a fixed seed: no private key in the sources.
    fn key(seed: u8) -> PrivateKey {
        PrivateKey::from(Ed25519Keypair::from_seed(&[seed; 32]))
    }

    fn bundle() -> Bundle {
        let k = |id: &str| KeyRef::Stored(id.into());
        Bundle {
            groups: vec![
                bundle::Group {
                    id: "g1".into(),
                    name: "Producción".into(),
                    identity: Some("i1".into()),
                    ..Default::default()
                },
                bundle::Group {
                    id: "g2".into(),
                    name: "Web".into(),
                    parent: Some("g1".into()),
                    ..Default::default()
                },
            ],
            hosts: vec![
                bundle::Host {
                    id: "h1".into(),
                    label: "bastion".into(),
                    address: "bastion.example.com".into(),
                    keys: vec![k("k2")],
                    ..Default::default()
                },
                bundle::Host {
                    id: "h2".into(),
                    label: "web-1".into(),
                    address: "web-1.example.com".into(),
                    group: Some("g2".into()),
                    jumps: vec![JumpRef::Host("h1".into())],
                    ..Default::default()
                },
                bundle::Host {
                    id: "h3".into(),
                    label: "switch".into(),
                    address: "10.0.9.2".into(),
                    unsupported: Some("telnet".into()),
                    ..Default::default()
                },
            ],
            identities: vec![bundle::Identity {
                id: "i1".into(),
                label: "deploy".into(),
                user: Some("deploy".into()),
                keys: vec![k("k1")],
            }],
            keys: vec![
                StoredKey {
                    id: "k1".into(),
                    label: "deploy".into(),
                    private_key: key(1)
                        .to_openssh(LineEnding::LF)
                        .unwrap()
                        .to_string()
                        .into(),
                    passphrase: None,
                },
                StoredKey {
                    id: "k2".into(),
                    label: "ci runner".into(),
                    private_key: key(2)
                        .to_openssh(LineEnding::LF)
                        .unwrap()
                        .to_string()
                        .into(),
                    passphrase: None,
                },
            ],
            tunnels: vec![Tunnel {
                host: "h2".into(),
                label: "Postgres".into(),
                kind: ForwardKind::Local,
                listen_address: None,
                listen_port: 5433,
                dest_host: Some("10.0.4.21".into()),
                dest_port: Some(5432),
                autostart: false,
            }],
            snippets: vec![bundle::Snippet {
                id: "s1".into(),
                label: "Reiniciar".into(),
                script: "sudo systemctl restart nginx".into(),
            }],
            known_hosts: vec![bundle::KnownHost {
                id: "kh1".into(),
                hosts: "bastion.example.com".into(),
                key: key(3).public_key().to_openssh().unwrap(),
                marker: None,
                comment: None,
            }],
            ..Default::default()
        }
    }

    #[test]
    fn keys_found_in_ssh_saved_on_request_and_a_second_import() {
        let dir = tempfile::tempdir().unwrap();
        let local = local(dir.path());
        fs::create_dir(&local.ssh_dir).unwrap();
        // The deploy key is already in ~/.ssh, under another name.
        fs::write(
            local.ssh_dir.join("id_deploy.pub"),
            key(1).public_key().to_openssh().unwrap(),
        )
        .unwrap();
        fs::write(local.ssh_dir.join("id_deploy"), "private").unwrap();
        let read = read(Program::Termius, bundle(), &local);
        assert_eq!(read.keys[0].found.as_deref(), Some("~/.ssh/id_deploy"));
        assert_eq!(read.keys[0].algorithm.as_deref(), Some("Ed25519"));
        assert_eq!(read.keys[1].found, None);
        assert_eq!(read.keys[1].save_as, "~/.ssh/termius-ci-runner");
        assert_eq!(read.keys[1].used_by, 1);

        let mut vault = Vault::open_in_memory().unwrap();
        let p = preview(&vault, &read);
        let labels: Vec<(&str, bool)> = p
            .items
            .iter()
            .map(|i| (i.label.as_str(), i.is_group))
            .collect();
        assert_eq!(
            labels,
            [
                ("Producción", true),
                ("Web", true),
                ("bastion", false),
                ("web-1", false),
                ("switch", false)
            ]
        );
        assert_eq!(p.items[3].jumps, ["bastion"]);
        assert_eq!(
            (p.new_tunnels, p.new_snippets, p.new_known_hosts),
            (1, 1, 1)
        );

        // Only web-1 picked: bastion comes along, its key saved.
        let choice = Choice {
            hosts: vec!["h2".into(), "h3".into()],
            group_name: "Termius".into(),
            save_keys: vec!["k2".into()],
        };
        let r = apply(&mut vault, &local, &read, &choice).unwrap();
        assert_eq!((r.hosts, r.groups, r.identities), (2, 3, 1));
        assert_eq!((r.tunnels, r.snippets, r.known_hosts), (1, 1, 1));
        assert_eq!(r.saved_keys, ["~/.ssh/termius-ci-runner"]);
        assert!(r.without_key.is_empty());
        let saved = local.ssh_dir.join("termius-ci-runner");
        assert!(
            fs::read_to_string(&saved)
                .unwrap()
                .starts_with("-----BEGIN OPENSSH PRIVATE KEY-----")
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&saved).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
        assert!(local.ssh_dir.join("termius-ci-runner.pub").is_file());

        let hosts = vault.hosts();
        let web = hosts.iter().find(|(_, h)| h.label == "web-1").unwrap().1;
        let bastion = hosts.iter().find(|(_, h)| h.label == "bastion").unwrap();
        assert_eq!(
            web.settings.route,
            Some(Route::Jump(vec![Jump::Host(bastion.0)]))
        );
        assert_eq!(
            bastion.1.settings.identity_files,
            Some(vec!["~/.ssh/termius-ci-runner".to_owned()])
        );
        let web_group = vault.group(web.group.unwrap()).unwrap();
        assert_eq!(web_group.name, "Web");
        let prod = vault.group(web_group.parent.unwrap()).unwrap();
        assert!(matches!(prod.settings.identity, Some(UseIdentity::Id(_))));
        let (_, deploy) = vault.identities()[0];
        assert_eq!(
            deploy.settings.identity_files,
            Some(vec!["~/.ssh/id_deploy".to_owned()])
        );
        assert!(hosts.iter().all(|(_, h)| h.label != "switch"));

        // Again: nothing new, nothing doubled, and the key not saved twice.
        let read = super::read(Program::Termius, bundle(), &local);
        assert_eq!(
            read.keys[1].found.as_deref(),
            Some("~/.ssh/termius-ci-runner")
        );
        let p = preview(&vault, &read);
        assert!(
            p.items
                .iter()
                .filter(|i| i.label != "switch")
                .all(|i| i.existing)
        );
        let r = apply(
            &mut vault,
            &local,
            &read,
            &Choice {
                hosts: vec!["h1".into(), "h2".into()],
                ..choice
            },
        )
        .unwrap();
        assert_eq!((r.hosts, r.groups, r.skipped), (0, 0, 2));
        assert_eq!((r.tunnels, r.snippets, r.known_hosts), (0, 0, 0));
        assert_eq!(vault.hosts().len(), 2);
    }

    /// IM-1: callers can construct Read directly, without the detector.
    #[test]
    fn unfiltered_tunnels_are_saved_for_manual_start_only() {
        let dir = tempfile::tempdir().unwrap();
        let local = local(dir.path());
        let mut b = bundle();
        b.tunnels = [
            ForwardKind::Local,
            ForwardKind::Remote,
            ForwardKind::Dynamic,
        ]
        .into_iter()
        .enumerate()
        .map(|(i, kind)| Tunnel {
            host: "h2".into(),
            label: format!("imported {kind:?}"),
            kind,
            listen_address: Some("0.0.0.0".into()),
            listen_port: 20000 + i as u16,
            dest_host: Some("127.0.0.1".into()),
            dest_port: Some(5432),
            autostart: true,
        })
        .collect();
        let read = read(Program::Termius, b, &local);
        let mut vault = Vault::open_in_memory().unwrap();
        let report = apply(
            &mut vault,
            &local,
            &read,
            &Choice {
                hosts: vec!["h2".into()],
                group_name: "Imported".into(),
                ..Choice::default()
            },
        )
        .unwrap();
        assert_eq!(report.tunnels, 3);
        assert_eq!(
            report
                .warnings
                .iter()
                .filter(|w| w.kind == bundle::WarningKind::TunnelAutostart)
                .count(),
            3
        );
        for (_, t) in vault.port_forwards() {
            assert!(
                !t.autostart,
                "{:?} must require the user to start it",
                t.kind
            );
            assert_eq!(t.listen_address, None);
            assert_eq!(t.dest_host.as_deref(), Some("127.0.0.1"));
            assert_eq!(t.dest_port, Some(5432));
        }
        // Explicit enablement after review remains available.
        let (id, tunnel) = vault.port_forwards()[0];
        let mut enabled = tunnel.clone();
        enabled.set_autostart(true);
        let rev = vault.get(id).unwrap().rev;
        vault.update(id, rev, Data::PortForward(enabled)).unwrap();
        assert!(vault.port_forward(id).unwrap().autostarts());
    }

    /// A key that `ssh-key` alone refuses (ECDSA P-256 with a 31-byte
    /// scalar, from `openward-ssh`'s fixtures) is read, and found in
    /// `~/.ssh` without its .pub.
    #[test]
    fn an_ecdsa_key_with_a_short_scalar_is_read_and_found() {
        let fixtures = Path::new(env!("CARGO_MANIFEST_DIR")).join("../openward-ssh/tests/fixtures");
        let text = |name: &str| fs::read_to_string(fixtures.join(name)).unwrap();
        let public = PublicKey::from_openssh(text("ecdsa-p256-short.pub").trim()).unwrap();
        for (name, passphrase) in [
            ("ecdsa-p256-short", None),
            ("ecdsa-p256-short-aes256-gcm", Some("openward-test")),
        ] {
            let read = public_key(&text(name), passphrase);
            assert_eq!(
                read.as_ref().map(PublicKey::key_data),
                Some(public.key_data()),
                "{name}"
            );
        }
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("mine"), text("ecdsa-p256-short")).unwrap();
        let found = ssh_dir_keys(dir.path());
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].1.key_data(), public.key_data());
    }

    #[test]
    fn a_key_not_found_and_not_saved_is_reported() {
        let dir = tempfile::tempdir().unwrap();
        let local = local(dir.path());
        let read = read(Program::Termius, bundle(), &local);
        let mut vault = Vault::open_in_memory().unwrap();
        let r = apply(
            &mut vault,
            &local,
            &read,
            &Choice {
                hosts: vec!["h1".into()],
                ..Choice::default()
            },
        )
        .unwrap();
        assert_eq!(r.without_key, ["bastion"]);
        assert!(!local.ssh_dir.exists());
        let (_, group) = vault.groups()[0];
        assert_eq!(group.name, "Termius");
    }
    /// A key is written aside and only takes its name at the end: dropped
    /// first (the vault failed) it leaves nothing; placed over a file that
    /// appeared meanwhile, it fails and replaces nothing.
    #[test]
    fn saved_keys_are_written_aside_and_never_replace_a_file() {
        let dir = tempfile::tempdir().unwrap();
        let local = local(dir.path());
        let b = bundle();
        let stored = &b.keys[0];
        let names = |d: &Path| -> Vec<String> {
            let mut n: Vec<_> = fs::read_dir(d)
                .unwrap()
                .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
                .collect();
            n.sort();
            n
        };

        let staged = stage_key(&local, "~/.ssh/termius-deploy", stored).unwrap();
        assert_eq!(
            names(&local.ssh_dir).len(),
            2,
            "the key and its .pub, hidden"
        );
        assert!(names(&local.ssh_dir).iter().all(|n| n.starts_with('.')));
        drop(staged);
        assert!(names(&local.ssh_dir).is_empty());

        let staged = stage_key(&local, "~/.ssh/termius-deploy", stored).unwrap();
        fs::write(local.ssh_dir.join("termius-deploy"), "mine").unwrap();
        assert!(matches!(staged.place(), Err(Error::Key { .. })));
        assert_eq!(names(&local.ssh_dir), ["termius-deploy"]);
        assert_eq!(
            fs::read_to_string(local.ssh_dir.join("termius-deploy")).unwrap(),
            "mine"
        );

        fs::remove_file(local.ssh_dir.join("termius-deploy")).unwrap();
        let staged = stage_key(&local, "~/.ssh/termius-deploy", stored).unwrap();
        assert_eq!(staged.place().unwrap(), "~/.ssh/termius-deploy");
        assert_eq!(
            names(&local.ssh_dir),
            ["termius-deploy", "termius-deploy.pub"]
        );
    }
}
