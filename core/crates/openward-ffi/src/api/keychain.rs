//! The keychain as Dart sees it: the keys in `~/.ssh`, making and bringing
//! in keys, and a key's public half (to copy, or to put on a server with
//! [`super::sftp::SftpBrowser::install_public_key`]).

use flutter_rust_bridge::frb;
use openward_app::keychain::{self, KeyFile, NewKey};
use zeroize::Zeroizing;

use super::app::OpenWard;

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
        let users = keychain::users(self.app.local(), &self.app.vault());
        keychain::list(self.app.local(), &users)
            .into_iter()
            .map(SshKey::from)
            .collect()
    }

    /// Makes `~/.ssh/<name>` and its `.pub`. RSA takes a few seconds.
    pub fn generate_key(
        &self,
        name: String,
        kind: SshKeyType,
        comment: String,
        passphrase: Option<String>,
    ) -> SshKeyResult {
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
            passphrase.as_deref(),
            || keychain::users(self.app.local(), &self.app.vault()),
        ))
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
    ) -> SshKeyResult {
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
                pin: pin.as_deref(),
                verify,
            },
            || keychain::users(self.app.local(), &self.app.vault()),
        ))
    }

    /// Saves a private key given as text as `~/.ssh/<name>`.
    pub fn import_key(&self, name: String, text: String) -> SshKeyResult {
        result(keychain::import(self.app.local(), &name, &text, || {
            keychain::users(self.app.local(), &self.app.vault())
        }))
    }

    /// Deletes a key of `~/.ssh` and its `.pub` and certificate; None if
    /// it went.
    pub fn delete_key(&self, path: String) -> Option<SshKeyFailure> {
        keychain::delete(self.app.local(), &path).err().map(failure)
    }

    /// Renames a key and its companions, and the settings that name it.
    pub fn rename_key(&self, path: String, name: String) -> SshKeyResult {
        result(keychain::rename(
            self.app.local(),
            &mut self.app.vault(),
            &path,
            &name,
        ))
    }

    /// Puts a key behind `new` (none if empty), opened with `old`; None if
    /// it went.
    pub fn change_key_passphrase(
        &self,
        path: String,
        old: Option<String>,
        new: Option<String>,
    ) -> Option<SshKeyFailure> {
        let old = old.map(Zeroizing::new);
        let new = new.map(Zeroizing::new);
        keychain::change_passphrase(
            self.app.local(),
            &path,
            old.as_deref().map(String::as_str),
            new.as_deref().map(String::as_str),
        )
        .err()
        .map(failure)
    }

    /// Where a key's file is, `~` expanded: to export it or show it.
    #[frb(sync)]
    pub fn key_file_path(&self, path: String) -> String {
        keychain::absolute(self.app.local(), &path)
            .to_string_lossy()
            .into_owned()
    }

    /// A key's public half, as an `authorized_keys` line.
    pub fn public_key_line(&self, path: String) -> Option<String> {
        keychain::public_line(self.app.local(), &path).ok()
    }

    /// The local user and computer, as a new key's comment usually says.
    #[frb(sync)]
    pub fn key_comment(&self) -> String {
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
    }
}
