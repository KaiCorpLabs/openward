//! Platform protection, never a UI-only success boolean. The caller receives a
//! zeroizing key only after the OS has performed the protected operation.
use zeroize::Zeroizing;
pub type Key = Zeroizing<[u8; 32]>;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    TouchId,
    WindowsHello,
    SessionKeyring,
    Unsupported,
}
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("native authentication was cancelled")]
    Cancelled,
    #[error("native protection is unavailable on this device")]
    Unavailable,
    #[error("this device's unlock key is missing")]
    Missing,
    #[error("native protection failed: {0}")]
    Failed(String),
}
pub trait Store: Send + Sync {
    fn kind(&self) -> Kind;
    fn create(&self, id: &str) -> Result<Key, Error>;
    fn read(&self, id: &str) -> Result<Key, Error>;
    fn remove(&self, id: &str) -> Result<(), Error>;
}
#[derive(Default)]
pub struct System;
pub fn kind() -> Kind {
    if cfg!(target_os = "macos") {
        Kind::TouchId
    } else if cfg!(windows) {
        Kind::WindowsHello
    } else if cfg!(target_os = "linux") {
        Kind::SessionKeyring
    } else {
        Kind::Unsupported
    }
}
const SERVICE: &str = "dev.openward.local-unlock.v1";
fn validate(id: &str) -> Result<(), Error> {
    let parts: Vec<_> = id.split('-').collect();
    if parts.len() != 4
        || parts[0] != "v1"
        || parts[1..]
            .iter()
            .any(|p| p.len() != 32 || !p.bytes().all(|b| b.is_ascii_hexdigit()))
    {
        return Err(Error::Failed("invalid local key identifier".into()));
    }
    Ok(())
}
#[cfg(not(windows))]
fn key(bytes: Zeroizing<Vec<u8>>) -> Result<Key, Error> {
    let b: [u8; 32] = bytes
        .as_slice()
        .try_into()
        .map_err(|_| Error::Failed("invalid native key length".into()))?;
    Ok(Zeroizing::new(b))
}
#[cfg(not(windows))]
fn random() -> Result<Key, Error> {
    let mut bytes = Zeroizing::new([0; 32]);
    getrandom::fill(bytes.as_mut())
        .map_err(|_| Error::Failed("secure randomness unavailable".into()))?;
    Ok(bytes)
}

#[cfg(target_os = "macos")]
mod platform {
    use super::*;
    use security_framework::{
        access_control::{ProtectionMode, SecAccessControl},
        passwords::{self, AccessControlOptions, PasswordOptions},
    };
    fn options(id: &str) -> PasswordOptions {
        let mut o = PasswordOptions::new_generic_password(SERVICE, id);
        o.use_protected_keychain();
        o.set_access_synchronized(Some(false));
        o
    }
    fn error(e: security_framework::base::Error) -> Error {
        match e.code() {
            -128 => Error::Cancelled,
            -25300 => Error::Missing,
            -34018 | -25291 | -25308 | -25293 => Error::Unavailable,
            _ => Error::Failed(format!("Keychain status {}", e.code())),
        }
    }
    pub fn create(id: &str) -> Result<Key, Error> {
        let clear = random()?;
        let mut o = options(id);
        let acl = SecAccessControl::create_with_protection(
            Some(ProtectionMode::AccessibleWhenUnlockedThisDeviceOnly),
            AccessControlOptions::BIOMETRY_CURRENT_SET.bits(),
        )
        .map_err(error)?;
        o.set_access_control(acl);
        o.set_label("OpenWard local vault unlock");
        passwords::set_generic_password_options(clear.as_ref(), o).map_err(error)?;
        // Enrolment must prove that this protected item can actually be read;
        // creation alone must not advertise a working Touch ID setup.
        match read(id) {
            Ok(proof) if proof.as_ref() == clear.as_ref() => Ok(clear),
            Ok(_) => {
                let _ = remove(id);
                Err(Error::Failed("native key verification failed".into()))
            }
            Err(e) => {
                let _ = remove(id);
                Err(e)
            }
        }
    }
    pub fn read(id: &str) -> Result<Key, Error> {
        key(Zeroizing::new(
            passwords::generic_password(options(id)).map_err(error)?,
        ))
    }
    pub fn remove(id: &str) -> Result<(), Error> {
        match passwords::delete_generic_password_options(options(id)) {
            Ok(()) => Ok(()),
            Err(e) if e.code() == -25300 => Ok(()),
            Err(e) => Err(error(e)),
        }
    }
}

