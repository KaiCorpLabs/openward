//! The keychain: the SSH keys in `~/.ssh`, made or brought in here, and
//! their public half put on a server (as `ssh-copy-id` does).
//!
//! In phase 1 the vault keeps no secrets, so a key is a file: made with a
//! name of the user's in `~/.ssh` (readable only by them, never replacing
//! one), its `.pub` next to it. Hosts and identities point at the file.

use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};

use openward_ssh::keyfile::{self, decode_secret_key};
use openward_ssh::russh::keys::HashAlg;
use openward_ssh::russh::keys::ssh_key::{
    Algorithm, EcdsaCurve, LineEnding, PrivateKey, PublicKey,
};
use openward_vault::Vault;
use openward_vault::proto::{Data, Settings};

use crate::keys::algorithm;
use crate::local::{Local, Tokens};

/// A private key in `~/.ssh`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeyFile {
    /// As settings write it: `~/.ssh/…`.
    pub path: String,
    pub name: String,
    /// `Ed25519`, `RSA 4096`…, when its public half could be read.
    pub algorithm: Option<String>,
    /// `SHA256:…`.
    pub fingerprint: Option<String>,
    pub comment: Option<String>,
    /// Behind a passphrase.
    pub encrypted: bool,
    /// A security key's (FIDO2): the secret is on the key, not here.
    pub security_key: bool,
    /// Its `.pub` is next to it.
    pub has_public: bool,
    /// A certificate (`-cert.pub`) is next to it.
    pub certificate: bool,
    /// When that certificate runs out; `None` if it never does (or there
    /// is none, or it cannot be read).
    pub certificate_until: Option<std::time::SystemTime>,
    /// Hosts, groups and identities whose keys include it, by name.
    pub used_by: Vec<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NewKey {
    /// The one to choose unless a server needs another.
    Ed25519,
    /// ECDSA on P-256.
    Ecdsa,
    /// RSA, 4096 bits: for servers that take nothing newer.
    Rsa,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum KeyError {
    #[error("a file named {0} is already in ~/.ssh")]
    Exists(String),
    #[error("{0} cannot name a key file")]
    BadName(String),
    #[error("that is not a private key OpenWard can read")]
    NotAKey,
    #[error("{0}")]
    Io(String),
    #[error("could not make the key: {0}")]
    Make(String),
    #[error("that is not the key's passphrase")]
    WrongPassphrase,
    /// PEM and PuTTY keys: their passphrase is changed with their program.
    #[error("only OpenSSH keys can be given another passphrase here")]
    NotOpenSsh,
    /// The security key did not make one.
    #[error("{0}")]
    SecurityKey(openward_fido::FidoError),
}

fn io(e: impl std::fmt::Display) -> KeyError {
    KeyError::Io(e.to_string())
}

/// Files in `~/.ssh` that are never keys.
const NOT_KEYS: &[&str] = &[
    "config",
    "known_hosts",
    "known_hosts.old",
    "authorized_keys",
    "authorized_keys2",
    "environment",
    "rc",
];

/// The private keys in `~/.ssh`, by name, with who uses each (from
/// [`users`], taken with the vault's lock, which reading the files does not
/// need).
pub fn list(local: &Local, users: &Users) -> Vec<KeyFile> {
    let Ok(entries) = fs::read_dir(&local.ssh_dir) else {
        return Vec::new();
    };
    let mut files: Vec<PathBuf> = entries.flatten().map(|e| e.path()).collect();
    files.sort();
    files
        .iter()
        .filter(|f| looks_like_key(f))
        .map(|f| describe(local, f, users))
        .collect()
}

/// A private key file: not a known OpenSSH file, not a `.pub`, small, and
/// starting like a key does.
fn looks_like_key(f: &Path) -> bool {
    let Some(name) = f.file_name().and_then(|n| n.to_str()) else {
        return false;
    };
    if name.starts_with('.') || name.ends_with(".pub") || NOT_KEYS.contains(&name) {
        return false;
    }
    let small = fs::metadata(f).is_ok_and(|m| m.is_file() && m.len() < 64 * 1024);
    small
        && fs::read_to_string(f).is_ok_and(|t| {
            let t = t.trim_start();
            (t.starts_with("-----BEGIN") && t.contains("PRIVATE KEY"))
                || t.starts_with("PuTTY-User-Key-File-")
        })
}

fn with_suffix(file: &Path, suffix: &str) -> PathBuf {
    let mut name = file.as_os_str().to_owned();
    name.push(suffix);
    PathBuf::from(name)
}

fn tilde(local: &Local, path: &Path) -> String {
    match path.strip_prefix(&local.home) {
        Ok(rest) => format!("~/{}", rest.to_string_lossy().replace('\\', "/")),
        Err(_) => path.to_string_lossy().into_owned(),
    }
}

/// For each key file that settings name, who names it.
pub type Users = Vec<(PathBuf, String)>;

/// Who names each key file, from the vault.
pub fn users(local: &Local, vault: &Vault) -> Users {
    let t = Tokens {
        host: "",
        port: 22,
        user: &local.user,
        alias: "",
    };
    let mut out = Vec::new();
    let mut add = |settings: &Settings, who: &str| {
        for f in settings.identity_files.iter().flatten() {
            if !f.contains('%') {
                out.push((local.path(f, &t), who.to_owned()));
            }
        }
    };
    for (_, h) in vault.hosts() {
        add(&h.settings, &h.label);
    }
    for (_, g) in vault.groups() {
        add(&g.settings, &g.name);
    }
    for (_, i) in vault.identities() {
        add(&i.settings, &i.label);
    }
    out
}

fn describe(local: &Local, file: &Path, users: &[(PathBuf, String)]) -> KeyFile {
    let text = fs::read_to_string(file).unwrap_or_default();
    let pub_path = with_suffix(file, ".pub");
    let public = PublicKey::read_openssh_file(&pub_path).ok().or_else(|| {
        keyfile::from_openssh(&text)
            .ok()
            .map(|k| k.public_key().clone())
    });
    let encrypted = match keyfile::from_openssh(&text) {
        Ok(k) => k.is_encrypted(),
        Err(_) => {
            text.contains("ENCRYPTED")
                || (text.starts_with("PuTTY-User-Key-File-") && !text.contains("Encryption: none"))
        }
    };
    let mut used_by: Vec<String> = users
        .iter()
        .filter(|(p, _)| p == file)
        .map(|(_, who)| who.clone())
        .collect();
    used_by.sort();
    used_by.dedup();
    KeyFile {
        path: tilde(local, file),
        name: file
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default(),
        algorithm: public.as_ref().map(|p| algorithm(p.key_data())),
        fingerprint: public
            .as_ref()
            .map(|p| p.fingerprint(HashAlg::Sha256).to_string()),
        comment: public
            .as_ref()
            .map(|p| p.comment().as_str_lossy().to_owned())
            .filter(|c| !c.is_empty()),
        encrypted,
        security_key: public.as_ref().is_some_and(|p| {
            matches!(
                p.algorithm(),
                openward_ssh::russh::keys::Algorithm::SkEd25519
                    | openward_ssh::russh::keys::Algorithm::SkEcdsaSha2NistP256
            )
        }),
        has_public: pub_path.is_file(),
        certificate: with_suffix(file, "-cert.pub").is_file(),
        certificate_until: openward_ssh::russh::keys::ssh_key::Certificate::read_file(
            &with_suffix(file, "-cert.pub"),
        )
        .ok()
        .and_then(|c| c.valid_before_time()),
        used_by,
    }
}

/// Where a new key named `name` goes, if that name can be used.
fn new_path(local: &Local, name: &str) -> Result<PathBuf, KeyError> {
    let ok = !name.is_empty()
        && name.len() <= 100
        && !name.starts_with('.')
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | '@'))
        && !name.ends_with(".pub")
        && !NOT_KEYS.contains(&name);
    if !ok {
        return Err(KeyError::BadName(name.to_owned()));
    }
    let path = local.ssh_dir.join(name);
    if path.exists() || with_suffix(&path, ".pub").exists() {
        return Err(KeyError::Exists(name.to_owned()));
    }
    Ok(path)
}

