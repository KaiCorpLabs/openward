use openward_crypto::{
    Error,
    hierarchy::{KemSuite, VaultHeader},
    password::KdfParams,
    unlock::{Purpose, RecoveryKit, UnlockBox},
};

#[test]
fn native_and_recovery_are_separate_and_password_rewrap_preserves_only_recovery() {
    let params = KdfParams::new(65536, 1).unwrap();
    let (header, keys) = VaultHeader::create(
        [1; 16],
        [2; 16],
        b"public password",
        params,
        KemSuite::XWingDraft06Pq05,
    )
    .unwrap();
    let kit = RecoveryKit::generate().unwrap();
    let native = UnlockBox::seal(&header, &keys, kit.secret(), Purpose::Native).unwrap();
    let recovery = UnlockBox::seal(&header, &keys, kit.secret(), Purpose::Recovery).unwrap();
    assert_eq!(
        native
            .open(&header, kit.secret(), Purpose::Native)
            .unwrap()
            .vault
            .secret(),
        keys.vault.secret()
    );
    assert!(matches!(
        native.open(&header, kit.secret(), Purpose::Recovery),
        Err(Error::Context)
    ));
    let changed =
        VaultHeader::from_keys([1; 16], [2; 16], 1, b"different password", params, &keys).unwrap();
    assert!(
        native
            .open(&changed, kit.secret(), Purpose::Native)
            .is_err()
    );
    assert_eq!(
        recovery
            .open(&changed, kit.secret(), Purpose::Recovery)
            .unwrap()
            .vault
            .secret(),
        keys.vault.secret()
    );
    for at in 0..174 {
        let mut bytes = recovery.to_bytes();
        bytes[at] ^= 1;
        assert!(
            UnlockBox::from_bytes(&bytes)
                .and_then(|b| b.open(&header, kit.secret(), Purpose::Recovery))
                .is_err()
        );
    }
    for n in 0..174 {
        assert!(UnlockBox::from_bytes(&recovery.to_bytes()[..n]).is_err());
    }
    assert!(recovery.open(&header, &[0; 32], Purpose::Recovery).is_err());
}

#[test]
fn recovery_kit_roundtrips_with_checksum_and_rejects_typoes_and_oversized_text() {
    let kit = RecoveryKit::generate().unwrap();
    let text = kit.text();
    assert_eq!(
        RecoveryKit::parse(&text.to_ascii_lowercase())
            .unwrap()
            .secret(),
        kit.secret()
    );
    let mut typo = text.to_string();
    typo.replace_range(6..7, if &text[6..7] == "0" { "1" } else { "0" });
    assert!(RecoveryKit::parse(&typo).is_err());
    assert!(RecoveryKit::parse(&"x".repeat(257)).is_err());
    assert!(RecoveryKit::parse("OWRK1-🤷").is_err());
}
