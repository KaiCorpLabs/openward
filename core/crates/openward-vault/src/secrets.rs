//! Secret values use the same signed v1 envelopes and revision graph as items.
//! Public projections contain no values; Debug is redacted and values zeroize.
pub use crate::proto::SecretKind;
use crate::proto::{Data, ItemId, StoredSecret};
use crate::{Error, Result, Vault};
use openward_crypto::local::LocalKey;
use zeroize::Zeroizing;

pub struct Secret {
    pub info: SecretInfo,
    pub value: Zeroizing<String>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SecretInfo {
    pub id: String,
    pub kind: SecretKind,
    pub label: String,
    pub binding: String,
}
impl Vault {
    /// Format3 keeps older clients (which write auxiliary plaintext) out.
    /// Durably commit this barrier before replacing any auxiliary file.
    pub fn require_protected_storage(&self) -> Result<()> {
        self.local_data_key()?;
        let version: i64 = self
            .store
            .conn
            .pragma_query_value(None, "user_version", |r| r.get(0))?;
        if version == 2 {
            self.store.conn.pragma_update(None, "synchronous", "FULL")?;
            self.store.conn.pragma_update(None, "user_version", 3)?;
        }
        Ok(())
    }
    pub fn local_data_key(&self) -> Result<LocalKey> {
        let h = self.store.header.as_ref().ok_or(Error::Locked)?;
        let k = self.store.keys.as_ref().ok_or(Error::Locked)?;
        Ok(LocalKey::derive(
            &k.vault,
            &[h.vault_id().as_slice(), h.device_id().as_slice()].concat(),
        )?)
    }
    pub fn secret_infos(&self) -> Result<Vec<SecretInfo>> {
        self.local_data_key()?;
        let mut out: Vec<_> = self
            .items
            .values()
            .filter_map(|i| match &i.body.data {
                Data::Secret(s) => Some(SecretInfo {
                    id: i.id.to_string(),
                    kind: s.kind,
                    label: s.label.clone(),
                    binding: s.binding.clone(),
                }),
                _ => None,
            })
            .collect();
        out.sort_by(|a, b| a.id.cmp(&b.id));
        Ok(out)
    }
    pub fn secret(&self, id: &str) -> Result<Secret> {
        self.local_data_key()?;
        let id = id
            .parse::<ItemId>()
            .map_err(|_| Error::Invalid("invalid credential id"))?;
        let item = self.item(id)?;
        let Data::Secret(s) = &item.body.data else {
            return Err(Error::Invalid("not a credential"));
        };
        Ok(Secret {
            info: SecretInfo {
                id: id.to_string(),
                kind: s.kind,
                label: s.label.clone(),
                binding: s.binding.clone(),
            },
            value: s.value.clone(),
        })
    }
    pub fn find_secret(&self, kind: SecretKind, binding: &str) -> Result<Option<Secret>> {
        for info in self.secret_infos()? {
            if info.kind == kind && info.binding == binding {
                return self.secret(&info.id).map(Some);
            }
        }
        Ok(None)
    }
    pub fn save_secret(
        &mut self,
        kind: SecretKind,
        label: &str,
        binding: &str,
        value: &str,
    ) -> Result<String> {
        if label.len() > 1024
            || binding.len() > 8192
            || value.is_empty()
            || value.len() > 1024 * 1024
        {
            return Err(Error::Invalid("invalid credential size"));
        }
        self.local_data_key()?;
        let old = self.find_secret(kind, binding)?.map(|s| s.info.id);
        let extra = old
            .as_ref()
            .and_then(|id| id.parse::<ItemId>().ok())
            .and_then(|id| self.items.get(&id))
            .and_then(|i| match &i.body.data {
                Data::Secret(s) => Some(s.extra.clone()),
                _ => None,
            })
            .unwrap_or_default();
        let data = Data::Secret(StoredSecret {
            extra,
            kind,
            label: label.into(),
            binding: binding.into(),
            value: Zeroizing::new(value.into()),
        });
        let id = if let Some(id) = old {
            let id = id
                .parse::<ItemId>()
                .map_err(|_| Error::Invalid("invalid credential id"))?;
            let rev = self.item(id)?.rev;
            self.update(id, rev, data)?;
            id
        } else {
            self.create(data)?
        };
        Ok(id.to_string())
    }
    pub fn delete_secret(&mut self, id: &str) -> Result<()> {
        self.secret(id)?;
        let id = id
            .parse()
            .map_err(|_| Error::Invalid("invalid credential id"))?;
        self.delete(id)
    }
    pub fn rename_secret(&mut self, id: &str, label: &str) -> Result<()> {
        let s = self.secret(id)?;
        self.save_secret(s.info.kind, label, &s.info.binding, &s.value)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::{Data, StoredSecret};
    #[test]
    fn secrets_require_encryption_are_redacted_persist_and_disappear_when_locked() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let mut plain = Vault::open(&path).unwrap();
        let secret = Data::Secret(StoredSecret {
            kind: SecretKind::Password,
            label: "fixture".into(),
            binding: "fixture-binding".into(),
            value: Zeroizing::new("private-value-TEST".into()),
            extra: Default::default(),
        });
        assert!(!format!("{secret:?}").contains("private-value"));
        assert!(plain.create(secret).is_err());
        drop(plain);
        drop(
            Vault::migrate_with_recovery(
                &path,
                b"public password",
                openward_crypto::password::KdfParams::new(65536, 1).unwrap(),
                &openward_crypto::unlock::RecoveryKit::generate().unwrap(),
            )
            .unwrap(),
        );
        let mut v = Vault::open_session(&path).unwrap();
        assert!(v.secret_infos().is_err());
        v.unlock_in_place(b"public password").unwrap();
        let id = v
            .save_secret(
                SecretKind::Password,
                "fixture host",
                "server-key-user-port",
                "private-value-TEST",
            )
            .unwrap();
        assert_eq!(*v.secret(&id).unwrap().value, "private-value-TEST");
        assert!(
            v.find_secret(SecretKind::Password, "different host key")
                .unwrap()
                .is_none()
        );
        let id2 = v
            .save_secret(
                SecretKind::Password,
                "fixture host",
                "server-key-user-port",
                "replacement-TEST",
            )
            .unwrap();
        assert_eq!(id, id2);
        v.lock_in_place().unwrap();
        assert!(v.secret(&id).is_err());
        drop(v);
        for file in std::fs::read_dir(dir.path()).unwrap() {
            let f = file.unwrap().path();
            if f.is_file() {
                let b = std::fs::read(f).unwrap();
                for needle in [
                    b"private-value-TEST".as_slice(),
                    b"replacement-TEST",
                    b"fixture host",
                ] {
                    assert!(!b.windows(needle.len()).any(|w| w == needle));
                }
            }
        }
        let mut v = Vault::open_session(&path).unwrap();
        v.unlock_in_place(b"public password").unwrap();
        assert_eq!(*v.secret(&id).unwrap().value, "replacement-TEST");
        v.delete_secret(&id).unwrap();
        assert!(v.secret_infos().unwrap().is_empty());
    }
}