/// The key file `path` names (`~/.ssh/…`), if it is one of the keys in
/// `~/.ssh`: nothing else is deleted or renamed through here.
fn key_file(local: &Local, path: &str) -> Result<PathBuf, KeyError> {
    let file = local.path(path, &tokens(local));
    if file.parent() != Some(local.ssh_dir.as_path()) || !looks_like_key(&file) {
        return Err(KeyError::NotAKey);
    }
    Ok(file)
}

fn tokens(local: &Local) -> Tokens<'_> {
    Tokens {
        host: "",
        port: 22,
        user: &local.user,
        alias: "",
    }
}

/// Where `path` (`~/.ssh/…`) is on this computer.
pub fn absolute(local: &Local, path: &str) -> PathBuf {
    local.path(path, &tokens(local))
}

/// What goes with a key file, beside it.
const COMPANIONS: &[&str] = &[".pub", "-cert.pub"];

/// Deletes a key and its `.pub` and certificate. Who names it keeps the
/// name: the app says who before asking.
pub fn delete(local: &Local, path: &str) -> Result<(), KeyError> {
    let file = key_file(local, path)?;
    fs::remove_file(&file).map_err(io)?;
    for suffix in COMPANIONS {
        let _ = fs::remove_file(with_suffix(&file, suffix));
    }
    Ok(())
}

