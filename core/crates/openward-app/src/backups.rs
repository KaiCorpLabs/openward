//! File operations stay in Rust. UI receives counts and a file digest only.
use crate::{
    App,
    vault::{self, backup::Snapshot},
};
use sha2::{Digest, Sha256};
use std::{io::Write, path::Path};
use zeroize::Zeroizing;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Format {
    Encrypted,
    Json,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Preview {
    pub format: Format,
    pub items: usize,
    pub secrets: usize,
    pub unreadable: usize,
    pub digest: String,
    pub destination_empty: bool,
}
fn digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|v| format!("{v:02x}"))
        .collect()
}
fn read(
    path: &Path,
    credential: &[u8],
    use_kit: bool,
) -> vault::Result<(Snapshot, Format, String)> {
    let bytes = Zeroizing::new(
        crate::protected::read_optional(path, openward_crypto::backup::MAX_ARCHIVE)?
            .ok_or(vault::Error::Invalid("backup file is missing"))?,
    );
    let hash = digest(&bytes);
    if bytes.starts_with(b"OWVA") {
        Ok((
            Snapshot::open(&bytes, credential, use_kit)?,
            Format::Encrypted,
            hash,
        ))
    } else {
        Ok((Snapshot::parse(&bytes)?, Format::Json, hash))
    }
}
fn stage(path: &Path, bytes: &[u8]) -> vault::Result<tempfile::NamedTempFile> {
    let mut file = tempfile::NamedTempFile::new_in(
        path.parent()
            .ok_or(vault::Error::Invalid("invalid backup destination"))?,
    )?;
    file.write_all(bytes)?;
    file.as_file().sync_all()?;
    Ok(file)
}
fn install(file: tempfile::NamedTempFile, path: &Path) -> vault::Result<()> {
    // Close the writer first for Windows; noclobber also rejects symlink leaves.
    file.into_temp_path()
        .persist_noclobber(path)
        .map_err(|e| e.error)?;
    #[cfg(unix)]
    std::fs::File::open(
        path.parent()
            .ok_or(vault::Error::Invalid("invalid backup destination"))?,
    )?
    .sync_all()?;
    Ok(())
}
impl App {
    pub fn export_vault_backup(
        &self,
        path: &Path,
        format: Format,
        password: Zeroizing<String>,
        acknowledge_plaintext: bool,
    ) -> vault::Result<()> {
        let gate = self.security().gate();
        let epoch = gate.ticket()?;
        let bytes = match format {
            Format::Encrypted => Zeroizing::new(self.vault().export_backup()?),
            Format::Json => self
                .vault()
                .export_json(password.as_bytes(), acknowledge_plaintext)?,
        };
        gate.check(epoch)?;
        let staged = stage(path, &bytes)?;
        let access = gate.read()?;
        if access.epoch() != epoch {
            return Err(vault::Error::Locked);
        }
        install(staged, path)
    }
    pub fn preview_vault_backup(
        &self,
        path: &Path,
        credential: Zeroizing<String>,
        use_kit: bool,
    ) -> vault::Result<Preview> {
        let gate = self.security().gate();
        let epoch = gate.ticket()?;
        let (snapshot, format, digest) = read(path, credential.as_bytes(), use_kit)?;
        let summary = snapshot.summary();
        let destination_empty = self.vault().empty_for_restore().is_ok();
        gate.check(epoch)?;
        Ok(Preview {
            format,
            items: summary.items,
            secrets: summary.secrets,
            unreadable: summary.unreadable,
            digest,
            destination_empty,
        })
    }
    pub fn restore_vault_backup(
        &self,
        path: &Path,
        credential: Zeroizing<String>,
        use_kit: bool,
        expected_digest: &str,
        confirmed: bool,
    ) -> vault::Result<()> {
        if !confirmed {
            return Err(vault::Error::Invalid("confirm backup restoration"));
        }
        let gate = self.security().gate();
        let epoch = gate.ticket()?;
        let (snapshot, _, digest) = read(path, credential.as_bytes(), use_kit)?;
        if expected_digest != digest {
            return Err(vault::Error::Invalid("backup changed after preview"));
        }
        let mut vault = self.vault();
        let import = vault.prepare_restore(snapshot)?;
        let access = gate.read()?;
        if access.epoch() != epoch {
            return Err(vault::Error::Locked);
        }
        vault.apply_restore(import)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Local;
    use crate::vault::{
        Vault,
        proto::{Data, Host},
    };
    use openward_crypto::{password::KdfParams, unlock::RecoveryKit};
    fn fixture() -> (tempfile::TempDir, App) {
        let d = tempfile::tempdir().unwrap();
        let path = d.path().join("vault.db");
        drop(Vault::open(&path).unwrap());
        drop(
            Vault::migrate_with_recovery(
                &path,
                b"Public D7 fixture password",
                KdfParams::new(65536, 1).unwrap(),
                &RecoveryKit::from_secret(Zeroizing::new([42; 32])),
            )
            .unwrap(),
        );
        let app = App::open_as(
            d.path(),
            Local {
                home: d.path().into(),
                user: "fixture".into(),
                ssh_dir: d.path().join("ssh"),
                system_ssh_dir: d.path().join("system"),
                agent: None,
            },
        )
        .unwrap();
        app.security()
            .unlock(b"Public D7 fixture password")
            .unwrap();
        (d, app)
    }
    fn credential() -> Zeroizing<String> {
        Zeroizing::new("Public D7 fixture password".into())
    }
    #[test]
    fn files_never_clobber_and_changed_preview_or_locked_state_never_restores() {
        let (d, source) = fixture();
        source
            .vault()
            .create(Data::Host(Host {
                label: "backup TEST".into(),
                address: "backup.invalid".into(),
                ..Default::default()
            }))
            .unwrap();
        let archive = d.path().join("copy.owvault");
        source
            .export_vault_backup(
                &archive,
                Format::Encrypted,
                Zeroizing::new(String::new()),
                false,
            )
            .unwrap();
        let original = std::fs::read(&archive).unwrap();
        assert!(
            source
                .export_vault_backup(&archive, Format::Encrypted, credential(), false)
                .is_err()
        );
        assert_eq!(std::fs::read(&archive).unwrap(), original);
        assert!(
            source
                .export_vault_backup(
                    &d.path().join("missing").join("full-disk.owvault"),
                    Format::Encrypted,
                    credential(),
                    false
                )
                .is_err()
        );
        let (_other, target) = fixture();
        let view = target
            .preview_vault_backup(&archive, credential(), false)
            .unwrap();
        assert!(view.destination_empty);
        assert_eq!(view.items, 1);
        let mut changed = original.clone();
        *changed.last_mut().unwrap() ^= 1;
        std::fs::write(&archive, changed).unwrap();
        assert!(
            target
                .restore_vault_backup(&archive, credential(), false, &view.digest, true)
                .is_err()
        );
        assert!(target.vault().hosts().is_empty());
        std::fs::write(&archive, &original).unwrap();
        assert!(
            target
                .restore_vault_backup(&archive, credential(), false, "stale", true)
                .is_err()
        );
        assert!(
            target
                .restore_vault_backup(&archive, credential(), false, &view.digest, false)
                .is_err()
        );
        target.lock_vault().unwrap();
        assert!(
            target
                .preview_vault_backup(&archive, credential(), false)
                .is_err()
        );
        assert!(
            target
                .restore_vault_backup(&archive, credential(), false, &view.digest, true)
                .is_err()
        );
        let blocked = d.path().join("blocked.json");
        assert!(
            target
                .export_vault_backup(&blocked, Format::Json, credential(), true)
                .is_err()
        );
        assert!(!blocked.exists());
        target
            .security()
            .unlock(b"Public D7 fixture password")
            .unwrap();
        target
            .restore_vault_backup(&archive, credential(), false, &view.digest, true)
            .unwrap();
        assert_eq!(target.vault().hosts()[0].1.label, "backup TEST");
        assert!(
            !target
                .preview_vault_backup(&archive, credential(), false)
                .unwrap()
                .destination_empty
        );
    }
    #[test]
    fn json_requires_current_password_and_acknowledgement_before_any_file_exists() {
        let (d, app) = fixture();
        let path = d.path().join("clear.json");
        assert!(
            app.export_vault_backup(&path, Format::Json, credential(), false)
                .is_err()
        );
        assert!(!path.exists());
        assert!(
            app.export_vault_backup(&path, Format::Json, Zeroizing::new("wrong".into()), true)
                .is_err()
        );
        assert!(!path.exists());
        app.export_vault_backup(&path, Format::Json, credential(), true)
            .unwrap();
        assert!(
            std::fs::read_to_string(path)
                .unwrap()
                .contains("openward-vault")
        );
    }
}
