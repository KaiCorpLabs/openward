//! Termius's tables as a [`Bundle`].
//!
//! Each table is a database of its own (`hosts`, `groups`, `ssh_configs`,
//! `ssh_identities`, `keys`…). Records point at each other with
//! `{id, local_id}`: `id` once synced, `local_id` on this computer (the
//! primary key). A host points at an SSH config, which points at an
//! identity (directly, or through `ssh_config_identities`), which points
//! at a key; groups have an SSH config too, and their hosts inherit it.
//!
//! Text fields may be encrypted ([`super::crypto`]); records also carry
//! `content`, a JSON copy of those fields, used when a field is missing.
//! An identity without `is_visible` is one Termius made for a single host
//! or group: its user and key go into that host's settings.

use std::collections::{BTreeMap, HashMap};

use openward_proto::{ForwardKind, HostKeyPolicy, Marker, Proxy, ProxyServer, Settings};

use super::crypto;
use super::idb::{Idb, Key, Record};
use super::v8::Value;
use crate::bundle::{
    Bundle, Group, Host, Identity, JumpRef, KeyRef, KnownHost, Missing, Snippet, StoredKey, Tunnel,
    Warning, WarningKind,
};

/// A table's live records, decrypted on demand.
struct Table<'a> {
    records: Vec<Row<'a>>,
    by_id: HashMap<i64, usize>,
    by_local: HashMap<i64, usize>,
}

struct Row<'a> {
    record: &'a Record,
    id: Option<i64>,
    local_id: Option<i64>,
    /// The decrypted `content` JSON, if any.
    content: Option<serde_json::Value>,
}

/// What reading the fields of a record ran into.
#[derive(Default)]
struct Trouble {
    shared: usize,
}

impl<'a> Table<'a> {
    fn new(db: &'a Idb, name: &str, key: &[u8; 32], trouble: &mut Trouble) -> Self {
        let mut records = Vec::new();
        let Some(database) = db.database(name) else {
            return Self {
                records,
                by_id: HashMap::new(),
                by_local: HashMap::new(),
            };
        };
        for record in db.records(database, None) {
            let v = &record.value;
            if v.get("status").and_then(Value::as_str) == Some("deleted") {
                continue;
            }
            // Items of a shared vault are encrypted with the team's key.
            if v.get("encrypted_with").is_some_and(|e| !e.is_unset()) {
                trouble.shared += 1;
                continue;
            }
            let content = v
                .get("content")
                .and_then(Value::as_str)
                .and_then(|c| crypto::decrypt(key, c).ok())
                .and_then(|c| serde_json::from_str(&c).ok());
            let local_id = v
                .get("local_id")
                .and_then(Value::as_i64)
                .or(match record.key {
                    Key::Number(n) if n.fract() == 0.0 => Some(n as i64),
                    _ => None,
                });
            records.push(Row {
                record,
                id: v.get("id").and_then(Value::as_i64),
                local_id,
                content,
            });
        }
        // The newest version wins when an entity was written twice.
        let at = |r: &Row| {
            r.record
                .value
                .get("updated_at")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_owned()
        };
        records.sort_by_key(|r| std::cmp::Reverse(at(r)));
        let mut seen_id = std::collections::HashSet::new();
        let mut seen_local = std::collections::HashSet::new();
        records.retain(|r| {
            r.id.is_none_or(|id| seen_id.insert(id))
                && r.local_id.is_none_or(|l| seen_local.insert(l))
        });
        // In the order they were made.
        records.sort_by_key(|r| (r.local_id.unwrap_or(i64::MAX), r.id));
        let mut by_id = HashMap::new();
        let mut by_local = HashMap::new();
        for (i, r) in records.iter().enumerate() {
            if let Some(id) = r.id {
                by_id.insert(id, i);
            }
            if let Some(l) = r.local_id {
                by_local.insert(l, i);
            }
        }
        Self {
            records,
            by_id,
            by_local,
        }
    }

    /// The record a `{id, local_id}` reference (or a bare number) points at.
    fn get(&self, reference: Option<&Value>) -> Option<&Row<'a>> {
        let r = reference?;
        let (id, local) = match r {
            Value::Object(_) => (
                r.get("id").and_then(Value::as_i64),
                r.get("local_id").and_then(Value::as_i64),
            ),
            other => (other.as_i64(), None),
        };
        id.and_then(|id| self.by_id.get(&id))
            .or_else(|| local.and_then(|l| self.by_local.get(&l)))
            .map(|&i| &self.records[i])
    }
}

