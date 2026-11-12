//! Portable OWVA1: authenticated whole-archive encryption, independent of paths.
use crate::{
    Error, VaultKey, codec,
    hierarchy::VaultHeader,
    unlock::{Purpose, RecoveryKit, UnlockBox},
};
use chacha20poly1305::{
    KeyInit, XChaCha20Poly1305, XNonce,
    aead::{Aead, Payload},
};
use zeroize::Zeroizing;

pub const MAX_PAYLOAD: usize = 64 * 1024 * 1024;
pub const MAX_ARCHIVE: usize = MAX_PAYLOAD + 17 * 1024;
fn key(vault: &VaultKey) -> Result<Zeroizing<[u8; 32]>, Error> {
    let mut out = Zeroizing::new([0; 32]);
    hkdf::Hkdf::<sha2::Sha256>::from_prk(vault.secret())
        .map_err(|_| Error::Authentication)?
        .expand(b"openward vault backup v1\0", out.as_mut())
        .map_err(|_| Error::Authentication)?;
    Ok(out)
}
pub fn seal(
    header: &VaultHeader,
    recovery: &[u8],
    vault: &VaultKey,
    clear: &[u8],
) -> Result<Vec<u8>, Error> {
    if clear.len() > MAX_PAYLOAD || recovery.len() > 512 {
        return Err(Error::Limit);
    }
    // Require a valid portable kit wrapper, never an OS-bound native record.
    UnlockBox::from_bytes(recovery)?;
    let mut out = codec::record(b"OWVA");
    codec::blob(&mut out, &header.to_bytes());
    codec::blob(&mut out, recovery);
    let mut nonce = [0; 24];
    getrandom::fill(&mut nonce).map_err(|_| Error::Randomness)?;
    out.extend(nonce);
    let k = key(vault)?;
    let ct = XChaCha20Poly1305::new((&*k).into())
        .encrypt(
            &XNonce::from(nonce),
            Payload {
                msg: clear,
                aad: &out,
            },
        )
        .map_err(|_| Error::Authentication)?;
    out.extend(ct);
    Ok(out)
}
pub fn open(bytes: &[u8], credential: &[u8], use_kit: bool) -> Result<Zeroizing<Vec<u8>>, Error> {
    if bytes.len() > MAX_ARCHIVE {
        return Err(Error::Limit);
    }
    let mut r = codec::Reader::new(bytes, b"OWVA")?;
    let h = r.blob(16 * 1024)?;
    let recovery = r.blob(512)?;
    let nonce: [u8; 24] = r.fixed()?;
    let prefix = 5 + 2 + h.len() + 2 + recovery.len() + 24;
    if bytes.len() < prefix + 16 {
        return Err(Error::Encoding);
    }
    let header = VaultHeader::from_bytes(h)?;
    let recovery = UnlockBox::from_bytes(recovery)?;
    let keys = if use_kit {
        let kit =
            RecoveryKit::parse(std::str::from_utf8(credential).map_err(|_| Error::Encoding)?)?;
        recovery.open(&header, kit.secret(), Purpose::Recovery)?
    } else {
        header.unlock(credential)?
    };
    let k = key(&keys.vault)?;
    XChaCha20Poly1305::new((&*k).into())
        .decrypt(
            &XNonce::from(nonce),
            Payload {
                msg: &bytes[prefix..],
                aad: &bytes[..prefix],
            },
        )
        .map(Zeroizing::new)
        .map_err(|_| Error::Authentication)
}
