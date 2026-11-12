//! Only UI documents leave Rust while unlocked; encryption keys never do.
use super::{app::OpenWard, vault::VaultError};
use flutter_rust_bridge::frb;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LocalDocument {
    History,
    Recent,
}
#[frb(ignore)]
fn name(kind: LocalDocument) -> &'static str {
    match kind {
        LocalDocument::History => "history",
        LocalDocument::Recent => "recent",
    }
}
impl OpenWard {
    #[frb(sync)]
    pub fn read_local_document(&self, kind: LocalDocument) -> Result<Option<String>, VaultError> {
        let gate = self.app.security().gate();
        Ok(
            super::security::access(&gate, false, || self.app.protected().document(name(kind)))??
                .map(|s| s.to_string()),
        )
    }
    #[frb(sync)]
    pub fn write_local_document(
        &self,
        kind: LocalDocument,
        json: String,
    ) -> Result<(), VaultError> {
        let json = zeroize::Zeroizing::new(json);
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            self.app.protected().write_document(name(kind), &json)
        })??;
        Ok(())
    }
    #[frb(sync)]
    pub fn erase_local_document(&self, kind: LocalDocument) -> Result<(), VaultError> {
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            self.app.protected().erase_document(name(kind))
        })??;
        Ok(())
    }
}
