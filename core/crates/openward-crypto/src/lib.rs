//! D3's envelope boundary (ADR-004/005). Keys and decrypted bytes remain
//! owned by Rust. The vault migration and key hierarchy build on this crate.
mod codec;
pub mod envelope;
pub mod hierarchy;
pub mod password;
pub mod plaintext;
mod wire;

pub use ed25519_dalek::{SigningKey, VerifyingKey};
use zeroize::Zeroizing;

/// A vault generation's secret. Deliberately neither Clone nor Debug.
pub struct VaultKey(Zeroizing<[u8; 32]>);

impl VaultKey {
    pub fn generate() -> Result<Self, Error> {
        let mut secret = Zeroizing::new([0; 32]);
        getrandom::fill(secret.as_mut()).map_err(|_| Error::Randomness)?;
        Ok(Self(secret))
    }

    pub fn from_secret(secret: Zeroizing<[u8; 32]>) -> Self {
        Self(secret)
    }

    /// Rust-only access for wrapping keys; this type is not exposed through FFI.
    pub fn secret(&self) -> &[u8; 32] {
        &self.0
    }
    /// Separate metadata domain. A uniform random vault key is suitable PRK
    /// input to HKDF-Expand (RFC 5869 §3.3).
    pub fn metadata_key(&self) -> Result<Self, Error> {
        let mut secret = Zeroizing::new([0; 32]);
        hkdf::Hkdf::<sha2::Sha256>::from_prk(self.secret())
            .map_err(|_| Error::Authentication)?
            .expand(b"openward private metadata v1", secret.as_mut())
            .map_err(|_| Error::Authentication)?;
        Ok(Self::from_secret(secret))
    }
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum Error {
    #[error("encrypted envelope exceeds its size or parent limit")]
    Limit,
    #[error("encrypted envelope is not in canonical v1 form")]
    Encoding,
    #[error("unsupported encrypted envelope version {0}")]
    Version(u64),
    #[error("encrypted envelope belongs to another vault, item or key generation")]
    Context,
    #[error("encrypted envelope signature is invalid")]
    Signature,
    #[error("encrypted envelope authentication failed")]
    Authentication,
    #[error("secure randomness is unavailable")]
    Randomness,
    #[error("unsupported or excessive password derivation parameters")]
    KdfParameters,
    #[error("not enough memory for password derivation")]
    Memory,
}
