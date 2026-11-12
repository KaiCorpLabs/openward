//! Device-only beta protection. The random password exists in the OS store,
//! never in the profile. The identifier is committed with encrypted migration.
use crate::{Error, Result, Vault};
use openward_crypto::{hierarchy::VaultHeader, password::KdfParams};
use rusqlite::OptionalExtension;
use std::path::Path;
pub(crate) const DEVICE: &str = "local_device_only_v1";
pub(crate) fn namespace(vault: [u8; 16], device: [u8; 16]) -> String {
    let hex = |v: [u8; 16]| v.iter().map(|b| format!("{b:02x}")).collect::<String>();
    format!("v1-{}-{}-", hex(vault), hex(device))
}
pub(crate) fn validate_id(header: &VaultHeader, id: &str) -> Result<()> {
    let prefix = namespace(header.vault_id(), header.device_id());
    if id.len() != 101
        || !id.starts_with(&prefix)
        || !id[prefix.len()..].bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Err(Error::Invalid("invalid device-only identifier"));
    }
    Ok(())
}
impl Vault {
    pub fn device_namespace(&self) -> Result<String> {
        match &self.store.header {
            Some(h) => Ok(namespace(h.vault_id(), h.device_id())),
            None => Ok(namespace(
                *self.store.vault_id.as_bytes(),
                *crate::store::id(&self.store.conn, "device_id")?.as_bytes(),
            )),
        }
    }
    pub fn is_device_only(&self) -> Result<bool> {
        Ok(self
            .store
            .conn
            .query_row("SELECT count(*) FROM meta WHERE key=?1", [DEVICE], |r| {
                r.get::<_, i64>(0)
            })?
            != 0)
    }
    pub fn device_id(&self) -> Result<Option<String>> {
        let value: Option<Option<Vec<u8>>> = self
            .store
            .conn
            .query_row(
                "SELECT CASE WHEN length(value)=101 THEN value END FROM meta WHERE key=?1",
                [DEVICE],
                |r| r.get(0),
            )
            .optional()?;
        let Some(value) = value else { return Ok(None) };
        let value = value.ok_or(Error::Invalid("invalid device-only identifier"))?;
        let id = String::from_utf8(value)
            .map_err(|_| Error::Invalid("invalid device-only identifier"))?;
        validate_id(self.store.header.as_ref().ok_or(Error::Locked)?, &id)?;
        Ok(Some(id))
    }
    pub fn migrate_device(path: &Path, key: &[u8], id: &str) -> Result<crate::LockedVault> {
        if key.len() != 32 {
            return Err(Error::Invalid("device key must have 256 bits"));
        }
        crate::migration::install_factors(
            path,
            key,
            KdfParams::new(65536, 1)?,
            true,
            None,
            Some(id),
            |_| Ok(()),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::{Data, Host};
    use openward_crypto::unlock::RecoveryKit;
    #[test]
    fn deferred_migration_and_password_conversion_preserve_items_and_recovery() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let mut old = Vault::open(&path).unwrap();
        let id = old
            .create(Data::Host(Host {
                label: "D8 public fixture".into(),
                address: "d8.invalid".into(),
                ..Default::default()
            }))
            .unwrap();
        let device_id = format!("{}{}", old.device_namespace().unwrap(), "12".repeat(16));
        drop(old);
        let key = [53; 32];
        let mut v = Vault::migrate_device(&path, &key, &device_id)
            .unwrap()
            .unlock(&key)
            .unwrap();
        assert!(v.is_device_only().unwrap());
        assert!(!v.has_recovery().unwrap());
        assert_eq!(
            v.store
                .conn
                .pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))
                .unwrap(),
            4
        );
        assert_eq!(v.hosts()[0].0, id);
        let local_key = v.local_data_key().unwrap();
        v.save_secret(
            crate::SecretKind::Password,
            "D8 password",
            "d8.invalid",
            "public fixture secret",
        )
        .unwrap();
        v.require_protected_storage().unwrap();
        assert_eq!(
            v.store
                .conn
                .pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))
                .unwrap(),
            4
        );
        let local_proof = local_key.seal(b"d8-fixture", b"kept").unwrap();
        let before = v
            .store
            .conn
            .query_row("SELECT envelope FROM items LIMIT 1", [], |r| {
                r.get::<_, Vec<u8>>(0)
            });
        // Item API survives the migration, and device-only data cannot be backed up without a kit.
        assert!(v.export_backup().is_err());
        assert!(v.empty_for_restore().is_err());
        let kit = RecoveryKit::generate().unwrap();
        assert!(
            v.prepare_device_password(
                b"wrong",
                b"new password",
                KdfParams::new(65536, 1).unwrap(),
                &kit
            )
            .is_err()
        );
        let update = v
            .prepare_device_password(
                &key,
                b"new password",
                KdfParams::new(65536, 1).unwrap(),
                &kit,
            )
            .unwrap();
        // Losing the marker before the new factors commit would lose the only
        // usable unlock route. Inject a transactional failure at that boundary.
        v.store.conn.execute_batch("CREATE TRIGGER reject_device_conversion BEFORE DELETE ON meta WHEN OLD.key='local_device_only_v1' BEGIN SELECT RAISE(ABORT,'D8 injected failure'); END;").unwrap();
        assert!(v.apply_credential_update(update).is_err());
        assert!(v.is_device_only().unwrap());
        assert!(!v.has_recovery().unwrap());
        v.verify_password(&key).unwrap();
        assert!(v.verify_password(b"new password").is_err());
        v.store
            .conn
            .execute_batch("DROP TRIGGER reject_device_conversion")
            .unwrap();
        let update = v
            .prepare_device_password(
                &key,
                b"new password",
                KdfParams::new(65536, 1).unwrap(),
                &kit,
            )
            .unwrap();
        v.apply_credential_update(update).unwrap();
        assert!(!v.is_device_only().unwrap());
        assert!(v.device_id().unwrap().is_none());
        assert_eq!(v.hosts()[0].0, id);
        assert_eq!(
            before.unwrap(),
            v.store
                .conn
                .query_row("SELECT envelope FROM items LIMIT 1", [], |r| r
                    .get::<_, Vec<u8>>(0))
                .unwrap()
        );
        v.lock_in_place().unwrap();
        assert!(v.unlock_in_place(&key).is_err());
        v.unlock_in_place(b"new password").unwrap();
        let backup = v.export_backup().unwrap();
        v.lock_in_place().unwrap();
        v.unlock_recovery(&kit).unwrap();
        assert_eq!(v.hosts()[0].1.address, "d8.invalid");
        assert_eq!(
            crate::backup::Snapshot::open(&backup, kit.text().as_bytes(), true)
                .unwrap()
                .summary()
                .items,
            2
        );
        assert_eq!(
            &*v.local_data_key()
                .unwrap()
                .open(b"d8-fixture", &local_proof)
                .unwrap(),
            b"kept"
        );
        drop(v);
        let mut reopened = Vault::open_session(&path).unwrap();
        assert!(!reopened.is_device_only().unwrap());
        reopened.unlock_recovery(&kit).unwrap();
        assert_eq!(reopened.hosts()[0].0, id);
    }
    #[test]
    fn malformed_device_marker_never_becomes_a_password_vault() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let old = Vault::open(&path).unwrap();
        let id = format!("{}{}", old.device_namespace().unwrap(), "34".repeat(16));
        drop(old);
        let mut v = Vault::migrate_device(&path, &[7; 32], &id)
            .unwrap()
            .unlock(&[7; 32])
            .unwrap();
        v.store
            .conn
            .execute(
                "UPDATE meta SET value=?1 WHERE key=?2",
                rusqlite::params![b"bad".as_slice(), DEVICE],
            )
            .unwrap();
        assert!(v.is_device_only().unwrap());
        assert!(v.device_id().is_err());
        v.lock_in_place().unwrap();
        assert!(v.device_id().is_err());
    }
}
