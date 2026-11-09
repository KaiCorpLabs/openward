//! The candidates behind one face: HPKE in base mode, HKDF-SHA256 and
//! ChaCha20-Poly1305, with DHKEM(X25519) or X-Wing. That is the suite the
//! vault would use to wrap a 32-byte key for an account's public key.

use std::cell::RefCell;
use std::marker::PhantomData;

use hpke::{Deserializable, OpModeR, OpModeS, Serializable};
use hpke_rs::hpke_types::{AeadAlgorithm, KdfAlgorithm, KemAlgorithm};
use hpke_rs::{Hpke, HpkePrivateKey, HpkePublicKey, Mode};
use hpke_rs_crypto::{HpkeCrypto, HpkeDefaultPrng};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kem {
    X25519,
    XWing,
}

impl Kem {
    pub const ALL: [Kem; 2] = [Kem::X25519, Kem::XWing];

    pub fn name(self) -> &'static str {
        match self {
            Kem::X25519 => "DHKEM(X25519)",
            Kem::XWing => "X-Wing",
        }
    }

    pub fn id(self) -> u16 {
        match self {
            Kem::X25519 => 0x0020,
            Kem::XWing => 0x647a,
        }
    }

    pub fn hpke_rs(self) -> KemAlgorithm {
        match self {
            Kem::X25519 => KemAlgorithm::DhKem25519,
            Kem::XWing => KemAlgorithm::XWingDraft06,
        }
    }
}

/// One library's HPKE for one KEM. Keys and messages go as bytes, so that
/// any library opens what another sealed.
pub trait Suite {
    fn library(&self) -> &'static str;
    fn kem(&self) -> Kem;
    /// A random key pair: (private, public).
    fn keypair(&self) -> (Vec<u8>, Vec<u8>);
    /// DeriveKeyPair: the same pair from the same seed, on any library.
    fn derive(&self, ikm: &[u8]) -> (Vec<u8>, Vec<u8>);
    /// Single-shot seal: (enc, ciphertext).
    fn seal(&self, pk: &[u8], info: &[u8], aad: &[u8], pt: &[u8]) -> (Vec<u8>, Vec<u8>);
    fn open(&self, sk: &[u8], enc: &[u8], info: &[u8], aad: &[u8], ct: &[u8]) -> Option<Vec<u8>>;
}

pub const LIBCRUX: &str = "hpke-rs 0.8.0 + libcrux";
pub const RUSTCRYPTO: &str = "hpke-rs 0.8.0 + RustCrypto";
pub const ROZBB: &str = "hpke 0.15.1 (rozbb)";

/// `hpke-rs` on one of its crypto back ends.
pub struct HpkeRs<C: HpkeCrypto + 'static> {
    library: &'static str,
    kem: Kem,
    hpke: RefCell<Hpke<C>>,
}

impl<C: HpkeCrypto + HpkeDefaultPrng + 'static> HpkeRs<C> {
    pub fn new(library: &'static str, kem: Kem) -> Self {
        Self {
            library,
            kem,
            hpke: RefCell::new(hpke_rs_config(kem)),
        }
    }
}

/// The suite, for `hpke-rs`.
pub fn hpke_rs_config<C: HpkeCrypto + HpkeDefaultPrng + 'static>(kem: Kem) -> Hpke<C> {
    Hpke::new(
        Mode::Base,
        kem.hpke_rs(),
        KdfAlgorithm::HkdfSha256,
        AeadAlgorithm::ChaCha20Poly1305,
    )
}

