//! Local alternate unlock. Native factors and recovery kits wrap account/device
//! seeds, never the master password. Ciphertext is bound to the canonical header.
use crate::{
    Error, codec,
    hierarchy::{UnlockedKeys, VaultHeader},
};
use chacha20poly1305::{
    KeyInit, XChaCha20Poly1305, XNonce,
    aead::{Aead, Payload},
};
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Purpose {
    Native = 1,
    Recovery = 2,
}

fn context(header: &VaultHeader, purpose: Purpose) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(b"openward alternate local unlock v1\0");
    h.update([purpose as u8]);
    if purpose == Purpose::Native {
        // Rewrap/password changes invalidate native enrollment; authenticate it
        // again. A kit must continue to work across a password-only rewrap.
        h.update(header.to_bytes());
    } else {
        h.update(header.vault_id());
        h.update(header.device_id());
        h.update(header.generation().to_be_bytes());
        h.update(header.account().to_bytes());
        h.update(header.certificate().to_bytes());
    }
    h.finalize().into()
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UnlockBox {
    purpose: Purpose,
    context: [u8; 32],
    nonce: [u8; 24],
    ct: Vec<u8>,
}
impl UnlockBox {
    fn prefix(&self) -> Vec<u8> {
        let mut b = codec::record(b"OWLU");
        b.push(self.purpose as u8);
        b.extend(self.context);
        b.extend(self.nonce);
        b
    }
    pub fn seal(
        header: &VaultHeader,
        keys: &UnlockedKeys,
        key: &[u8; 32],
        purpose: Purpose,
    ) -> Result<Self, Error> {
        let mut clear = Zeroizing::new(Vec::with_capacity(96));
        clear.extend_from_slice(keys.account.secret().as_ref());
        clear.extend_from_slice(keys.device.secret().as_ref());
        let checked = header.restore_keys(&clear)?;
        if checked.vault.secret() != keys.vault.secret() {
            return Err(Error::Context);
        }
        let mut b = Self {
            purpose,
            context: context(header, purpose),
            nonce: [0; 24],
            ct: Vec::new(),
        };
        getrandom::fill(&mut b.nonce).map_err(|_| Error::Randomness)?;
        b.ct = XChaCha20Poly1305::new(key.into())
            .encrypt(
                &XNonce::from(b.nonce),
                Payload {
                    msg: &clear,
                    aad: &b.prefix(),
                },
            )
            .map_err(|_| Error::Authentication)?;
        Ok(b)
    }
    pub fn open(
        &self,
        header: &VaultHeader,
        key: &[u8; 32],
        expected: Purpose,
    ) -> Result<UnlockedKeys, Error> {
        if self.purpose != expected || self.context != context(header, expected) {
            return Err(Error::Context);
        }
        let clear = Zeroizing::new(
            XChaCha20Poly1305::new(key.into())
                .decrypt(
                    &XNonce::from(self.nonce),
                    Payload {
                        msg: &self.ct,
                        aad: &self.prefix(),
                    },
                )
                .map_err(|_| Error::Authentication)?,
        );
        header.restore_keys(&clear)
    }
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut b = self.prefix();
        b.extend(&self.ct);
        b
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, Error> {
        if bytes.len() != 174 {
            return Err(Error::Encoding);
        }
        let mut r = codec::Reader::new(bytes, b"OWLU")?;
        let purpose = match r.u8()? {
            1 => Purpose::Native,
            2 => Purpose::Recovery,
            _ => return Err(Error::Encoding),
        };
        let context = r.fixed()?;
        let nonce = r.fixed()?;
        let ct = r.take(112)?.to_vec();
        r.finish()?;
        Ok(Self {
            purpose,
            context,
            nonce,
            ct,
        })
    }
}

/// 256 random bits, independently rotatable from the account and password.
/// Text is deliberately disclosed only for recovery-kit presentation.
pub struct RecoveryKit(Zeroizing<[u8; 32]>);
impl RecoveryKit {
    pub fn generate() -> Result<Self, Error> {
        let mut b = Zeroizing::new([0; 32]);
        getrandom::fill(b.as_mut()).map_err(|_| Error::Randomness)?;
        Ok(Self(b))
    }
    pub fn secret(&self) -> &[u8; 32] {
        &self.0
    }
    fn checksum(&self) -> [u8; 4] {
        let mut h = Sha256::new();
        h.update(b"openward recovery kit checksum v1\0");
        h.update(self.0.as_ref());
        h.finalize()[..4].try_into().unwrap()
    }
    pub fn text(&self) -> Zeroizing<String> {
        use std::fmt::Write;
        let mut text = Zeroizing::new(String::from("OWRK1"));
        for group in self.0.as_chunks::<2>().0 {
            write!(&mut *text, "-{:02X}{:02X}", group[0], group[1]).unwrap();
        }
        text.push('-');
        for byte in self.checksum() {
            write!(&mut *text, "{byte:02X}").unwrap();
        }
        text
    }
    pub fn parse(text: &str) -> Result<Self, Error> {
        if text.len() > 256 || !text.is_ascii() {
            return Err(Error::Limit);
        }
        let compact = Zeroizing::new(
            text.chars()
                .filter(|c| !c.is_ascii_whitespace())
                .map(|c| c.to_ascii_uppercase())
                .collect::<String>(),
        );
        let parts: Vec<_> = compact.split('-').collect();
        if parts.len() != 18 || parts[0] != "OWRK1" || parts[17].len() != 8 {
            return Err(Error::Encoding);
        }
        let mut key = Zeroizing::new([0; 32]);
        for (i, p) in parts[1..17].iter().enumerate() {
            if p.len() != 4 {
                return Err(Error::Encoding);
            }
            key[i * 2] = u8::from_str_radix(&p[..2], 16).map_err(|_| Error::Encoding)?;
            key[i * 2 + 1] = u8::from_str_radix(&p[2..], 16).map_err(|_| Error::Encoding)?;
        }
        let kit = Self(key);
        let checksum = u32::from_str_radix(parts[17], 16).map_err(|_| Error::Encoding)?;
        if checksum.to_be_bytes() != kit.checksum() {
            return Err(Error::Authentication);
        }
        Ok(kit)
    }
}
