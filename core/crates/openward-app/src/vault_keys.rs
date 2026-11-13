//! SSH private keys stored as encrypted vault items; references stay opaque.
use crate::{
    keychain::{KeyError, KeyFile, NewKey},
    local::Local,
};
use openward_ssh::{
    keyfile,
    russh::keys::{HashAlg, PrivateKey},
};
use openward_vault::{SecretKind, Vault};
use ssh_key::{Algorithm, EcdsaCurve, LineEnding};
use std::{
    fs,
    path::{Path, PathBuf},
};
use zeroize::Zeroizing;

pub fn reference(path: &Path) -> Option<String> {
    let text = path.to_str()?.strip_prefix("vault:")?;
    let id = text.parse::<crate::vault::proto::ItemId>().ok()?;
    (id.to_string() == text).then(|| text.into())
}
pub fn text(vault: &Vault, path: &Path) -> Result<Zeroizing<String>, KeyError> {
    let id = reference(path).ok_or(KeyError::NotAKey)?;
    let s = vault.secret(&id).map_err(|_| KeyError::NotAKey)?;
    if s.info.kind != SecretKind::PrivateKey {
        return Err(KeyError::NotAKey);
    }
    Ok(s.value)
}
pub fn decode(
    vault: &Vault,
    path: &Path,
    phrase: Option<&str>,
) -> Result<PrivateKey, openward_ssh::client::KeyError> {
    let text = text(vault, path)
        .map_err(|_| openward_ssh::client::KeyError::Unreadable("vault key unavailable".into()))?;
    keyfile::decode_secret_key(&text, phrase).map_err(|_| {
        if phrase.is_some() {
            openward_ssh::client::KeyError::WrongPassphrase
        } else {
            openward_ssh::client::KeyError::Encrypted
        }
    })
}
fn info(id: &str, label: &str, text: &str) -> Result<KeyFile, KeyError> {
    let key = keyfile::from_openssh(text).map_err(|_| KeyError::NotAKey)?;
    let public = key.public_key();
    Ok(KeyFile {
        path: format!("vault:{id}"),
        name: label.into(),
        algorithm: Some(public.algorithm().to_string()),
        fingerprint: Some(public.fingerprint(HashAlg::Sha256).to_string()),
        comment: Some(public.comment().as_str_lossy().to_owned()),
        encrypted: key.is_encrypted(),
        security_key: openward_fido::is_security_key(&key),
        has_public: true,
        certificate: false,
        certificate_until: None,
        used_by: Vec::new(),
    })
}
pub fn list(vault: &Vault) -> Vec<KeyFile> {
    vault
        .secret_infos()
        .unwrap_or_default()
        .into_iter()
        .filter(|s| s.kind == SecretKind::PrivateKey)
        .filter_map(|s| {
            let value = vault.secret(&s.id).ok()?;
            info(&s.id, &s.label, &value.value).ok()
        })
        .collect()
}
fn canonical(text: &str, phrase: Option<&str>) -> Result<Zeroizing<String>, KeyError> {
    if text.len() > crate::keys::MAX_PRIVATE as usize {
        return Err(KeyError::NotAKey);
    }
    if keyfile::from_openssh(text).is_ok() {
        return Ok(Zeroizing::new(text.to_owned()));
    }
    let key = keyfile::decode_secret_key(text, phrase).map_err(|_| KeyError::NotAKey)?;
    let key = if let Some(p) = phrase.filter(|s| !s.is_empty()) {
        key.encrypt(&mut rand::rng(), p)
            .map_err(|_| KeyError::WrongPassphrase)?
    } else {
        key
    };
    key.to_openssh(LineEnding::LF)
        .map_err(|_| KeyError::NotAKey)
}
fn new_label(vault: &Vault, name: &str) -> Result<(), KeyError> {
    if name.trim().is_empty() || name.len() > 1024 {
        return Err(KeyError::BadName(name.into()));
    }
    if vault
        .secret_infos()
        .map_err(|_| KeyError::Io("unlock the encrypted vault first".into()))?
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
}
pub fn import(
    vault: &mut Vault,
    name: &str,
    text: &str,
    phrase: Option<&str>,
) -> Result<KeyFile, KeyError> {
    new_label(vault, name)?;
    let text = canonical(text, phrase)?;
    info("", name, &text)?;
    let binding = crate::vault::proto::ItemId::new().to_string();
    let id = vault
        .save_secret(SecretKind::PrivateKey, name, &binding, &text)
        .map_err(|_| KeyError::Io("could not store encrypted key".into()))?;
    let saved = vault
        .secret(&id)
        .map_err(|_| KeyError::Io("could not verify encrypted key".into()))?;
    if *saved.value != *text {
        return Err(KeyError::Io("encrypted key verification failed".into()));
    }
    info(&id, name, &text)
}

