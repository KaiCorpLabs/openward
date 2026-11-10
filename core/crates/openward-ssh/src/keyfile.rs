//! Private key files, read with `ssh-key` (through `russh`) as they are,
//! and with one fix when it refuses them.
//!
//! OpenSSH writes an ECDSA private scalar as an `mpint`, which drops
//! leading zero bytes: a P-256 scalar below 2^247, about one key in 512
//! that `ssh-keygen` makes, takes 31 bytes, not 32 (or 33 with the sign
//! byte). `ssh-key` (0.7.0-rc.11 and rc.12) asks for at least 32 bytes and
//! refuses those keys with "length invalid", also once an encrypted one is
//! decrypted (reported upstream: RustCrypto/SSH#620). Here the scalar is
//! padded with zeros to the curve's size and the key read again.
//!
//! P-384 and P-521 keys with a short scalar load as they are (32 bytes is
//! well below their size), but they are padded the same way should that
//! change. PEM, PKCS#8 and PuTTY keys keep a scalar `ssh-key` reads.
//!
//! Every function here first does what `ssh-key` does; the fix only runs
//! when it fails for that reason, so no other key takes another path.

use std::path::Path;

use russh::keys::ssh_key::cipher::Tag;
use russh::keys::ssh_key::encoding::pem::PemLabel;
use russh::keys::ssh_key::encoding::{self, Decode, DecodePem, Encode, Reader};
use russh::keys::ssh_key::{self, Cipher, Kdf, PrivateKey};
use zeroize::Zeroizing;

/// The start of OpenSSH's private key format (`PROTOCOL.key`).
const MAGIC: &[u8; 15] = b"openssh-key-v1\0";

/// [`PrivateKey::from_openssh`], also for an unencrypted key with a short
/// ECDSA scalar. An encrypted key is read without decrypting it.
pub fn from_openssh(text: impl AsRef<[u8]>) -> ssh_key::Result<PrivateKey> {
    let text = text.as_ref();
    match PrivateKey::from_openssh(text) {
        Err(e) if too_short(&e) => padded_pem(text, None).ok_or(e),
        other => other,
    }
}

/// [`PrivateKey::decrypt`], also when the decrypted key has a short ECDSA
/// scalar.
pub fn decrypt(key: &PrivateKey, passphrase: impl AsRef<[u8]>) -> ssh_key::Result<PrivateKey> {
    let passphrase = passphrase.as_ref();
    match key.decrypt(passphrase) {
        Err(e) if too_short(&e) => key
            .to_bytes()
            .ok()
            .and_then(|bytes| padded(&bytes, Some(passphrase)))
            .ok_or(e),
        other => other,
    }
}

/// [`russh::keys::decode_secret_key`] (OpenSSH, PEM, PKCS#8 or PuTTY's
/// format, decrypted with `passphrase`), also for an OpenSSH key with a
/// short ECDSA scalar.
pub fn decode_secret_key(
    text: &str,
    passphrase: Option<&str>,
) -> Result<PrivateKey, russh::keys::Error> {
    match russh::keys::decode_secret_key(text, passphrase) {
        Err(russh::keys::Error::SshKey(e)) if too_short(&e) => {
            padded_pem(text.trim().as_bytes(), passphrase.map(str::as_bytes))
                .ok_or(russh::keys::Error::SshKey(e))
        }
        other => other,
    }
}

/// [`russh::keys::load_secret_key`]: [`decode_secret_key`] on the file at
/// `path`.
pub fn load_secret_key(
    path: impl AsRef<Path>,
    passphrase: Option<&str>,
) -> Result<PrivateKey, russh::keys::Error> {
    let text = Zeroizing::new(std::fs::read_to_string(path)?);
    decode_secret_key(&text, passphrase)
}

/// How `ssh-key` refuses a scalar shorter than it wants.
fn too_short(e: &ssh_key::Error) -> bool {
    matches!(e, ssh_key::Error::Encoding(encoding::Error::Length))
}

