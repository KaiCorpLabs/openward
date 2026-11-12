//! D0-1: the portable account package needs both password and recovery kit.
//! The local kit cache is separate ciphertext, encrypted with the vault key;
//! neither that cache nor a password-only local header belongs on a server.
use crate::{
    Error, codec,
    hierarchy::{AccountKey, AccountPublic, UnlockedKeys, VaultHeader},
    password::KdfParams,
    unlock::RecoveryKit,
};
use chacha20poly1305::{
    KeyInit, XChaCha20Poly1305, XNonce,
    aead::{Aead, Payload},
};
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AccountPackage {
    account: AccountPublic,
    params: KdfParams,
    salt: [u8; 16],
    nonce: [u8; 24],
    ciphertext: Vec<u8>,
}
impl AccountPackage {
    pub fn account(&self) -> &AccountPublic {
        &self.account
    }
    fn prefix(&self) -> Vec<u8> {
        let mut b = codec::record(b"OWRP");
        codec::blob(&mut b, &self.account.to_bytes());
        b.extend(self.params.memory_kib().to_be_bytes());
        b.extend(self.params.passes().to_be_bytes());
        b.extend(self.salt);
        b.extend(self.nonce);
        b
    }
    fn key(&self, password: &[u8], kit: &RecoveryKit) -> Result<Zeroizing<[u8; 32]>, Error> {
        let derived = self.params.derive(password, &self.salt)?;
        let mut key = Zeroizing::new([0; 32]);
        // HKDF-Extract salt is an independent 256-bit secret. A server cannot
        // verify a password guess without the kit, even knowing account public.
        hkdf::Hkdf::<Sha256>::new(Some(kit.secret()), derived.as_ref())
            .expand(
                &[
                    b"openward remote account package v1\0".as_slice(),
                    &self.prefix(),
                ]
                .concat(),
                key.as_mut(),
            )
            .map_err(|_| Error::Authentication)?;
        Ok(key)
    }
    pub fn seal(
        account: &AccountKey,
        password: &[u8],
        kit: &RecoveryKit,
        params: KdfParams,
    ) -> Result<Self, Error> {
        let mut b = Self {
            account: account.public().clone(),
            params,
            salt: [0; 16],
            nonce: [0; 24],
            ciphertext: Vec::new(),
        };
        getrandom::fill(&mut b.salt).map_err(|_| Error::Randomness)?;
        getrandom::fill(&mut b.nonce).map_err(|_| Error::Randomness)?;
        let key = b.key(password, kit)?;
        b.ciphertext = XChaCha20Poly1305::new((&*key).into())
            .encrypt(
                &XNonce::from(b.nonce),
                Payload {
                    msg: account.secret().as_ref(),
                    aad: &b.prefix(),
                },
            )
            .map_err(|_| Error::Authentication)?;
        Ok(b)
    }
    pub fn open(&self, password: &[u8], kit: &RecoveryKit) -> Result<AccountKey, Error> {
        let key = self.key(password, kit)?;
        let clear = Zeroizing::new(
            XChaCha20Poly1305::new((&*key).into())
                .decrypt(
                    &XNonce::from(self.nonce),
                    Payload {
                        msg: &self.ciphertext,
                        aad: &self.prefix(),
                    },
                )
                .map_err(|_| Error::Authentication)?,
        );
        let account = AccountKey::from_secret(
            self.account.suite(),
            Zeroizing::new(clear.as_slice().try_into().map_err(|_| Error::Encoding)?),
        )?;
        if account.public() != &self.account {
            return Err(Error::Context);
        }
        Ok(account)
    }
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut b = self.prefix();
        b.extend(&self.ciphertext);
        b
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, Error> {
        if bytes.len() > 2200 {
            return Err(Error::Limit);
        }
        let mut r = codec::Reader::new(bytes, b"OWRP")?;
        let account = AccountPublic::from_bytes(r.blob(2048)?)?;
        let params = KdfParams::new(r.u32()?, r.u32()?)?;
        let salt = r.fixed()?;
        let nonce = r.fixed()?;
        let ciphertext = r.take(80)?.to_vec();
        r.finish()?;
        Ok(Self {
            account,
            params,
            salt,
            nonce,
            ciphertext,
        })
    }
}

/// Local only. Enables password changes without asking for the saved kit again.
/// A distinct HKDF domain and stable identity AAD bind it to this device/vault.
pub fn seal_local_kit(
    header: &VaultHeader,
    keys: &UnlockedKeys,
    kit: &RecoveryKit,
) -> Result<Vec<u8>, Error> {
    let mut b = codec::record(b"OWKS");
    let mut nonce = [0; 24];
    getrandom::fill(&mut nonce).map_err(|_| Error::Randomness)?;
    b.extend(nonce);
    let key = cache_key(keys)?;
    let ct = XChaCha20Poly1305::new((&*key).into())
        .encrypt(
            &XNonce::from(nonce),
            Payload {
                msg: kit.secret(),
                aad: &cache_aad(header, &b),
            },
        )
        .map_err(|_| Error::Authentication)?;
    b.extend(ct);
    Ok(b)
}
pub fn open_local_kit(
    bytes: &[u8],
    header: &VaultHeader,
    keys: &UnlockedKeys,
) -> Result<RecoveryKit, Error> {
    if bytes.len() != 77 {
        return Err(Error::Encoding);
    }
    let mut r = codec::Reader::new(bytes, b"OWKS")?;
    let nonce = r.fixed::<24>()?;
    let ct = r.take(48)?;
    r.finish()?;
    let key = cache_key(keys)?;
    let clear = Zeroizing::new(
        XChaCha20Poly1305::new((&*key).into())
            .decrypt(
                &XNonce::from(nonce),
                Payload {
                    msg: ct,
                    aad: &cache_aad(header, &bytes[..29]),
                },
            )
            .map_err(|_| Error::Authentication)?,
    );
    Ok(RecoveryKit::from_secret(Zeroizing::new(
        clear.as_slice().try_into().map_err(|_| Error::Encoding)?,
    )))
}
fn cache_key(keys: &UnlockedKeys) -> Result<Zeroizing<[u8; 32]>, Error> {
    let mut key = Zeroizing::new([0; 32]);
    hkdf::Hkdf::<Sha256>::from_prk(keys.vault.secret())
        .map_err(|_| Error::Authentication)?
        .expand(b"openward local recovery cache v1", key.as_mut())
        .map_err(|_| Error::Authentication)?;
    Ok(key)
}
fn cache_aad(header: &VaultHeader, prefix: &[u8]) -> Vec<u8> {
    let mut h = Sha256::new();
    h.update(b"openward local recovery cache identity v1\0");
    h.update(header.vault_id());
    h.update(header.device_id());
    h.update(header.generation().to_be_bytes());
    h.update(header.account().to_bytes());
    [prefix, &h.finalize()].concat()
}
