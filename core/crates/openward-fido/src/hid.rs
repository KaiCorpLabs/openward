//! The security key plugged into this computer, over USB HID (CTAP2,
//! with `ctap-hid-fido2`). One key at a time: with two plugged in, which
//! to use is not clear and it says so.
//!
//! On Windows, programs other than the system's need administrator rights
//! to talk to a FIDO key: there it says so, and the key goes through the
//! agent of Windows' OpenSSH, which uses WebAuthn.

use ctap_hid_fido2::fidokey::get_assertion::get_assertion_params::GetAssertionArgsBuilder;
use ctap_hid_fido2::fidokey::make_credential::make_credential_params::{
    CredentialSupportedKeyType, MakeCredentialArgsBuilder,
};
use ctap_hid_fido2::public_key::PublicKeyType;
use ctap_hid_fido2::{FidoKeyHidFactory, LibCfg};

use crate::{Assertion, Authenticator, FidoError, Kind, Made, ecdsa_der_to_ssh};

/// The key plugged in now (found anew on each call).
#[derive(Clone, Copy, Debug, Default)]
pub struct HidKeys;

fn device() -> Result<ctap_hid_fido2::FidoKeyHid, FidoError> {
    let mut cfg = LibCfg::init();
    // Its own "touch the key" lines would go to stdout: the app says it.
    cfg.enable_keep_alive_msg = false;
    FidoKeyHidFactory::create(&cfg).map_err(|e| {
        let text = format!("{e:#}");
        if text.contains("not found") {
            FidoError::NoKey
        } else if text.contains("Multiple") || text.contains("multiple") {
            FidoError::TooManyKeys
        } else if cfg!(windows) || denied(&text) {
            FidoError::NoAccess
        } else {
            FidoError::Other(text)
        }
    })
}

/// The system would not open the key: on Linux, no udev rule gives this
/// user `/dev/hidraw*`.
fn denied(text: &str) -> bool {
    ["ermission denied", "Failed opening", "failed to open"]
        .iter()
        .any(|w| text.contains(w))
}

/// The CTAP2 status in an error, as words the app can tell apart.
fn ctap_error(e: anyhow::Error) -> FidoError {
    let text = format!("{e:#}");
    let has = |words: &[&str]| words.iter().any(|w| text.contains(w));
    if has(&["PIN_REQUIRED", "PUAT_REQUIRED", "pin required"]) {
        FidoError::PinRequired
    } else if has(&["PIN_INVALID"]) {
        FidoError::WrongPin
    } else if has(&["PIN_BLOCKED", "PIN_AUTH_BLOCKED"]) {
        FidoError::Locked
    } else if denied(&text) {
        FidoError::NoAccess
    } else if has(&["NO_CREDENTIALS"]) {
        FidoError::NotThisKey
    } else if has(&[
        "USER_ACTION_TIMEOUT",
        "ACTION_TIMEOUT",
        "OPERATION_DENIED",
        "KEEPALIVE_CANCEL",
    ]) {
        FidoError::NotTouched
    } else {
        FidoError::Other(text)
    }
}

impl Authenticator for HidKeys {
    fn assert(
        &self,
        application: &str,
        key_handle: &[u8],
        data: &[u8],
        pin: Option<&str>,
    ) -> Result<Assertion, FidoError> {
        let device = device()?;
        // The challenge is hashed into the client data hash: SHA-256 of
        // the data, as OpenSSH asks.
        let mut args = GetAssertionArgsBuilder::new(application, data).credential_id(key_handle);
        args = match pin {
            Some(pin) => args.pin(pin),
            None => args.without_pin_and_uv(),
        };
        let found = device
            .get_assertion_with_args(&args.build())
            .map_err(ctap_error)?;
        let a = found.into_iter().next().ok_or(FidoError::NotThisKey)?;
        // authData: rpIdHash (32), flags (1), counter (4), …
        let flags = *a
            .auth_data
            .get(32)
            .ok_or_else(|| FidoError::Other("short authenticator data".into()))?;
        let signature = if a.signature.first() == Some(&0x30) {
            ecdsa_der_to_ssh(&a.signature)?
        } else {
            a.signature
        };
        Ok(Assertion {
            flags,
            counter: a.sign_count,
            signature,
        })
    }

    fn make(
        &self,
        kind: Kind,
        application: &str,
        pin: Option<&str>,
        verify: bool,
    ) -> Result<Made, FidoError> {
        let device = device()?;
        let challenge: Vec<u8> = (0..32).map(|i| i as u8 ^ 0x5a).collect();
        let key_type = match kind {
            Kind::Ed25519 => CredentialSupportedKeyType::Ed25519,
            Kind::Ecdsa => CredentialSupportedKeyType::Ecdsa256,
        };
        let mut args = MakeCredentialArgsBuilder::new(application, &challenge).key_type(key_type);
        args = match pin {
            Some(pin) => args.pin(pin),
            None => args.without_pin_and_uv(),
        };
        let made = device
            .make_credential_with_args(&args.build())
            .map_err(ctap_error)?;
        let der = &made.credential_publickey.der;
        // The public key in DER (SubjectPublicKeyInfo): its last bytes are
        // the key itself.
        let public = match (made.credential_publickey.key_type, kind) {
            (PublicKeyType::Ed25519, Kind::Ed25519) if der.len() >= 32 => {
                der[der.len() - 32..].to_vec()
            }
            (PublicKeyType::Ecdsa256, Kind::Ecdsa) if der.len() >= 65 => {
                der[der.len() - 65..].to_vec()
            }
            _ => return Err(FidoError::Other("the key made another kind of key".into())),
        };
        Ok(Made {
            kind,
            public,
            key_handle: made.credential_descriptor.id,
            flags: crate::USER_PRESENCE | if verify { crate::USER_VERIFIED } else { 0 },
        })
    }
}
