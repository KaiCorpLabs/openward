use openward_crypto::{Error, VaultKey, plaintext};

#[test]
fn s4_full_snapshot_shape_preserves_opaque_body_bytes() {
    // Independently written canonical CBOR: five fields, clock 24, opaque
    // empty-map body, empty unset/clocks. Same field-clock shape as S4.
    let expected =
        hex::decode("a563686c6318186462617365181864626f647941a065756e736574a066636c6f636b73a0")
            .unwrap();
    assert_eq!(plaintext::snapshot(&[0xa0], 24).unwrap(), expected);
    assert_eq!(plaintext::body(&expected).unwrap(), (24, &[0xa0][..]));
    // A known legacy outer form with a future body is passed through unchanged.
    let old = hex::decode("a264626f647941a0617600").unwrap();
    assert_eq!(plaintext::legacy_body(&old).unwrap(), &[0xa0]);
    for cut in 0..expected.len() {
        assert!(plaintext::body(&expected[..cut]).is_err());
    }
    let mut trailing = old.clone();
    trailing.push(0);
    assert!(plaintext::legacy_body(&trailing).is_err());
    let mut future = old;
    *future.last_mut().unwrap() = 2;
    assert!(matches!(
        plaintext::legacy_body(&future),
        Err(Error::Version(2))
    ));
}

#[test]
fn clocks_reject_duplicates_noncanonical_order_and_future_times() {
    // Prefix through unset; clocks map is supplied below.
    let prefix =
        hex::decode("a563686c6318186462617365181864626f647941a065756e736574a066636c6f636b73")
            .unwrap();
    for map in [
        "a2616101616102",
        "a2616201616102",
        "a161611819",
        "baffffffff",
    ] {
        let mut bytes = prefix.clone();
        bytes.extend(hex::decode(map).unwrap());
        assert!(plaintext::body(&bytes).is_err());
    }
    let mut valid = prefix;
    valid.extend(hex::decode("a2616101616202").unwrap());
    assert_eq!(plaintext::body(&valid).unwrap().0, 24);
}

#[test]
fn metadata_key_has_a_separate_domain_and_depends_on_the_vault_key() {
    let a = VaultKey::from_secret(zeroize::Zeroizing::new([7; 32]));
    let b = VaultKey::from_secret(zeroize::Zeroizing::new([8; 32]));
    assert_ne!(a.secret(), a.metadata_key().unwrap().secret());
    assert_ne!(
        a.metadata_key().unwrap().secret(),
        b.metadata_key().unwrap().secret()
    );
    assert_eq!(
        a.metadata_key().unwrap().secret(),
        a.metadata_key().unwrap().secret()
    );
}
