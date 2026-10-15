//! Importing `~/.ssh/config` into the vault, in a group of its own.
//!
//! Aliases imported before are left alone, so edits made in OpenWard
//! survive a second import; only new aliases come in. Jumps to an alias
//! imported earlier point at that host.
//!
//! [`preview`] shows what an import would bring without touching the
//! vault, so the user can pick; picking a host brings the hosts it jumps
//! through along.

use std::collections::{HashMap, HashSet};
use std::path::Path;

use openward_import::ssh_config::{self, Paths, SshConfig, Warning};
use openward_vault::Vault;
use openward_vault::proto::{Data, Group, Host, ItemId, Jump, Route, Source};

/// The group imported hosts go to, at the top level.
pub const GROUP: &str = "~/.ssh/config";

#[derive(Debug)]
pub struct Report {
    pub group: ItemId,
    pub created: usize,
    /// Aliases already in the vault from an earlier import.
    pub skipped: usize,
    pub warnings: Vec<Warning>,
}

/// One alias as an import would bring it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Preview {
    pub alias: String,
    pub address: String,
    pub user: Option<String>,
    pub port: Option<u16>,
    /// What it jumps through, in order: aliases of the same file, or
    /// addresses.
    pub jumps: Vec<String>,
    /// Imported before: importing again leaves it as it is.
    pub existing: bool,
}

/// What [`ssh_config`] would bring in, in the file's order.
pub fn preview(vault: &Vault, file: &Path, paths: &Paths) -> Vec<Preview> {
    let imported = ssh_config::import(&SshConfig::load(file, paths));
    let existing = existing_aliases(vault);
    let labels: HashMap<ItemId, &str> = imported
        .hosts
        .iter()
        .map(|(id, h)| (*id, h.label.as_str()))
        .collect();
    imported
        .hosts
        .iter()
        .map(|(_, h)| Preview {
            alias: h.label.clone(),
            address: h.address.clone(),
            user: h.settings.user.clone(),
            port: h.settings.port,
            jumps: match &h.settings.route {
                Some(Route::Jump(jumps)) => jumps
                    .iter()
                    .map(|j| match j {
                        Jump::Host(id) => labels.get(id).copied().unwrap_or_default().to_owned(),
                        Jump::Address { host, .. } => host.clone(),
                    })
                    .collect(),
                _ => Vec::new(),
            },
            existing: existing.contains_key(&h.label.to_lowercase()),
        })
        .collect()
}

/// Imports `file`; with `only`, just those aliases (any case) and the
/// imported hosts they jump through.
pub fn ssh_config(
    vault: &mut Vault,
    file: &Path,
    paths: &Paths,
    only: Option<&[String]>,
) -> openward_vault::Result<Report> {
    let config = SshConfig::load(file, paths);
    let mut imported = ssh_config::import(&config);
    if let Some(only) = only {
        imported.hosts = select(imported.hosts, only);
        let kept: HashSet<String> = imported
            .hosts
            .iter()
            .map(|(_, h)| h.label.to_lowercase())
            .collect();
        imported.warnings.retain(|w| match w {
            Warning::JumpLossy { alias, .. } => kept.contains(&alias.to_lowercase()),
            _ => true,
        });
    }

    let existing = existing_aliases(vault);
    // Fresh ids of aliases that already exist → the existing host.
    let remap: HashMap<ItemId, ItemId> = imported
        .hosts
        .iter()
        .filter_map(|(id, h)| existing.get(&h.label.to_lowercase()).map(|old| (*id, *old)))
        .collect();

    let found = vault
        .groups()
        .into_iter()
        .find(|(_, g)| g.parent.is_none() && g.name == GROUP)
        .map(|(id, _)| id);
    let group = found.unwrap_or_else(ItemId::new);
    let mut items = Vec::new();
    if found.is_none() {
        items.push((
            group,
            Data::Group(Group {
                name: GROUP.into(),
                ..Group::default()
            }),
        ));
    }
    let mut skipped = 0;
    for (id, mut host) in imported.hosts {
        if remap.contains_key(&id) {
            skipped += 1;
            continue;
        }
        host.group = Some(group);
        if let Some(Route::Jump(jumps)) = &mut host.settings.route {
            for jump in jumps {
                if let Jump::Host(target) = jump
                    && let Some(old) = remap.get(target)
                {
                    *target = *old;
                }
            }
        }
        items.push((id, Data::Host(host)));
    }
    let created = items.len() - usize::from(found.is_none());
    if created > 0 {
        vault.create_all(items)?;
    }
    Ok(Report {
        group,
        created,
        skipped,
        warnings: imported.warnings,
    })
}

/// Aliases imported before (lowercased) → their host.
fn existing_aliases(vault: &Vault) -> HashMap<String, ItemId> {
    vault
        .hosts()
        .into_iter()
        .filter_map(|(id, h)| match &h.source {
            Some(Source::SshConfig { alias }) => Some((alias.to_lowercase(), id)),
            _ => None,
        })
        .collect()
}

