//! A security key in software, for the tests: it signs as a real one
//! does (the same data, flags and counter), with keys it keeps in memory,
//! and is always touched.

use std::collections::HashMap;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU32, Ordering};

use signature::Signer;
use ssh_key::sha2::{Digest, Sha256};
use ssh_key::{Algorithm, EcdsaCurve, PrivateKey};

use crate::{Assertion, Authenticator, FidoError, Kind, Made, USER_PRESENCE, USER_VERIFIED};

#[derive(Default)]
pub struct SoftKeys {
    keys: Mutex<HashMap<Vec<u8>, (PrivateKey, bool)>>,
    counter: AtomicU32,
    pin: Option<String>,
}

impl SoftKeys {
    pub fn new() -> Self {
        Self::default()
    }

    /// One that has a PIN set.
    pub fn with_pin(pin: &str) -> Self {
        Self {
            pin: Some(pin.to_owned()),
            ..Self::default()
        }
    }

    fn check_pin(&self, given: Option<&str>) -> Result<(), FidoError> {
        match (&self.pin, given) {
            (None, _) => Ok(()),
            (Some(_), None) => Err(FidoError::PinRequired),
            (Some(p), Some(g)) if p == g => Ok(()),
            (Some(_), Some(_)) => Err(FidoError::WrongPin),
        }
    }
}

impl Authenticator for SoftKeys {
    fn assert(
        &self,
        application: &str,
        key_handle: &[u8],
        data: &[u8],
        pin: Option<&str>,
    ) -> Result<Assertion, FidoError> {
        let keys = self.keys.lock().unwrap();
        let (key, verify) = keys.get(key_handle).ok_or(FidoError::NotThisKey)?;
        if *verify {
            self.check_pin(pin)?;
        }
        let flags = USER_PRESENCE | if *verify { USER_VERIFIED } else { 0 };
        let counter = self.counter.fetch_add(1, Ordering::Relaxed) + 1;
        let mut signed = Sha256::digest(application.as_bytes()).to_vec();
        signed.push(flags);
        signed.extend(counter.to_be_bytes());
        signed.extend(Sha256::digest(data));
        let signature = key
            .try_sign(&signed)
            .map_err(|e| FidoError::Other(e.to_string()))?;
        Ok(Assertion {
            flags,
            counter,
            signature: signature.as_bytes().to_vec(),
        })
    }

    fn make(
        &self,
        kind: Kind,
        _application: &str,
        pin: Option<&str>,
        verify: bool,
    ) -> Result<Made, FidoError> {
        self.check_pin(pin)?;
        let algorithm = match kind {
            Kind::Ed25519 => Algorithm::Ed25519,
            Kind::Ecdsa => Algorithm::Ecdsa {
                curve: EcdsaCurve::NistP256,
            },
        };
        let key = PrivateKey::random(&mut rand::rng(), algorithm)
            .map_err(|e| FidoError::Other(e.to_string()))?;
        let public = match key.public_key().key_data() {
            ssh_key::public::KeyData::Ed25519(k) => k.0.to_vec(),
            ssh_key::public::KeyData::Ecdsa(k) => k.as_sec1_bytes().to_vec(),
            _ => unreachable!("made as Ed25519 or P-256"),
        };
        let key_handle: Vec<u8> = (0..32).map(|_| rand::random::<u8>()).collect();
        self.keys
            .lock()
            .unwrap()
            .insert(key_handle.clone(), (key, verify));
        Ok(Made {
            kind,
            public,
            key_handle,
            flags: USER_PRESENCE | if verify { USER_VERIFIED } else { 0 },
        })
    }
}
