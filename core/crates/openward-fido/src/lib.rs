//! Security keys (FIDO2) for SSH: the `sk-ssh-ed25519@openssh.com` and
//! `sk-ecdsa-sha2-nistp256@openssh.com` keys of OpenSSH 8.2+, whose
//! secret never leaves the key (ADR-003).
//!
//! The private key file holds no secret: its public half, the key's handle
//! for it (the credential id) and its flags. Signing asks the key for an
//! assertion over `SHA-256(data)` for the application `ssh:`, touched (and
//! with its PIN when the key file says so), and makes OpenSSH's signature
//! from it: the key's signature, its flags and its counter (PROTOCOL.u2f).
//!
//! [`Authenticator`] is what talks to a key: over USB HID on desktop
//! ([`hid`]), or in software for the tests ([`soft`]).

use ssh_key::private::{KeypairData, SkEcdsaSha2NistP256 as SkEcdsaPair, SkEd25519 as SkEdPair};
use ssh_key::public::{SkEcdsaSha2NistP256, SkEd25519};
use ssh_key::{Algorithm, PrivateKey, Signature};

#[cfg(feature = "hid")]
pub mod hid;
#[cfg(any(test, feature = "soft"))]
pub mod soft;

/// The application OpenSSH uses (`ssh:`), and so the one keys are made
/// for.
pub const APPLICATION: &str = "ssh:";

/// The key was touched (user presence).
pub const USER_PRESENCE: u8 = 0x01;
/// Its PIN (or fingerprint) was checked: asked for by keys made with
/// `verify-required`.
pub const USER_VERIFIED: u8 = 0x04;

/// Which kind of security key.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Ed25519,
    /// ECDSA on P-256: every FIDO2 key has it, not all have Ed25519.
    Ecdsa,
}

/// What a key answered: its flags, its counter, and its signature over
/// `SHA-256("ssh:") ‖ flags ‖ counter ‖ SHA-256(data)`, as SSH writes it
/// (Ed25519's 64 bytes; ECDSA's `r` and `s` as two mpints).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Assertion {
    pub flags: u8,
    pub counter: u32,
    pub signature: Vec<u8>,
}

/// A credential just made on a key.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Made {
    pub kind: Kind,
    /// Ed25519's 32 bytes, or P-256's uncompressed point (65).
    pub public: Vec<u8>,
    /// The key's id for it.
    pub key_handle: Vec<u8>,
    /// What signing will ask: presence, and verification if made so.
    pub flags: u8,
}

#[derive(Clone, Debug, thiserror::Error, PartialEq, Eq)]
pub enum FidoError {
    /// No security key is plugged in.
    #[error("no security key is plugged in")]
    NoKey,
    /// More than one: which is not clear.
    #[error("more than one security key is plugged in")]
    TooManyKeys,
    /// The key asks for its PIN.
    #[error("the security key asks for its PIN")]
    PinRequired,
    #[error("wrong PIN")]
    WrongPin,
    /// Too many wrong PINs: it is locked until it is unplugged (or reset).
    #[error("the security key is locked")]
    Locked,
    /// It was not touched in time.
    #[error("the security key was not touched")]
    NotTouched,
    /// This key does not hold that credential: another key's file.
    #[error("this security key does not hold that key")]
    NotThisKey,
    /// The operating system does not let this program talk to the key:
    /// Windows without administrator rights, Linux without a udev rule
    /// for `/dev/hidraw*`.
    #[error("the system does not let OpenWard talk to the security key")]
    NoAccess,
    #[error("security key: {0}")]
    Other(String),
}

/// What talks to a security key. Its calls block while the key waits for
/// a touch: run them off the async runtime.
pub trait Authenticator: Send + Sync {
    /// Signs `data` with the credential `key_handle` of `application`.
    fn assert(
        &self,
        application: &str,
        key_handle: &[u8],
        data: &[u8],
        pin: Option<&str>,
    ) -> Result<Assertion, FidoError>;

