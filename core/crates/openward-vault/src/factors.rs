//! Alternate factors contain authenticated ciphertext only. Metadata remains
//! bounded even before a password has been provided.
use crate::{Error, Result, Vault};
use openward_crypto::{
    password::KdfParams,
    unlock::{Purpose, RecoveryKit, UnlockBox},
};
use rusqlite::OptionalExtension;
use std::path::Path;

pub(crate) const RECOVERY: &str = "local_recovery_v1";
const NATIVE: &str = "local_native_v1";

impl Vault {
    pub fn migrate_with_recovery(
        path: &Path,
        password: &[u8],
        params: KdfParams,
        kit: &RecoveryKit,
    ) -> Result<crate::LockedVault> {
        crate::migration::install_with_recovery(path, password, params, true, Some(kit), |_| Ok(()))
    }
    fn factor(&self, name: &str) -> Result<Option<Vec<u8>>> {
        let value: Option<Option<Vec<u8>>> = self
            .store
            .conn
            .query_row(
                "SELECT CASE WHEN length(value)<=512 THEN value END FROM meta WHERE key=?1",
                [name],
                |r| r.get(0),
            )
            .optional()?;
        match value {
            Some(None) => Err(Error::Invalid("invalid local unlock record")),
            Some(Some(v)) => Ok(Some(v)),
            None => Ok(None),
        }
    }
    pub fn has_recovery(&self) -> Result<bool> {
        Ok(self.factor(RECOVERY)?.is_some())
    }
    pub fn native_namespace(&self) -> Result<String> {
        let h = self
            .store
            .header
            .as_ref()
            .ok_or(Error::Invalid("encrypt the vault first"))?;
        fn hex(b: [u8; 16]) -> String {
            b.iter().map(|v| format!("{v:02x}")).collect()
        }
        Ok(format!("v1-{}-{}-", hex(h.vault_id()), hex(h.device_id())))
    }
    pub fn native_id(&self) -> Result<Option<String>> {
        let Some(record) = self.factor(NATIVE)? else {
            return Ok(None);
        };
        if record.len() != 101 + 174 {
            return Err(Error::Invalid("invalid local unlock record"));
        }
        let id = std::str::from_utf8(&record[..101])
            .map_err(|_| Error::Invalid("invalid native identifier"))?;
        let prefix = self.native_namespace()?;
        if !id.starts_with(&prefix) || !id[prefix.len()..].bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(Error::Invalid("foreign native identifier"));
        }
        UnlockBox::from_bytes(&record[101..])?;
        Ok(Some(id.to_owned()))
    }
    pub fn enroll_native(&mut self, id: &str, key: &[u8; 32]) -> Result<()> {
        let prefix = self.native_namespace()?;
        if id.len() != 101
            || !id.starts_with(&prefix)
            || !id[prefix.len()..].bytes().all(|b| b.is_ascii_hexdigit())
        {
            return Err(Error::Invalid("foreign native identifier"));
        }
        let h = self.store.header.as_ref().ok_or(Error::Locked)?;
        let keys = self.store.keys.as_ref().ok_or(Error::Locked)?;
        let sealed = UnlockBox::seal(h, keys, key, Purpose::Native)?;
        sealed.open(h, key, Purpose::Native)?;
        let mut record = id.as_bytes().to_vec();
        record.extend(sealed.to_bytes());
        self.store.conn.execute(
            "INSERT OR REPLACE INTO meta VALUES (?1,?2)",
            rusqlite::params![NATIVE, record],
        )?;
        Ok(())
    }
    pub fn disable_native(&mut self) -> Result<()> {
        if self.is_locked() {
            return Err(Error::Locked);
        }
        self.store
            .conn
            .execute("DELETE FROM meta WHERE key=?1", [NATIVE])?;
        Ok(())
    }
    pub fn unlock_native(&mut self, key: &[u8; 32]) -> Result<()> {
        self.native_id()?
            .ok_or(Error::Invalid("native unlock is not enabled"))?;
        let record = self.factor(NATIVE)?.ok_or(Error::Locked)?;
        self.unlock_factor(&record[101..], key, Purpose::Native)
    }
    pub fn unlock_recovery(&mut self, kit: &RecoveryKit) -> Result<()> {
        let record = self
            .factor(RECOVERY)?
            .ok_or(Error::Invalid("no local recovery kit"))?;
        self.unlock_factor(&record, kit.secret(), Purpose::Recovery)
    }
    fn unlock_factor(&mut self, record: &[u8], key: &[u8; 32], purpose: Purpose) -> Result<()> {
        let loaded = (|| {
            let h = self.store.header.as_ref().ok_or(Error::Locked)?;
            self.store.keys = Some(UnlockBox::from_bytes(record)?.open(h, key, purpose)?);
            self.store.private_metadata()?;
            Self::load_index(&mut self.store)
        })();
        self.finish_unlock(loaded)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::{Data, Host};
    #[test]
    fn recovered_migration_preserves_items_and_native_factor_is_bound_to_this_vault() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let mut vault = Vault::open(&path).unwrap();
        let id = vault
            .create(Data::Host(Host {
                label: "private host".into(),
                address: "private.example".into(),
                ..Host::default()
            }))
            .unwrap();
        drop(vault);
        let kit = RecoveryKit::generate().unwrap();
        drop(
            Vault::migrate_with_recovery(
                &path,
                b"public test password",
                KdfParams::new(65536, 1).unwrap(),
                &kit,
            )
            .unwrap(),
        );
        let mut vault = Vault::open_session(&path).unwrap();
        assert!(vault.is_locked());
        assert!(vault.has_recovery().unwrap());
        let wrong = RecoveryKit::generate().unwrap();
        assert!(vault.unlock_recovery(&wrong).is_err());
        assert!(vault.is_locked());
        vault.unlock_recovery(&kit).unwrap();
        assert_eq!(vault.host(id).unwrap().label, "private host");
        let native_id = format!("{}{}", vault.native_namespace().unwrap(), "ab".repeat(16));
        assert!(
            vault
                .enroll_native(&format!("v1-{}", "00".repeat(49)), &[7; 32])
                .is_err()
        );
        vault.enroll_native(&native_id, &[7; 32]).unwrap();
        vault.lock_in_place().unwrap();
        assert!(vault.unlock_native(&[8; 32]).is_err());
        assert!(vault.is_locked());
        vault.unlock_native(&[7; 32]).unwrap();
        assert_eq!(vault.host(id).unwrap().label, "private host");
        vault.disable_native().unwrap();
        vault.lock_in_place().unwrap();
        assert!(vault.native_id().unwrap().is_none());
        assert!(vault.unlock_native(&[7; 32]).is_err());
        vault.unlock_in_place(b"public test password").unwrap();
        assert!(vault.host(id).is_ok());
    }
    #[test]
    fn locked_deletion_and_untrusted_factor_identifiers_are_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let mut vault =
            Vault::create_encrypted(&path, b"public password", KdfParams::new(65536, 1).unwrap())
                .unwrap();
        let id = vault
            .create(Data::Host(Host {
                label: "private".into(),
                address: "private.example".into(),
                ..Host::default()
            }))
            .unwrap();
        vault.lock_in_place().unwrap();
        assert!(matches!(vault.store.write(&[], &[id]), Err(Error::Locked)));
        assert_eq!(
            vault
                .store
                .conn
                .query_row("SELECT count(*) FROM items", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            1
        );
        vault
            .store
            .conn
            .execute(
                "INSERT INTO meta VALUES (?1,?2)",
                rusqlite::params![NATIVE, vec![0u8; 65536]],
            )
            .unwrap();
        assert!(vault.native_id().is_err());
        assert!(vault.is_locked());
    }
}