/// Renames a key, its `.pub` and its certificate, and the hosts, groups
/// and identities that name it with it, in one change: if the vault cannot
/// take it, the files go back.
pub fn rename(
    local: &Local,
    vault: &mut Vault,
    path: &str,
    name: &str,
) -> Result<KeyFile, KeyError> {
    let from = key_file(local, path)?;
    let to = new_path(local, name)?;
    if COMPANIONS.iter().any(|s| with_suffix(&to, s).exists()) {
        return Err(KeyError::Exists(name.to_owned()));
    }
    let moved: Vec<(PathBuf, PathBuf)> = std::iter::once((from.clone(), to.clone()))
        .chain(COMPANIONS.iter().filter_map(|s| {
            let f = with_suffix(&from, s);
            f.exists().then(|| (f, with_suffix(&to, s)))
        }))
        .collect();
    let back = |done: &[(PathBuf, PathBuf)]| {
        for (a, b) in done.iter().rev() {
            let _ = fs::rename(b, a);
        }
    };
    for (i, (a, b)) in moved.iter().enumerate() {
        if let Err(e) = fs::rename(a, b) {
            back(&moved[..i]);
            return Err(io(e));
        }
    }
    let t = tokens(local);
    let named = tilde(local, &to);
    let rename_in = |s: &Settings| -> Option<Settings> {
        let files = s.identity_files.as_ref()?;
        if !files.iter().any(|f| local.path(f, &t) == from) {
            return None;
        }
        let mut s = s.clone();
        s.identity_files = Some(
            files
                .iter()
                .map(|f| {
                    if local.path(f, &t) == from {
                        named.clone()
                    } else {
                        f.clone()
                    }
                })
                .collect(),
        );
        Some(s)
    };
    let changes: Vec<_> = vault
        .items()
        .filter_map(|item| {
            let data = match &item.body.data {
                Data::Host(h) => Data::Host(openward_vault::proto::Host {
                    settings: rename_in(&h.settings)?,
                    ..h.clone()
                }),
                Data::Group(g) => Data::Group(openward_vault::proto::Group {
                    settings: rename_in(&g.settings)?,
                    ..g.clone()
                }),
                Data::Identity(i) => Data::Identity(openward_vault::proto::Identity {
                    settings: rename_in(&i.settings)?,
                    ..i.clone()
                }),
                _ => return None,
            };
            Some((item.id, item.rev, data))
        })
        .collect();
    if !changes.is_empty()
        && let Err(e) = vault.update_all(changes)
    {
        back(&moved);
        return Err(io(e));
    }
    Ok(describe(local, &to, &users(local, vault)))
}

/// Puts an OpenSSH key behind another passphrase, or none: `old` opens
/// it (unused if it has none), `new` closes it. The file is replaced
/// whole, never left half written.
pub fn change_passphrase(
    local: &Local,
    path: &str,
    old: Option<&str>,
    new: Option<&str>,
) -> Result<(), KeyError> {
    let file = key_file(local, path)?;
    let text = zeroize::Zeroizing::new(fs::read_to_string(&file).map_err(io)?);
    let key = keyfile::from_openssh(text.as_str()).map_err(|_| KeyError::NotOpenSsh)?;
    let key = if key.is_encrypted() {
        keyfile::decrypt(&key, old.unwrap_or_default()).map_err(|_| KeyError::WrongPassphrase)?
    } else {
        key
    };
    let key = match new.filter(|p| !p.is_empty()) {
        Some(p) => key
            .encrypt(&mut rand::rng(), p)
            .map_err(|e| KeyError::Make(e.to_string()))?,
        None => key,
    };
    let out = key
        .to_openssh(LineEnding::LF)
        .map_err(|e| KeyError::Make(e.to_string()))?;
    let tmp = with_suffix(&file, ".ow-new");
    let _ = fs::remove_file(&tmp);
    write_new(&tmp, out.as_bytes(), 0o600).map_err(io)?;
    fs::rename(&tmp, &file).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        io(e)
    })
}

