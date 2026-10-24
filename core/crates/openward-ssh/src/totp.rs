//! TOTP codes (RFC 6238: HMAC-SHA1, 30 s steps, 6 digits), as Google
//! Authenticator and most 2FA PAM modules use. The test servers' secret
//! comes from the fixtures; a product would ask the user instead.

use hmac::{Hmac, KeyInit, Mac};
use sha1::Sha1;

pub fn code(secret_base32: &str, unix_time: u64) -> anyhow::Result<String> {
    let secret = data_encoding::BASE32_NOPAD
        .decode(secret_base32.trim().trim_end_matches('=').as_bytes())
        .map_err(|e| anyhow::anyhow!("TOTP secret is not base32: {e}"))?;
    let counter = unix_time / 30;
    let mut mac = Hmac::<Sha1>::new_from_slice(&secret)?;
    mac.update(&counter.to_be_bytes());
    let hash = mac.finalize().into_bytes();
    let offset = usize::from(hash[19] & 0x0F);
    let bin = u32::from_be_bytes([
        hash[offset] & 0x7F,
        hash[offset + 1],
        hash[offset + 2],
        hash[offset + 3],
    ]);
    Ok(format!("{:06}", bin % 1_000_000))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_rfc_6238_vectors() {
        // RFC 6238 appendix B, SHA-1 secret "12345678901234567890".
        let secret = data_encoding::BASE32_NOPAD.encode(b"12345678901234567890");
        assert_eq!(code(&secret, 59).unwrap(), "287082");
        assert_eq!(code(&secret, 1_111_111_109).unwrap(), "081804");
        assert_eq!(code(&secret, 2_000_000_000).unwrap(), "279037");
    }
}
