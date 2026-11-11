//! Canonical v1 envelope, matching S4's accepted wire format. AAD binds
//! every routing field; callers must also supply the intended storage slot.
use crate::{Error, VaultKey, wire};
use chacha20poly1305::aead::{Aead, Payload};
use chacha20poly1305::{KeyInit, XChaCha20Poly1305, XNonce};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

pub type Id = [u8; 16];
pub type Revision = [u8; 32];
pub const MAX_PLAINTEXT: usize = 64 << 20;
pub const MAX_PARENTS: usize = 64;
pub const MAX_ENVELOPE: usize = MAX_PLAINTEXT + MAX_PARENTS * 34 + 512;
const SIGNED: &[u8] = b"openward envelope v1 signature\0";
const REVISION: &[u8] = b"openward envelope v1 revision\0";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Header {
    pub vault: Id,
    pub item: Id,
    pub device: Id,
    pub key_gen: u32,
    /// Strictly ascending, without duplicates.
    pub parents: Vec<Revision>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Slot {
    pub vault: Id,
    pub item: Id,
    pub key_gen: u32,
}

impl Header {
    fn validate(&self) -> Result<(), Error> {
        if self.parents.len() > MAX_PARENTS {
            return Err(Error::Limit);
        }
        if !self.parents.windows(2).all(|w| w[0] < w[1]) {
            return Err(Error::Encoding);
        }
        Ok(())
    }
    pub fn slot(&self) -> Slot {
        Slot {
            vault: self.vault,
            item: self.item,
            key_gen: self.key_gen,
        }
    }
    fn fields(&self, out: &mut Vec<u8>) {
        for (name, id) in [
            ("item", &self.item),
            ("vault", &self.vault),
            ("device", &self.device),
        ] {
            wire::key(out, name);
            wire::bytes(out, id);
        }
        self.last_fields(out);
    }
    fn last_fields(&self, out: &mut Vec<u8>) {
        wire::key(out, "key_gen");
        wire::number(out, 0, u64::from(self.key_gen));
        wire::key(out, "parents");
        wire::number(out, 4, self.parents.len() as u64);
        for parent in &self.parents {
            wire::bytes(out, parent);
        }
    }
    pub fn aad(&self) -> Result<Vec<u8>, Error> {
        self.validate()?;
        let mut out = Vec::new();
        wire::number(&mut out, 5, 6);
        wire::key(&mut out, "v");
        wire::number(&mut out, 0, 1);
        self.fields(&mut out);
        Ok(out)
    }
}

/// Fields are private so validated sizes/order cannot change after construction.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Envelope {
    header: Header,
    nonce: [u8; 24],
    ct: Vec<u8>,
    sig: [u8; 64],
}

impl Envelope {
    pub fn seal(
        header: Header,
        plaintext: &[u8],
        key: &VaultKey,
        signer: &SigningKey,
    ) -> Result<Self, Error> {
        header.validate()?;
        if plaintext.len() > MAX_PLAINTEXT {
            return Err(Error::Limit);
        }
        let mut nonce = [0; 24];
        getrandom::fill(&mut nonce).map_err(|_| Error::Randomness)?;
        Self::seal_with_nonce(header, plaintext, key, signer, nonce)
    }

    fn seal_with_nonce(
        header: Header,
        plaintext: &[u8],
        key: &VaultKey,
        signer: &SigningKey,
        nonce: [u8; 24],
    ) -> Result<Self, Error> {
        header.validate()?;
        if plaintext.len() > MAX_PLAINTEXT {
            return Err(Error::Limit);
        }
        let ct = XChaCha20Poly1305::new(key.secret().into())
            .encrypt(
                &XNonce::from(nonce),
                Payload {
                    msg: plaintext,
                    aad: &header.aad()?,
                },
            )
            .map_err(|_| Error::Authentication)?;
        let mut envelope = Self {
            header,
            nonce,
            ct,
            sig: [0; 64],
        };
        envelope.sig = signer.sign(&envelope.signed_message()).to_bytes();
        Ok(envelope)
    }
    pub fn header(&self) -> &Header {
        &self.header
    }

