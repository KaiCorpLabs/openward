//! Local-only derived stores and per-recording keys. Keys never cross FFI.
use crate::{Error, VaultKey};
use chacha20poly1305::{
    KeyInit, XChaCha20Poly1305, XNonce,
    aead::{Aead, Payload},
};
use sha2::Sha256;
use zeroize::Zeroizing;

pub const MAX_LOCAL_BYTES: usize = 16 * 1024 * 1024;
pub struct LocalKey(Zeroizing<[u8; 32]>);
impl LocalKey {
    pub fn generate() -> Result<Self, Error> {
        let mut k = Zeroizing::new([0; 32]);
        getrandom::fill(k.as_mut()).map_err(|_| Error::Randomness)?;
        Ok(Self(k))
    }
    pub fn derive(vault: &VaultKey, context: &[u8]) -> Result<Self, Error> {
        if context.len() > 512 {
            return Err(Error::Limit);
        }
        let mut k = Zeroizing::new([0; 32]);
        hkdf::Hkdf::<Sha256>::from_prk(vault.secret())
            .map_err(|_| Error::Authentication)?
            .expand(
                &[b"openward protected local data v1\0".as_slice(), context].concat(),
                k.as_mut(),
            )
            .map_err(|_| Error::Authentication)?;
        Ok(Self(k))
    }
    pub fn from_secret(k: Zeroizing<[u8; 32]>) -> Self {
        Self(k)
    }
    pub fn secret(&self) -> &[u8; 32] {
        &self.0
    }
    pub fn seal(&self, label: &[u8], clear: &[u8]) -> Result<Vec<u8>, Error> {
        if label.len() > 512 || clear.len() > MAX_LOCAL_BYTES {
            return Err(Error::Limit);
        }
        let mut b = b"OWLD\x01".to_vec();
        let mut nonce = [0; 24];
        getrandom::fill(&mut nonce).map_err(|_| Error::Randomness)?;
        b.extend(nonce);
        let ct = XChaCha20Poly1305::new((&*self.0).into())
            .encrypt(
                &XNonce::from(nonce),
                Payload {
                    msg: clear,
                    aad: &[b"openward local blob v1\0".as_slice(), &b, label].concat(),
                },
            )
            .map_err(|_| Error::Authentication)?;
        b.extend(ct);
        Ok(b)
    }
    pub fn open(&self, label: &[u8], b: &[u8]) -> Result<Zeroizing<Vec<u8>>, Error> {
        if label.len() > 512 || b.len() > MAX_LOCAL_BYTES + 45 {
            return Err(Error::Limit);
        }
        if b.len() < 45 || !b.starts_with(b"OWLD\x01") {
            return Err(Error::Encoding);
        }
        let nonce: [u8; 24] = b[5..29].try_into().unwrap();
        XChaCha20Poly1305::new((&*self.0).into())
            .decrypt(
                &XNonce::from(nonce),
                Payload {
                    msg: &b[29..],
                    aad: &[b"openward local blob v1\0".as_slice(), &b[..29], label].concat(),
                },
            )
            .map(Zeroizing::new)
            .map_err(|_| Error::Authentication)
    }
}
