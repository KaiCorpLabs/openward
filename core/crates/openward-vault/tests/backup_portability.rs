//! Fixed public macOS-produced v1 files are restored by all CI platforms.
use openward_crypto::{password::KdfParams, unlock::RecoveryKit};
use openward_vault::{Vault, backup::Snapshot};
use zeroize::Zeroizing;
#[test]
fn the_same_versioned_files_restore_by_password_kit_and_json_on_another_machine() {
    let source = include_bytes!("fixtures/vault-d7.owvault");
    let json = include_bytes!("fixtures/vault-d7.json");
    let kit = RecoveryKit::from_secret(Zeroizing::new([42; 32]));
    for mode in 0..3 {
        let d = tempfile::tempdir().unwrap();
        let path = d.path().join("destination.db");
        drop(Vault::open(&path).unwrap());
        let target_kit = RecoveryKit::from_secret(Zeroizing::new([93; 32]));
        let mut target = Vault::migrate_with_recovery(
            &path,
            b"Different destination password",
            KdfParams::new(65536, 1).unwrap(),
            &target_kit,
        )
        .unwrap()
        .unlock(b"Different destination password")
        .unwrap();
        let snapshot = match mode {
            0 => Snapshot::open(source, b"Public D7 fixture password", false).unwrap(),
            1 => Snapshot::open(source, kit.text().as_bytes(), true).unwrap(),
            _ => Snapshot::parse(json).unwrap(),
        };
        assert_eq!(snapshot.summary().items, 2);
        let prepared = target.prepare_restore(snapshot).unwrap();
        target.apply_restore(prepared).unwrap();
        assert_eq!(target.hosts()[0].1.label, "Public D7 backup fixture");
        let secret = target.secret_infos().unwrap().pop().unwrap();
        assert_eq!(
            *target.secret(&secret.id).unwrap().value,
            "public D7 test secret"
        );
        target.lock_in_place().unwrap();
        assert!(
            target
                .unlock_in_place(b"Public D7 fixture password")
                .is_err()
        );
        assert!(target.unlock_recovery(&kit).is_err());
        target.unlock_recovery(&target_kit).unwrap();
        assert_eq!(target.hosts()[0].1.address, "backup.invalid");
    }
}
