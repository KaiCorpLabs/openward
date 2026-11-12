use openward_crypto::{
    hierarchy::{AccountKey, KemSuite, VaultHeader},
    password::KdfParams,
    recovery::{AccountPackage, open_local_kit, seal_local_kit},
    unlock::RecoveryKit,
};
fn params() -> KdfParams {
    KdfParams::new(65536, 1).unwrap()
}
#[test]
fn remote_account_requires_both_factors_and_only_contains_the_account() {
    let (header, keys) = VaultHeader::create(
        [1; 16],
        [2; 16],
        b"test password",
        params(),
        KemSuite::XWingDraft06Pq05,
    )
    .unwrap();
    let kit = RecoveryKit::generate().unwrap();
    let package = AccountPackage::seal(&keys.account, b"test password", &kit, params()).unwrap();
    let bytes = package.to_bytes();
    let parsed = AccountPackage::from_bytes(&bytes).unwrap();
    let recovered = parsed.open(b"test password", &kit).unwrap();
    assert_eq!(recovered.public(), header.account());
    let wrapped = keys.account.wrap([1; 16], 1, &keys.vault).unwrap();
    assert_eq!(
        recovered.unwrap(&wrapped, [1; 16], 1).unwrap().secret(),
        keys.vault.secret()
    );
    let device = openward_crypto::hierarchy::DeviceKey::generate().unwrap();
    recovered
        .certify([9; 16], &device.signer().verifying_key())
        .verify(recovered.public(), [9; 16])
        .unwrap();
    let wrong = RecoveryKit::generate().unwrap();
    assert!(parsed.open(b"test password", &wrong).is_err());
    assert!(parsed.open(b"wrong password", &kit).is_err());
    assert!(!bytes.windows(32).any(|b| b == kit.secret()));
    assert!(
        !bytes
            .windows(64)
            .any(|b| b == keys.account.secret().as_ref())
    );
    let mut changed = bytes.clone();
    *changed.last_mut().unwrap() ^= 1;
    assert!(
        AccountPackage::from_bytes(&changed)
            .unwrap()
            .open(b"test password", &kit)
            .is_err()
    );
    for end in 0..bytes.len() {
        assert!(AccountPackage::from_bytes(&bytes[..end]).is_err());
    }
    let mut trailing = bytes.clone();
    trailing.push(0);
    assert!(AccountPackage::from_bytes(&trailing).is_err());
    // Salt/KDF fields are parsed and bounded before Argon2 allocation.
    let offset = 7 + header.account().to_bytes().len();
    let mut excessive = bytes;
    excessive[offset..offset + 4].copy_from_slice(&u32::MAX.to_be_bytes());
    assert!(AccountPackage::from_bytes(&excessive).is_err());
}
#[test]
fn local_cache_is_bound_to_vault_and_device_and_survives_password_rewrap() {
    let (h, k) =
        VaultHeader::create([3; 16], [4; 16], b"old", params(), KemSuite::X25519Rfc9180).unwrap();
    let kit = RecoveryKit::generate().unwrap();
    let bytes = seal_local_kit(&h, &k, &kit).unwrap();
    assert_eq!(
        open_local_kit(&bytes, &h, &k).unwrap().secret(),
        kit.secret()
    );
    let rewrapped = VaultHeader::from_keys([3; 16], [4; 16], 1, b"new", params(), &k).unwrap();
    assert_eq!(
        open_local_kit(&bytes, &rewrapped, &k).unwrap().secret(),
        kit.secret()
    );
    let other = VaultHeader::from_keys([3; 16], [5; 16], 1, b"new", params(), &k).unwrap();
    assert!(open_local_kit(&bytes, &other, &k).is_err());
    let mut changed = bytes;
    changed[29] ^= 1;
    assert!(open_local_kit(&changed, &h, &k).is_err());
    let foreign = AccountKey::generate(KemSuite::X25519Rfc9180).unwrap();
    assert_ne!(foreign.public(), h.account());
}

#[test]
fn portable_account_fixture_opens_on_every_ci_platform() {
    let fixture: serde_json::Value =
        serde_json::from_str(include_str!("vectors/recovery-v1.json")).unwrap();
    let kit = RecoveryKit::parse(fixture["kit"].as_str().unwrap()).unwrap();
    let package =
        AccountPackage::from_bytes(&hex::decode(fixture["package_hex"].as_str().unwrap()).unwrap())
            .unwrap();
    let account = package
        .open(fixture["password"].as_str().unwrap().as_bytes(), &kit)
        .unwrap();
    assert_eq!(
        hex::encode(account.public().to_bytes()),
        fixture["account_hex"].as_str().unwrap()
    );
}
