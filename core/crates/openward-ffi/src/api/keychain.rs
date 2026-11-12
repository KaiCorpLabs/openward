//! The keychain as Dart sees it: the keys in `~/.ssh`, making and bringing
//! in keys, and a key's public half (to copy, or to put on a server with
//! [`super::sftp::SftpBrowser::install_public_key`]).

use flutter_rust_bridge::frb;
use openward_app::keychain::{self, KeyFile, NewKey};
use zeroize::Zeroizing;

use super::app::OpenWard;
use super::vault::VaultError;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SshKey {
    /// As settings write it: `~/.ssh/…`.
    pub path: String,
    pub name: String,
    pub algorithm: Option<String>,
    pub fingerprint: Option<String>,
    pub comment: Option<String>,
    pub encrypted: bool,
    /// A security key's (FIDO2): no passphrase needed, it asks for a touch.
    pub security_key: bool,
    pub has_public: bool,
    pub certificate: bool,
    /// When the certificate runs out, in milliseconds since the epoch;
    /// `None` if it never does (or there is none).
    pub certificate_until_ms: Option<i64>,
    /// Hosts, groups and identities that use it.
    pub used_by: Vec<String>,
}

impl From<KeyFile> for SshKey {
    fn from(k: KeyFile) -> Self {
        Self {
            path: k.path,
            name: k.name,
            algorithm: k.algorithm,
            fingerprint: k.fingerprint,
            comment: k.comment,
            encrypted: k.encrypted,
            security_key: k.security_key,
            has_public: k.has_public,
            certificate: k.certificate,
            certificate_until_ms: k.certificate_until.map(|t| {
                t.duration_since(std::time::UNIX_EPOCH)
                    .map_or(0, |d| d.as_millis() as i64)
            }),
            used_by: k.used_by,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SshKeyType {
    Ed25519,
    Ecdsa,
    Rsa,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SshKeyFailureKind {
    Exists,
    BadName,
    NotAKey,
    Io,
    Make,
    WrongPassphrase,
    /// PEM and PuTTY keys change their passphrase with their program.
    NotOpenSsh,
    /// The security key did not make it (`security_key` says why).
    SecurityKey,
}

/// Which kind of key to make on a security key.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SecurityKeyType {
    Ed25519,
    /// ECDSA on P-256: every FIDO2 key has it.
    Ecdsa,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SshKeyFailure {
    pub kind: SshKeyFailureKind,
    pub message: String,
    pub security_key: Option<super::session::SecurityKeyKind>,
}

/// A key made or brought in, or why not.
pub struct SshKeyResult {
    pub key: Option<SshKey>,
    pub failure: Option<SshKeyFailure>,
}

fn failure(e: keychain::KeyError) -> SshKeyFailure {
    SshKeyFailure {
        message: e.to_string(),
        security_key: match &e {
            keychain::KeyError::SecurityKey(f) => Some(super::session::SecurityKeyKind::of(
                openward_app::events::SecurityKeyProblem::of(f),
            )),
            _ => None,
        },
        kind: match e {
            keychain::KeyError::Exists(_) => SshKeyFailureKind::Exists,
            keychain::KeyError::BadName(_) => SshKeyFailureKind::BadName,
            keychain::KeyError::NotAKey => SshKeyFailureKind::NotAKey,
            keychain::KeyError::Io(_) => SshKeyFailureKind::Io,
            keychain::KeyError::Make(_) => SshKeyFailureKind::Make,
            keychain::KeyError::WrongPassphrase => SshKeyFailureKind::WrongPassphrase,
            keychain::KeyError::NotOpenSsh => SshKeyFailureKind::NotOpenSsh,
            keychain::KeyError::SecurityKey(_) => SshKeyFailureKind::SecurityKey,
        },
    }
}

fn result(r: Result<KeyFile, keychain::KeyError>) -> SshKeyResult {
    match r {
        Ok(k) => SshKeyResult {
            key: Some(k.into()),
            failure: None,
        },
        Err(e) => SshKeyResult {
            key: None,
            failure: Some(failure(e)),
        },
    }
}

impl OpenWard {
    /// The private keys in `~/.ssh`, by name.
    pub fn keys(&self) -> Vec<SshKey> {
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            let users = keychain::users(self.app.local(), &self.app.vault());
            let mut keys = keychain::list(self.app.local(), &users);
            let mut stored = openward_app::vault_keys::list(&self.app.vault());
            for key in &mut stored {
                let path = keychain::absolute(self.app.local(), &key.path);
                key.used_by = users
                    .iter()
                    .filter(|(p, _)| p == &path)
                    .map(|(_, name)| name.clone())
                    .collect();
            }
            keys.extend(stored);
            keys.into_iter().map(SshKey::from).collect()
        })
        .unwrap_or_default()
    }

    /// Makes `~/.ssh/<name>` and its `.pub`. RSA takes a few seconds.
    pub fn generate_key(
        &self,
        name: String,
        kind: SshKeyType,
        comment: String,
        passphrase: Option<String>,
    ) -> Result<SshKeyResult, VaultError> {
        let passphrase = passphrase.map(Zeroizing::new);
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            let kind = match kind {
                SshKeyType::Ed25519 => NewKey::Ed25519,
                SshKeyType::Ecdsa => NewKey::Ecdsa,
                SshKeyType::Rsa => NewKey::Rsa,
            };
            // The vault only after the key is made: an RSA key takes seconds.
            result(keychain::generate(
                self.app.local(),
                &name,
                kind,
                &comment,
                passphrase.as_deref().map(String::as_str),
                || keychain::users(self.app.local(), &self.app.vault()),
            ))
        })
        .map_err(Into::into)
    }

