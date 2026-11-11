//! The v1 envelope: one revision of one item, as the vault stores it and as
//! the sync ships it.
//!
//! ```text
//! { v: 1, ct, sig, item, nonce, vault, device, key_gen, parents }
//! ```
//!
//! - **Canonical CBOR**, so that the signature and the revision id cover one
//!   value: anything else is refused.
//! - **The revision id is not a field:** it is SHA-256 of the envelope
//!   without `sig`, so nobody can name a revision for content it is not.
//!   `parents` name revisions by that id.
//! - **AAD = the header** (`v`, `vault`, `item`, `device`, `key_gen`,
//!   `parents`), in canonical CBOR: the ciphertext opens only in its place
//!   in the DAG, even where nobody checks the signature.
//! - **Signed by the device** (Ed25519) over a context and the envelope
//!   without `sig`.
//! - In the clear: what the sync needs to place it, and nothing about the
//!   item: its type, names, addresses and times go inside `ct`.

use chacha20poly1305::aead::{Aead, Payload};
use chacha20poly1305::{KeyInit, XChaCha20Poly1305, XNonce};
use ciborium::Value;
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use rand::Rng;
use sha2::{Digest, Sha256};

use crate::cbor;

pub type Rev = [u8; 32];
pub type Id = [u8; 16];

