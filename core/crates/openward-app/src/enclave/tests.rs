use super::*;
use signature::Signer;
use std::{
    collections::HashSet,
    sync::{
        Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};

struct Fake {
    key: p256::ecdsa::SigningKey,
    ids: Mutex<HashSet<String>>,
    fail: Mutex<Option<Error>>,
    on_sign: Mutex<Option<Box<dyn FnOnce() + Send>>>,
    calls: AtomicUsize,
    removed: AtomicUsize,
}
impl Default for Fake {
    fn default() -> Self {
        Self {
            key: p256::ecdsa::SigningKey::from_slice(&[7; 32]).unwrap(),
            ids: Mutex::default(),
            fail: Mutex::default(),
            on_sign: Mutex::default(),
            calls: AtomicUsize::new(0),
            removed: AtomicUsize::new(0),
        }
    }
}
impl Backend for Fake {
    fn create(&self, id: &str) -> Result<PublicKey, Error> {
        assert!(valid_id(id));
        assert!(self.ids.lock().unwrap().insert(id.into()));
        Ok(PublicKey::new(
            ssh_key::public::EcdsaPublicKey::from(self.key.verifying_key()).into(),
            "",
        ))
    }
    fn sign(&self, id: &str, _: &PublicKey, data: &[u8]) -> Result<Vec<u8>, Error> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        if let Some(f) = self.on_sign.lock().unwrap().take() {
            f();
        }
        if let Some(e) = self.fail.lock().unwrap().clone() {
            return Err(e);
        }
        if !self.ids.lock().unwrap().contains(id) {
            return Err(Error::Missing);
        }
        let sig: p256::ecdsa::Signature = self.key.sign(data);
        Ok(sig.to_der().as_bytes().to_vec())
    }
    fn remove(&self, id: &str, _: &PublicKey) -> Result<(), Error> {
        self.ids.lock().unwrap().remove(id);
        self.removed.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }
}
const PASSWORD: &[u8] = b"public test password";
fn session() -> (tempfile::TempDir, Arc<VaultSession>) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    drop(
        Vault::create_encrypted(
            &path,
            PASSWORD,
            openward_crypto::password::KdfParams::new(65536, 1).unwrap(),
        )
        .unwrap(),
    );
    let s = Arc::new(VaultSession::open(&path).unwrap());
    s.unlock(PASSWORD).unwrap();
    (dir, s)
}
fn desc(s: &VaultSession, k: &KeyFile) -> Descriptor {
    descriptor(&crate::connect::lock(&s.vault()), Path::new(&k.path)).unwrap()
}

#[test]
fn authenticated_creation_stores_only_public_metadata_and_survives_lock_and_reopen() {
    let (dir, s) = session();
    let backend = Fake::default();
    let k = generate(&s, &backend, "deploy", "demo@test").unwrap();
    assert!(k.path.starts_with("enclave:"));
    assert_eq!(backend.calls.load(Ordering::SeqCst), 1);
    let d = desc(&s, &k);
    let value = serde_json::to_string(&d).unwrap();
    assert!(!value.contains("PRIVATE"));
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&value)
            .unwrap()
            .as_object()
            .unwrap()
            .len(),
        3
    );
    assert_eq!(list(&crate::connect::lock(&s.vault())).len(), 1);
    let bytes = std::fs::read(dir.path().join("vault.db")).unwrap();
    assert!(!bytes.windows(value.len()).any(|w| w == value.as_bytes()));
    s.lock().unwrap();
    assert!(list(&crate::connect::lock(&s.vault())).is_empty());
    assert!(descriptor(&crate::connect::lock(&s.vault()), Path::new(&k.path)).is_err());
    drop(s);
    let s = VaultSession::open(&dir.path().join("vault.db")).unwrap();
    s.unlock(PASSWORD).unwrap();
    assert_eq!(
        public(&crate::connect::lock(&s.vault()), Path::new(&k.path)).unwrap(),
        d.public_key
    );
    delete(&s, &backend, Path::new(&k.path)).unwrap();
    assert!(list(&crate::connect::lock(&s.vault())).is_empty());
    assert_eq!(backend.removed.load(Ordering::SeqCst), 1);
}

#[test]
fn cancelled_or_failed_enrolment_never_publishes_a_key_and_cleans_up() {
    let (_dir, s) = session();
    for error in [
        Error::Cancelled,
        Error::Unavailable,
        Error::Invalid,
        Error::Missing,
    ] {
        let backend = Fake::default();
        *backend.fail.lock().unwrap() = Some(error);
        assert!(generate(&s, &backend, "cancelled", "").is_err());
        assert!(list(&crate::connect::lock(&s.vault())).is_empty());
        assert!(backend.ids.lock().unwrap().is_empty());
        assert_eq!(backend.removed.load(Ordering::SeqCst), 1);
    }
}

#[test]
fn locked_or_legacy_vault_and_bad_names_do_not_call_the_os() {
    let (_dir, s) = session();
    let backend = Fake::default();
    assert!(generate(&s, &backend, "", "").is_err());
    assert!(generate(&s, &backend, "x", "newline\ncommand").is_err());
    s.lock().unwrap();
    assert!(generate(&s, &backend, "locked", "").is_err());
    let dir = tempfile::tempdir().unwrap();
    let legacy = VaultSession::open(&dir.path().join("vault.db")).unwrap();
    assert!(generate(&legacy, &backend, "legacy", "").is_err());
    assert!(backend.ids.lock().unwrap().is_empty());
    assert_eq!(backend.calls.load(Ordering::SeqCst), 0);
}

