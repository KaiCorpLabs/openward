//! Device-bound SSH P-256 keys. The encrypted vault holds only a public key
//! and a random handle; private material is generated and used by the OS.
use crate::{
    keychain::{KeyError, KeyFile},
    security::{AccessGate, VaultSession},
};
use openward_vault::{SecretKind, Vault, proto::ItemId};
use serde::{Deserialize, Serialize};
use signature::{SignatureEncoding, Verifier};
use ssh_key::{Algorithm, EcdsaCurve, HashAlg, PublicKey};
use std::{path::Path, sync::Arc};

mod native;
pub use native::System;

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum Error {
    #[error("Secure Enclave authentication was cancelled")]
    Cancelled,
    #[error("Secure Enclave with Touch ID is unavailable on this device")]
    Unavailable,
    #[error("this Secure Enclave key is missing on this device")]
    Missing,
    #[error("Secure Enclave key or signature does not match")]
    Invalid,
    #[error("the vault was locked while Secure Enclave was in use")]
    Locked,
    #[error("Secure Enclave operation failed (status {0})")]
    Native(isize),
}

/// A blocking OS operation, called off the network/UI threads. There is no
/// private export method and no software fallback in the production backend.
pub trait Backend: Send + Sync {
    fn create(&self, id: &str) -> Result<PublicKey, Error>;
    fn sign(&self, id: &str, expected: &PublicKey, message: &[u8]) -> Result<Vec<u8>, Error>;
    fn remove(&self, id: &str, expected: &PublicKey) -> Result<(), Error>;
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Descriptor {
    version: u8,
    id: String,
    public_key: String,
}
impl Descriptor {
    pub fn public(&self) -> Result<PublicKey, Error> {
        if self.version != 1
            || !valid_id(&self.id)
            || self.public_key.len() > 4096
            || self.public_key.chars().any(char::is_control)
        {
            return Err(Error::Invalid);
        }
        let p = PublicKey::from_openssh(&self.public_key).map_err(|_| Error::Invalid)?;
        if p.algorithm()
            != (Algorithm::Ecdsa {
                curve: EcdsaCurve::NistP256,
            })
        {
            return Err(Error::Invalid);
        }
        Ok(p)
    }
}
pub(crate) fn valid_id(id: &str) -> bool {
    id.parse::<ItemId>().is_ok_and(|i| i.to_string() == id)
}
pub fn reference(path: &Path) -> Option<String> {
    let id = path.to_str()?.strip_prefix("enclave:")?;
    valid_id(id).then(|| id.into())
}
pub fn descriptor(vault: &Vault, path: &Path) -> Result<Descriptor, Error> {
    let id = reference(path).ok_or(Error::Invalid)?;
    let secret = vault.secret(&id).map_err(|_| Error::Locked)?;
    if secret.info.kind != SecretKind::SecureEnclaveKey || secret.value.len() > 8192 {
        return Err(Error::Invalid);
    }
    let d: Descriptor = serde_json::from_str(&secret.value).map_err(|_| Error::Invalid)?;
    d.public()?;
    if secret.info.binding != d.id {
        return Err(Error::Invalid);
    }
    Ok(d)
}
pub fn public(vault: &Vault, path: &Path) -> Result<String, Error> {
    descriptor(vault, path)?
        .public()?
        .to_openssh()
        .map_err(|_| Error::Invalid)
}
pub fn list(vault: &Vault) -> Vec<KeyFile> {
    vault
        .secret_infos()
        .unwrap_or_default()
        .into_iter()
        .filter(|s| s.kind == SecretKind::SecureEnclaveKey)
        .filter_map(|s| {
            let path = format!("enclave:{}", s.id);
            let p = descriptor(vault, Path::new(&path)).ok()?.public().ok()?;
            Some(KeyFile {
                path,
                name: s.label,
                algorithm: Some("ECDSA P-256 · Secure Enclave".into()),
                fingerprint: Some(p.fingerprint(HashAlg::Sha256).to_string()),
                comment: Some(p.comment().as_str_lossy().to_owned()),
                encrypted: false,
                security_key: false,
                has_public: true,
                certificate: false,
                certificate_until: None,
                used_by: vec![],
            })
        })
        .collect()
}
fn key_error(e: Error) -> KeyError {
    KeyError::Make(e.to_string())
}
fn permitted(gate: &AccessGate, epoch: u64) -> Result<(), Error> {
    gate.check(epoch).map_err(|_| Error::Locked)
}
/// Convert Apple's ASN.1 DER ECDSA response to SSH's nested positive mpints.
/// Verification pins both the message (hashed exactly once) and public key.
fn ssh_signature(public: &PublicKey, message: &[u8], der: &[u8]) -> Result<Vec<u8>, Error> {
    let p256 = p256::ecdsa::Signature::from_der(der).map_err(|_| Error::Invalid)?;
    let sig = ssh_key::Signature::try_from(p256).map_err(|_| Error::Invalid)?;
    Verifier::verify(public, message, &sig).map_err(|_| Error::Invalid)?;
    Ok(sig.to_bytes())
}
pub fn sign(
    backend: &dyn Backend,
    d: &Descriptor,
    gate: &AccessGate,
    epoch: u64,
    message: &[u8],
) -> Result<Vec<u8>, Error> {
    permitted(gate, epoch)?;
    let public = d.public()?;
    let der = backend.sign(&d.id, &public, message)?;
    let signature = ssh_signature(&public, message, &der)?;
    permitted(gate, epoch)?;
    Ok(signature)
}
/// Generate, prove one authenticated signature, then commit the reference.
/// Never hold a gate/vault lock while Touch ID is waiting. A late result is
/// deleted instead of being published after lock (even after unlock again).
pub fn generate(
    session: &VaultSession,
    backend: &dyn Backend,
    name: &str,
    comment: &str,
) -> Result<KeyFile, KeyError> {
    if name.trim().is_empty()
        || name.len() > 1024
        || comment.len() > 1024
        || comment.chars().any(char::is_control)
    {
        return Err(KeyError::BadName(name.into()));
    }
    let gate = session.gate();
    let epoch = gate.ticket().map_err(|_| key_error(Error::Locked))?;
    let check_name = |vault: &Vault| -> Result<(), KeyError> {
        if vault
            .secret_infos()
            .map_err(|_| key_error(Error::Locked))?
            .iter()
            .any(|s| {
                matches!(
                    s.kind,
                    SecretKind::PrivateKey | SecretKind::SecureEnclaveKey
                ) && s.label == name
            })
        {
            return Err(KeyError::Exists(name.into()));
        }
        Ok(())
    };
    check_name(&crate::connect::lock(&session.vault()))?;
    let id = ItemId::new().to_string();
    permitted(&gate, epoch).map_err(key_error)?;
    let mut public = backend.create(&id).map_err(key_error)?;
    public.set_comment(comment);
    let d = Descriptor {
        version: 1,
        id: id.clone(),
        public_key: public.to_openssh().map_err(|_| key_error(Error::Invalid))?,
    };
    let result = (|| {
        let challenge = format!("dev.openward.ssh.secure-enclave.v1/enrol/{id}");
        sign(backend, &d, &gate, epoch, challenge.as_bytes()).map_err(key_error)?;
        let permission = gate.read().map_err(|_| key_error(Error::Locked))?;
        if permission.epoch() != epoch {
            return Err(key_error(Error::Locked));
        }
        let shared = session.vault();
        let mut vault = crate::connect::lock(&shared);
        check_name(&vault)?;
        let text = serde_json::to_string(&d).map_err(|_| key_error(Error::Invalid))?;
        let item = vault
            .save_secret(SecretKind::SecureEnclaveKey, name, &id, &text)
            .map_err(|_| key_error(Error::Locked))?;
        list(&vault)
            .into_iter()
            .find(|k| k.path == format!("enclave:{item}"))
            .ok_or_else(|| key_error(Error::Invalid))
    })();
    if let Err(ref e) = result
        && let Err(cleanup) = backend.remove(&id, &public)
    {
        return Err(KeyError::Make(format!(
            "{e}; could not remove local Secure Enclave key {id}: {cleanup}"
        )));
    }
    result
}
pub fn delete(session: &VaultSession, backend: &dyn Backend, path: &Path) -> Result<(), KeyError> {
    let gate = session.gate();
    let epoch = gate.ticket().map_err(|_| key_error(Error::Locked))?;
    let d = descriptor(&crate::connect::lock(&session.vault()), path).map_err(key_error)?;
    permitted(&gate, epoch).map_err(key_error)?;
    backend
        .remove(&d.id, &d.public().map_err(key_error)?)
        .map_err(key_error)?;
    let permission = gate.read().map_err(|_| key_error(Error::Locked))?;
    if permission.epoch() != epoch {
        return Err(key_error(Error::Locked));
    }
    crate::connect::lock(&session.vault())
        .delete_secret(&reference(path).ok_or(KeyError::NotAKey)?)
        .map_err(|_| KeyError::NotAKey)
}
pub fn signer(
    backend: Arc<dyn Backend>,
    d: Descriptor,
    gate: Arc<AccessGate>,
    epoch: u64,
) -> openward_ssh::client::SignFn {
    Arc::new(move |data| sign(&*backend, &d, &gate, epoch, data).map_err(anyhow::Error::new))
}

#[cfg(test)]
mod tests;