const SIGNED: &[u8] = b"openward envelope v1 signature\0";
const REV: &[u8] = b"openward envelope v1 revision\0";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Header {
    pub vault: Id,
    pub item: Id,
    pub device: Id,
    pub key_gen: u32,
    /// In ascending order, with no repeats.
    pub parents: Vec<Rev>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Envelope {
    pub header: Header,
    pub nonce: [u8; 24],
    pub ct: Vec<u8>,
    pub sig: [u8; 64],
}

#[derive(Debug, PartialEq, Eq)]
pub enum Error {
    /// Not CBOR, or not in its one deterministic form.
    NotCanonical,
    Shape(&'static str),
    Version(u64),
    Signature,
    Decrypt,
}

impl Header {
    fn entries(&self) -> Vec<(&'static str, Value)> {
        vec![
            ("v", Value::from(1)),
            ("vault", Value::Bytes(self.vault.to_vec())),
            ("item", Value::Bytes(self.item.to_vec())),
            ("device", Value::Bytes(self.device.to_vec())),
            ("key_gen", Value::from(self.key_gen)),
            (
                "parents",
                Value::Array(
                    self.parents
                        .iter()
                        .map(|p| Value::Bytes(p.to_vec()))
                        .collect(),
                ),
            ),
        ]
    }

    pub fn aad(&self) -> Vec<u8> {
        cbor::encode(&cbor::text_map(self.entries()))
    }
}

impl Envelope {
    pub fn seal(
        mut header: Header,
        plaintext: &[u8],
        vault_key: &[u8; 32],
        device: &SigningKey,
    ) -> Self {
        header.parents.sort();
        header.parents.dedup();
        let mut nonce = [0u8; 24];
        rand::rng().fill_bytes(&mut nonce);
        let ct = XChaCha20Poly1305::new(vault_key.into())
            .encrypt(
                &XNonce::from(nonce),
                Payload {
                    msg: plaintext,
                    aad: &header.aad(),
                },
            )
            .expect("encrypting cannot fail");
        let mut env = Self {
            header,
            nonce,
            ct,
            sig: [0; 64],
        };
        env.sig = device.sign(&env.signed_message()).to_bytes();
        env
    }

    fn unsigned(&self) -> Vec<(&'static str, Value)> {
        let mut entries = self.header.entries();
        entries.push(("nonce", Value::Bytes(self.nonce.to_vec())));
        entries.push(("ct", Value::Bytes(self.ct.clone())));
        entries
    }

    fn unsigned_bytes(&self) -> Vec<u8> {
        cbor::encode(&cbor::text_map(self.unsigned()))
    }

    /// What the device signs.
    pub fn signed_message(&self) -> Vec<u8> {
        [SIGNED, &self.unsigned_bytes()].concat()
    }

    pub fn rev(&self) -> Rev {
        Sha256::new()
            .chain_update(REV)
            .chain_update(self.unsigned_bytes())
            .finalize()
            .into()
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut entries = self.unsigned();
        entries.push(("sig", Value::Bytes(self.sig.to_vec())));
        cbor::encode(&cbor::text_map(entries))
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, Error> {
        Self::from_value(&cbor::decode_canonical(bytes).ok_or(Error::NotCanonical)?)
    }

    /// What this device stored after checking it on the way in: the
    /// canonical form is not checked again.
    pub fn from_stored(bytes: &[u8]) -> Result<Self, Error> {
        Self::from_value(&ciborium::from_reader(bytes).map_err(|_| Error::NotCanonical)?)
    }

    fn from_value(value: &Value) -> Result<Self, Error> {
        let map = value.as_map().ok_or(Error::Shape("not a map"))?;
        let field = |k| cbor::get(map, k).ok_or(Error::Shape(k));
        let v = cbor::uint(field("v")?).ok_or(Error::Shape("v"))?;
        if v != 1 {
            return Err(Error::Version(v));
        }
        if map.len() != 9 {
            return Err(Error::Shape("unknown or missing fields"));
        }
        let parents = field("parents")?
            .as_array()
            .ok_or(Error::Shape("parents"))?
            .iter()
            .map(|p| cbor::bytes::<32>(p).ok_or(Error::Shape("parents")))
            .collect::<Result<Vec<_>, _>>()?;
        if !parents.windows(2).all(|w| w[0] < w[1]) {
            return Err(Error::Shape("parents out of order"));
        }
        Ok(Self {
            header: Header {
                vault: cbor::bytes(field("vault")?).ok_or(Error::Shape("vault"))?,
                item: cbor::bytes(field("item")?).ok_or(Error::Shape("item"))?,
                device: cbor::bytes(field("device")?).ok_or(Error::Shape("device"))?,
                key_gen: cbor::uint(field("key_gen")?)
                    .and_then(|g| u32::try_from(g).ok())
                    .ok_or(Error::Shape("key_gen"))?,
                parents,
            },
            nonce: cbor::bytes(field("nonce")?).ok_or(Error::Shape("nonce"))?,
            ct: field("ct")?.as_bytes().ok_or(Error::Shape("ct"))?.clone(),
            sig: cbor::bytes(field("sig")?).ok_or(Error::Shape("sig"))?,
        })
    }

    pub fn verify(&self, device: &VerifyingKey) -> Result<(), Error> {
        device
            .verify_strict(&self.signed_message(), &Signature::from_bytes(&self.sig))
            .map_err(|_| Error::Signature)
    }

    pub fn open(&self, vault_key: &[u8; 32]) -> Result<Vec<u8>, Error> {
        XChaCha20Poly1305::new(vault_key.into())
            .decrypt(
                &XNonce::from(self.nonce),
                Payload {
                    msg: &self.ct,
                    aad: &self.header.aad(),
                },
            )
            .map_err(|_| Error::Decrypt)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn keys() -> ([u8; 32], SigningKey) {
        ([7; 32], SigningKey::from_bytes(&[9; 32]))
    }

    fn sealed() -> Envelope {
        let (k, d) = keys();
        let header = Header {
            vault: [1; 16],
            item: [2; 16],
            device: [3; 16],
            key_gen: 1,
            parents: vec![[5; 32], [4; 32]],
        };
        Envelope::seal(header, b"a host", &k, &d)
    }

    #[test]
    fn it_round_trips_and_opens() {
        let (k, d) = keys();
        let env = sealed();
        let back = Envelope::from_bytes(&env.to_bytes()).unwrap();
        assert_eq!(back, env);
        assert_eq!(back.header.parents, vec![[4; 32], [5; 32]]);
        back.verify(&d.verifying_key()).unwrap();
        assert_eq!(back.open(&k).unwrap(), b"a host");
    }

    #[test]
    fn any_changed_byte_is_refused() {
        let (k, d) = keys();
        let bytes = sealed().to_bytes();
        for i in 0..bytes.len() {
            let mut bad = bytes.clone();
            bad[i] ^= 0x01;
            let refused = match Envelope::from_bytes(&bad) {
                Err(_) => true,
                Ok(env) => env.verify(&d.verifying_key()).is_err() || env.open(&k).is_err(),
            };
            assert!(refused, "byte {i} changed and still accepted");
        }
    }

    #[test]
    fn moved_to_another_item_or_generation_it_does_not_open() {
        let (k, _) = keys();
        let mut env = sealed();
        env.header.item = [8; 16];
        assert_eq!(env.open(&k), Err(Error::Decrypt));
        let mut env = sealed();
        env.header.key_gen = 2;
        assert_eq!(env.open(&k), Err(Error::Decrypt));
        let mut env = sealed();
        env.header.parents.pop();
        assert_eq!(env.open(&k), Err(Error::Decrypt));
    }

    #[test]
    fn the_revision_is_the_content() {
        let a = sealed();
        let b = sealed();
        // Same header and plaintext, a different nonce: two revisions.
        assert_ne!(a.rev(), b.rev());
        let mut c = a.clone();
        c.sig = [0; 64];
        assert_eq!(a.rev(), c.rev());
    }
}