#[test]
fn lock_during_native_generation_does_not_block_and_late_success_is_deleted() {
    let (_dir, s) = session();
    let backend = Fake::default();
    let changed = Arc::clone(&s);
    *backend.on_sign.lock().unwrap() = Some(Box::new(move || {
        changed.lock().unwrap();
        changed.unlock(PASSWORD).unwrap();
    }));
    assert!(generate(&s, &backend, "late", "").is_err());
    assert!(list(&crate::connect::lock(&s.vault())).is_empty());
    assert!(backend.ids.lock().unwrap().is_empty());
    assert_eq!(backend.removed.load(Ordering::SeqCst), 1);
}

#[test]
fn signing_rechecks_the_epoch_and_propagates_cancellation_or_missing_key() {
    let (_dir, s) = session();
    let backend = Fake::default();
    let k = generate(&s, &backend, "key", "").unwrap();
    let d = desc(&s, &k);
    let gate = s.gate();
    let epoch = gate.ticket().unwrap();
    for e in [Error::Cancelled, Error::Missing, Error::Unavailable] {
        *backend.fail.lock().unwrap() = Some(e.clone());
        assert_eq!(sign(&backend, &d, &gate, epoch, b"ssh packet"), Err(e));
    }
    *backend.fail.lock().unwrap() = None;
    let changed = Arc::clone(&s);
    *backend.on_sign.lock().unwrap() = Some(Box::new(move || {
        changed.lock().unwrap();
        changed.unlock(PASSWORD).unwrap();
    }));
    assert_eq!(
        sign(&backend, &d, &gate, epoch, b"ssh packet"),
        Err(Error::Locked)
    );
    let calls = backend.calls.load(Ordering::SeqCst);
    assert_eq!(
        sign(&backend, &d, &gate, epoch, b"later"),
        Err(Error::Locked)
    );
    assert_eq!(backend.calls.load(Ordering::SeqCst), calls);
}

#[test]
fn der_conversion_verifies_the_exact_message_and_public_key_and_ssh_mpints() {
    let backend = Fake::default();
    let id = ItemId::new().to_string();
    let p = backend.create(&id).unwrap();
    let mut padded = false;
    for i in 0..32 {
        let msg = format!("SSH session id and userauth payload {i}");
        let der = backend.sign(&id, &p, msg.as_bytes()).unwrap();
        let blob = ssh_signature(&p, msg.as_bytes(), &der).unwrap();
        let sig = ssh_key::Signature::try_from(blob.as_slice()).unwrap();
        Verifier::verify(&p, msg.as_bytes(), &sig).unwrap();
        let scalars = p256::ecdsa::Signature::from_der(&der).unwrap().to_bytes();
        padded |= scalars[0] >= 128 || scalars[32] >= 128;
        assert_eq!(
            ssh_signature(&p, b"different message", &der),
            Err(Error::Invalid)
        );
    }
    assert!(padded, "exercise positive mpints with a leading zero");
    for invalid in [&[][..], &[0x30, 0][..], &[0; 80][..]] {
        assert_eq!(ssh_signature(&p, b"x", invalid), Err(Error::Invalid));
    }
    let other = p256::ecdsa::SigningKey::from_slice(&[8; 32]).unwrap();
    let sig: p256::ecdsa::Signature = other.sign(b"x");
    assert_eq!(
        ssh_signature(&p, b"x", sig.to_der().as_bytes()),
        Err(Error::Invalid)
    );
}

#[test]
fn references_are_canonical_and_descriptors_reject_other_algorithms_or_versions() {
    let id = ItemId::new().to_string();
    assert_eq!(
        reference(Path::new(&format!("enclave:{id}"))),
        Some(id.clone())
    );
    for p in [
        format!("enclave:{id}/../other"),
        "enclave:../../key".into(),
        "enclave:invalid".into(),
        format!("enclave:{}", id.to_uppercase()),
    ] {
        assert!(reference(Path::new(&p)).is_none(), "{p}");
    }
    let backend = Fake::default();
    let p = backend.create(&id).unwrap();
    let mut d = Descriptor {
        version: 2,
        id,
        public_key: p.to_openssh().unwrap(),
    };
    assert_eq!(d.public(), Err(Error::Invalid));
    d.version = 1;
    assert!(d.public().is_ok());
    let canonical = d.public_key.clone();
    d.public_key.push_str("\nsecond authorized key");
    assert_eq!(d.public(), Err(Error::Invalid));
    d.public_key = canonical;
    d.public_key = ssh_key::PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519)
        .unwrap()
        .public_key()
        .to_openssh()
        .unwrap();
    assert_eq!(d.public(), Err(Error::Invalid));
}

#[test]
fn backup_restores_public_reference_but_a_new_device_cannot_sign() {
    let (_dir, source) = session();
    let backend = Fake::default();
    let k = generate(&source, &backend, "device-bound", "test").unwrap();
    let json = crate::connect::lock(&source.vault())
        .export_json(PASSWORD, true)
        .unwrap();
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("restored.db");
    let mut target = Vault::create_encrypted(
        &path,
        PASSWORD,
        openward_crypto::password::KdfParams::new(65536, 1).unwrap(),
    )
    .unwrap();
    let snapshot = openward_vault::backup::Snapshot::parse(&json).unwrap();
    let import = target.prepare_restore(snapshot).unwrap();
    target.apply_restore(import).unwrap();
    drop(target);
    let target = VaultSession::open(&path).unwrap();
    target.unlock(PASSWORD).unwrap();
    let d = desc(&target, &k);
    assert_eq!(d.public_key, desc(&source, &k).public_key);
    let other_device = Fake::default();
    assert_eq!(
        sign(
            &other_device,
            &d,
            &target.gate(),
            target.gate().ticket().unwrap(),
            b"SSH"
        ),
        Err(Error::Missing)
    );
}
