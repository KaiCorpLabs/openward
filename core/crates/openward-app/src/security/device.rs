//! Explicit beta "Later" protection by the OS session, separate from biometrics.
//! This is never used as an implicit fallback for Touch ID or Windows Hello.
use super::native::{Error, Key, Kind, Store};
#[cfg(any(target_os = "macos", target_os = "ios", target_os = "linux", windows))]
use zeroize::Zeroizing;
#[cfg(any(target_os = "macos", target_os = "ios", target_os = "linux", windows))]
const SERVICE: &str = "dev.openward.device-only.v1";
pub struct System;
fn validate(id: &str) -> Result<(), Error> {
    let parts: Vec<_> = id.split('-').collect();
    if parts.len() != 4
        || parts[0] != "v1"
        || parts[1..]
            .iter()
            .any(|p| p.len() != 32 || !p.bytes().all(|b| b.is_ascii_hexdigit()))
    {
        return Err(Error::Failed("invalid device identifier".into()));
    }
    Ok(())
}
#[cfg(any(target_os = "macos", target_os = "ios", target_os = "linux", windows))]
fn random() -> Result<Key, Error> {
    let mut k = Zeroizing::new([0; 32]);
    getrandom::fill(k.as_mut()).map_err(|_| Error::Unavailable)?;
    Ok(k)
}
#[cfg(any(target_os = "macos", target_os = "ios"))]
mod platform {
    use super::*;
    use security_framework::passwords::{self, PasswordOptions};
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
            _ => Error::Unavailable,
        }
    }
    pub fn create(id: &str) -> Result<Key, Error> {
        let key = random()?;
        passwords::set_generic_password_options(key.as_ref(), options(id)).map_err(error)?;
        Ok(key)
    }
    pub fn read(id: &str) -> Result<Key, Error> {
        let bytes = Zeroizing::new(passwords::generic_password(options(id)).map_err(error)?);
        if bytes.len() != 32 {
            return Err(Error::Missing);
        }
        let mut key = Zeroizing::new([0; 32]);
        key.copy_from_slice(&bytes);
        Ok(key)
    }
    pub fn remove(id: &str) -> Result<(), Error> {
        match passwords::delete_generic_password_options(options(id)) {
            Ok(()) => Ok(()),
            Err(e) if e.code() == -25300 => Ok(()),
            Err(e) => Err(error(e)),
        }
    }
}
#[cfg(target_os = "linux")]
mod platform {
    use super::*;
    use secret_service::{EncryptionType, blocking::SecretService};
    use std::collections::HashMap;
    pub fn create(id: &str) -> Result<Key, Error> {
        let key = random()?;
        let s = SecretService::connect(EncryptionType::Dh).map_err(|_| Error::Unavailable)?;
        let c = s.get_default_collection().map_err(|_| Error::Unavailable)?;
        c.unlock().map_err(|_| Error::Cancelled)?;
        c.create_item(
            "OpenWard temporary device protection",
            HashMap::from([("application", SERVICE), ("id", id)]),
            key.as_ref(),
            false,
            "application/octet-stream",
        )
        .map_err(|_| Error::Unavailable)?;
        Ok(key)
    }
    pub fn read(id: &str) -> Result<Key, Error> {
        let s = SecretService::connect(EncryptionType::Dh).map_err(|_| Error::Unavailable)?;
        let items = s
            .search_items(HashMap::from([("application", SERVICE), ("id", id)]))
            .map_err(|_| Error::Unavailable)?;
        let item = items
            .unlocked
            .into_iter()
            .chain(items.locked)
            .next()
            .ok_or(Error::Missing)?;
        item.unlock().map_err(|_| Error::Cancelled)?;
        let bytes = Zeroizing::new(item.get_secret().map_err(|_| Error::Unavailable)?);
        if bytes.len() != 32 {
            return Err(Error::Missing);
        }
        let mut key = Zeroizing::new([0; 32]);
        key.copy_from_slice(&bytes);
        Ok(key)
    }
    pub fn remove(id: &str) -> Result<(), Error> {
        let s = SecretService::connect(EncryptionType::Dh).map_err(|_| Error::Unavailable)?;
        let items = s
            .search_items(HashMap::from([("application", SERVICE), ("id", id)]))
            .map_err(|_| Error::Unavailable)?;
        for item in items.unlocked.into_iter().chain(items.locked) {
            item.delete().map_err(|_| Error::Unavailable)?;
        }
        Ok(())
    }
}
#[cfg(windows)]
mod platform {
    use super::*;
    use windows::{
        Security::Credentials::{PasswordCredential, PasswordVault},
        core::HSTRING,
    };
    pub fn create(id: &str) -> Result<Key, Error> {
        let key = random()?;
        let text = Zeroizing::new(key.iter().map(|b| format!("{b:02x}")).collect::<String>());
        let credential = PasswordCredential::CreatePasswordCredential(
            &HSTRING::from(SERVICE),
            &HSTRING::from(id),
            &HSTRING::from(text.as_str()),
        )
        .map_err(|_| Error::Unavailable)?;
        PasswordVault::new()
            .map_err(|_| Error::Unavailable)?
            .Add(&credential)
            .map_err(|_| Error::Unavailable)?;
        Ok(key)
    }
    pub fn read(id: &str) -> Result<Key, Error> {
        let credential = PasswordVault::new()
            .map_err(|_| Error::Unavailable)?
            .Retrieve(&HSTRING::from(SERVICE), &HSTRING::from(id))
            .map_err(|_| Error::Missing)?;
        credential
            .RetrievePassword()
            .map_err(|_| Error::Unavailable)?;
        let text = Zeroizing::new(
            credential
                .Password()
                .map_err(|_| Error::Unavailable)?
                .to_string(),
        );
        if text.len() != 64 {
            return Err(Error::Missing);
        }
        let mut key = Zeroizing::new([0; 32]);
        for (i, p) in text.as_bytes().as_chunks::<2>().0.iter().enumerate() {
            let digit = |b| match b {
                b'0'..=b'9' => Ok(b - b'0'),
                b'a'..=b'f' => Ok(b - b'a' + 10),
                _ => Err(Error::Missing),
            };
            key[i] = digit(p[0])? * 16 + digit(p[1])?;
        }
        Ok(key)
    }
    pub fn remove(id: &str) -> Result<(), Error> {
        let vault = PasswordVault::new().map_err(|_| Error::Unavailable)?;
        if let Ok(credential) = vault.Retrieve(&HSTRING::from(SERVICE), &HSTRING::from(id)) {
            vault.Remove(&credential).map_err(|_| Error::Unavailable)?;
        }
        Ok(())
    }
}
#[cfg(target_os = "android")]
mod platform {
    use super::*;
    use crate::security::android;
    pub fn create(id: &str) -> Result<Key, Error> {
        android::create(id, false)
    }
    pub fn read(id: &str) -> Result<Key, Error> {
        android::read(id, false)
    }
    pub fn remove(id: &str) -> Result<(), Error> {
        android::remove(id, false)
    }
}
#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "linux",
    windows,
    target_os = "android"
)))]
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
        if cfg!(any(
            target_os = "macos",
            target_os = "ios",
            target_os = "linux",
            windows,
            target_os = "android"
        )) {
            Kind::SessionKeyring
        } else {
            Kind::Unsupported
        }
    }
    fn create(&self, id: &str) -> Result<Key, Error> {
        validate(id)?;
        let key = platform::create(id)?;
        match platform::read(id) {
            Ok(proof) if proof.as_ref() == key.as_ref() => Ok(key),
            _ => {
                let _ = platform::remove(id);
                Err(Error::Unavailable)
            }
        }
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
