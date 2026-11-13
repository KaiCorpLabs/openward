use super::{Backend, Error, valid_id};
use ssh_key::PublicKey;
#[derive(Default)]
pub struct System;

#[cfg(any(target_os = "macos", target_os = "ios"))]
mod mac {
    use super::*;
    use security_framework::{
        access_control::{ProtectionMode, SecAccessControl},
        item::{
            CloudSync, ItemClass, ItemSearchOptions, KeyClass, Limit, Location, Reference,
            SearchResult,
        },
        key::{Algorithm, GenerateKeyOptions, KeyType, SecKey, Token},
        passwords::AccessControlOptions,
    };
    fn error(code: isize) -> Error {
        match code {
            -128 | -2 | -4 | -9 => Error::Cancelled,
            -25300 => Error::Missing,
            -34018 | -25291 | -25308 | -25293 | -6 | -7 | -8 => Error::Unavailable,
            _ => Error::Native(code),
        }
    }
    fn label(id: &str) -> Result<String, Error> {
        if !valid_id(id) {
            return Err(Error::Invalid);
        }
        Ok(format!("dev.openward.ssh.secure-enclave.v1/{id}"))
    }
    fn public(key: &SecKey) -> Result<PublicKey, Error> {
        let bytes = key
            .public_key()
            .and_then(|k| k.external_representation())
            .ok_or(Error::Invalid)?;
        let p = ssh_key::public::EcdsaPublicKey::from_sec1_bytes(bytes.bytes())
            .map_err(|_| Error::Invalid)?;
        Ok(PublicKey::new(p.into(), ""))
    }
    fn query(id: &str) -> Result<ItemSearchOptions, Error> {
        let mut q = ItemSearchOptions::new();
        q.class(ItemClass::key())
            .key_class(KeyClass::private())
            .label(&label(id)?)
            .cloud_sync(CloudSync::MatchSyncNo);
        // iOS has only the data protection keychain.
        #[cfg(target_os = "macos")]
        q.ignore_legacy_keychains();
        Ok(q)
    }
    fn remove_local(id: &str, key: &SecKey) -> Result<(), Error> {
        let mut q = query(id)?;
        let hash = key.application_label().ok_or(Error::Invalid)?;
        q.application_label(&hash);
        match q.delete() {
            Ok(()) => Ok(()),
            Err(e) if e.code() == -25300 => Ok(()),
            Err(e) => Err(error(e.code() as isize)),
        }
    }
    fn lookup(id: &str) -> Result<SecKey, Error> {
        let mut q = query(id)?;
        q.load_refs(true).limit(Limit::All);
        let mut found = q.search().map_err(|e| error(e.code() as isize))?;
        if found.len() != 1 {
            return Err(Error::Invalid);
        }
        match found.pop() {
            Some(SearchResult::Ref(Reference::Key(k))) => Ok(k),
            _ => Err(Error::Invalid),
        }
    }
    fn pinned(id: &str, expected: &PublicKey) -> Result<SecKey, Error> {
        let k = lookup(id)?;
        if public(&k)?.key_data() != expected.key_data() {
            return Err(Error::Invalid);
        }
        Ok(k)
    }
    impl Backend for System {
        fn create(&self, id: &str) -> Result<PublicKey, Error> {
            let label = label(id)?;
            // Never overwrite an existing local key, even on a collision.
            match lookup(id) {
                Err(Error::Missing) => {}
                Err(e) => return Err(e),
                Ok(_) => return Err(Error::Invalid),
            }
            let acl = SecAccessControl::create_with_protection(
                Some(ProtectionMode::AccessibleWhenUnlockedThisDeviceOnly),
                (AccessControlOptions::PRIVATE_KEY_USAGE
                    | AccessControlOptions::BIOMETRY_CURRENT_SET)
                    .bits(),
            )
            .map_err(|e| error(e.code() as isize))?;
            let mut o = GenerateKeyOptions::default();
            o.set_key_type(KeyType::ec_sec_prime_random())
                .set_size_in_bits(256)
                .set_token(Token::SecureEnclave)
                .set_location(Location::DataProtectionKeychain)
                .set_access_control(acl)
                .set_label(label)
                .set_synchronizable(false);
            let key = SecKey::new(&o).map_err(|e| error(e.code()))?;
            match public(&key) {
                Ok(p) => Ok(p),
                Err(e) => {
                    let _ = remove_local(id, &key);
                    Err(e)
                }
            }
        }
        fn sign(&self, id: &str, expected: &PublicKey, message: &[u8]) -> Result<Vec<u8>, Error> {
            pinned(id, expected)?
                .create_signature(Algorithm::ECDSASignatureMessageX962SHA256, message)
                .map_err(|e| error(e.code()))
        }
        fn remove(&self, id: &str, expected: &PublicKey) -> Result<(), Error> {
            match pinned(id, expected) {
                Ok(k) => remove_local(id, &k),
                Err(Error::Missing) => Ok(()),
                Err(e) => Err(e),
            }
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        #[test]
        #[ignore = "requires a signed macOS app/session, Secure Enclave and physical Touch ID; OPENWARD_TEST_SECURE_ENCLAVE=1"]
        fn physical_touch_id_signs_and_private_key_is_not_exportable() {
            assert_eq!(
                std::env::var("OPENWARD_TEST_SECURE_ENCLAVE").as_deref(),
                Ok("1")
            );
            let id = openward_vault::proto::ItemId::new().to_string();
            let public = System.create(&id).unwrap();
            struct Cleanup(String, PublicKey);
            impl Drop for Cleanup {
                fn drop(&mut self) {
                    let _ = System.remove(&self.0, &self.1);
                }
            }
            let _cleanup = Cleanup(id.clone(), public.clone());
            let message = b"OpenWard physical Secure Enclave SSH signing test";
            let der = System.sign(&id, &public, message).unwrap();
            assert!(super::super::super::ssh_signature(&public, message, &der).is_ok());
            assert!(
                pinned(&id, &public)
                    .unwrap()
                    .external_representation()
                    .is_none(),
                "private material must never be exportable"
            );
        }
    }
}
#[cfg(not(any(target_os = "macos", target_os = "ios")))]
impl Backend for System {
    fn create(&self, _: &str) -> Result<PublicKey, Error> {
        Err(Error::Unavailable)
    }
    fn sign(&self, _: &str, _: &PublicKey, _: &[u8]) -> Result<Vec<u8>, Error> {
        Err(Error::Unavailable)
    }
    // An imported reference can be removed on another platform; its original
    // device's hardware key is unaffected, as with an offline backup copy.
    fn remove(&self, id: &str, _: &PublicKey) -> Result<(), Error> {
        if valid_id(id) {
            Ok(())
        } else {
            Err(Error::Invalid)
        }
    }
}
