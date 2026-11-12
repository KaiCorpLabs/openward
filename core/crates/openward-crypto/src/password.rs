//! Argon2id v19 → local KEK. Parameters are validated before allocating memory.
use crate::{Error, codec};
use argon2::{Algorithm, Argon2, Block, Params, Version};
use chacha20poly1305::{
    KeyInit, XChaCha20Poly1305, XNonce,
    aead::{Aead, Payload},
};
use std::time::{Duration, Instant};
use zeroize::Zeroizing;

pub const MIN_MEMORY_KIB: u32 = 64 * 1024;
const MAX_MEMORY_KIB: u32 = 256 * 1024;
const MAX_WORK_KIB: u32 = 2 * 1024 * 1024;
pub const MAX_SECRET_BYTES: usize = 4096;
pub const MAX_CONTEXT_BYTES: usize = 8192;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KdfParams {
    memory_kib: u32,
    passes: u32,
}
impl KdfParams {
    pub fn new(memory_kib: u32, passes: u32) -> Result<Self, Error> {
        if !(MIN_MEMORY_KIB..=MAX_MEMORY_KIB).contains(&memory_kib)
            || !memory_kib.is_multiple_of(4)
            || !(1..=16).contains(&passes)
            || memory_kib
                .checked_mul(passes)
                .is_none_or(|n| n > MAX_WORK_KIB)
        {
            return Err(Error::KdfParameters);
        }
        Ok(Self { memory_kib, passes })
    }
    pub fn memory_kib(self) -> u32 {
        self.memory_kib
    }
    pub fn passes(self) -> u32 {
        self.passes
    }
    pub fn derive(self, password: &[u8], salt: &[u8; 16]) -> Result<Zeroizing<[u8; 32]>, Error> {
        Self::new(self.memory_kib, self.passes)?;
        if password.is_empty() || password.len() > MAX_SECRET_BYTES {
            return Err(Error::Limit);
        }
        let p = Params::new(self.memory_kib, self.passes, 1, Some(32))
            .map_err(|_| Error::KdfParameters)?;
        let mut blocks = Zeroizing::new(Vec::<Block>::new());
        blocks
            .try_reserve_exact(p.block_count())
            .map_err(|_| Error::Memory)?;
        blocks.resize_with(p.block_count(), Block::default);
        let mut key = Zeroizing::new([0; 32]);
        Argon2::new(Algorithm::Argon2id, Version::V0x13, p)
            .hash_password_into_with_memory(password, salt, key.as_mut(), blocks.as_mut_slice())
            .map_err(|_| Error::KdfParameters)?;
        Ok(key)
    }
}
impl Default for KdfParams {
    fn default() -> Self {
        Self {
            memory_kib: MIN_MEMORY_KIB,
            passes: 3,
        }
    }
}

/// Run on a Rust worker at setup. The measured result is returned, including
/// when a slow/fast machine cannot meet the target within the resource policy.
pub fn calibrate() -> Result<(KdfParams, Duration), Error> {
    let mut passes = 1;
    let mut memory = MIN_MEMORY_KIB;
    loop {
        let params = KdfParams::new(memory, passes)?;
        let start = Instant::now();
        drop(params.derive(b"openward calibration probe", &[0; 16])?);
        let elapsed = start.elapsed();
        if elapsed >= Duration::from_millis(500) {
            return Ok((params, elapsed));
        }
        if passes == 16 {
            if memory == MIN_MEMORY_KIB {
                memory *= 2;
                continue;
            }
            return Ok((params, elapsed));
        }
        let next = ((passes as u128 * 750) / elapsed.as_millis().max(1))
            .clamp(passes as u128 + 1, 16) as u32;
        passes = next;
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PasswordBox {
    params: KdfParams,
    salt: [u8; 16],
    nonce: [u8; 24],
    ciphertext: Vec<u8>,
}
impl PasswordBox {
    fn prefix(&self) -> Vec<u8> {
        let mut out = codec::record(b"OWKB");
        out.extend(self.params.memory_kib.to_be_bytes());
        out.extend(self.params.passes.to_be_bytes());
        out.extend(self.salt);
        out.extend(self.nonce);
        out
    }
    fn aad(&self, context: &[u8]) -> Result<Vec<u8>, Error> {
        if context.len() > MAX_CONTEXT_BYTES {
            return Err(Error::Limit);
        }
        Ok([
            b"openward local key box v1\0".as_slice(),
            &self.prefix(),
            context,
        ]
        .concat())
    }
    pub fn seal(
        password: &[u8],
        params: KdfParams,
        context: &[u8],
        secret: &[u8],
    ) -> Result<Self, Error> {
        if secret.len() > MAX_SECRET_BYTES || context.len() > MAX_CONTEXT_BYTES {
            return Err(Error::Limit);
        }
        let mut b = Self {
            params,
            salt: [0; 16],
            nonce: [0; 24],
            ciphertext: Vec::new(),
        };
        getrandom::fill(&mut b.salt).map_err(|_| Error::Randomness)?;
        getrandom::fill(&mut b.nonce).map_err(|_| Error::Randomness)?;
        let key = params.derive(password, &b.salt)?;
        b.ciphertext = XChaCha20Poly1305::new((&*key).into())
            .encrypt(
                &XNonce::from(b.nonce),
                Payload {
                    msg: secret,
                    aad: &b.aad(context)?,
                },
            )
            .map_err(|_| Error::Authentication)?;
        Ok(b)
    }
    pub fn open(&self, password: &[u8], context: &[u8]) -> Result<Zeroizing<Vec<u8>>, Error> {
        let aad = self.aad(context)?;
        let key = self.params.derive(password, &self.salt)?;
        XChaCha20Poly1305::new((&*key).into())
            .decrypt(
                &XNonce::from(self.nonce),
                Payload {
                    msg: &self.ciphertext,
                    aad: &aad,
                },
            )
            .map(Zeroizing::new)
            .map_err(|_| Error::Authentication)
    }
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = self.prefix();
        codec::blob(&mut out, &self.ciphertext);
        out
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, Error> {
        let mut r = codec::Reader::new(bytes, b"OWKB")?;
        let params = KdfParams::new(r.u32()?, r.u32()?)?;
        let salt = r.fixed()?;
        let nonce = r.fixed()?;
        let ciphertext = r.blob(MAX_SECRET_BYTES + 16)?;
        if ciphertext.len() < 16 {
            return Err(Error::Encoding);
        }
        let ciphertext = ciphertext.to_vec();
        r.finish()?;
        Ok(Self {
            params,
            salt,
            nonce,
            ciphertext,
        })
    }
    pub fn params(&self) -> KdfParams {
        self.params
    }
}