    fn encode(&self, signed: bool) -> Vec<u8> {
        let mut out = Vec::with_capacity(self.ct.len() + self.header.parents.len() * 34 + 512);
        wire::number(&mut out, 5, if signed { 9 } else { 8 });
        wire::key(&mut out, "v");
        wire::number(&mut out, 0, 1);
        wire::key(&mut out, "ct");
        wire::bytes(&mut out, &self.ct);
        if signed {
            wire::key(&mut out, "sig");
            wire::bytes(&mut out, &self.sig);
        }
        wire::key(&mut out, "item");
        wire::bytes(&mut out, &self.header.item);
        wire::key(&mut out, "nonce");
        wire::bytes(&mut out, &self.nonce);
        wire::key(&mut out, "vault");
        wire::bytes(&mut out, &self.header.vault);
        wire::key(&mut out, "device");
        wire::bytes(&mut out, &self.header.device);
        self.header.last_fields(&mut out);
        out
    }
    fn signed_message(&self) -> Vec<u8> {
        [SIGNED, &self.encode(false)].concat()
    }
    pub fn revision(&self) -> Revision {
        Sha256::new()
            .chain_update(REVISION)
            .chain_update(self.encode(false))
            .finalize()
            .into()
    }
    pub fn to_bytes(&self) -> Vec<u8> {
        self.encode(true)
    }

    /// Parse bounded canonical bytes. Verify the writer before admitting a
    /// received envelope to storage; authenticated local reads may skip it.
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, Error> {
        if bytes.len() > MAX_ENVELOPE {
            return Err(Error::Limit);
        }
        let mut r = wire::Reader::new(bytes);
        if r.number(5)? != 9 {
            return Err(Error::Encoding);
        }
        r.key("v")?;
        let version = r.number(0)?;
        if version != 1 {
            return Err(Error::Version(version));
        }
        r.key("ct")?;
        let ct = r.bytes(MAX_PLAINTEXT + 16)?;
        if ct.len() < 16 {
            return Err(Error::Encoding);
        }
        r.key("sig")?;
        let sig = r.fixed()?;
        r.key("item")?;
        let item = r.fixed()?;
        r.key("nonce")?;
        let nonce = r.fixed()?;
        r.key("vault")?;
        let vault = r.fixed()?;
        r.key("device")?;
        let device = r.fixed()?;
        r.key("key_gen")?;
        let key_gen = u32::try_from(r.number(0)?).map_err(|_| Error::Encoding)?;
        r.key("parents")?;
        let count = r.number(4)?;
        if count > MAX_PARENTS as u64 {
            return Err(Error::Limit);
        }
        let mut parents = Vec::with_capacity(count as usize);
        for _ in 0..count {
            parents.push(r.fixed()?);
        }
        if !r.done() {
            return Err(Error::Encoding);
        }
        let header = Header {
            vault,
            item,
            device,
            key_gen,
            parents,
        };
        header.validate()?;
        Ok(Self {
            header,
            nonce,
            ct: ct.to_vec(),
            sig,
        })
    }

    pub fn verify(&self, writer: &VerifyingKey) -> Result<(), Error> {
        writer
            .verify_strict(&self.signed_message(), &Signature::from_bytes(&self.sig))
            .map_err(|_| Error::Signature)
    }

    /// The intended slot must come from trusted storage/caller state, rather
    /// than being taken from this envelope. Local unlock uses AEAD, as in ADR-005.
    pub fn open(&self, slot: Slot, key: &VaultKey) -> Result<Zeroizing<Vec<u8>>, Error> {
        if self.header.slot() != slot {
            return Err(Error::Context);
        }
        XChaCha20Poly1305::new(key.secret().into())
            .decrypt(
                &XNonce::from(self.nonce),
                Payload {
                    msg: &self.ct,
                    aad: &self.header.aad()?,
                },
            )
            .map(Zeroizing::new)
            .map_err(|_| Error::Authentication)
    }