    /// Makes a new credential for `application`, verified by PIN when
    /// `verify` (`verify-required`).
    fn make(
        &self,
        kind: Kind,
        application: &str,
        pin: Option<&str>,
        verify: bool,
    ) -> Result<Made, FidoError>;
}

/// Whether `key` is a security key's.
pub fn is_security_key(key: &PrivateKey) -> bool {
    matches!(
        key.key_data(),
        KeypairData::SkEd25519(_) | KeypairData::SkEcdsaSha2NistP256(_)
    )
}

/// Whether signing with `key` needs its PIN (made with `verify-required`).
pub fn needs_pin(key: &PrivateKey) -> bool {
    parts(key).is_some_and(|(_, flags, _, _)| flags & USER_VERIFIED != 0)
}

/// The algorithm, flags, handle and application of a security key's file.
fn parts(key: &PrivateKey) -> Option<(Algorithm, u8, &[u8], &str)> {
    match key.key_data() {
        KeypairData::SkEd25519(k) => Some((
            Algorithm::SkEd25519,
            k.flags(),
            k.key_handle(),
            k.public().application(),
        )),
        KeypairData::SkEcdsaSha2NistP256(k) => Some((
            Algorithm::SkEcdsaSha2NistP256,
            k.flags(),
            k.key_handle(),
            k.public().application(),
        )),
        _ => None,
    }
}

/// OpenSSH's signature of `data` with the security key whose file is
/// `key`, ready for SSH (its encoding, without the outer length).
pub fn sign(
    auth: &dyn Authenticator,
    key: &PrivateKey,
    data: &[u8],
    pin: Option<&str>,
) -> Result<Vec<u8>, FidoError> {
    let (algorithm, flags, handle, application) =
        parts(key).ok_or_else(|| FidoError::Other("not a security key's file".into()))?;
    let pin = if flags & USER_VERIFIED != 0 {
        pin
    } else {
        None
    };
    let a = auth.assert(application, handle, data, pin)?;
    let mut raw = a.signature;
    raw.push(a.flags);
    raw.extend(a.counter.to_be_bytes());
    let signature = Signature::new(algorithm, raw).map_err(|e| FidoError::Other(e.to_string()))?;
    ssh_key::encoding::Encode::encode_vec(&signature).map_err(|e| FidoError::Other(e.to_string()))
}

/// A new key on the security key: the file to save (no secret in it) and,
/// from it, its public half.
pub fn new_key(
    auth: &dyn Authenticator,
    kind: Kind,
    comment: &str,
    pin: Option<&str>,
    verify: bool,
) -> Result<PrivateKey, FidoError> {
    let made = auth.make(kind, APPLICATION, pin, verify)?;
    let bad = |e: ssh_key::Error| FidoError::Other(e.to_string());
    let pair = match made.kind {
        Kind::Ed25519 => {
            let public: [u8; 32] = made
                .public
                .as_slice()
                .try_into()
                .map_err(|_| FidoError::Other("an Ed25519 key of another size".into()))?;
            let public = SkEd25519::new(ssh_key::public::Ed25519PublicKey(public), APPLICATION);
            KeypairData::SkEd25519(SkEdPair::new(public, made.flags, made.key_handle).map_err(bad)?)
        }
        Kind::Ecdsa => {
            let point =
                ssh_key::sec1::EncodedPoint::<ssh_key::sec1::consts::U32>::from_bytes(&made.public)
                    .map_err(|_| FidoError::Other("not a P-256 point".into()))?;
            let public = SkEcdsaSha2NistP256::new(point, APPLICATION);
            KeypairData::SkEcdsaSha2NistP256(
                SkEcdsaPair::new(public, made.flags, made.key_handle).map_err(bad)?,
            )
        }
    };
    PrivateKey::new(pair, comment).map_err(bad)
}