#[cfg(windows)]
mod platform {
    use super::*;
    use sha2::{Digest, Sha256};
    use windows::{
        Security::{
            Credentials::{KeyCredentialCreationOption, KeyCredentialManager, KeyCredentialStatus},
            Cryptography::CryptographicBuffer,
        },
        core::HSTRING,
    };
    fn error(e: windows::core::Error) -> Error {
        Error::Failed(format!("Windows Hello status 0x{:08x}", e.code().0 as u32))
    }
    fn credential(
        id: &str,
        create: bool,
    ) -> Result<windows::Security::Credentials::KeyCredential, Error> {
        if !KeyCredentialManager::IsSupportedAsync()
            .map_err(error)?
            .join()
            .map_err(error)?
        {
            return Err(Error::Unavailable);
        }
        let name = HSTRING::from(format!("{SERVICE}/{id}"));
        let result = if create {
            KeyCredentialManager::RequestCreateAsync(
                &name,
                KeyCredentialCreationOption::FailIfExists,
            )
            .map_err(error)?
            .join()
            .map_err(error)?
        } else {
            KeyCredentialManager::OpenAsync(&name)
                .map_err(error)?
                .join()
                .map_err(error)?
        };
        match result.Status().map_err(error)? {
            KeyCredentialStatus::Success => result.Credential().map_err(error),
            KeyCredentialStatus::UserCanceled | KeyCredentialStatus::UserPrefersPassword => {
                Err(Error::Cancelled)
            }
            KeyCredentialStatus::NotFound => Err(Error::Missing),
            _ => Err(Error::Unavailable),
        }
    }
    fn derive(
        id: &str,
        credential: windows::Security::Credentials::KeyCredential,
    ) -> Result<Key, Error> {
        // Hello exposes RSA-2048 PKCS#1/SHA256 signing, not a raw exportable key.
        // A dedicated, never-exported deterministic signature is a local secret
        // KDF input. This key is never reused for remote authentication.
        let message = format!("{SERVICE}\0local encryption only\0{id}");
        let challenge =
            CryptographicBuffer::CreateFromByteArray(message.as_bytes()).map_err(error)?;
        let proof = credential
            .RequestSignAsync(&challenge)
            .map_err(error)?
            .join()
            .map_err(error)?;
        if proof.Status().map_err(error)? != KeyCredentialStatus::Success {
            return Err(Error::Cancelled);
        }
        let proof = proof.Result().map_err(error)?;
        if proof.Length().map_err(error)? != 256 {
            return Err(Error::Failed("unexpected Hello signature length".into()));
        }
        let mut signature = Zeroizing::new([0u8; 256]);
        windows::Storage::Streams::DataReader::FromBuffer(&proof)
            .map_err(error)?
            .ReadBytes(signature.as_mut())
            .map_err(error)?;
        let mut h = Sha256::new();
        h.update(b"openward Hello local KEK v1\0");
        h.update(signature.as_slice());
        Ok(Zeroizing::new(h.finalize().into()))
    }
    pub fn create(id: &str) -> Result<Key, Error> {
        match derive(id, credential(id, true)?) {
            Ok(k) => Ok(k),
            Err(e) => {
                let _ = remove(id);
                Err(e)
            }
        }
    }
    pub fn read(id: &str) -> Result<Key, Error> {
        derive(id, credential(id, false)?)
    }
    pub fn remove(id: &str) -> Result<(), Error> {
        KeyCredentialManager::DeleteAsync(&HSTRING::from(format!("{SERVICE}/{id}")))
            .map_err(error)?
            .join()
            .map_err(error)
    }
}

#[cfg(target_os = "linux")]
mod platform {
    use super::*;
    use secret_service::{EncryptionType, blocking::SecretService};
    use std::collections::HashMap;
    fn error(e: secret_service::Error) -> Error {
        Error::Failed(e.to_string())
    }
    fn service<'a>() -> Result<SecretService<'a>, Error> {
        SecretService::connect(EncryptionType::Dh).map_err(error)
    }
    fn attributes(id: &str) -> HashMap<&str, &str> {
        HashMap::from([("application", SERVICE), ("id", id)])
    }
    pub fn create(id: &str) -> Result<Key, Error> {
        let secret = random()?;
        let s = service()?;
        let c = s.get_default_collection().map_err(error)?;
        c.unlock().map_err(error)?;
        c.create_item(
            "OpenWard local vault unlock",
            attributes(id),
            secret.as_ref(),
            false,
            "application/octet-stream",
        )
        .map_err(error)?;
        Ok(secret)
    }
    pub fn read(id: &str) -> Result<Key, Error> {
        let s = service()?;
        let result = s.search_items(attributes(id)).map_err(error)?;
        let item = result
            .unlocked
            .into_iter()
            .chain(result.locked)
            .next()
            .ok_or(Error::Missing)?;
        item.unlock().map_err(error)?;
        key(Zeroizing::new(item.get_secret().map_err(error)?))
    }
    pub fn remove(id: &str) -> Result<(), Error> {
        let s = service()?;
        let result = s.search_items(attributes(id)).map_err(error)?;
        for item in result.unlocked.into_iter().chain(result.locked) {
            item.delete().map_err(error)?;
        }
        Ok(())
    }
}

#[cfg(not(any(target_os = "macos", windows, target_os = "linux")))]
mod platform {
    use super::*;
    pub fn create(_: &str) -> Result<Key, Error> {
        Err(Error::Unavailable)
    }
    pub fn read(_: &str) -> Result<Key, Error> {
        Err(Error::Unavailable)
    }
    pub fn remove(_: &str) -> Result<(), Error> {
        Err(Error::Unavailable)
    }
}
impl Store for System {
    fn kind(&self) -> Kind {
        kind()
    }
    fn create(&self, id: &str) -> Result<Key, Error> {
        validate(id)?;
        platform::create(id)
    }
    fn read(&self, id: &str) -> Result<Key, Error> {
        validate(id)?;
        platform::read(id)
    }
    fn remove(&self, id: &str) -> Result<(), Error> {
        validate(id)?;
        platform::remove(id)
    }
}