impl<C: HpkeCrypto + 'static> Suite for HpkeRs<C> {
    fn library(&self) -> &'static str {
        self.library
    }

    fn kem(&self) -> Kem {
        self.kem
    }

    fn keypair(&self) -> (Vec<u8>, Vec<u8>) {
        let (sk, pk) = self
            .hpke
            .borrow_mut()
            .generate_key_pair()
            .expect("key pair")
            .into_keys();
        (sk.as_slice().to_vec(), pk.as_slice().to_vec())
    }

    fn derive(&self, ikm: &[u8]) -> (Vec<u8>, Vec<u8>) {
        let pair = self.hpke.borrow().derive_key_pair(ikm).expect("derive");
        let (sk, pk) = pair.into_keys();
        (sk.as_slice().to_vec(), pk.as_slice().to_vec())
    }

    fn seal(&self, pk: &[u8], info: &[u8], aad: &[u8], pt: &[u8]) -> (Vec<u8>, Vec<u8>) {
        self.hpke
            .borrow_mut()
            .seal(
                &HpkePublicKey::new(pk.to_vec()),
                info,
                aad,
                pt,
                None,
                None,
                None,
            )
            .expect("seal")
    }

    fn open(&self, sk: &[u8], enc: &[u8], info: &[u8], aad: &[u8], ct: &[u8]) -> Option<Vec<u8>> {
        self.hpke
            .borrow()
            .open(
                enc,
                &HpkePrivateKey::new(sk.to_vec()),
                info,
                aad,
                ct,
                None,
                None,
                None,
            )
            .ok()
    }
}

/// `hpke` (rozbb), whose KEM is a type.
pub struct Rozbb<K> {
    kem: Kem,
    _kem: PhantomData<K>,
}

impl<K> Rozbb<K> {
    pub fn new(kem: Kem) -> Self {
        Self {
            kem,
            _kem: PhantomData,
        }
    }
}

pub type RozbbAead = hpke::aead::ChaCha20Poly1305;
pub type RozbbKdf = hpke::kdf::HkdfSha256;

impl<K: hpke::Kem> Suite for Rozbb<K> {
    fn library(&self) -> &'static str {
        ROZBB
    }

    fn kem(&self) -> Kem {
        self.kem
    }

    fn keypair(&self) -> (Vec<u8>, Vec<u8>) {
        let (sk, pk) = K::gen_keypair();
        (sk.to_bytes().to_vec(), pk.to_bytes().to_vec())
    }

    fn derive(&self, ikm: &[u8]) -> (Vec<u8>, Vec<u8>) {
        let (sk, pk) = K::derive_keypair(ikm);
        (sk.to_bytes().to_vec(), pk.to_bytes().to_vec())
    }

    fn seal(&self, pk: &[u8], info: &[u8], aad: &[u8], pt: &[u8]) -> (Vec<u8>, Vec<u8>) {
        let pk = K::PublicKey::from_bytes(pk).expect("public key");
        let (enc, ct) =
            hpke::single_shot_seal::<RozbbAead, RozbbKdf, K>(&OpModeS::Base, &pk, info, pt, aad)
                .expect("seal");
        (enc.to_bytes().to_vec(), ct)
    }

    fn open(&self, sk: &[u8], enc: &[u8], info: &[u8], aad: &[u8], ct: &[u8]) -> Option<Vec<u8>> {
        let sk = K::PrivateKey::from_bytes(sk).ok()?;
        let enc = K::EncappedKey::from_bytes(enc).ok()?;
        hpke::single_shot_open::<RozbbAead, RozbbKdf, K>(&OpModeR::Base, &sk, &enc, info, ct, aad)
            .ok()
    }
}

/// Every candidate, for one KEM.
pub fn all(kem: Kem) -> Vec<Box<dyn Suite>> {
    let rozbb: Box<dyn Suite> = match kem {
        Kem::X25519 => Box::new(Rozbb::<hpke::kem::X25519HkdfSha256>::new(kem)),
        Kem::XWing => Box::new(Rozbb::<hpke::kem::XWing>::new(kem)),
    };
    vec![
        Box::new(HpkeRs::<hpke_rs_libcrux::HpkeLibcrux>::new(LIBCRUX, kem)),
        Box::new(HpkeRs::<hpke_rs_rust_crypto::HpkeRustCrypto>::new(
            RUSTCRYPTO, kem,
        )),
        rozbb,
    ]
}