impl Row<'_> {
    fn raw(&self, field: &str) -> Option<&Value> {
        self.record.value.get(field).filter(|v| !v.is_unset())
    }

    /// A text field, decrypted if it is encrypted; from `content` if the
    /// record has no such field. `None` when unset or empty.
    fn text(&self, field: &str, key: &[u8; 32]) -> Option<String> {
        let direct = match self.raw(field) {
            Some(Value::String(s)) if crypto::is_encrypted(s) => crypto::decrypt(key, s).ok(),
            Some(Value::String(s)) => Some(s.clone()),
            Some(Value::Int(n)) => Some(n.to_string()),
            _ => None,
        };
        direct
            .or_else(|| match self.content.as_ref()?.get(field)? {
                serde_json::Value::String(s) => Some(s.clone()),
                serde_json::Value::Number(n) => Some(n.to_string()),
                _ => None,
            })
            .map(|s| s.trim().to_owned())
            .filter(|s| !s.is_empty())
    }

    fn number(&self, field: &str, key: &[u8; 32]) -> Option<i64> {
        match self.raw(field) {
            Some(v) if v.as_i64().is_some() => v.as_i64(),
            _ => self
                .text(field, key)
                .and_then(|t| t.parse().ok())
                .or_else(|| self.content.as_ref()?.get(field)?.as_i64()),
        }
    }

    fn flag(&self, field: &str) -> Option<bool> {
        self.raw(field)
            .and_then(Value::as_bool)
            .or_else(|| self.content.as_ref()?.get(field)?.as_bool())
    }

    /// The entity's id for `imported.id`: Termius's own once synced, else
    /// this computer's.
    fn key(&self) -> String {
        match (self.id, self.local_id) {
            (Some(id), _) => format!("id:{id}"),
            (None, Some(l)) => format!("local:{l}"),
            (None, None) => String::from("unknown"),
        }
    }
}

/// The id of a bundle item: `id:…|local:…` once synced, so an item first
/// imported with only its local id is still recognized; see
/// [`crate::bundle::same_item`].
fn both(row: &Row) -> String {
    match (row.id, row.local_id) {
        (Some(id), Some(l)) => format!("id:{id}|local:{l}"),
        _ => row.key(),
    }
}

