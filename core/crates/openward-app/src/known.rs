//! The trusted host keys as a screen lists them: OpenWard's and the
//! lines of `~/.ssh/known_hosts`, with the saved hosts each one is for.

use std::io::Write;
use std::path::Path;

pub use openward_ssh::known_hosts::Marker;
use openward_ssh::known_hosts::{Line, lines};
use openward_ssh::russh::keys::HashAlg;
use openward_vault::Vault;
use openward_vault::proto::ItemId;

use crate::keys::algorithm;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KnownSource {
    /// Trusted in OpenWard, at `added` (ms since the epoch).
    OpenWard { id: ItemId, added: i64 },
    /// A line of `~/.ssh/known_hosts`, from 1.
    File { line: usize },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KnownEntry {
    pub source: KnownSource,
    /// The line as written, to remove exactly that one.
    pub text: String,
    pub marker: Option<Marker>,
    /// The patterns; `None` when the name is hashed.
    pub hosts: Option<String>,
    /// For a hashed name: a host it is known to stand for (a saved
    /// host's address, or what was searched).
    pub revealed: Option<String>,
    /// `Ed25519`, `RSA 3072`…
    pub algorithm: String,
    /// `SHA256:…`
    pub fingerprint: String,
    pub comment: Option<String>,
    /// Saved hosts whose address and port it names.
    pub saved: Vec<ItemId>,
}

/// `host`, `host:port` or `[host]:port`.
fn host_and_port(query: &str) -> (String, u16) {
    let q = query.trim();
    if let Some(rest) = q.strip_prefix('[')
        && let Some((host, port)) = rest.split_once("]:")
        && let Ok(port) = port.parse()
    {
        return (host.to_owned(), port);
    }
    match q.rsplit_once(':') {
        Some((host, port)) if !host.contains(':') => match port.parse() {
            Ok(port) => (host.to_owned(), port),
            Err(_) => (q.to_owned(), 22),
        },
        _ => (q.to_owned(), 22),
    }
}

fn entry(source: KnownSource, line: Line, saved: &[(ItemId, String, String, u16)]) -> KnownEntry {
    let matched: Vec<&(ItemId, String, String, u16)> = saved
        .iter()
        .filter(|(_, _, address, port)| line.matches(address, *port))
        .collect();
    KnownEntry {
        source,
        marker: line.marker,
        revealed: match (&line.hosts, matched.first()) {
            (None, Some((_, _, address, _))) => Some(address.clone()),
            _ => None,
        },
        hosts: line.hosts.clone(),
        algorithm: algorithm(line.key.key_data()),
        fingerprint: line.key.fingerprint(HashAlg::Sha256).to_string(),
        comment: line.comment.clone(),
        saved: matched.iter().map(|(id, ..)| *id).collect(),
        text: line.text,
    }
}

/// OpenWard's keys and then the file's, keeping those that match `query`
/// (any of it, or every one when it is empty): by pattern, fingerprint,
/// comment or saved host, and a hashed name when `query` is its host.
/// What the known hosts screen needs of the vault, taken under its lock so
/// that reading `~/.ssh/known_hosts` and matching names happen without it.
pub struct Ours {
    /// Saved hosts: id, label, address and port.
    saved: Vec<(ItemId, String, String, u16)>,
    /// OpenWard's trusted keys: id, `known_hosts` line, and when added.
    keys: Vec<(ItemId, String, i64)>,
}

impl Ours {
    pub fn of(vault: &Vault) -> Self {
        let saved = vault
            .hosts()
            .into_iter()
            .map(|(id, h)| {
                let port = vault
                    .effective(id)
                    .ok()
                    .and_then(|e| e.settings.port)
                    .unwrap_or(22);
                (id, h.label.clone(), h.address.clone(), port)
            })
            .collect();
        let keys = vault
            .known_hosts_with_dates()
            .into_iter()
            .filter(|(_, k, _)| k.usable_for_connections())
            .map(|(id, k, added)| (id, k.to_line(), added))
            .collect();
        Self { saved, keys }
    }
}

/// How many trusted keys there are, OpenWard's and `file`'s: what a list of
/// them would hold, without matching them to hosts.
pub fn known_host_count(ours: &Ours, file: &Path) -> usize {
    let text = std::fs::read_to_string(file).unwrap_or_default();
    ours.keys.len() + lines(&text).len()
}

pub fn known_hosts(ours: Ours, file: &Path, query: &str) -> Vec<KnownEntry> {
    let Ours { saved, keys } = ours;
    let mut all = Vec::new();
    for (id, line, added) in keys {
        for line in lines(&line) {
            all.push((KnownSource::OpenWard { id, added }, line));
        }
    }
    let text = std::fs::read_to_string(file).unwrap_or_default();
    for line in lines(&text) {
        all.push((KnownSource::File { line: line.number }, line));
    }
    let q = query.trim().to_lowercase();
    let (host, port) = host_and_port(&q);
    all.into_iter()
        .filter_map(|(source, line)| {
            let named = !q.is_empty() && line.matches(&host, port);
            let hashed = line.hosts.is_none();
            let mut e = entry(source, line, &saved);
            if q.is_empty() {
                return Some(e);
            }
            let labels = e
                .saved
                .iter()
                .filter_map(|id| saved.iter().find(|s| s.0 == *id))
                .flat_map(|(_, label, address, _)| [label.to_lowercase(), address.to_lowercase()]);
            let hit = named
                || e.hosts
                    .as_deref()
                    .is_some_and(|h| h.to_lowercase().contains(&q))
                || e.fingerprint.to_lowercase().contains(&q)
                || e.comment
                    .as_deref()
                    .is_some_and(|c| c.to_lowercase().contains(&q))
                || labels.into_iter().any(|l| l.contains(&q));
            if named && hashed && e.revealed.is_none() {
                e.revealed = Some(host.clone());
            }
            hit.then_some(e)
        })
        .collect()
}

#[derive(Debug, thiserror::Error)]
pub enum ForgetError {
    #[error("the file changed: line {0} is not the one shown")]
    Changed(usize),
    #[error("{0}")]
    Io(#[from] std::io::Error),
}

/// Removes line `number` of `file` if it still reads `text`, keeping a copy
/// of the file in `<file>.old` first, as `ssh-keygen -R` does.
pub fn forget_line(file: &Path, number: usize, text: &str) -> Result<(), ForgetError> {
    let content = std::fs::read_to_string(file)?;
    let all: Vec<&str> = content.split_inclusive('\n').collect();
    let at = number.wrapping_sub(1);
    let same = all
        .get(at)
        .is_some_and(|l| l.trim_end_matches(['\n', '\r']) == text);
    if !same {
        return Err(ForgetError::Changed(number));
    }
    let mut old = file.as_os_str().to_owned();
    old.push(".old");
    std::fs::copy(file, &old)?;
    let kept: String = all
        .iter()
        .enumerate()
        .filter(|(i, _)| *i != at)
        .map(|(_, l)| *l)
        .collect();
    // Next to it, then over it: a crash leaves the old file or the new one.
    let dir = file.parent().unwrap_or(Path::new("."));
    let mut tmp = tempfile::NamedTempFile::new_in(dir)?;
    tmp.write_all(kept.as_bytes())?;
    tmp.as_file()
        .set_permissions(std::fs::metadata(file)?.permissions())?;
    tmp.persist(file).map_err(|e| e.error)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use hmac::{Hmac, KeyInit, Mac};
    use openward_vault::proto::{Data, Host, Settings};
    use sha1::Sha1;

    use super::*;

    const KEY: &str =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg+ccEU+buKk8f5ORMPyzCAzWM04Omv+MOaI8CvGd7f";
    const OTHER: &str =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJON9ypgHeCkesivXcy8heayyTUCM9gTjTKSUZit/91";

    fn hashed(host: &str) -> String {
        let salt = b"0123456789abcdefghij";
        let mut mac = Hmac::<Sha1>::new_from_slice(salt).unwrap();
        mac.update(host.as_bytes());
        let b64 = data_encoding::BASE64;
        format!(
            "|1|{}|{}",
            b64.encode(salt),
            b64.encode(&mac.finalize().into_bytes())
        )
    }

    #[test]
    fn both_sources_with_their_saved_hosts_and_search() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("known_hosts");
        std::fs::write(
            &file,
            format!(
                "# comment\n{} {OTHER}\n10.0.4.21 {KEY} db\n@revoked old.example.com {OTHER}\n",
                hashed("bastion.example.com")
            ),
        )
        .unwrap();
        let mut v = Vault::open_in_memory().unwrap();
        let bastion = v
            .create(Data::Host(Host {
                label: "bastion".into(),
                address: "bastion.example.com".into(),
                ..Host::default()
            }))
            .unwrap();
        let web = v
            .create(Data::Host(Host {
                label: "web".into(),
                address: "web.example.com".into(),
                settings: Settings {
                    port: Some(2222),
                    ..Settings::default()
                },
                ..Host::default()
            }))
            .unwrap();
        v.trust_host_key("web.example.com", 2222, KEY).unwrap();

        assert_eq!(known_host_count(&Ours::of(&v), &file), 4);
        let all = known_hosts(Ours::of(&v), &file, "");
        assert_eq!(all.len(), 4);
        assert!(matches!(all[0].source, KnownSource::OpenWard { .. }));
        assert_eq!(all[0].hosts.as_deref(), Some("[web.example.com]:2222"));
        assert_eq!(all[0].saved, [web]);
        assert_eq!(all[1].source, KnownSource::File { line: 2 });
        assert_eq!(all[1].hosts, None);
        assert_eq!(all[1].revealed.as_deref(), Some("bastion.example.com"));
        assert_eq!(all[1].saved, [bastion]);
        assert_eq!(all[2].comment.as_deref(), Some("db"));
        assert_eq!(all[3].marker, Some(Marker::Revoked));
        assert_eq!(all[0].algorithm, "Ed25519");

        // A hashed line answers to its host; the saved host's name too.
        let found = known_hosts(Ours::of(&v), &file, "bastion.example.com");
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].source, KnownSource::File { line: 2 });
        assert_eq!(known_hosts(Ours::of(&v), &file, "bastion").len(), 1);
        assert_eq!(
            known_hosts(Ours::of(&v), &file, "web.example.com:2222").len(),
            1
        );
        assert_eq!(known_hosts(Ours::of(&v), &file, "nothing-like-it").len(), 0);
    }

    #[test]
    fn forgetting_a_line_keeps_a_copy_and_checks_it_is_the_same() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("known_hosts");
        let text = format!("a {KEY}\nb {OTHER}\nc {KEY}\n");
        std::fs::write(&file, &text).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o600)).unwrap();
        }
        assert!(matches!(
            forget_line(&file, 2, &format!("a {KEY}")),
            Err(ForgetError::Changed(2))
        ));
        forget_line(&file, 2, &format!("b {OTHER}")).unwrap();
        assert_eq!(
            std::fs::read_to_string(&file).unwrap(),
            format!("a {KEY}\nc {KEY}\n")
        );
        assert_eq!(
            std::fs::read_to_string(dir.path().join("known_hosts.old")).unwrap(),
            text
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&file).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o600);
        }
        assert!(matches!(
            forget_line(&file, 9, "x"),
            Err(ForgetError::Changed(9))
        ));
    }
}