    pub fn open_received(
        bytes: &[u8],
        slot: Slot,
        key: &VaultKey,
        writer: &VerifyingKey,
    ) -> Result<Zeroizing<Vec<u8>>, Error> {
        let envelope = Self::from_bytes(bytes)?;
        envelope.verify(writer)?;
        envelope.open(slot, key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;
    fn fixture() -> Value {
        serde_json::from_str(include_str!("../tests/fixtures/s4-envelope-v1.json")).unwrap()
    }
    fn hex(value: &Value, name: &str) -> Vec<u8> {
        value[name]
            .as_str()
            .unwrap()
            .as_bytes()
            .as_chunks::<2>()
            .0
            .iter()
            .map(|c| u8::from_str_radix(std::str::from_utf8(c).unwrap(), 16).unwrap())
            .collect()
    }
    fn header() -> Header {
        Header {
            vault: [1; 16],
            item: [2; 16],
            device: [3; 16],
            key_gen: 1,
            parents: vec![[4; 32], [5; 32]],
        }
    }
    fn key() -> VaultKey {
        VaultKey::from_secret(Zeroizing::new([7; 32]))
    }
    fn signer() -> SigningKey {
        SigningKey::from_bytes(&[9; 32])
    }
    fn sealed() -> Envelope {
        Envelope::seal(header(), b"public test body", &key(), &signer()).unwrap()
    }

    #[test]
    fn accepted_s4_fixture_is_byte_identical_in_both_directions() {
        let f = fixture();
        let encoded = hex(&f, "envelope");
        let key = VaultKey::from_secret(Zeroizing::new(hex(&f, "key").try_into().unwrap()));
        let seed: [u8; 32] = hex(&f, "signing_seed").try_into().unwrap();
        let signer = SigningKey::from_bytes(&seed);
        let nonce = hex(&f, "nonce").try_into().unwrap();
        let plaintext = hex(&f, "plaintext");
        let back = Envelope::from_bytes(&encoded).unwrap();
        assert_eq!(back.header(), &header());
        assert_eq!(back.to_bytes(), encoded);
        assert_eq!(back.header.aad().unwrap(), hex(&f, "aad"));
        assert_eq!(back.revision().as_slice(), hex(&f, "revision"));
        assert_eq!(
            signer.verifying_key().as_bytes().as_slice(),
            hex(&f, "public_key")
        );
        assert_eq!(
            Envelope::open_received(&encoded, header().slot(), &key, &signer.verifying_key())
                .unwrap()
                .as_slice(),
            plaintext
        );
        let fresh = Envelope::seal_with_nonce(header(), &plaintext, &key, &signer, nonce).unwrap();
        assert_eq!(fresh.to_bytes(), encoded);
    }

    #[test]
    fn ordinary_and_empty_bodies_round_trip_with_fresh_nonces() {
        let vault_key = VaultKey::generate().unwrap();
        for body in [b"".as_slice(), b"a host with private metadata"] {
            let first = Envelope::seal(header(), body, &vault_key, &signer()).unwrap();
            let second = Envelope::seal(header(), body, &vault_key, &signer()).unwrap();
            assert_ne!(first.nonce, second.nonce);
            assert_ne!(first.revision(), second.revision());
            assert_eq!(
                first.open(header().slot(), &vault_key).unwrap().as_slice(),
                body
            );
        }
    }

    #[test]
    fn every_changed_byte_and_truncated_encoding_is_refused() {
        let original = sealed().to_bytes();
        let writer = signer().verifying_key();
        for index in 0..original.len() {
            let mut bad = original.clone();
            bad[index] ^= 1;
            assert!(
                Envelope::open_received(&bad, header().slot(), &key(), &writer).is_err(),
                "byte {index}"
            );
            assert!(
                Envelope::from_bytes(&original[..index]).is_err(),
                "prefix {index}"
            );
        }
    }

    #[test]
    fn correct_signature_cannot_move_ciphertext_between_headers() {
        let original = sealed();
        let mutations: [fn(&mut Header); 5] = [
            |h| h.vault[0] ^= 1,
            |h| h.item[0] ^= 1,
            |h| h.device[0] ^= 1,
            |h| h.key_gen += 1,
            |h| h.parents = vec![[6; 32], [7; 32]],
        ];
        for change in mutations {
            let mut moved = original.clone();
            change(&mut moved.header);
            moved.sig = signer().sign(&moved.signed_message()).to_bytes();
            moved.verify(&signer().verifying_key()).unwrap();
            assert_eq!(
                moved.open(moved.header.slot(), &key()).unwrap_err(),
                Error::Authentication
            );
        }
    }

    #[test]
    fn intended_slot_writer_and_key_are_required() {
        let original = sealed();
        for slot in [
            Slot {
                vault: [0; 16],
                ..header().slot()
            },
            Slot {
                item: [0; 16],
                ..header().slot()
            },
            Slot {
                key_gen: 2,
                ..header().slot()
            },
        ] {
            assert_eq!(original.open(slot, &key()).unwrap_err(), Error::Context);
        }
        let wrong = VaultKey::from_secret(Zeroizing::new([6; 32]));
        assert_eq!(
            original.open(header().slot(), &wrong).unwrap_err(),
            Error::Authentication
        );
        assert_eq!(
            original.verify(&SigningKey::from_bytes(&[5; 32]).verifying_key()),
            Err(Error::Signature)
        );
    }

    #[test]
    fn declarations_are_bounded_before_allocation() {
        let f = fixture();
        let bytes = hex(&f, "envelope");
        // The ciphertext starts at byte7 in this fixed canonical fixture.
        let mut huge = bytes[..7].to_vec();
        huge.push(0x5b);
        huge.extend([255; 8]);
        huge.extend(&bytes[9..]);
        assert_eq!(Envelope::from_bytes(&huge).unwrap_err(), Error::Limit);
        let position = bytes.windows(7).position(|w| w == b"parents").unwrap() + 7;
        let mut huge = bytes[..position].to_vec();
        huge.push(0x9b);
        huge.extend([255; 8]);
        assert_eq!(Envelope::from_bytes(&huge).unwrap_err(), Error::Limit);
        let mut too_many = header();
        too_many.parents = (0..=MAX_PARENTS).map(|i| [i as u8; 32]).collect();
        assert_eq!(
            Envelope::seal(too_many, b"", &key(), &signer()).unwrap_err(),
            Error::Limit
        );
    }

    #[test]
    fn equivalent_noncanonical_unknown_and_trailing_forms_are_refused() {
        let f = fixture();
        let bytes = hex(&f, "envelope");
        let mut wider = bytes[..7].to_vec();
        wider.extend([0x59, 0, bytes[8]]);
        wider.extend(&bytes[9..]);
        assert_eq!(Envelope::from_bytes(&wider).unwrap_err(), Error::Encoding);
        let mut future = bytes.clone();
        future[3] = 2;
        assert_eq!(
            Envelope::from_bytes(&future).unwrap_err(),
            Error::Version(2)
        );
        let mut tail = bytes.clone();
        tail.push(0);
        assert_eq!(Envelope::from_bytes(&tail).unwrap_err(), Error::Encoding);
        let mut duplicate = bytes.clone();
        let at = duplicate.windows(5).position(|w| w == b"vault").unwrap();
        duplicate[at..at + 5].copy_from_slice(b"nonce");
        assert_eq!(
            Envelope::from_bytes(&duplicate).unwrap_err(),
            Error::Encoding
        );
        let mut unordered = header();
        unordered.parents.reverse();
        assert_eq!(
            Envelope::seal(unordered, b"", &key(), &signer()).unwrap_err(),
            Error::Encoding
        );
        let mut duplicate = header();
        duplicate.parents[1] = duplicate.parents[0];
        assert_eq!(
            Envelope::seal(duplicate, b"", &key(), &signer()).unwrap_err(),
            Error::Encoding
        );
    }

    proptest::proptest! {
        #[test]
        fn arbitrary_bytes_are_bounded_or_refused(bytes in proptest::collection::vec(proptest::prelude::any::<u8>(),0..4096)) {
            if let Ok(envelope)=Envelope::from_bytes(&bytes) {
                proptest::prop_assert_eq!(envelope.to_bytes(),bytes);
            }
        }
    }
}
