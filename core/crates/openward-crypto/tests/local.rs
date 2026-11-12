use openward_crypto::{VaultKey, local::LocalKey};
#[test]
fn blobs_are_separated_by_vault_domain_and_name_and_authenticate_every_byte() {
    let a = VaultKey::generate().unwrap();
    let b = VaultKey::generate().unwrap();
    let key = LocalKey::derive(&a, b"device one").unwrap();
    let other = LocalKey::derive(&b, b"device one").unwrap();
    let device = LocalKey::derive(&a, b"device two").unwrap();
    let sealed = key.seal(b"history", b"synthetic private command").unwrap();
    assert_eq!(
        key.open(b"history", &sealed).unwrap().as_slice(),
        b"synthetic private command"
    );
    assert!(key.open(b"recent", &sealed).is_err());
    assert!(other.open(b"history", &sealed).is_err());
    assert!(device.open(b"history", &sealed).is_err());
    assert_ne!(
        key.seal(b"history", b"synthetic private command").unwrap(),
        sealed
    );
    for i in 0..sealed.len() {
        let mut changed = sealed.clone();
        changed[i] ^= 1;
        assert!(key.open(b"history", &changed).is_err());
    }
    for i in 0..sealed.len() {
        assert!(key.open(b"history", &sealed[..i]).is_err());
    }
    assert!(key.seal(&[0; 513], b"secret").is_err());
}