/// Reads Termius's tables with its local key.
pub fn bundle(db: &Idb, key: &[u8; 32]) -> Bundle {
    let mut trouble = Trouble::default();
    let mut t = |name| Table::new(db, name, key, &mut trouble);
    let hosts = t("hosts");
    let groups = t("groups");
    let configs = t("ssh_configs");
    let config_identities = t("ssh_config_identities");
    let identities = t("ssh_identities");
    let keys = t("keys");
    let proxies = t("proxies");
    let rules = t("pf_rules");
    let snippets = t("snippets");
    let tags = t("tags");
    let tag_hosts = t("tag_hosts");
    let known = t("known_hosts");
    let chains = t("host_chains");
    drop(t);

    let mut out = Bundle::default();
    if trouble.shared > 0 {
        out.warnings.push(Warning::general(WarningKind::Shared {
            count: trouble.shared,
        }));
    }
    if !chains.records.is_empty() {
        out.warnings.push(Warning::general(WarningKind::HostChain));
    }

    // Keys, and the identities that have a name.
    let mut stored = std::collections::BTreeSet::new();
    for k in &keys.records {
        let Some(private_key) = k.text("private_key", key) else {
            continue;
        };
        let passphrase = k.text("passphrase", key);
        if passphrase.is_some() {
            out.passphrases += 1;
        }
        stored.insert(both(k));
        out.keys.push(StoredKey {
            id: both(k),
            label: k.text("label", key).unwrap_or_else(|| "Termius".into()),
            private_key: private_key.into(),
            passphrase: passphrase.map(Into::into),
        });
    }
    let key_ref = |identity: &Row| -> Vec<KeyRef> {
        keys.get(identity.raw("ssh_key"))
            .map(both)
            .filter(|id| stored.contains(id))
            .map(KeyRef::Stored)
            .into_iter()
            .collect()
    };
    let visible = |i: &Row| i.flag("is_visible").unwrap_or(false) && i.text("label", key).is_some();
    for i in &identities.records {
        if i.text("password", key).is_some() {
            out.passwords += 1;
        }
        if visible(i) {
            out.identities.push(Identity {
                id: both(i),
                label: i.text("label", key).unwrap_or_default(),
                user: i.text("username", key),
                keys: key_ref(i),
            });
        }
    }

    // An SSH config as settings, and its identity: a named one, or its
    // user and key.
    struct Config {
        settings: Settings,
        identity: Option<String>,
        keys: Vec<KeyRef>,
        mosh: bool,
        startup: bool,
    }
    let config = |row: Option<&Row>, subject: &str, warnings: &mut Vec<Warning>| -> Config {
        let mut c = Config {
            settings: Settings::default(),
            identity: None,
            keys: Vec::new(),
            mosh: false,
            startup: false,
        };
        let Some(row) = row else {
            return c;
        };
        let s = &mut c.settings;
        if let Some(port) = row.number("port", key) {
            match u16::try_from(port) {
                Ok(p) if p > 0 => s.port = Some(p),
                _ => warnings.push(Warning::about(
                    subject,
                    WarningKind::BadValue {
                        field: "port".into(),
                        value: port.to_string(),
                    },
                )),
            }
        }
        if let Some(on) = row.flag("agent_forwarding") {
            s.agent_forward = Some(on);
        }
        if row.flag("strict_host_key_check") == Some(true) {
            s.host_key_policy = Some(HostKeyPolicy::Strict);
        }
        if let Some(secs) = row.number("keep_alive_packages", key)
            && let Ok(secs) = u32::try_from(secs)
            && secs > 0
        {
            s.keepalive_secs = Some(secs);
        }
        if let Some(env) = row.text("env_variables", key) {
            let vars = env_variables(&env);
            if !vars.is_empty() {
                s.env = Some(vars);
            }
        }
        if let Some(p) = proxies.get(row.raw("proxycommand")) {
            match proxy(p, key, &identities) {
                Ok(p) => s.proxy = Some(p),
                Err(kind) => warnings.push(Warning::about(subject, WarningKind::Unsupported(kind))),
            }
        }
        c.mosh = row.flag("use_mosh") == Some(true);
        c.startup = row.raw("startup_snippet").is_some();
        // The config's identity, or the first linked through the join table.
        let identity = identities.get(row.raw("identity")).or_else(|| {
            config_identities
                .records
                .iter()
                .filter(|j| configs.get(j.raw("ssh_config")).map(Row::key) == Some(row.key()))
                .find_map(|j| identities.get(j.raw("identity")))
        });
        if let Some(i) = identity {
            if i.raw("hardware_key").is_some() {
                warnings.push(Warning::about(
                    subject,
                    WarningKind::Unsupported(Missing::HardwareKey),
                ));
            }
            if visible(i) {
                c.identity = Some(both(i));
            } else {
                s.user = i.text("username", key);
                c.keys = key_ref(i);
            }
        }
        c
    };

    for g in &groups.records {
        let name = g.text("label", key).unwrap_or_else(|| "Termius".into());
        let c = config(configs.get(g.raw("ssh_config")), &name, &mut out.warnings);
        out.groups.push(Group {
            id: both(g),
            name,
            parent: groups.get(g.raw("parent_group")).map(both),
            settings: c.settings,
            identity: c.identity,
            keys: c.keys,
        });
    }

    let mut host_tags: HashMap<String, Vec<String>> = HashMap::new();
    for th in &tag_hosts.records {
        if let (Some(h), Some(tag)) = (hosts.get(th.raw("host")), tags.get(th.raw("tag")))
            && let Some(label) = tag.text("label", key)
        {
            host_tags.entry(both(h)).or_default().push(label);
        }
    }

    for h in &hosts.records {
        let address = h.text("address", key).map(|a| expand_packed_ipv4(&a));
        let label = h
            .text("label", key)
            .or_else(|| address.clone())
            .unwrap_or_else(|| "Termius".into());
        let ssh = configs.get(h.raw("ssh_config"));
        let unsupported = match (ssh, h.raw("telnet_config")) {
            (None, Some(_)) => Some("telnet".to_owned()),
            _ => None,
        };
        let c = config(ssh, &label, &mut out.warnings);
        if c.mosh {
            out.warnings.push(Warning::about(&label, WarningKind::Mosh));
        }
        if c.startup {
            out.warnings
                .push(Warning::about(&label, WarningKind::StartupCommand));
        }
        let mut host_tags = host_tags.remove(&both(h)).unwrap_or_default();
        host_tags.sort();
        out.hosts.push(Host {
            id: both(h),
            label,
            address: address.unwrap_or_default(),
            group: groups.get(h.raw("group")).map(both),
            settings: c.settings,
            identity: c.identity,
            keys: c.keys,
            jumps: Vec::<JumpRef>::new(),
            tags: host_tags,
            notes: None,
            unsupported,
        });
    }

    for r in &rules.records {
        let Some(host) = hosts.get(r.raw("host")).map(both) else {
            continue;
        };
        let kind = match r
            .text("pf_type", key)
            .unwrap_or_default()
            .to_ascii_lowercase()
        {
            t if t.starts_with("remote") => ForwardKind::Remote,
            t if t.starts_with("dynamic") => ForwardKind::Dynamic,
            _ => ForwardKind::Local,
        };
        let Some(listen_port) = r
            .number("local_port", key)
            .and_then(|p| u16::try_from(p).ok())
        else {
            continue;
        };
        let dynamic = kind == ForwardKind::Dynamic;
        out.tunnels.push(Tunnel {
            host,
            label: r.text("label", key).unwrap_or_default(),
            kind,
            listen_address: r
                .text("bound_address", key)
                .filter(|a| a != "127.0.0.1" && a != "localhost"),
            listen_port,
            dest_host: (!dynamic).then(|| r.text("hostname", key)).flatten(),
            dest_port: (!dynamic)
                .then(|| {
                    r.number("remote_port", key)
                        .and_then(|p| u16::try_from(p).ok())
                })
                .flatten(),
            autostart: false,
        });
    }

    for s in &snippets.records {
        if let Some(script) = s.text("script", key) {
            out.snippets.push(Snippet {
                id: both(s),
                label: s
                    .text("label", key)
                    .unwrap_or_else(|| script.lines().next().unwrap_or_default().to_owned()),
                script,
            });
        }
    }

    for k in &known.records {
        let (Some(hosts), Some(public)) = (k.text("hostnames", key), k.text("key", key)) else {
            continue;
        };
        out.known_hosts.push(KnownHost {
            id: both(k),
            hosts,
            key: public,
            marker: match k.text("marker", key).as_deref() {
                Some("@cert-authority" | "cert-authority") => Some(Marker::CertAuthority),
                Some("@revoked" | "revoked") => Some(Marker::Revoked),
                _ => None,
            },
            comment: k.text("comment", key),
        });
    }
    out
}