/// Makes a key in `~/.ssh/<name>`, with its `.pub`; behind `passphrase`
/// if there is one. The comment is often `user@computer`.
/// `users` is asked once the key is written: generating an RSA key takes
/// seconds, and needs nothing from the vault.
pub fn generate(
    local: &Local,
    name: &str,
    kind: NewKey,
    comment: &str,
    passphrase: Option<&str>,
    users: impl FnOnce() -> Users,
) -> Result<KeyFile, KeyError> {
    let path = new_path(local, name)?;
    let mut rng = rand::rng();
    let algorithm = match kind {
        NewKey::Ed25519 => Algorithm::Ed25519,
        NewKey::Ecdsa => Algorithm::Ecdsa {
            curve: EcdsaCurve::NistP256,
        },
        NewKey::Rsa => Algorithm::Rsa { hash: None },
    };
    let mut key =
        PrivateKey::random(&mut rng, algorithm).map_err(|e| KeyError::Make(e.to_string()))?;
    key.set_comment(comment);
    let public = key
        .public_key()
        .to_openssh()
        .map_err(|e| KeyError::Make(e.to_string()))?;
    let key = match passphrase.filter(|p| !p.is_empty()) {
        Some(p) => key
            .encrypt(&mut rng, p)
            .map_err(|e| KeyError::Make(e.to_string()))?,
        None => key,
    };
    let text = key
        .to_openssh(LineEnding::LF)
        .map_err(|e| KeyError::Make(e.to_string()))?;
    write_pair(&path, text.as_bytes(), Some(&public))?;
    Ok(describe(local, &path, &users()))
}

/// A key to make on a security key.
pub struct NewSecurityKey<'a> {
    pub kind: openward_fido::Kind,
    pub comment: &'a str,
    /// The security key's PIN, when it has one.
    pub pin: Option<&'a str>,
    /// Asked for at every use (`verify-required`), not only touched.
    pub verify: bool,
}

/// Makes `~/.ssh/<name>` on the security key plugged in: touched, with its
/// PIN when it has one. The file holds no secret: the key does.
pub fn generate_security_key(
    local: &Local,
    name: &str,
    keys: &dyn openward_fido::Authenticator,
    new: NewSecurityKey,
    users: impl FnOnce() -> Users,
) -> Result<KeyFile, KeyError> {
    let path = new_path(local, name)?;
    let pin = new.pin.filter(|p| !p.is_empty());
    let key = openward_fido::new_key(keys, new.kind, new.comment, pin, new.verify)
        .map_err(KeyError::SecurityKey)?;
    let public = key
        .public_key()
        .to_openssh()
        .map_err(|e| KeyError::Make(e.to_string()))?;
    let text = key
        .to_openssh(LineEnding::LF)
        .map_err(|e| KeyError::Make(e.to_string()))?;
    write_pair(&path, text.as_bytes(), Some(&public))?;
    Ok(describe(local, &path, &users()))
}

/// Saves a private key given as text (OpenSSH, PEM or PuTTY's) as
/// `~/.ssh/<name>`, with its `.pub` when its public half can be read.
pub fn import(
    local: &Local,
    name: &str,
    text: &str,
    users: impl FnOnce() -> Users,
) -> Result<KeyFile, KeyError> {
    let path = new_path(local, name)?;
    let text = text.replace("\r\n", "\n");
    let text = text.trim();
    let openssh = keyfile::from_openssh(text).ok();
    // Encrypted PEM and PPK keys cannot be checked without the
    // passphrase: their header has to do.
    let readable = openssh.is_some()
        || decode_secret_key(text, None).is_ok()
        || text.contains("ENCRYPTED")
        || (text.starts_with("PuTTY-User-Key-File-") && !text.contains("Encryption: none"));
    if !readable {
        return Err(KeyError::NotAKey);
    }
    let public = openssh
        .map(|k| k.public_key().clone())
        .or_else(|| {
            decode_secret_key(text, None)
                .ok()
                .map(|k| k.public_key().clone())
        })
        .and_then(|p| p.to_openssh().ok());
    write_pair(&path, format!("{text}\n").as_bytes(), public.as_deref())?;
    Ok(describe(local, &path, &users()))
}

fn write_pair(path: &Path, private: &[u8], public: Option<&str>) -> Result<(), KeyError> {
    let public = public
        .map(|line| {
            let key = PublicKey::from_openssh(line).map_err(io)?;
            public_key_line(&key)
        })
        .transpose()?;
    if let Some(dir) = path.parent()
        && !dir.is_dir()
    {
        let mut b = fs::DirBuilder::new();
        b.recursive(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            b.mode(0o700);
        }
        b.create(dir).map_err(io)?;
    }
    write_new(path, private, 0o600).map_err(io)?;
    if let Some(line) = public {
        write_new(
            &with_suffix(path, ".pub"),
            format!("{line}\n").as_bytes(),
            0o644,
        )
        .map_err(io)?;
    }
    Ok(())
}

