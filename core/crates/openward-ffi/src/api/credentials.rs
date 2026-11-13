//! Credential management projects metadata only. There is no secret-value getter.
use super::{app::OpenWard, vault::VaultError};
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CredentialKind {
    Password,
    Passphrase,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SavedCredential {
    pub id: String,
    pub label: String,
    pub kind: CredentialKind,
}
impl OpenWard {
    pub fn saved_credentials(&self) -> Vec<SavedCredential> {
        let gate = self.app.security().gate();
        super::security::access(&gate, true, || {
            self.app
                .vault()
                .secret_infos()
                .unwrap_or_default()
                .into_iter()
                .filter_map(|s| {
                    Some(SavedCredential {
                        id: s.id,
                        label: s.label,
                        kind: match s.kind {
                            openward_app::vault::SecretKind::Password => CredentialKind::Password,
                            openward_app::vault::SecretKind::Passphrase => {
                                CredentialKind::Passphrase
                            }
                            _ => return None,
                        },
                    })
                })
                .collect()
        })
        .unwrap_or_default()
    }
    pub fn forget_credential(&self, id: String) -> Result<(), VaultError> {
        let gate = self.app.security().gate();
        super::security::access(&gate, true, || -> openward_app::vault::Result<()> {
            let mut v = self.app.vault();
            let s = v.secret(&id)?;
            if matches!(
                s.info.kind,
                openward_app::vault::SecretKind::PrivateKey
                    | openward_app::vault::SecretKind::SecureEnclaveKey
            ) {
                return Err(openward_app::vault::Error::Invalid(
                    "delete private keys from the key manager",
                ));
            }
            v.delete_secret(&id)
        })??;
        Ok(())
    }
}
