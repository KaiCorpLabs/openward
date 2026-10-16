//! Termius's local key, from the system keychain where Termius keeps it
//! (as `localKey`, through node-keytar). Reading another app's item makes
//! the system ask the user first, at least on macOS.
//!
//! Installs differ in the service name, so every candidate is returned and
//! the caller keeps the one that decrypts a real field.

/// Candidate keys, the most likely first. An empty list means none was
/// found; an error, that the keychain could not be asked (or said no).
pub fn local_keys() -> Result<Vec<[u8; 32]>, String> {
    let mut keys = Vec::new();
    let mut errors = Vec::new();
    for service in SERVICES {
        match read(service) {
            Ok(Some(stored)) => {
                if let Some(key) = super::crypto::key_from_keychain(&stored) {
                    keys.push(key);
                }
            }
            Ok(None) => {}
            Err(e) => errors.push(format!("{service}: {e}")),
        }
    }
    if keys.is_empty() && !errors.is_empty() {
        return Err(errors.join("; "));
    }
    Ok(keys)
}

#[cfg(not(any(target_os = "ios", target_os = "android")))]
const ACCOUNT: &str = "localKey";

#[cfg(target_os = "macos")]
const SERVICES: &[&str] = &["Termius", "Termius (MAS)"];

#[cfg(target_os = "macos")]
fn read(service: &str) -> Result<Option<String>, String> {
    use security_framework::passwords::get_generic_password;
    // errSecItemNotFound
    const NOT_FOUND: i32 = -25300;
    match get_generic_password(service, ACCOUNT) {
        Ok(bytes) => Ok(Some(String::from_utf8_lossy(&bytes).into_owned())),
        Err(e) if e.code() == NOT_FOUND => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

#[cfg(windows)]
const SERVICES: &[&str] = &["Termius"];

#[cfg(windows)]
fn read(service: &str) -> Result<Option<String>, String> {
    // keytar names the credential `service/account` and stores UTF-8.
    let target = format!("{service}/{ACCOUNT}");
    let entry =
        keyring::Entry::new_with_target(&target, service, ACCOUNT).map_err(|e| e.to_string())?;
    match entry.get_secret() {
        Ok(bytes) => Ok(Some(String::from_utf8_lossy(&bytes).into_owned())),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

#[cfg(all(
    unix,
    not(target_os = "macos"),
    not(target_os = "ios"),
    not(target_os = "android")
))]
const SERVICES: &[&str] = &["termius-app", "Termius"];

/// Through `secret-tool` (libsecret), as keytar stores it: attributes
/// `service` and `account`.
#[cfg(all(
    unix,
    not(target_os = "macos"),
    not(target_os = "ios"),
    not(target_os = "android")
))]
fn read(service: &str) -> Result<Option<String>, String> {
    let out = std::process::Command::new("secret-tool")
        .args(["lookup", "service", service, "account", ACCOUNT])
        .output()
        .map_err(|e| format!("secret-tool: {e}"))?;
    let text = String::from_utf8_lossy(&out.stdout).trim().to_owned();
    Ok((out.status.success() && !text.is_empty()).then_some(text))
}

#[cfg(any(target_os = "ios", target_os = "android"))]
const SERVICES: &[&str] = &[];

#[cfg(any(target_os = "ios", target_os = "android"))]
fn read(_service: &str) -> Result<Option<String>, String> {
    Ok(None)
}