fn write_new(path: &Path, bytes: &[u8], mode: u32) -> std::io::Result<()> {
    let mut o = fs::OpenOptions::new();
    o.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        o.mode(mode);
    }
    #[cfg(not(unix))]
    let _ = mode;
    o.open(path)?.write_all(bytes)
}

/// The public half of a key file, as an `authorized_keys` line: from its
/// `.pub`, or from the key when that can be read without a passphrase.
pub fn public_line(local: &Local, path: &str) -> Result<String, KeyError> {
    let t = Tokens {
        host: "",
        port: 22,
        user: &local.user,
        alias: "",
    };
    let file = local.path(path, &t);
    if let Ok(p) = PublicKey::read_openssh_file(with_suffix(&file, ".pub")) {
        return public_key_line(&p);
    }
    let text = fs::read_to_string(&file).map_err(io)?;
    let public = keyfile::from_openssh(&text)
        .map(|k| k.public_key().clone())
        .or_else(|_| decode_secret_key(&text, None).map(|k| k.public_key().clone()))
        .map_err(|_| KeyError::NotAKey)?;
    public_key_line(&public)
}

/// Comments read from key files are data, even when the decoder preserves
/// line breaks. Every public half written or offered by the app is one line.
pub(crate) fn public_key_line(key: &PublicKey) -> Result<String, KeyError> {
    let mut key = key.clone();
    let comment: String = key
        .comment()
        .as_str_lossy()
        .chars()
        .map(|c| if line_control(c) { ' ' } else { c })
        .collect();
    key.set_comment(comment);
    key.to_openssh().map_err(io)
}

fn line_control(c: char) -> bool {
    c.is_control() || matches!(c, '\u{2028}' | '\u{2029}')
}

/// Validates direct installation input before any remote operations. A
/// rejected line is an error, never "the key was already installed".
pub fn authorized_line(line: &str) -> std::io::Result<String> {
    let bad = || {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "expected exactly one SSH public key line",
        )
    };
    let line = line.trim();
    if line.is_empty() || line.chars().any(line_control) {
        return Err(bad());
    }
    PublicKey::from_openssh(line)
        .map_err(|_| bad())?
        .to_openssh()
        .map_err(|_| bad())
}

