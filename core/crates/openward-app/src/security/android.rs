//! The Android Keystore, through the app's own `VaultKeystore` (Kotlin),
//! called over JNI. The Keystore keeps an AES key that never leaves the
//! secure hardware; with it `VaultKeystore` encrypts the 32-byte random key
//! that unlocks the vault, behind BiometricPrompt for [`super::native`] and
//! without a prompt for [`super::device`]. The key comes back here and never
//! crosses into Dart.
//!
//! `openward-ffi` hands over the Java VM and the class from `JNI_OnLoad`,
//! which runs when the activity loads the library (`MainActivity.kt`).
use super::native::{Error, Key};
use jni::JavaVM;
use jni::objects::{GlobalRef, JByteArray, JClass, JValue};
use std::sync::OnceLock;
use zeroize::Zeroizing;

/// The class the activity defines: `dev.openward.openward.VaultKeystore`.
pub const CLASS: &str = "dev/openward/openward/VaultKeystore";

static BRIDGE: OnceLock<(JavaVM, GlobalRef)> = OnceLock::new();

/// Called once, from `JNI_OnLoad`, with the class found on the loading
/// thread: other threads see only the system class loader.
pub fn init(vm: JavaVM, class: GlobalRef) {
    let _ = BRIDGE.set((vm, class));
}

/// What `VaultKeystore` answers in one byte when there is no key.
fn failure(code: u8) -> Error {
    match code {
        1 => Error::Cancelled,
        2 => Error::Unavailable,
        3 => Error::Missing,
        _ => Error::Failed("Android Keystore".into()),
    }
}

/// Calls `VaultKeystore.<method>(id, biometric): byte[]`.
fn call(method: &str, id: &str, biometric: bool) -> Result<Zeroizing<Vec<u8>>, Error> {
    let (vm, class) = BRIDGE.get().ok_or(Error::Unavailable)?;
    let mut env = vm
        .attach_current_thread()
        .map_err(|e| Error::Failed(format!("JNI: {e}")))?;
    let class: &JClass = class.as_obj().into();
    let id = env
        .new_string(id)
        .map_err(|e| Error::Failed(format!("JNI: {e}")))?;
    let answer = env.call_static_method(
        class,
        method,
        "(Ljava/lang/String;Z)[B",
        &[JValue::Object(&id), JValue::Bool(u8::from(biometric))],
    );
    let answer = match answer {
        Ok(v) => v,
        Err(e) => {
            // An exception left pending would fail every later call.
            let _ = env.exception_clear();
            return Err(Error::Failed(format!("JNI: {e}")));
        }
    };
    let array: JByteArray = answer
        .l()
        .map_err(|e| Error::Failed(format!("JNI: {e}")))?
        .into();
    let bytes = Zeroizing::new(
        env.convert_byte_array(&array)
            .map_err(|e| Error::Failed(format!("JNI: {e}")))?,
    );
    Ok(bytes)
}

fn key(method: &str, id: &str, biometric: bool) -> Result<Key, Error> {
    let bytes = call(method, id, biometric)?;
    match bytes.len() {
        32 => {
            let mut key = Zeroizing::new([0; 32]);
            key.copy_from_slice(&bytes);
            Ok(key)
        }
        1 => Err(failure(bytes[0])),
        _ => Err(Error::Failed("Android Keystore: invalid key length".into())),
    }
}

/// Makes a new key for `id`: behind the fingerprint or the face when
/// `biometric`, which asks for it once to encrypt.
pub fn create(id: &str, biometric: bool) -> Result<Key, Error> {
    key("create", id, biometric)
}

/// The key of `id`, asking for the fingerprint or the face when
/// `biometric`.
pub fn read(id: &str, biometric: bool) -> Result<Key, Error> {
    key("read", id, biometric)
}

/// Forgets the key of `id` and its Keystore key. Missing is no error.
pub fn remove(id: &str, biometric: bool) -> Result<(), Error> {
    let bytes = call("remove", id, biometric)?;
    match bytes.first() {
        None | Some(3) => Ok(()),
        Some(&code) => Err(failure(code)),
    }
}
