use openward_crypto::{
    Error, VaultKey,
    envelope::Envelope,
    hierarchy::{
        AccountKey, AccountPublic, DeviceCertificate, DeviceKey, KemSuite, VaultHeader,
        WrappedVaultKey,
    },
    password::{KdfParams, MIN_MEMORY_KIB, PasswordBox},
};
use zeroize::Zeroizing;

#[test]
fn argon2id_matches_rfc9106_section_5_3() {
    // This primitive KAT deliberately uses the RFC's 32 KiB. Public KdfParams
    // rejects that memory size; the local-vault floor is tested separately.
    use argon2::{Algorithm, Argon2, AssociatedData, ParamsBuilder, Version};
    let params = ParamsBuilder::new()
        .m_cost(32)
        .t_cost(3)
        .p_cost(4)
        .data(AssociatedData::new(&[4; 12]).unwrap())
        .build()
        .unwrap();
    let mut memory = Zeroizing::new(vec![argon2::Block::default(); 32]);
    let mut tag = Zeroizing::new([0; 32]);
    Argon2::new_with_secret(&[3; 8], Algorithm::Argon2id, Version::V0x13, params)
        .unwrap()
        .hash_password_into_with_memory(&[1; 32], &[2; 16], tag.as_mut(), memory.as_mut_slice())
        .unwrap();
    assert_eq!(
        hex::encode(*tag),
        "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659"
    );
}

#[test]
fn account_certificates_and_generations_bind_every_recipient_context() {
    for suite in [KemSuite::XWingDraft06Pq05, KemSuite::X25519Rfc9180] {
        let a = AccountKey::generate(suite).unwrap();
        let other = AccountKey::generate(suite).unwrap();
        assert_eq!(
            a.public(),
            &AccountPublic::from_bytes(&a.public().to_bytes()).unwrap()
        );
        let device = DeviceKey::generate().unwrap();
        let cert = a.certify([3; 16], &device.signer().verifying_key());
        let cert = DeviceCertificate::from_bytes(&cert.to_bytes()).unwrap();
        assert_eq!(
            cert.verify(a.public(), [3; 16]).unwrap(),
            device.signer().verifying_key()
        );
        assert!(cert.verify(other.public(), [3; 16]).is_err());
        assert!(cert.verify(a.public(), [4; 16]).is_err());
        let key = VaultKey::generate().unwrap();
        let wrap = a.wrap([1; 16], 1, &key).unwrap();
        let wrap = WrappedVaultKey::from_bytes(&wrap.to_bytes()).unwrap();
        assert_eq!(a.unwrap(&wrap, [1; 16], 1).unwrap().secret(), key.secret());
        assert!(a.unwrap(&wrap, [2; 16], 1).is_err());
        assert!(a.unwrap(&wrap, [1; 16], 2).is_err());
        assert!(other.unwrap(&wrap, [1; 16], 1).is_err());
        for index in [5, 6, 22, 26, 58, wrap.to_bytes().len() - 1] {
            let mut bad = wrap.to_bytes();
            bad[index] ^= 1;
            assert!(
                WrappedVaultKey::from_bytes(&bad)
                    .and_then(|w| a.unwrap(&w, [1; 16], 1))
                    .is_err()
            );
        }
        // A fresh generation has a different vault key; rewrapping does not
        // change historical keys, which remain readable by their own slot.
        let next = VaultKey::generate().unwrap();
        let wrap2 = a.wrap([1; 16], 2, &next).unwrap();
        assert_eq!(
            a.unwrap(&wrap2, [1; 16], 2).unwrap().secret(),
            next.secret()
        );
        assert_ne!(next.secret(), key.secret());
    }
}