pub fn generate(
    vault: &mut Vault,
    name: &str,
    kind: NewKey,
    comment: &str,
    phrase: Option<&str>,
) -> Result<KeyFile, KeyError> {
    let mut rng = rand::rng();
    let alg = match kind {
        NewKey::Ed25519 => Algorithm::Ed25519,
        NewKey::Ecdsa => Algorithm::Ecdsa {
            curve: EcdsaCurve::NistP256,
        },
        NewKey::Rsa => Algorithm::Rsa { hash: None },
    };
    let mut key = ssh_key::PrivateKey::random(&mut rng, alg)
        .map_err(|_| KeyError::Make("key generation failed".into()))?;
    key.set_comment(comment);
    let key = if let Some(phrase) = phrase.filter(|s| !s.is_empty()) {
        key.encrypt(&mut rng, phrase)
            .map_err(|_| KeyError::Make("key encryption failed".into()))?
    } else {
        key
    };
    let text = key
        .to_openssh(LineEnding::LF)
        .map_err(|_| KeyError::NotAKey)?;
    import(vault, name, &text, None)
}
pub fn public(vault: &Vault, path: &Path) -> Result<String, KeyError> {
    let text = text(vault, path)?;
    let key = keyfile::from_openssh(&text).map_err(|_| KeyError::NotAKey)?;
    crate::keychain::public_key_line(key.public_key())
}
pub fn store_file(
    vault: &mut Vault,
    local: &Local,
    path: &str,
    remove: bool,
    phrase: Option<&str>,
) -> Result<KeyFile, KeyError> {
    let from = crate::keychain::absolute(local, path);
    let md = fs::symlink_metadata(&from).map_err(|_| KeyError::NotAKey)?;
    if !md.is_file() {
        return Err(KeyError::NotAKey);
    }
    let original = read_import_file(&from)?;
    let text = canonical(&original, phrase)?;
    let name = from
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or(KeyError::NotAKey)?;
    new_label(vault, name)?;
    info("", name, &text)?;
    let id = crate::vault::proto::ItemId::new();
    let reference = format!("vault:{id}");
    let mut cert = from.as_os_str().to_owned();
    cert.push("-cert.pub");
    let cert = PathBuf::from(cert);
    let rewrite =
        |settings: &crate::vault::proto::Settings| -> Option<crate::vault::proto::Settings> {
            let files = settings.identity_files.as_ref()?;
            if !files
                .iter()
                .any(|p| crate::keychain::absolute(local, p) == from)
            {
                return None;
            }
            let mut next = settings.clone();
            next.identity_files = Some(
                files
                    .iter()
                    .map(|p| {
                        if crate::keychain::absolute(local, p) == from {
                            reference.clone()
                        } else {
                            p.clone()
                        }
                    })
                    .collect(),
            );
            if cert.is_file() {
                let list = next.certificate_files.get_or_insert_with(Vec::new);
                let path = cert.to_string_lossy().into_owned();
                if !list.contains(&path) {
                    list.push(path)
                }
            }
            Some(next)
        };
    use crate::vault::proto::Data;
    let changes = vault
        .items()
        .filter_map(|item| {
            let data = match &item.body.data {
                Data::Host(h) => Data::Host(crate::vault::proto::Host {
                    settings: rewrite(&h.settings)?,
                    ..h.clone()
                }),
                Data::Group(g) => Data::Group(crate::vault::proto::Group {
                    settings: rewrite(&g.settings)?,
                    ..g.clone()
                }),
                Data::Identity(i) => Data::Identity(crate::vault::proto::Identity {
                    settings: rewrite(&i.settings)?,
                    ..i.clone()
                }),
                _ => return None,
            };
            Some((item.id, item.rev, data))
        })
        .collect();
    let data = Data::Secret(crate::vault::proto::StoredSecret {
        kind: SecretKind::PrivateKey,
        label: name.into(),
        binding: format!("file:{}", from.display()),
        value: text.clone(),
        extra: Default::default(),
    });
    vault
        .create_and_update(id, data, changes)
        .map_err(|_| KeyError::Io("could not store key and update references".into()))?;
    let saved = vault
        .secret(&id.to_string())
        .map_err(|_| KeyError::Io("could not verify stored key".into()))?;
    if *saved.value != *text {
        return Err(KeyError::Io("stored key verification failed".into()));
    }
    if remove {
        let current = read_import_file(&from)
            .map_err(|_| KeyError::Io("key saved; source not removed".into()))?;
        if *current != *original {
            return Err(KeyError::Io(
                "key saved; source changed and was not removed".into(),
            ));
        }
        fs::remove_file(&from).map_err(|_| KeyError::Io("key saved; source not removed".into()))?;
    }
    info(&id.to_string(), name, &text)
}