/// The hosts named in `only` and, all the way down, the hosts they jump
/// through.
fn select(hosts: Vec<(ItemId, Host)>, only: &[String]) -> Vec<(ItemId, Host)> {
    let keep = {
        let by_id: HashMap<ItemId, &Host> = hosts.iter().map(|(id, h)| (*id, h)).collect();
        let mut keep: HashSet<ItemId> = hosts
            .iter()
            .filter(|(_, h)| only.iter().any(|a| a.eq_ignore_ascii_case(&h.label)))
            .map(|(id, _)| *id)
            .collect();
        let mut queue: Vec<ItemId> = keep.iter().copied().collect();
        while let Some(id) = queue.pop() {
            if let Some(Route::Jump(jumps)) = &by_id[&id].settings.route {
                for jump in jumps {
                    if let Jump::Host(target) = jump
                        && by_id.contains_key(target)
                        && keep.insert(*target)
                    {
                        queue.push(*target);
                    }
                }
            }
        }
        keep
    };
    hosts
        .into_iter()
        .filter(|(id, _)| keep.contains(id))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_second_import_brings_only_new_aliases() {
        let dir = tempfile::tempdir().unwrap();
        let paths = Paths::new(dir.path());
        std::fs::create_dir_all(&paths.ssh_dir).unwrap();
        let file = paths.user_config();
        std::fs::write(
            &file,
            "Host bastion\n  User ops\nHost web\n  ProxyJump bastion\n",
        )
        .unwrap();

        let mut vault = Vault::open_in_memory().unwrap();
        let first = ssh_config(&mut vault, &file, &paths, None).unwrap();
        assert_eq!((first.created, first.skipped), (2, 0));

        // Edited in OpenWard: must survive the next import.
        let (bastion, _) = vault
            .hosts()
            .into_iter()
            .find(|(_, h)| h.label == "bastion")
            .unwrap();
        let Data::Host(mut h) = vault.get(bastion).unwrap().body.data.clone() else {
            unreachable!()
        };
        h.address = "bastion.example.com".into();
        vault.update(bastion, 1, Data::Host(h)).unwrap();

        std::fs::write(
            &file,
            "Host bastion\n  User ops\nHost web\n  ProxyJump bastion\nHost db\n  ProxyJump bastion\n",
        )
        .unwrap();
        let second = ssh_config(&mut vault, &file, &paths, None).unwrap();
        assert_eq!((second.created, second.skipped), (1, 2));
        assert_eq!(second.group, first.group);
        assert_eq!(vault.host(bastion).unwrap().address, "bastion.example.com");
        let (db, _) = vault
            .hosts()
            .into_iter()
            .find(|(_, h)| h.label == "db")
            .unwrap();
        assert_eq!(vault.jump_users(bastion).len(), 2);
        assert_eq!(vault.host(db).unwrap().group, Some(first.group));
    }

    #[test]
    fn picking_a_host_brings_the_hosts_it_jumps_through() {
        let dir = tempfile::tempdir().unwrap();
        let paths = Paths::new(dir.path());
        std::fs::create_dir_all(&paths.ssh_dir).unwrap();
        let file = paths.user_config();
        std::fs::write(
            &file,
            "Host bastion\n  HostName bastion.example.com\n  User ops\n\
             Host web\n  ProxyJump bastion\n  Port 2222\n\
             Host old\n  ProxyJump gone.example.com\n\
             Host db\n",
        )
        .unwrap();

        let mut vault = Vault::open_in_memory().unwrap();
        let first = preview(&vault, &file, &paths);
        let web = first.iter().find(|p| p.alias == "web").unwrap();
        assert_eq!(web.jumps, ["bastion"]);
        assert_eq!(web.port, Some(2222));
        let bastion = first.iter().find(|p| p.alias == "bastion").unwrap();
        assert_eq!(
            (bastion.address.as_str(), bastion.user.as_deref()),
            ("bastion.example.com", Some("ops"))
        );
        assert!(first.iter().all(|p| !p.existing));

        let report = ssh_config(&mut vault, &file, &paths, Some(&["WEB".into()])).unwrap();
        assert_eq!(report.created, 2);
        let mut labels: Vec<String> = vault
            .hosts()
            .into_iter()
            .map(|(_, h)| h.label.clone())
            .collect();
        labels.sort();
        assert_eq!(labels, ["bastion", "web"]);
        // Warnings about hosts left out are left out too.
        assert!(
            !report
                .warnings
                .iter()
                .any(|w| matches!(w, Warning::JumpLossy { alias, .. } if alias == "old"))
        );

        let again = preview(&vault, &file, &paths);
        let existing: Vec<&str> = again
            .iter()
            .filter(|p| p.existing)
            .map(|p| p.alias.as_str())
            .collect();
        assert_eq!(existing, ["bastion", "web"]);
    }
}