#[test]
fn local_header_recovers_certified_writer_and_vault_without_plain_seeds() {
    let params = KdfParams::new(MIN_MEMORY_KIB, 1).unwrap();
    let (header, keys) = VaultHeader::create(
        [1; 16],
        [2; 16],
        b"test master password",
        params,
        KemSuite::XWingDraft06Pq05,
    )
    .unwrap();
    let bytes = header.to_bytes();
    assert!(
        !bytes
            .windows(64)
            .any(|w| w == keys.account.secret().as_slice())
    );
    let parsed = VaultHeader::from_bytes(&bytes).unwrap();
    let opened = parsed.unlock(b"test master password").unwrap();
    assert_eq!(opened.account.public(), keys.account.public());
    assert_eq!(opened.vault.secret(), keys.vault.secret());
    assert!(parsed.unlock(b"incorrect password").is_err());
    let envelope = Envelope::seal(
        openward_crypto::envelope::Header {
            vault: header.vault_id(),
            item: [4; 16],
            device: header.device_id(),
            key_gen: 1,
            parents: vec![],
        },
        b"private body",
        &keys.vault,
        keys.device.signer(),
    )
    .unwrap();
    let writer = header
        .certificate()
        .verify(header.account(), header.device_id())
        .unwrap();
    assert_eq!(
        Envelope::open_received(
            &envelope.to_bytes(),
            envelope.header().slot(),
            &opened.vault,
            &writer
        )
        .unwrap()
        .as_slice(),
        b"private body"
    );
    // Rewrap the same hierarchy with another password; ciphertext items and
    // account identity are preserved, and the previous password cannot open it.
    let changed =
        VaultHeader::from_keys([1; 16], [2; 16], 1, b"new password", params, &keys).unwrap();
    assert!(changed.unlock(b"test master password").is_err());
    assert_eq!(
        changed.unlock(b"new password").unwrap().vault.secret(),
        keys.vault.secret()
    );
    let mut bad = bytes.clone();
    let last = bad.len() - 1;
    bad[last] ^= 1;
    assert!(
        VaultHeader::from_bytes(&bad)
            .unwrap()
            .unlock(b"test master password")
            .is_err()
    );
    for cut in [0, 4, 5, 20, bytes.len() - 1] {
        assert!(VaultHeader::from_bytes(&bytes[..cut]).is_err());
    }
    let mut trailing = bytes;
    trailing.push(0);
    assert!(VaultHeader::from_bytes(&trailing).is_err());
}

#[test]
fn password_derivation_enforces_floor_and_work_budget_before_allocating() {
    for (memory, passes) in [
        (1, 1),
        (MIN_MEMORY_KIB, 0),
        (u32::MAX, 1),
        (MIN_MEMORY_KIB, 17),
        (256 * 1024, 16),
    ] {
        assert_eq!(
            KdfParams::new(memory, passes).unwrap_err(),
            Error::KdfParameters
        );
    }
    let params = KdfParams::new(MIN_MEMORY_KIB, 1).unwrap();
    assert_eq!(params.derive(&[], &[0; 16]).unwrap_err(), Error::Limit);
    let first = params.derive(b"test password", &[4; 16]).unwrap();
    assert_eq!(*first, *params.derive(b"test password", &[4; 16]).unwrap());
    assert_ne!(*first, *params.derive(b"test password", &[5; 16]).unwrap());
    let b = PasswordBox::seal(b"test password", params, b"vault A", b"account seed").unwrap();
    assert_eq!(
        b.open(b"test password", b"vault A").unwrap().as_slice(),
        b"account seed"
    );
    assert!(b.open(b"test password", b"vault B").is_err());
    let second = PasswordBox::seal(b"test password", params, b"vault A", b"account seed").unwrap();
    assert_ne!(b.to_bytes(), second.to_bytes());
    let mut bad = b.to_bytes();
    bad[5..9].copy_from_slice(&u32::MAX.to_be_bytes());
    assert_eq!(
        PasswordBox::from_bytes(&bad).unwrap_err(),
        Error::KdfParameters
    );
    let seed = Zeroizing::new([9; 64]);
    let a = AccountKey::from_secret(KemSuite::XWingDraft06Pq05, seed).unwrap();
    assert_eq!(
        a.public(),
        AccountKey::from_secret(KemSuite::XWingDraft06Pq05, a.secret())
            .unwrap()
            .public()
    );
}
