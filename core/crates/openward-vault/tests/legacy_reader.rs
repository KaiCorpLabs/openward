//! Frozen format1 Store from main5e10cdb: an independent old-reader oracle.
//! The copied backup tests describe the old latent behavior, not production.
pub use openward_vault::{Error, Result};
#[allow(dead_code)]
#[path = "support/store_5e10.rs"]
mod legacy;

#[test]
fn the_existing_0_3_reader_refuses_format2_instead_of_hiding_every_item() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    drop(legacy::Store::open(&path).unwrap());
    let params = openward_crypto::password::KdfParams::new(64 * 1024, 1).unwrap();
    drop(openward_vault::Vault::migrate_encrypted(&path, b"test password", params).unwrap());
    assert!(matches!(
        legacy::Store::open(&path),
        Err(Error::NewerFormat(2))
    ));
    assert!(openward_vault::Vault::open_encrypted(&path, b"test password").is_ok());
}