/// The bytes of an OpenSSH private key file, its PEM armor removed.
struct Armored(Zeroizing<Vec<u8>>);

impl PemLabel for Armored {
    const PEM_LABEL: &'static str = "OPENSSH PRIVATE KEY";
}

impl Decode for Armored {
    type Error = encoding::Error;

    fn decode(reader: &mut impl Reader) -> encoding::Result<Self> {
        let mut bytes = Zeroizing::new(vec![0; reader.remaining_len()]);
        reader.read(&mut bytes)?;
        Ok(Self(bytes))
    }
}

fn padded_pem(text: &[u8], passphrase: Option<&[u8]>) -> Option<PrivateKey> {
    padded(&Armored::decode_pem(text).ok()?.0, passphrase)
}

/// The key in `bytes` (OpenSSH's format, armor removed), decrypted with
/// `passphrase` if it is encrypted, with its ECDSA scalar padded to the
/// curve's size: `None` when no scalar was short, or the key cannot be
/// read anyway.
fn padded(bytes: &[u8], passphrase: Option<&[u8]>) -> Option<PrivateKey> {
    let r = &mut &*bytes;
    if <[u8; 15]>::decode(r).ok()? != *MAGIC {
        return None;
    }
    let cipher = Cipher::new(&String::decode(r).ok()?).ok()?;
    let kdf = Kdf::decode(r).ok()?;
    if u32::decode(r).ok()? != 1 {
        return None;
    }
    let public = Vec::<u8>::decode(r).ok()?;
    let mut private = Zeroizing::new(Vec::<u8>::decode(r).ok()?);
    if cipher.is_some() {
        // AEAD ciphers put their tag after the private section.
        let tag = if cipher.has_tag() {
            let mut tag = Tag::default();
            let (bytes, rest) = r.split_at_checked(tag.len())?;
            tag.copy_from_slice(bytes);
            *r = rest;
            Some(tag)
        } else {
            None
        };
        let (key, iv) = kdf.derive_key_and_iv(cipher, passphrase?).ok()?;
        cipher.decrypt(&key, &iv, &mut private, tag).ok()?;
    }
    if !r.is_empty() {
        return None;
    }
    let private = padded_private(&private)?;

    let mut out = Zeroizing::new(Vec::new());
    out.extend_from_slice(MAGIC);
    Cipher::None.as_str().encode(&mut *out).ok()?;
    // `none`, and no KDF options.
    Kdf::None.encode(&mut *out).ok()?;
    1u32.encode(&mut *out).ok()?;
    public.encode(&mut *out).ok()?;
    private.encode(&mut *out).ok()?;
    PrivateKey::from_bytes(&out).ok()
}