/// `SEQUENCE { INTEGER r, INTEGER s }` (an authenticator's ECDSA
/// signature) as SSH writes ECDSA: two mpints.
pub fn ecdsa_der_to_ssh(der: &[u8]) -> Result<Vec<u8>, FidoError> {
    let bad = || FidoError::Other("an ECDSA signature that does not read".into());
    let mut at = 0usize;
    let mut take = |want: u8| -> Result<Vec<u8>, FidoError> {
        if der.get(at) != Some(&want) {
            return Err(bad());
        }
        let len = *der.get(at + 1).ok_or_else(bad)? as usize;
        if len >= 0x80 {
            return Err(bad());
        }
        let start = at + 2;
        let body = der.get(start..start + len).ok_or_else(bad)?.to_vec();
        at = start + if want == 0x30 { 0 } else { len };
        Ok(body)
    };
    take(0x30)?;
    let r = take(0x02)?;
    let s = take(0x02)?;
    let mut out = Vec::new();
    for n in [r, s] {
        // Minimal, positive: what OpenSSH's mpint is.
        let trimmed: Vec<u8> = n.iter().copied().skip_while(|&b| b == 0).collect();
        let mut v = if trimmed.first().is_some_and(|&b| b & 0x80 != 0) {
            vec![0]
        } else {
            Vec::new()
        };
        v.extend(trimmed);
        out.extend((v.len() as u32).to_be_bytes());
        out.extend(v);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use signature::Verifier;

    #[test]
    fn signatures_of_both_kinds_verify_as_openssh_does() {
        let soft = soft::SoftKeys::new();
        for kind in [Kind::Ed25519, Kind::Ecdsa] {
            let key = new_key(&soft, kind, "ana@yubikey", None, false).unwrap();
            assert!(is_security_key(&key) && !needs_pin(&key));
            let data = b"session id and a userauth request";
            let blob = sign(&soft, &key, data, None).unwrap();
            let signature: Signature =
                ssh_key::encoding::Decode::decode(&mut blob.as_slice()).unwrap();
            key.public_key()
                .key_data()
                .verify(data, &signature)
                .unwrap_or_else(|e| panic!("{kind:?}: {e}"));
            assert!(
                key.public_key()
                    .key_data()
                    .verify(b"something else", &signature)
                    .is_err(),
                "{kind:?}"
            );
            // The file goes and comes back as OpenSSH writes it.
            let file = key.to_openssh(ssh_key::LineEnding::LF).unwrap();
            let again = PrivateKey::from_openssh(&*file).unwrap();
            assert_eq!(again.public_key(), key.public_key());
            assert!(sign(&soft, &again, data, None).is_ok());
        }
    }

    #[test]
    fn a_key_made_with_verify_required_asks_its_pin() {
        let soft = soft::SoftKeys::with_pin("1234");
        let key = new_key(&soft, Kind::Ed25519, "", Some("1234"), true).unwrap();
        assert!(needs_pin(&key));
        assert_eq!(sign(&soft, &key, b"x", None), Err(FidoError::PinRequired));
        assert_eq!(
            sign(&soft, &key, b"x", Some("0000")),
            Err(FidoError::WrongPin)
        );
        assert!(sign(&soft, &key, b"x", Some("1234")).is_ok());
    }

    #[test]
    fn another_keys_file_is_said() {
        let one = soft::SoftKeys::new();
        let other = soft::SoftKeys::new();
        let key = new_key(&one, Kind::Ecdsa, "", None, false).unwrap();
        assert_eq!(sign(&other, &key, b"x", None), Err(FidoError::NotThisKey));
    }

    #[test]
    fn der_signatures_become_mpints() {
        // r with its high bit set (a 0 goes in front), s with a 0 to drop.
        let der = [
            0x30, 0x0a, 0x02, 0x03, 0x00, 0x81, 0x02, 0x02, 0x03, 0x00, 0x00, 0x7f,
        ];
        assert_eq!(
            ecdsa_der_to_ssh(&der).unwrap(),
            [0, 0, 0, 3, 0x00, 0x81, 0x02, 0, 0, 0, 1, 0x7f]
        );
        assert!(ecdsa_der_to_ssh(&[0x30, 0x02, 0x02]).is_err());
    }
}
