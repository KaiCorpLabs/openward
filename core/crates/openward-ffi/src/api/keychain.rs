//! The keychain as Dart sees it: the keys in `~/.ssh`, making and bringing
//! in keys, and a key's public half (to copy, or to put on a server with
//! [`super::sftp::SftpBrowser::install_public_key`]).

use flutter_rust_bridge::frb;
use openward_app::keychain::{self, KeyFile, NewKey};

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
    pub has_public: bool,
    pub certificate: bool,
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
            has_public: k.has_public,
            certificate: k.certificate,
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
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SshKeyFailure {
    pub kind: SshKeyFailureKind,
    pub message: String,
}

/// A key made or brought in, or why not.
pub struct SshKeyResult {
    pub key: Option<SshKey>,
    pub failure: Option<SshKeyFailure>,
}

fn result(r: Result<KeyFile, keychain::KeyError>) -> SshKeyResult {
    match r {
        Ok(k) => SshKeyResult {
            key: Some(k.into()),
            failure: None,
        },
        Err(e) => SshKeyResult {
            key: None,
            failure: Some(SshKeyFailure {
                message: e.to_string(),
                kind: match e {
                    keychain::KeyError::Exists(_) => SshKeyFailureKind::Exists,
                    keychain::KeyError::BadName(_) => SshKeyFailureKind::BadName,
                    keychain::KeyError::NotAKey => SshKeyFailureKind::NotAKey,
                    keychain::KeyError::Io(_) => SshKeyFailureKind::Io,
                    keychain::KeyError::Make(_) => SshKeyFailureKind::Make,
                },
            }),
        },
    }
}

impl OpenWard {
    /// The private keys in `~/.ssh`, by name.
    #[frb(sync)]
    pub fn keys(&self) -> Vec<SshKey> {
        keychain::list(self.app.local(), &self.app.vault())
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
        result(keychain::generate(
            self.app.local(),
            &self.app.vault(),
            &name,
            kind,
            &comment,
            passphrase.as_deref(),
        ))
    }

    /// Saves a private key given as text as `~/.ssh/<name>`.
    pub fn import_key(&self, name: String, text: String) -> SshKeyResult {
        result(keychain::import(
            self.app.local(),
            &self.app.vault(),
            &name,
            &text,
        ))
    }

    /// A key's public half, as an `authorized_keys` line.
    #[frb(sync)]
    pub fn public_key_line(&self, path: String) -> Option<String> {
        keychain::public_line(self.app.local(), &path).ok()
    }

    /// The local user and computer, as a new key's comment usually says.
    #[frb(sync)]
    pub fn key_comment(&self) -> String {
        let host = std::env::var("HOSTNAME")
            .ok()
            .or_else(|| {
                std::process::Command::new("hostname")
                    .output()
                    .ok()
                    .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned())
            })
            .filter(|h| !h.is_empty())
            .unwrap_or_else(|| "openward".into());
        format!(
            "{}@{}",
            self.app.local().user,
            host.trim_end_matches(".local")
        )
    }
}
