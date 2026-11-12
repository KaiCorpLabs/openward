//! A public fixture generated on macOS, recovered by the Linux/macOS/Windows CI
//! runners. It includes all D5 credential records and one synthetic host.
use openward_crypto::{password::KdfParams, recovery::AccountPackage, unlock::RecoveryKit};
use openward_vault::Vault;

#[test]
fn another_machine_recovers_the_fixed_vault_and_changes_its_password() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("copied-vault.db");
    std::fs::write(&path, include_bytes!("fixtures/vault-d5-recovery.sqlite")).unwrap();
    let kit = RecoveryKit::from_secret(zeroize::Zeroizing::new([42; 32]));
    let mut vault = Vault::open_session(&path).unwrap();
    assert!(vault.is_locked());
    assert!(vault.unlock_in_place(b"forgotten").is_err());
    vault.unlock_recovery(&kit).unwrap();
    assert_eq!(vault.hosts().len(), 1);
    assert_eq!(vault.hosts()[0].1.label, "Public D5 recovery fixture");
    let account = AccountPackage::from_bytes(&vault.account_package().unwrap().unwrap())
        .unwrap()
        .open(b"Public portability fixture only", &kit)
        .unwrap();
    let update = vault
        .prepare_password_change(
            kit.text().as_bytes(),
            true,
            b"New public fixture password",
            KdfParams::new(65536, 1).unwrap(),
        )
        .unwrap();
    vault.apply_credential_update(update).unwrap();
    drop(vault);
    let mut vault = Vault::open_session(&path).unwrap();
    assert!(
        vault
            .unlock_in_place(b"Public portability fixture only")
            .is_err()
    );
    vault
        .unlock_in_place(b"New public fixture password")
        .unwrap();
    let new_account = AccountPackage::from_bytes(&vault.account_package().unwrap().unwrap())
        .unwrap()
        .open(b"New public fixture password", &kit)
        .unwrap();
    assert_eq!(account.public(), new_account.public());
    vault.lock_in_place().unwrap();
    vault.unlock_recovery(&kit).unwrap();
    assert_eq!(vault.hosts()[0].1.address, "recovery.invalid");
}