/// A proxy of an SSH config: HTTP or SOCKS (any version here is 5).
fn proxy(row: &Row, key: &[u8; 32], identities: &Table) -> Result<Proxy, Missing> {
    let kind = row
        .text("type", key)
        .unwrap_or_default()
        .to_ascii_lowercase();
    let host = row.text("hostname", key).ok_or(Missing::IncompleteProxy)?;
    let port = row
        .number("port", key)
        .and_then(|p| u16::try_from(p).ok())
        .ok_or(Missing::IncompleteProxy)?;
    let user = identities
        .get(row.raw("identity"))
        .and_then(|i| i.text("username", key));
    let server = ProxyServer {
        host,
        port,
        user,
        extra: Default::default(),
    };
    if kind.contains("socks") {
        Ok(Proxy::Socks5(server))
    } else if kind.contains("http") {
        Ok(Proxy::Http(server))
    } else {
        Err(Missing::Proxy(kind))
    }
}

/// `{"NAME": "value"}`, or a list of `{name, value}`.
fn env_variables(text: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    match serde_json::from_str::<serde_json::Value>(text) {
        Ok(serde_json::Value::Object(map)) => {
            for (k, v) in map {
                if let Some(v) = v.as_str() {
                    out.insert(k, v.to_owned());
                }
            }
        }
        Ok(serde_json::Value::Array(items)) => {
            for item in items {
                if let (Some(k), Some(v)) = (
                    item.get("name").and_then(|v| v.as_str()),
                    item.get("value").and_then(|v| v.as_str()),
                ) {
                    out.insert(k.to_owned(), v.to_owned());
                }
            }
        }
        _ => {}
    }
    out
}

/// Termius stores some IPv4 addresses as a 32-bit number.
fn expand_packed_ipv4(address: &str) -> String {
    match address.parse::<u32>() {
        Ok(n) if address.len() > 3 => std::net::Ipv4Addr::from(n).to_string(),
        _ => address.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packed_addresses_and_plain_ones() {
        assert_eq!(expand_packed_ipv4("3221226008"), "192.0.2.24");
        assert_eq!(expand_packed_ipv4("web-1.example.com"), "web-1.example.com");
        assert_eq!(expand_packed_ipv4("10.0.0.1"), "10.0.0.1");
    }

    #[test]
    fn env_variables_in_both_shapes() {
        let want: BTreeMap<String, String> = [("LANG".to_owned(), "es_ES.UTF-8".to_owned())].into();
        assert_eq!(env_variables(r#"{"LANG": "es_ES.UTF-8"}"#), want);
        assert_eq!(
            env_variables(r#"[{"name": "LANG", "value": "es_ES.UTF-8"}]"#),
            want
        );
        assert!(env_variables("{}").is_empty());
    }
}
