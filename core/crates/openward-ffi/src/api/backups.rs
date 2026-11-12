//! No archive contents, credentials, or decrypted private keys return to Dart.
use super::{app::OpenWard, vault::VaultError};
use openward_app::backups::{Format, Preview};
use zeroize::Zeroizing;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BackupFormat {
    Encrypted,
    Json,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackupPreview {
    pub format: BackupFormat,
    pub items: u32,
    pub secrets: u32,
    pub unreadable: u32,
    pub digest: String,
    pub destination_empty: bool,
}
impl From<Preview> for BackupPreview {
    fn from(p: Preview) -> Self {
        Self {
            format: match p.format {
                Format::Encrypted => BackupFormat::Encrypted,
                Format::Json => BackupFormat::Json,
            },
            items: p.items as u32,
            secrets: p.secrets as u32,
            unreadable: p.unreadable as u32,
            digest: p.digest,
            destination_empty: p.destination_empty,
        }
    }
}
impl OpenWard {
    pub fn export_vault_backup(
        &self,
        path: String,
        format: BackupFormat,
        password: String,
        acknowledge_plaintext: bool,
    ) -> Result<(), VaultError> {
        self.app
            .export_vault_backup(
                std::path::Path::new(&path),
                match format {
                    BackupFormat::Encrypted => Format::Encrypted,
                    BackupFormat::Json => Format::Json,
                },
                Zeroizing::new(password),
                acknowledge_plaintext,
            )
            .map_err(Into::into)
    }
    pub fn preview_vault_backup(
        &self,
        path: String,
        credential: String,
        use_kit: bool,
    ) -> Result<BackupPreview, VaultError> {
        self.app
            .preview_vault_backup(
                std::path::Path::new(&path),
                Zeroizing::new(credential),
                use_kit,
            )
            .map(Into::into)
            .map_err(Into::into)
    }
    pub fn restore_vault_backup(
        &self,
        path: String,
        credential: String,
        use_kit: bool,
        expected_digest: String,
        confirmed: bool,
    ) -> Result<(), VaultError> {
        self.app
            .restore_vault_backup(
                std::path::Path::new(&path),
                Zeroizing::new(credential),
                use_kit,
                &expected_digest,
                confirmed,
            )
            .map_err(Into::into)
    }
}