/// The private section of a decrypted key (checkints, key, comment,
/// padding) with its ECDSA scalar padded, and padded again for no cipher.
fn padded_private(private: &[u8]) -> Option<Zeroizing<Vec<u8>>> {
    let r = &mut &*private;
    let check = u32::decode(r).ok()?;
    if u32::decode(r).ok()? != check {
        return None;
    }
    let algorithm = String::decode(r).ok()?;
    let size = match algorithm.as_str() {
        "ecdsa-sha2-nistp256" => 32,
        "ecdsa-sha2-nistp384" => 48,
        "ecdsa-sha2-nistp521" => 66,
        _ => return None,
    };
    let curve = Vec::<u8>::decode(r).ok()?;
    let point = Vec::<u8>::decode(r).ok()?;
    let scalar = Zeroizing::new(Vec::<u8>::decode(r).ok()?);
    // A positive mpint shorter than the curve: one `ssh-key` may refuse.
    if scalar.is_empty() || scalar.len() >= size || scalar[0] & 0x80 != 0 {
        return None;
    }
    let comment = Vec::<u8>::decode(r).ok()?;
    // The padding as `PROTOCOL.key` has it: 1, 2, 3…, under a block of 16
    // (PuTTYgen writes a whole one).
    if r.len() > 16 || !r.iter().zip(1..).all(|(&b, i)| b == i) {
        return None;
    }

    let mut scalar_bytes = Zeroizing::new(vec![0; size]);
    scalar_bytes[size - scalar.len()..].copy_from_slice(&scalar);
    let mut out = Zeroizing::new(Vec::new());
    check.encode(&mut *out).ok()?;
    check.encode(&mut *out).ok()?;
    algorithm.encode(&mut *out).ok()?;
    curve.encode(&mut *out).ok()?;
    point.encode(&mut *out).ok()?;
    scalar_bytes.encode(&mut *out).ok()?;
    comment.encode(&mut *out).ok()?;
    let padding = Cipher::None.padding_len(out.len());
    out.extend((1..=16u8).take(padding));
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use russh::keys::ssh_key::{EcdsaCurve, LineEnding, PublicKey};

    /// Keys made by `ssh-keygen` (OpenSSH 10.5) whose ECDSA scalar is short:
    /// 31 bytes for P-256, 47 for P-384, 64 for P-521. Test material only.
    fn fixture(name: &str) -> String {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
        std::fs::read_to_string(path.join(name)).unwrap()
    }

    const PASSPHRASE: &str = "openward-test";

    fn p256_public() -> PublicKey {
        PublicKey::from_openssh(fixture("ecdsa-p256-short.pub").trim()).unwrap()
    }

    #[test]
    fn ssh_key_still_refuses_a_short_p256_scalar() {
        // When this fails, `ssh-key` reads them itself and this module can go.
        let e = PrivateKey::from_openssh(fixture("ecdsa-p256-short")).unwrap_err();
        assert!(too_short(&e), "{e:?}");
        let encrypted = PrivateKey::from_openssh(fixture("ecdsa-p256-short-aes256-ctr")).unwrap();
        let e = encrypted.decrypt(PASSPHRASE).unwrap_err();
        assert!(too_short(&e), "{e:?}");
    }

    #[test]
    fn a_short_p256_scalar_is_padded() {
        let key = from_openssh(fixture("ecdsa-p256-short")).unwrap();
        assert_eq!(key.public_key().key_data(), p256_public().key_data());
        assert_eq!(key.comment().as_str_lossy(), "openward-test-p256-short");
        assert!(!key.is_encrypted());
        let scalar = key.key_data().ecdsa().unwrap().private_key_bytes();
        assert_eq!(scalar.len(), 32);
        assert_eq!(scalar[0], 0);

        // It signs, and the signature checks with the public key.
        let sig = key
            .sign("openward", ssh_key::HashAlg::Sha256, b"m")
            .unwrap();
        p256_public()
            .verify("openward", b"m", &sig)
            .expect("signature from the padded key");
    }

    #[test]
    fn an_encrypted_short_p256_scalar_is_padded_once_decrypted() {
        for cipher in ["aes256-ctr", "aes256-gcm", "chacha20-poly1305"] {
            let text = fixture(&format!("ecdsa-p256-short-{cipher}"));
            let encrypted = from_openssh(&text).unwrap();
            assert!(encrypted.is_encrypted(), "{cipher}");
            assert_eq!(encrypted.cipher().as_str().split('@').next(), Some(cipher));

            let key = decrypt(&encrypted, PASSPHRASE).unwrap();
            assert_eq!(key.public_key().key_data(), p256_public().key_data());
            assert!(!key.is_encrypted());

            let key = decode_secret_key(&text, Some(PASSPHRASE)).unwrap();
            assert_eq!(key.public_key().key_data(), p256_public().key_data());

            // A wrong passphrase is still wrong, and says the same.
            let wrong = decrypt(&encrypted, "wrong").unwrap_err();
            assert!(
                matches!(wrong, ssh_key::Error::Crypto),
                "{cipher}: {wrong:?}"
            );
            assert!(decode_secret_key(&text, Some("wrong")).is_err());
            assert!(matches!(
                decode_secret_key(&text, None),
                Err(russh::keys::Error::KeyIsEncrypted)
            ));
        }
    }

    #[test]
    fn russh_s_loader_reads_it_too() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/ecdsa-p256-short");
        let key = load_secret_key(&path, None).unwrap();
        assert_eq!(key.public_key().key_data(), p256_public().key_data());
        // And through the connection's loader, with or without a passphrase.
        assert!(crate::client::load_key(&path, None).is_ok());
        let encrypted = path.with_file_name("ecdsa-p256-short-aes256-ctr");
        let key = crate::client::load_key(&encrypted, Some(PASSPHRASE)).unwrap();
        assert_eq!(key.public_key().key_data(), p256_public().key_data());
        assert!(matches!(
            crate::client::load_key(&encrypted, None),
            Err(crate::client::KeyError::Encrypted)
        ));
        assert!(matches!(
            crate::client::load_key(&encrypted, Some("wrong")),
            Err(crate::client::KeyError::WrongPassphrase)
        ));
    }

    #[test]
    fn with_windows_line_endings_too() {
        // As a key pasted on Windows comes, or a checkout there.
        let crlf = |name| fixture(name).replace("\r\n", "\n").replace('\n', "\r\n");
        assert!(from_openssh(crlf("ecdsa-p256-short")).is_ok());
        assert!(decode_secret_key(&crlf("ecdsa-p256-short"), None).is_ok());
        let text = crlf("ecdsa-p256-short-aes256-gcm");
        assert!(decode_secret_key(&text, Some(PASSPHRASE)).is_ok());
        assert!(decrypt(&from_openssh(&text).unwrap(), PASSPHRASE).is_ok());
    }

    #[test]
    fn p384_and_p521_short_scalars_load() {
        for (name, curve, size) in [
            ("ecdsa-p384-short", EcdsaCurve::NistP384, 48),
            ("ecdsa-p521-short", EcdsaCurve::NistP521, 66),
        ] {
            let key = from_openssh(fixture(name)).unwrap();
            let ecdsa = key.key_data().ecdsa().unwrap();
            assert_eq!(ecdsa.curve(), curve);
            assert_eq!(ecdsa.private_key_bytes().len(), size);
            assert_eq!(ecdsa.private_key_bytes()[0], 0, "{name}");
            // And so does what the fix makes of them.
            let bytes = Armored::decode_pem(fixture(name)).unwrap().0;
            let fixed = padded(&bytes, None).unwrap();
            assert_eq!(fixed, key);
        }
    }

    #[test]
    fn a_padded_key_written_again_reads_back() {
        let key = from_openssh(fixture("ecdsa-p256-short")).unwrap();
        let text = key.to_openssh(LineEnding::LF).unwrap();
        // Written by `ssh-key`, the scalar has its 32 bytes: no fix needed.
        let again = PrivateKey::from_openssh(&*text).unwrap();
        assert_eq!(again, key);
    }

    #[test]
    fn other_keys_are_left_to_ssh_key() {
        // A full-length scalar: nothing to pad, so no second reading.
        let key = from_openssh(fixture("ecdsa-p256-short")).unwrap();
        let bytes = key.to_bytes().unwrap();
        assert!(padded(&bytes, None).is_none());
        // Not a key at all: `ssh-key`'s own error.
        assert!(from_openssh("not a key").is_err());
        assert!(decode_secret_key("not a key", None).is_err());
        // Cut short: refused, not read past its end.
        let mut bytes = Armored::decode_pem(fixture("ecdsa-p256-short")).unwrap().0;
        for len in (0..bytes.len()).rev() {
            bytes.truncate(len);
            assert!(padded(&bytes, None).is_none(), "{len}");
        }
    }
}
