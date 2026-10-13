//! Importing `~/.ssh/config` into the vault, in a group of its own.
//!
//! Aliases imported before are left alone, so edits made in OpenWard
//! survive a second import; only new aliases come in. Jumps to an alias
//! imported earlier point at that host.

use std::collections::HashMap;
use std::path::Path;

use openward_import::ssh_config::{self, Paths, SshConfig, Warning};
use openward_vault::Vault;
use openward_vault::proto::{Data, Group, ItemId, Jump, Route, Source};

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

pub fn ssh_config(vault: &mut Vault, file: &Path, paths: &Paths) -> openward_vault::Result<Report> {
    let config = SshConfig::load(file, paths);
    let imported = ssh_config::import(&config);

    let existing: HashMap<String, ItemId> = vault
        .hosts()
        .into_iter()
        .filter_map(|(id, h)| match &h.source {
            Some(Source::SshConfig { alias }) => Some((alias.to_lowercase(), id)),
            _ => None,
        })
        .collect();
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
        let first = ssh_config(&mut vault, &file, &paths).unwrap();
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
        let second = ssh_config(&mut vault, &file, &paths).unwrap();
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
}
