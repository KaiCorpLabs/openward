//! Rewrapping changes only credential records, atomically. Item ciphertext and
//! account/device/vault keys remain unchanged. Prepared updates contain no keys.
use crate::{
    Error, Result, Vault,
    factors::{NATIVE, RECOVERY},
    store::CRYPTO,
};
use openward_crypto::{
    hierarchy::{UnlockedKeys, VaultHeader},
    password::KdfParams,
    recovery::{AccountPackage, open_local_kit, seal_local_kit},
    unlock::{Purpose, RecoveryKit, UnlockBox},
};
use rusqlite::{Connection, OptionalExtension};

const CACHE: &str = "local_recovery_secret_v1";
const PACKAGE: &str = "remote_account_package_v1";

pub struct CredentialUpdate {
    header: VaultHeader,
    recovery: Vec<u8>,
    cache: Vec<u8>,
    package: Vec<u8>,
    remove_native: bool,
    expected: Option<(Vec<u8>, RecoveryVersion)>,
}
impl CredentialUpdate {
    pub(crate) fn prepare(
        header: VaultHeader,
        keys: &UnlockedKeys,
        password: &[u8],
        params: KdfParams,
        kit: &RecoveryKit,
        remove_native: bool,
    ) -> Result<Self> {
        let recovery = UnlockBox::seal(&header, keys, kit.secret(), Purpose::Recovery)?.to_bytes();
        UnlockBox::from_bytes(&recovery)?.open(&header, kit.secret(), Purpose::Recovery)?;
        let cache = seal_local_kit(&header, keys, kit)?;
        if open_local_kit(&cache, &header, keys)?.secret() != kit.secret() {
            return Err(Error::Invalid("recovery verification failed"));
        }
        let package = AccountPackage::seal(&keys.account, password, kit, params)?.to_bytes();
        if AccountPackage::from_bytes(&package)?
            .open(password, kit)?
            .public()
            != header.account()
        {
            return Err(Error::Invalid("account package verification failed"));
        }
        Ok(Self {
            header,
            recovery,
            cache,
            package,
            remove_native,
            expected: None,
        })
    }
    pub(crate) fn write(&self, conn: &Connection) -> Result<()> {
        for (name, value) in [
            (CRYPTO, self.header.to_bytes()),
            (RECOVERY, self.recovery.clone()),
            (CACHE, self.cache.clone()),
            (PACKAGE, self.package.clone()),
        ] {
            conn.execute(
                "INSERT OR REPLACE INTO meta VALUES (?1,?2)",
                rusqlite::params![name, value],
            )?;
        }
        if self.remove_native {
            conn.execute("DELETE FROM meta WHERE key=?1", [NATIVE])?;
        }
        Ok(())
    }
}
impl Vault {
    /// Authenticate independently of the currently unlocked session, including
    /// one opened with biometrics. Never turns a wrong credential into success.
    pub fn verify_password(&self, password: &[u8]) -> Result<()> {
        let keys = self.store.keys.as_ref().ok_or(Error::Locked)?;
        let checked = self
            .store
            .header
            .as_ref()
            .ok_or(Error::Locked)?
            .unlock(password)?;
        if checked.vault.secret() != keys.vault.secret() {
            return Err(Error::Invalid("credential mismatch"));
        }
        Ok(())
    }
    pub fn prepare_recovery_rotation(
        &self,
        password: &[u8],
        kit: &RecoveryKit,
    ) -> Result<CredentialUpdate> {
        self.verify_password(password)?;
        let header = self.store.header.as_ref().ok_or(Error::Locked)?;
        let mut update = CredentialUpdate::prepare(
            header.clone(),
            self.store.keys.as_ref().ok_or(Error::Locked)?,
            password,
            header.kdf_params(),
            kit,
            false,
        )?;
        update.expected = Some((header.to_bytes(), recovery_version(&self.store.conn)?));
        Ok(update)
    }
    pub fn prepare_password_change(
        &self,
        authorization: &[u8],
        use_kit: bool,
        password: &[u8],
        params: KdfParams,
    ) -> Result<CredentialUpdate> {
        let keys = self.store.keys.as_ref().ok_or(Error::Locked)?;
        let old = self.store.header.as_ref().ok_or(Error::Locked)?;
        let kit = if use_kit {
            let kit = RecoveryKit::parse(
                std::str::from_utf8(authorization).map_err(|_| Error::Invalid("invalid kit"))?,
            )?;
            let record = bounded(&self.store.conn, RECOVERY, 512)?
                .ok_or(Error::Invalid("missing recovery kit"))?;
            let checked =
                UnlockBox::from_bytes(&record)?.open(old, kit.secret(), Purpose::Recovery)?;
            if checked.vault.secret() != keys.vault.secret() {
                return Err(Error::Invalid("credential mismatch"));
            }
            kit
        } else {
            self.verify_password(authorization)?;
            let cache = bounded(&self.store.conn, CACHE, 77)?.ok_or(Error::Invalid(
                "regenerate the recovery kit before changing this older vault password",
            ))?;
            let kit = open_local_kit(&cache, old, keys)?;
            // A cache copied from another generation of the kit cannot preserve
            // stale access. Validate against the active local recovery wrapper.
            let record = bounded(&self.store.conn, RECOVERY, 512)?
                .ok_or(Error::Invalid("missing recovery kit"))?;
            UnlockBox::from_bytes(&record)?.open(old, kit.secret(), Purpose::Recovery)?;
            kit
        };
        let header = VaultHeader::from_keys(
            old.vault_id(),
            old.device_id(),
            old.generation(),
            password,
            params,
            keys,
        )?;
        let mut update = CredentialUpdate::prepare(header, keys, password, params, &kit, true)?;
        update.expected = Some((old.to_bytes(), recovery_version(&self.store.conn)?));
        Ok(update)
    }
    /// Call under a short access lease after expensive preparation. SQLite
    /// rollback leaves both in-memory header and all factors unchanged on error.
    pub fn apply_credential_update(&mut self, update: CredentialUpdate) -> Result<()> {
        if self.is_locked() {
            return Err(Error::Locked);
        }
        let expected = update
            .expected
            .as_ref()
            .ok_or(Error::Invalid("unbound credential update"))?;
        if self.store.header.as_ref().ok_or(Error::Locked)?.to_bytes() != expected.0
            || recovery_version(&self.store.conn)? != expected.1
        {
            return Err(Error::Invalid("stale or foreign credential update"));
        }
        let tx = self.store.conn.transaction()?;
        update.write(&tx)?;
        tx.commit()?;
        self.store.header = Some(update.header);
        Ok(())
    }
    pub(crate) fn verified_backup_recovery(&self) -> Result<Vec<u8>> {
        let header = self.store.header.as_ref().ok_or(Error::Locked)?;
        let keys = self.store.keys.as_ref().ok_or(Error::Locked)?;
        let cache = bounded(&self.store.conn, CACHE, 77)?.ok_or(Error::Invalid(
            "regenerate the recovery kit before exporting this older vault",
        ))?;
        let kit = open_local_kit(&cache, header, keys)?;
        let record = bounded(&self.store.conn, RECOVERY, 512)?
            .ok_or(Error::Invalid("missing recovery kit"))?;
        let checked =
            UnlockBox::from_bytes(&record)?.open(header, kit.secret(), Purpose::Recovery)?;
        if checked.vault.secret() != keys.vault.secret() {
            return Err(Error::Invalid("recovery verification failed"));
        }
        Ok(record)
    }
    pub fn account_package(&self) -> Result<Option<Vec<u8>>> {
        if self.is_locked() {
            return Err(Error::Locked);
        }
        let bytes = bounded(&self.store.conn, PACKAGE, 2200)?;
        if let Some(bytes) = &bytes {
            let package = AccountPackage::from_bytes(bytes)?;
            if package.account() != self.store.header.as_ref().ok_or(Error::Locked)?.account() {
                return Err(Error::Invalid("foreign account package"));
            }
        }
        Ok(bytes)
    }
}
// A malformed oversized record has no usable factor. Password-authorized
// regeneration may replace it without allocating attacker-controlled bytes.
// Valid-sized records retain exact stale-update binding.
#[derive(PartialEq, Eq)]
enum RecoveryVersion {
    Missing,
    Oversized,
    Record(Vec<u8>),
}
fn recovery_version(conn: &Connection) -> Result<RecoveryVersion> {
    let value: Option<Option<Vec<u8>>> = conn
        .query_row(
            "SELECT CASE WHEN length(value)<=512 THEN value END FROM meta WHERE key=?1",
            [RECOVERY],
            |r| r.get(0),
        )
        .optional()?;
    Ok(match value {
        None => RecoveryVersion::Missing,
        Some(None) => RecoveryVersion::Oversized,
        Some(Some(bytes)) => RecoveryVersion::Record(bytes),
    })
}
fn bounded(conn: &Connection, name: &str, limit: usize) -> Result<Option<Vec<u8>>> {
    let value: Option<Option<Vec<u8>>> = conn
        .query_row(
            "SELECT CASE WHEN length(value)<=?2 THEN value END FROM meta WHERE key=?1",
            rusqlite::params![name, limit as i64],
            |r| r.get(0),
        )
        .optional()?;
    match value {
        Some(None) => Err(Error::Invalid("invalid recovery record")),
        Some(Some(v)) => Ok(Some(v)),
        None => Ok(None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::{Data, Host};
    fn params() -> KdfParams {
        KdfParams::new(65536, 1).unwrap()
    }
    fn fixture() -> (tempfile::TempDir, Vault, RecoveryKit, crate::proto::ItemId) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let mut plain = Vault::open(&path).unwrap();
        let id = plain
            .create(Data::Host(Host {
                label: "private fixture".into(),
                address: "fixture.example".into(),
                ..Host::default()
            }))
            .unwrap();
        drop(plain);
        let kit = RecoveryKit::generate().unwrap();
        drop(Vault::migrate_with_recovery(&path, b"old public password", params(), &kit).unwrap());
        let mut v = Vault::open_session(&path).unwrap();
        v.unlock_in_place(b"old public password").unwrap();
        (dir, v, kit, id)
    }
    fn items(v: &Vault) -> Vec<Vec<u8>> {
        v.store
            .conn
            .prepare("SELECT envelope FROM items ORDER BY item_id")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .collect::<std::result::Result<_, _>>()
            .unwrap()
    }
    #[test]
    fn password_and_kit_changes_preserve_items_and_recover_a_copied_vault() {
        let (dir, mut v, kit, id) = fixture();
        let original = items(&v);
        let native_id = format!("{}{}", v.native_namespace().unwrap(), "aa".repeat(16));
        v.enroll_native(&native_id, &[9; 32]).unwrap();
        assert!(
            v.prepare_password_change(b"wrong", false, b"new public password", params())
                .is_err()
        );
        let update = v
            .prepare_password_change(
                b"old public password",
                false,
                b"new public password",
                params(),
            )
            .unwrap();
        v.apply_credential_update(update).unwrap();
        assert_eq!(items(&v), original);
        assert!(v.native_id().unwrap().is_none());
        let package = v.account_package().unwrap().unwrap();
        AccountPackage::from_bytes(&package)
            .unwrap()
            .open(b"new public password", &kit)
            .unwrap();
        v.lock_in_place().unwrap();
        assert!(v.unlock_in_place(b"old public password").is_err());
        assert!(v.unlock_native(&[9; 32]).is_err());
        v.unlock_recovery(&kit).unwrap();
        v.enroll_native(&native_id, &[5; 32]).unwrap();
        let next = RecoveryKit::generate().unwrap();
        let update = v
            .prepare_recovery_rotation(b"new public password", &next)
            .unwrap();
        let stale = v
            .prepare_recovery_rotation(b"new public password", &kit)
            .unwrap();
        v.apply_credential_update(update).unwrap();
        v.lock_in_place().unwrap();
        v.unlock_native(&[5; 32]).unwrap();
        assert!(v.apply_credential_update(stale).is_err());
        let package = v.account_package().unwrap().unwrap();
        assert!(
            AccountPackage::from_bytes(&package)
                .unwrap()
                .open(b"new public password", &kit)
                .is_err()
        );
        AccountPackage::from_bytes(&package)
            .unwrap()
            .open(b"new public password", &next)
            .unwrap();
        v.lock_in_place().unwrap();
        assert!(v.unlock_recovery(&kit).is_err());
        v.unlock_recovery(&next).unwrap();
        assert_eq!(v.host(id).unwrap().label, "private fixture");
        assert_eq!(items(&v), original);
        // No password knowledge: authorize a second password change with kit.
        let update = v
            .prepare_password_change(
                next.text().as_bytes(),
                true,
                b"third public password",
                params(),
            )
            .unwrap();
        v.apply_credential_update(update).unwrap();
        drop(v);
        let other = tempfile::tempdir().unwrap();
        let copied = other.path().join("another-device.db");
        std::fs::copy(dir.path().join("vault.db"), &copied).unwrap();
        let mut recovered = Vault::open_session(&copied).unwrap();
        assert!(recovered.unlock_in_place(b"new public password").is_err());
        recovered.unlock_recovery(&next).unwrap();
        assert_eq!(recovered.host(id).unwrap().label, "private fixture");
        recovered.lock_in_place().unwrap();
        recovered.unlock_in_place(b"third public password").unwrap();
        assert_eq!(items(&recovered), original);
    }
    #[test]
    fn failed_commit_preserves_header_recovery_package_and_native_factor() {
        let (_dir, mut v, kit, _) = fixture();
        let native_id = format!("{}{}", v.native_namespace().unwrap(), "bc".repeat(16));
        v.enroll_native(&native_id, &[3; 32]).unwrap();
        let old_header = v.store.header.as_ref().unwrap().to_bytes();
        let old_package = v.account_package().unwrap();
        let update = v
            .prepare_password_change(b"old public password", false, b"replacement", params())
            .unwrap();
        v.store.conn.execute_batch("CREATE TRIGGER fail_update BEFORE INSERT ON meta WHEN NEW.key='remote_account_package_v1' BEGIN SELECT RAISE(ABORT,'injected commit failure'); END;").unwrap();
        assert!(v.apply_credential_update(update).is_err());
        assert_eq!(v.store.header.as_ref().unwrap().to_bytes(), old_header);
        assert_eq!(v.account_package().unwrap(), old_package);
        v.lock_in_place().unwrap();
        assert!(v.unlock_in_place(b"replacement").is_err());
        v.unlock_native(&[3; 32]).unwrap();
        v.lock_in_place().unwrap();
        v.unlock_recovery(&kit).unwrap();
        v.lock_in_place().unwrap();
        v.unlock_in_place(b"old public password").unwrap();
    }
    #[test]
    fn older_d4_vault_can_upgrade_with_kit_or_password_authorized_regeneration() {
        let (_dir, mut v, kit, _) = fixture();
        v.store
            .conn
            .execute("DELETE FROM meta WHERE key IN (?1,?2)", [CACHE, PACKAGE])
            .unwrap();
        assert!(
            v.prepare_password_change(b"old public password", false, b"new", params())
                .is_err()
        );
        let update = v
            .prepare_password_change(kit.text().as_bytes(), true, b"new", params())
            .unwrap();
        v.apply_credential_update(update).unwrap();
        assert!(v.account_package().unwrap().is_some());
        v.lock_in_place().unwrap();
        v.unlock_recovery(&kit).unwrap();
        let update = v
            .prepare_password_change(b"new", false, b"next", params())
            .unwrap();
        v.apply_credential_update(update).unwrap();
    }
    #[test]
    fn password_authorized_regeneration_repairs_a_corrupt_oversized_factor() {
        let (_dir, mut v, _kit, id) = fixture();
        v.store
            .conn
            .execute(
                "INSERT OR REPLACE INTO meta VALUES (?1,?2)",
                rusqlite::params![RECOVERY, vec![0u8; 65536]],
            )
            .unwrap();
        v.lock_in_place().unwrap();
        v.unlock_in_place(b"old public password").unwrap();
        let next = RecoveryKit::generate().unwrap();
        assert!(v.prepare_recovery_rotation(b"wrong", &next).is_err());
        let update = v
            .prepare_recovery_rotation(b"old public password", &next)
            .unwrap();
        v.apply_credential_update(update).unwrap();
        v.lock_in_place().unwrap();
        v.unlock_recovery(&next).unwrap();
        assert_eq!(v.host(id).unwrap().label, "private fixture");
        assert!(v.account_package().unwrap().is_some());
    }
    #[test]
    fn prepared_update_cannot_be_applied_to_another_vault() {
        let (_dir, v, _kit, _) = fixture();
        let (_other, mut other, _kit2, _) = fixture();
        let update = v
            .prepare_password_change(b"old public password", false, b"new", params())
            .unwrap();
        assert!(other.apply_credential_update(update).is_err());
        let foreign = v.account_package().unwrap().unwrap();
        other
            .store
            .conn
            .execute(
                "INSERT OR REPLACE INTO meta VALUES (?1,?2)",
                rusqlite::params![PACKAGE, foreign],
            )
            .unwrap();
        assert!(other.account_package().is_err());
        other.lock_in_place().unwrap();
        assert!(other.account_package().is_err());
        assert!(
            other
                .prepare_password_change(b"old public password", false, b"new", params())
                .is_err()
        );
    }
}