    /// Makes `~/.ssh/<name>` on the security key plugged in: it waits
    /// for the touch. `verify`: its PIN at every use (`verify-required`).
    pub fn generate_security_key(
        &self,
        name: String,
        kind: SecurityKeyType,
        comment: String,
        pin: Option<String>,
        verify: bool,
    ) -> Result<SshKeyResult, VaultError> {
        let pin = pin.map(Zeroizing::new);
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            let keys = self.app.security_keys();
            result(keychain::generate_security_key(
                self.app.local(),
                &name,
                &*keys,
                keychain::NewSecurityKey {
                    kind: match kind {
                        SecurityKeyType::Ed25519 => openward_fido::Kind::Ed25519,
                        SecurityKeyType::Ecdsa => openward_fido::Kind::Ecdsa,
                    },
                    comment: &comment,
                    pin: pin.as_deref().map(String::as_str),
                    verify,
                },
                || keychain::users(self.app.local(), &self.app.vault()),
            ))
        })
        .map_err(Into::into)
    }

    /// Saves a private key given as text as `~/.ssh/<name>`.
    pub fn import_key(&self, name: String, text: String) -> Result<SshKeyResult, VaultError> {
        let text = Zeroizing::new(text);
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            result(keychain::import(self.app.local(), &name, &text, || {
                keychain::users(self.app.local(), &self.app.vault())
            }))
        })
        .map_err(Into::into)
    }

    pub fn generate_vault_key(
        &self,
        name: String,
        kind: SshKeyType,
        comment: String,
        passphrase: Option<String>,
    ) -> Result<SshKeyResult, VaultError> {
        let phrase = passphrase.map(Zeroizing::new);
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            result(openward_app::vault_keys::generate(
                &mut self.app.vault(),
                &name,
                match kind {
                    SshKeyType::Ed25519 => NewKey::Ed25519,
                    SshKeyType::Ecdsa => NewKey::Ecdsa,
                    SshKeyType::Rsa => NewKey::Rsa,
                },
                &comment,
                phrase.as_deref().map(String::as_str),
            ))
        })
        .map_err(Into::into)
    }
    pub fn import_vault_key(
        &self,
        name: String,
        text: String,
        passphrase: Option<String>,
    ) -> Result<SshKeyResult, VaultError> {
        let phrase = passphrase.map(Zeroizing::new);
        let text = Zeroizing::new(text);
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            result(openward_app::vault_keys::import(
                &mut self.app.vault(),
                &name,
                &text,
                phrase.as_deref().map(String::as_str),
            ))
        })
        .map_err(Into::into)
    }
    pub fn import_vault_key_file(
        &self,
        name: String,
        path: String,
        passphrase: Option<String>,
    ) -> Result<SshKeyResult, VaultError> {
        let phrase = passphrase.map(Zeroizing::new);
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            let text = match openward_app::vault_keys::read_import_file(std::path::Path::new(&path))
            {
                Ok(t) => t,
                Err(e) => return result(Err(e)),
            };
            result(openward_app::vault_keys::import(
                &mut self.app.vault(),
                &name,
                &text,
                phrase.as_deref().map(String::as_str),
            ))
        })
        .map_err(Into::into)
    }
    pub fn store_key_file(
        &self,
        path: String,
        remove_source: bool,
        passphrase: Option<String>,
    ) -> Result<SshKeyResult, VaultError> {
        let phrase = passphrase.map(Zeroizing::new);
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            result(openward_app::vault_keys::store_file(
                &mut self.app.vault(),
                self.app.local(),
                &path,
                remove_source,
                phrase.as_deref().map(String::as_str),
            ))
        })
        .map_err(Into::into)
    }
    pub fn export_vault_key(&self, path: String, to: String) -> Result<(), VaultError> {
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || -> openward_app::vault::Result<()> {
            let text =
                openward_app::vault_keys::text(&self.app.vault(), std::path::Path::new(&path))
                    .map_err(|_| openward_app::vault::Error::Invalid("key unavailable"))?;
            let dest = std::path::Path::new(&to);
            let mut file = tempfile::NamedTempFile::new_in(
                dest.parent()
                    .ok_or(openward_app::vault::Error::Invalid("invalid destination"))?,
            )?;
            use std::io::Write;
            file.write_all(text.as_bytes())?;
            file.as_file().sync_all()?;
            file.persist_noclobber(dest).map_err(|e| e.error)?;
            Ok(())
        })??;
        Ok(())
    }
    /// Deletes a key of `~/.ssh` and its `.pub` and certificate; None if
    /// it went.
    pub fn delete_key(&self, path: String) -> Result<Option<SshKeyFailure>, VaultError> {
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            if let Some(id) = openward_app::vault_keys::reference(std::path::Path::new(&path)) {
                self.app
                    .vault()
                    .delete_secret(&id)
                    .err()
                    .map(|_| failure(keychain::KeyError::NotAKey))
            } else {
                keychain::delete(self.app.local(), &path).err().map(failure)
            }
        })
        .map_err(Into::into)
    }

    /// Renames a key and its companions, and the settings that name it.
    pub fn rename_key(&self, path: String, name: String) -> Result<SshKeyResult, VaultError> {
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            if let Some(id) = openward_app::vault_keys::reference(std::path::Path::new(&path)) {
                let mut v = self.app.vault();
                let renamed = v.rename_secret(&id, &name);
                return match renamed {
                    Ok(()) => result(
                        openward_app::vault_keys::list(&v)
                            .into_iter()
                            .find(|k| k.path == path)
                            .ok_or(keychain::KeyError::NotAKey),
                    ),
                    Err(_) => result(Err(keychain::KeyError::NotAKey)),
                };
            }
            result(keychain::rename(
                self.app.local(),
                &mut self.app.vault(),
                &path,
                &name,
            ))
        })
        .map_err(Into::into)
    }

    /// Puts a key behind `new` (none if empty), opened with `old`; None if
    /// it went.
    pub fn change_key_passphrase(
        &self,
        path: String,
        old: Option<String>,
        new: Option<String>,
    ) -> Result<Option<SshKeyFailure>, VaultError> {
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            let old = old.map(Zeroizing::new);
            let new = new.map(Zeroizing::new);
            if openward_app::vault_keys::reference(std::path::Path::new(&path)).is_some() {
                return openward_app::vault_keys::change_phrase(
                    &mut self.app.vault(),
                    std::path::Path::new(&path),
                    old.as_deref().map(String::as_str),
                    new.as_deref().map(String::as_str),
                )
                .err()
                .map(failure);
            }
            keychain::change_passphrase(
                self.app.local(),
                &path,
                old.as_deref().map(String::as_str),
                new.as_deref().map(String::as_str),
            )
            .err()
            .map(failure)
        })
        .map_err(Into::into)
    }

    /// Where a key's file is, `~` expanded: to export it or show it.
    #[frb(sync)]
    pub fn key_file_path(&self, path: String) -> String {
        let gate = self.app.security().gate();
        super::security::access(&gate, true, || {
            keychain::absolute(self.app.local(), &path)
                .to_string_lossy()
                .into_owned()
        })
        .unwrap_or_default()
    }

    /// A key's public half, as an `authorized_keys` line.
    pub fn public_key_line(&self, path: String) -> Option<String> {
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            if openward_app::vault_keys::reference(std::path::Path::new(&path)).is_some() {
                openward_app::vault_keys::public(&self.app.vault(), std::path::Path::new(&path))
                    .ok()
            } else {
                keychain::public_line(self.app.local(), &path).ok()
            }
        })
        .unwrap_or_default()
    }

    /// The local user and computer, as a new key's comment usually says.
    #[frb(sync)]
    pub fn key_comment(&self) -> String {
        let gate = self.app.security().gate();
        super::security::access(&gate, true, || {
            // Asked of `hostname` once: apps started from the Finder have no
            // HOSTNAME.
            static HOST: std::sync::OnceLock<String> = std::sync::OnceLock::new();
            let host = HOST.get_or_init(|| {
                std::env::var("HOSTNAME")
                    .ok()
                    .or_else(|| {
                        std::process::Command::new("hostname")
                            .output()
                            .ok()
                            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned())
                    })
                    .filter(|h| !h.is_empty())
                    .unwrap_or_else(|| "openward".into())
            });
            format!(
                "{}@{}",
                self.app.local().user,
                host.trim_end_matches(".local")
            )
        })
        .unwrap_or_default()
    }
}