/// `authorized_keys` with `line` in it: `None` when the key is there
/// already (whatever its options or comment).
pub fn with_authorized(existing: Option<&[u8]>, line: &str) -> std::io::Result<Option<Vec<u8>>> {
    let line = authorized_line(line)?;
    let mut words = line.split_whitespace();
    let (kind, blob) = (words.next().unwrap_or(""), words.next().unwrap_or(""));
    let text = existing.map(String::from_utf8_lossy).unwrap_or_default();
    let present = text.lines().any(|l| {
        let w: Vec<&str> = l.split_whitespace().collect();
        w.windows(2).any(|p| p[0] == kind && p[1] == blob)
    });
    if present {
        return Ok(None);
    }
    let mut out = text.into_owned();
    if !out.is_empty() && !out.ends_with('\n') {
        out.push('\n');
    }
    out.push_str(line.trim());
    out.push('\n');
    Ok(Some(out.into_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A key made on a security key: its file and .pub, described as one,
    /// with no secret in the file.
    #[test]
    fn a_key_made_on_a_security_key() {
        let home = tempfile::tempdir().unwrap();
        let local = Local {
            home: home.path().to_owned(),
            user: "ana".into(),
            ssh_dir: home.path().join(".ssh"),
            system_ssh_dir: home.path().join("etc-ssh"),
            agent: None,
        };
        let soft = openward_fido::soft::SoftKeys::new();
        let new = |kind| NewSecurityKey {
            kind,
            comment: "ana@yubikey",
            pin: None,
            verify: false,
        };
        let k = generate_security_key(
            &local,
            "id_ed25519_sk",
            &soft,
            new(openward_fido::Kind::Ed25519),
            Users::default,
        )
        .unwrap();
        assert_eq!(k.algorithm.as_deref(), Some("Ed25519-SK"));
        assert!(k.has_public && !k.encrypted && k.security_key);
        let k = generate_security_key(
            &local,
            "id_ecdsa_sk",
            &soft,
            new(openward_fido::Kind::Ecdsa),
            Users::default,
        )
        .unwrap();
        assert_eq!(k.algorithm.as_deref(), Some("ECDSA-SK P-256"));
        let none = openward_fido::soft::SoftKeys::with_pin("1234");
        assert_eq!(
            generate_security_key(
                &local,
                "id_x",
                &none,
                new(openward_fido::Kind::Ed25519),
                Users::default
            ),
            Err(KeyError::SecurityKey(openward_fido::FidoError::PinRequired))
        );
    }

    fn local(dir: &Path) -> Local {
        Local {
            home: dir.to_owned(),
            user: "ana".into(),
            ssh_dir: dir.join(".ssh"),
            system_ssh_dir: dir.join("etc-ssh"),
            agent: None,
        }
    }

    #[test]
    fn made_listed_and_never_replaced() {
        let dir = tempfile::tempdir().unwrap();
        let local = local(dir.path());
        let vault = Vault::open_in_memory().unwrap();
        let k = generate(
            &local,
            "id_demo",
            NewKey::Ed25519,
            "ana@mac",
            Some("frase"),
            || users(&local, &vault),
        )
        .unwrap();
        assert_eq!(k.path, "~/.ssh/id_demo");
        assert_eq!(k.algorithm.as_deref(), Some("Ed25519"));
        assert!(k.encrypted && k.has_public);
        assert_eq!(k.comment.as_deref(), Some("ana@mac"));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = |p: &Path| fs::metadata(p).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode(&local.ssh_dir), 0o700);
            assert_eq!(mode(&local.ssh_dir.join("id_demo")), 0o600);
        }
        let again = generate(&local, "id_demo", NewKey::Ecdsa, "", None, || {
            users(&local, &vault)
        });
        assert_eq!(again, Err(KeyError::Exists("id_demo".into())));
        assert_eq!(
            generate(&local, "../x", NewKey::Ed25519, "", None, || users(
                &local, &vault
            )),
            Err(KeyError::BadName("../x".into()))
        );
        let e = generate(&local, "id_ecdsa_x", NewKey::Ecdsa, "", None, || {
            users(&local, &vault)
        })
        .unwrap();
        assert_eq!(e.algorithm.as_deref(), Some("ECDSA P-256"));
        fs::write(local.ssh_dir.join("config"), "Host *\n").unwrap();
        fs::write(local.ssh_dir.join("notes.txt"), "hello").unwrap();
        let names: Vec<String> = list(&local, &users(&local, &vault))
            .into_iter()
            .map(|k| k.name)
            .collect();
        assert_eq!(names, ["id_demo", "id_ecdsa_x"]);
        // The public line comes from the .pub even behind a passphrase.
        let line = public_line(&local, "~/.ssh/id_demo").unwrap();
        assert!(line.starts_with("ssh-ed25519 ") && line.ends_with("ana@mac"));
    }

    #[test]
    fn imported_from_text_and_who_uses_it() {
        let dir = tempfile::tempdir().unwrap();
        let local = local(dir.path());
        let mut vault = Vault::open_in_memory().unwrap();
        let key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
        let text = key.to_openssh(LineEnding::CRLF).unwrap();
        assert_eq!(
            import(&local, "x", "not a key", || users(&local, &vault)),
            Err(KeyError::NotAKey)
        );
        vault
            .create(openward_vault::proto::Data::Host(
                openward_vault::proto::Host {
                    label: "web".into(),
                    address: "web.example.com".into(),
                    group: None,
                    tags: vec![],
                    settings: Settings {
                        identity_files: Some(vec!["~/.ssh/traida".into()]),
                        ..Settings::default()
                    },
                    ..Default::default()
                },
            ))
            .unwrap();
        let k = import(&local, "traida", &text, || users(&local, &vault)).unwrap();
        assert!(k.has_public && !k.encrypted && !k.security_key);
        assert_eq!(k.used_by, ["web"]);
        assert_eq!(
            k.fingerprint,
            Some(key.public_key().fingerprint(HashAlg::Sha256).to_string())
        );
    }

    /// A key from `openward-ssh`'s fixtures: ECDSA P-256 made by
    /// `ssh-keygen` with a 31-byte scalar, which `ssh-key` alone refuses.
    fn short_scalar(name: &str) -> String {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../openward-ssh/tests/fixtures");
        fs::read_to_string(dir.join(name)).unwrap()
    }

    /// About one P-256 key in 512 from `ssh-keygen`: brought in, listed
    /// without its .pub, its public line, and another passphrase.
    #[test]
    fn an_ecdsa_key_with_a_short_scalar() {
        let dir = tempfile::tempdir().unwrap();
        let local = local(dir.path());
        let public = PublicKey::from_openssh(short_scalar("ecdsa-p256-short.pub").trim()).unwrap();
        let fingerprint = Some(public.fingerprint(HashAlg::Sha256).to_string());

        let k = import(&local, "short", &short_scalar("ecdsa-p256-short"), Vec::new).unwrap();
        assert_eq!(k.algorithm.as_deref(), Some("ECDSA P-256"));
        assert_eq!(k.fingerprint, fingerprint);
        assert!(k.has_public && !k.encrypted);
        let text = short_scalar("ecdsa-p256-short-aes256-ctr");
        let e = import(&local, "short_pass", &text, Vec::new).unwrap();
        assert_eq!(e.fingerprint, fingerprint);
        assert!(e.has_public && e.encrypted);

        // Without the .pub, what is listed comes from the key itself.
        for name in ["short", "short_pass"] {
            fs::remove_file(local.ssh_dir.join(format!("{name}.pub"))).unwrap();
        }
        let listed = |name: &str| {
            list(&local, &Vec::new())
                .into_iter()
                .find(|k| k.name == name)
                .unwrap()
        };
        let k = listed("short");
        assert_eq!(k.fingerprint, fingerprint);
        assert!(!k.has_public && !k.encrypted);
        assert_eq!(listed("short_pass").fingerprint, fingerprint);
        let line = public_line(&local, "~/.ssh/short").unwrap();
        assert_eq!(line, public.to_openssh().unwrap());

        // Its passphrase: wrong, then taken off; the key written again has
        // the 32 bytes that `ssh-key` reads by itself.
        assert_eq!(
            change_passphrase(&local, "~/.ssh/short_pass", Some("otra"), None),
            Err(KeyError::WrongPassphrase)
        );
        change_passphrase(&local, "~/.ssh/short_pass", Some("openward-test"), None).unwrap();
        let k = listed("short_pass");
        assert!(!k.encrypted);
        let written = fs::read_to_string(local.ssh_dir.join("short_pass")).unwrap();
        let key = PrivateKey::from_openssh(&written).unwrap();
        assert_eq!(key.public_key().key_data(), public.key_data());
        // And one put on, on a key that had none.
        change_passphrase(&local, "~/.ssh/short", None, Some("frase")).unwrap();
        assert!(listed("short").encrypted);
        let path = local.ssh_dir.join("short");
        let key = openward_ssh::client::load_key(&path, Some("frase")).unwrap();
        assert_eq!(key.public_key().key_data(), public.key_data());
    }

    /// DA-3: a public or private key comment is data, never another key.
    #[test]
    fn public_lines_do_not_preserve_executable_comment_lines() {
        let dir = tempfile::tempdir().unwrap();
        let local = local(dir.path());
        fs::create_dir_all(&local.ssh_dir).unwrap();
        let mut rng = rand::rng();
        let mut key = PrivateKey::random(&mut rng, Algorithm::Ed25519).unwrap();
        let extra = PrivateKey::random(&mut rng, Algorithm::Ed25519).unwrap();
        key.set_comment(format!(
            "deploy\n{}",
            extra.public_key().to_openssh().unwrap()
        ));
        for with_public in [false, true] {
            let path = if with_public {
                "with-public"
            } else {
                "private-only"
            };
            fs::write(
                local.ssh_dir.join(path),
                key.to_openssh(LineEnding::LF).unwrap(),
            )
            .unwrap();
            if with_public {
                fs::write(
                    local.ssh_dir.join(format!("{path}.pub")),
                    key.public_key().to_openssh().unwrap(),
                )
                .unwrap();
            }
            let line = public_line(&local, &format!("~/.ssh/{path}")).unwrap();
            assert_eq!(line.lines().count(), 1);
            assert_eq!(
                PublicKey::from_openssh(&line).unwrap().key_data(),
                key.public_key().key_data()
            );
        }
    }

    #[test]
    fn authorized_keys_gets_the_line_once() {
        let mut key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
        key.set_comment("ana@mac");
        let line = key.public_key().to_openssh().unwrap();
        let added = with_authorized(None, &format!("{line}\r\n"))
            .unwrap()
            .unwrap();
        assert_eq!(added, format!("{line}\n").as_bytes());
        let other = b"ssh-rsa AAAAB3 bob";
        let both = with_authorized(Some(other), &line).unwrap().unwrap();
        assert_eq!(both, format!("ssh-rsa AAAAB3 bob\n{line}\n").as_bytes());
        // There already, with options and another comment.
        let mut public = key.public_key().clone();
        public.set_comment("old comment");
        let there = format!("from=\"10.0.0.0/8\" {}\n", public.to_openssh().unwrap());
        assert_eq!(
            with_authorized(Some(there.as_bytes()), &line).unwrap(),
            None
        );
    }

    #[test]
    fn installation_rejects_extra_lines_controls_and_invalid_keys() {
        let key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
        let line = key.public_key().to_openssh().unwrap();
        for separator in [
            "\n", "\r\n", "\r", "\u{000b}", "\u{0085}", "\u{2028}", "\u{2029}",
        ] {
            let injected = format!("{line} deploy{separator}{line} extra");
            let error = with_authorized(None, &injected).unwrap_err();
            assert_eq!(error.kind(), std::io::ErrorKind::InvalidInput);
            // Duplicate detection must not turn an invalid request into success.
            assert!(with_authorized(Some(line.as_bytes()), &injected).is_err());
        }
        for invalid in ["", "ssh-ed25519 !!!", "ssh-ed25519 AAAAC3Nz", "not a key"] {
            assert!(with_authorized(None, invalid).is_err());
        }
    }

    #[test]
    fn generated_and_imported_public_files_have_safe_comments() {
        let dir = tempfile::tempdir().unwrap();
        let local = local(dir.path());
        let comment = "deployment\r\nsecond\u{2028}third";
        generate(
            &local,
            "generated",
            NewKey::Ed25519,
            comment,
            None,
            Users::default,
        )
        .unwrap();
        let mut key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
        key.set_comment(comment);
        import(
            &local,
            "imported",
            &key.to_openssh(LineEnding::LF).unwrap(),
            Users::default,
        )
        .unwrap();
        for name in ["generated", "imported"] {
            let written = fs::read_to_string(local.ssh_dir.join(format!("{name}.pub"))).unwrap();
            assert_eq!(written.lines().count(), 1);
            assert!(!written.trim().chars().any(line_control));
        }
    }

    /// Deleting, renaming and another passphrase: only keys in `~/.ssh`, and
    /// a rename takes who names the key along.
    #[test]
    fn a_key_deleted_renamed_and_given_another_passphrase() {
        let dir = tempfile::tempdir().unwrap();
        let local = local(dir.path());
        let mut vault = Vault::open_in_memory().unwrap();
        let new = |name: &str, phrase: Option<&str>| {
            generate(&local, name, NewKey::Ed25519, "ana@mac", phrase, Vec::new).unwrap()
        };
        new("id_old", None);
        fs::write(local.ssh_dir.join("id_old-cert.pub"), "cert").unwrap();
        let host = vault
            .create(Data::Host(openward_vault::proto::Host {
                label: "web".into(),
                address: "web.example.com".into(),
                settings: Settings {
                    identity_files: Some(vec!["~/.ssh/id_old".into(), "~/.ssh/id_other".into()]),
                    ..Settings::default()
                },
                ..Default::default()
            }))
            .unwrap();

        // Renamed: the files and the host that names it.
        let k = rename(&local, &mut vault, "~/.ssh/id_old", "id_web").unwrap();
        assert_eq!(k.path, "~/.ssh/id_web");
        assert_eq!(k.used_by, ["web"]);
        assert!(k.has_public && k.certificate);
        assert!(!local.ssh_dir.join("id_old").exists());
        let Data::Host(h) = &vault.get(host).unwrap().body.data else {
            panic!("not a host")
        };
        assert_eq!(
            h.settings.identity_files.as_deref(),
            Some(&["~/.ssh/id_web".to_owned(), "~/.ssh/id_other".to_owned()][..])
        );
        new("id_taken", None);
        assert_eq!(
            rename(&local, &mut vault, "~/.ssh/id_web", "id_taken").map(|_| ()),
            Err(KeyError::Exists("id_taken".into()))
        );

        // Another passphrase: put on, needed to take it off, taken off.
        change_passphrase(&local, "~/.ssh/id_web", None, Some("frase")).unwrap();
        let listed = |name: &str| {
            list(&local, &users(&local, &vault))
                .into_iter()
                .find(|k| k.name == name)
                .unwrap()
        };
        assert!(listed("id_web").encrypted);
        assert_eq!(
            change_passphrase(&local, "~/.ssh/id_web", Some("otra"), None),
            Err(KeyError::WrongPassphrase)
        );
        change_passphrase(&local, "~/.ssh/id_web", Some("frase"), None).unwrap();
        assert!(!listed("id_web").encrypted);
        assert!(!local.ssh_dir.join("id_web.ow-new").exists());

        // Deleted, with what goes with it; nothing that is not a key.
        delete(&local, "~/.ssh/id_web").unwrap();
        for f in ["id_web", "id_web.pub", "id_web-cert.pub"] {
            assert!(!local.ssh_dir.join(f).exists(), "{f}");
        }
        fs::write(local.ssh_dir.join("config"), "Host *\n").unwrap();
        for not_a_key in ["~/.ssh/config", "~/.ssh/../.ssh/id_taken.pub", "/etc/hosts"] {
            assert_eq!(
                delete(&local, not_a_key),
                Err(KeyError::NotAKey),
                "{not_a_key}"
            );
        }
        assert!(local.ssh_dir.join("config").exists());
    }
}