pub fn source_path(vault: &Vault, path: &Path) -> Option<PathBuf> {
    let id = reference(path)?;
    let s = vault.secret(&id).ok()?;
    let file = s.info.binding.strip_prefix("file:")?;
    Some(PathBuf::from(file))
}
pub fn change_phrase(
    vault: &mut Vault,
    path: &Path,
    old: Option<&str>,
    new: Option<&str>,
) -> Result<(), KeyError> {
    let id = reference(path).ok_or(KeyError::NotAKey)?;
    let saved = vault.secret(&id).map_err(|_| KeyError::NotAKey)?;
    let key =
        keyfile::decode_secret_key(&saved.value, old).map_err(|_| KeyError::WrongPassphrase)?;
    let key = if let Some(phrase) = new.filter(|s| !s.is_empty()) {
        key.encrypt(&mut rand::rng(), phrase)
            .map_err(|_| KeyError::WrongPassphrase)?
    } else {
        key
    };
    let text = key
        .to_openssh(LineEnding::LF)
        .map_err(|_| KeyError::NotAKey)?;
    vault
        .save_secret(
            SecretKind::PrivateKey,
            &saved.info.label,
            &saved.info.binding,
            &text,
        )
        .map_err(|_| KeyError::Io("could not store encrypted key".into()))?;
    Ok(())
}

pub fn read_import_file(path: &Path) -> Result<Zeroizing<String>, KeyError> {
    crate::keys::read_text(path, crate::keys::MAX_PRIVATE)
        .map(Zeroizing::new)
        .map_err(|_| KeyError::NotAKey)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::proto::{Data, Host, Settings};
    use openward_crypto::{password::KdfParams, unlock::RecoveryKit};

    fn encrypted(path: &Path) -> Vault {
        drop(Vault::open(path).unwrap());
        let locked = Vault::migrate_with_recovery(
            path,
            b"fixture password",
            KdfParams::new(65536, 1).unwrap(),
            &RecoveryKit::generate().unwrap(),
        )
        .unwrap();
        locked.unlock(b"fixture password").unwrap()
    }
    #[test]
    fn generated_keys_are_opaque_and_keep_their_public_identity_across_phrase_changes_and_lock() {
        let d = tempfile::tempdir().unwrap();
        let mut v = encrypted(&d.path().join("vault.db"));
        let k = generate(
            &mut v,
            "private fixture",
            NewKey::Ed25519,
            "fixture",
            Some("old phrase"),
        )
        .unwrap();
        let path = Path::new(&k.path);
        assert!(reference(path).is_some());
        assert!(k.encrypted);
        let public_before = public(&v, path).unwrap();
        assert!(decode(&v, path, Some("wrong")).is_err());
        assert!(decode(&v, path, Some("old phrase")).is_ok());
        change_phrase(&mut v, path, Some("old phrase"), Some("new phrase")).unwrap();
        assert_eq!(public_before, public(&v, path).unwrap());
        assert!(decode(&v, path, Some("old phrase")).is_err());
        assert!(decode(&v, path, Some("new phrase")).is_ok());
        assert!(generate(&mut v, "private fixture", NewKey::Ed25519, "", None).is_err());
        v.lock_in_place().unwrap();
        assert!(list(&v).is_empty());
        assert!(text(&v, path).is_err());
        v.unlock_in_place(b"fixture password").unwrap();
        assert_eq!(public(&v, path).unwrap(), public_before);
        v.delete_secret(&reference(path).unwrap()).unwrap();
        assert!(decode(&v, path, Some("new phrase")).is_err());
    }
    #[test]
    fn moving_a_file_commits_the_key_and_references_together_and_preserves_source_on_failure() {
        let d = tempfile::tempdir().unwrap();
        let mut v = encrypted(&d.path().join("vault.db"));
        let key = ssh_key::PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
        let original = key.to_openssh(LineEnding::LF).unwrap();
        let source = d.path().join("id_fixture");
        fs::write(&source, original.as_bytes()).unwrap();
        let local = Local {
            home: d.path().into(),
            user: "fixture".into(),
            ssh_dir: d.path().join("ssh"),
            system_ssh_dir: d.path().join("system"),
            agent: None,
        };
        let host = v
            .create(Data::Host(Host {
                label: "fixture".into(),
                address: "fixture.example".into(),
                settings: Settings {
                    identity_files: Some(vec![source.display().to_string()]),
                    ..Default::default()
                },
                ..Default::default()
            }))
            .unwrap();
        let db = rusqlite::Connection::open(d.path().join("vault.db")).unwrap();
        db.execute_batch("CREATE TRIGGER refuse_secret BEFORE INSERT ON items BEGIN SELECT RAISE(FAIL, 'injected'); END;").unwrap();
        assert!(store_file(&mut v, &local, source.to_str().unwrap(), true, None).is_err());
        assert!(source.exists());
        assert!(v.secret_infos().unwrap().is_empty());
        assert_eq!(
            v.effective(host).unwrap().settings.identity_files,
            Some(vec![source.display().to_string()])
        );
        db.execute_batch("DROP TRIGGER refuse_secret").unwrap();
        let saved = store_file(&mut v, &local, source.to_str().unwrap(), true, None).unwrap();
        assert!(!source.exists());
        assert_eq!(
            v.effective(host).unwrap().settings.identity_files,
            Some(vec![saved.path.clone()])
        );
        assert_eq!(
            decode(&v, Path::new(&saved.path), None)
                .unwrap()
                .public_key(),
            key.public_key()
        );
        assert!(list(&v).iter().any(|k| k.path == saved.path));
    }
}
