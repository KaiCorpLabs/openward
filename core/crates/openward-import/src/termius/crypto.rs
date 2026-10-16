//! Termius's encrypted fields: base64 of a two-byte version (`04 01`),
//! a 24-byte nonce and NaCl's secretbox (XSalsa20-Poly1305) of the text,
//! under the 32-byte key Termius keeps in the system keychain.

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD;
use crypto_secretbox::aead::{Aead, KeyInit};
use crypto_secretbox::{Nonce, XSalsa20Poly1305};

const VERSION: [u8; 2] = [0x04, 0x01];
const NONCE: usize = 24;
const TAG: usize = 16;

/// The decoded bytes of an encrypted field: never guessed from "looks like
/// base64", only from the version header and a length that can hold it.
fn envelope(field: &str) -> Option<Vec<u8>> {
    let bytes = STANDARD.decode(field.trim()).ok()?;
    (bytes.len() >= VERSION.len() + NONCE + TAG && bytes[..2] == VERSION).then_some(bytes)
}

pub fn is_encrypted(field: &str) -> bool {
    envelope(field).is_some()
}

#[derive(Debug, PartialEq, Eq)]
pub enum Error {
    NotEncrypted,
    /// Wrong key, or a damaged field.
    WrongKey,
    NotText,
}

/// The key from its keychain form: base64 of 32 bytes.
pub fn key_from_keychain(stored: &str) -> Option<[u8; 32]> {
    STANDARD.decode(stored.trim()).ok()?.try_into().ok()
}

pub fn decrypt(key: &[u8; 32], field: &str) -> Result<String, Error> {
    let bytes = envelope(field).ok_or(Error::NotEncrypted)?;
    let (nonce, sealed) = bytes[2..].split_at(NONCE);
    let plain = XSalsa20Poly1305::new(key.into())
        .decrypt(Nonce::from_slice(nonce), sealed)
        .map_err(|_| Error::WrongKey)?;
    String::from_utf8(plain).map_err(|_| Error::NotText)
}

/// Encrypts as Termius does: for tests and fixtures.
pub fn encrypt(key: &[u8; 32], nonce: &[u8; NONCE], text: &str) -> String {
    let sealed = XSalsa20Poly1305::new(key.into())
        .encrypt(Nonce::from_slice(nonce), text.as_bytes())
        .expect("secretbox never fails to encrypt");
    let mut out = VERSION.to_vec();
    out.extend_from_slice(nonce);
    out.extend(sealed);
    STANDARD.encode(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_and_a_wrong_key() {
        let key = [7u8; 32];
        let field = encrypt(&key, &[1; NONCE], "web-1.example.com");
        assert!(is_encrypted(&field));
        assert_eq!(decrypt(&key, &field).unwrap(), "web-1.example.com");
        assert_eq!(decrypt(&[8u8; 32], &field), Err(Error::WrongKey));
    }

    #[test]
    fn plain_text_is_not_mistaken_for_a_field() {
        assert!(!is_encrypted("web-1.example.com"));
        // Valid base64 of the right length but without the version.
        assert!(!is_encrypted(&STANDARD.encode([0u8; 48])));
        // An empty text still has the header, nonce and tag.
        assert!(is_encrypted(&encrypt(&[1; 32], &[2; NONCE], "")));
    }
}
