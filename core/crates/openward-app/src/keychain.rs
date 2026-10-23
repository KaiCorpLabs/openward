//! The keychain: the SSH keys in `~/.ssh`, made or brought in here, and
//! their public half put on a server (as `ssh-copy-id` does).
//!
//! In phase 1 the vault keeps no secrets, so a key is a file: made with a
//! name of the user's in `~/.ssh` (readable only by them, never replacing
//! one), its `.pub` next to it. Hosts and identities point at the file.

use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};

use openward_ssh::russh::keys::ssh_key::{
    Algorithm, EcdsaCurve, LineEnding, PrivateKey, PublicKey,
};
use openward_ssh::russh::keys::{HashAlg, decode_secret_key};
use openward_vault::Vault;
use openward_vault::proto::Settings;

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
    /// Its `.pub` is next to it.
    pub has_public: bool,
    /// A certificate (`-cert.pub`) is next to it.
    pub certificate: bool,
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
        PrivateKey::from_openssh(&text)
            .ok()
            .map(|k| k.public_key().clone())
    });
    let encrypted = match PrivateKey::from_openssh(&text) {
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
        has_public: pub_path.is_file(),
        certificate: with_suffix(file, "-cert.pub").is_file(),
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
    let openssh = PrivateKey::from_openssh(text).ok();
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
        return p.to_openssh().map_err(io);
    }
    let text = fs::read_to_string(&file).map_err(io)?;
    PrivateKey::from_openssh(&text)
        .map(|k| k.public_key().clone())
        .or_else(|_| decode_secret_key(&text, None).map(|k| k.public_key().clone()))
        .map_err(|_| KeyError::NotAKey)?
        .to_openssh()
        .map_err(io)
}

/// `authorized_keys` with `line` in it: `None` when the key is there
/// already (whatever its options or comment).
pub fn with_authorized(existing: Option<&[u8]>, line: &str) -> Option<Vec<u8>> {
    let mut words = line.split_whitespace();
    let (kind, blob) = (words.next().unwrap_or(""), words.next().unwrap_or(""));
    let text = existing.map(String::from_utf8_lossy).unwrap_or_default();
    let present = text.lines().any(|l| {
        let w: Vec<&str> = l.split_whitespace().collect();
        w.windows(2).any(|p| p[0] == kind && p[1] == blob)
    });
    if present {
        return None;
    }
    let mut out = text.into_owned();
    if !out.is_empty() && !out.ends_with('\n') {
        out.push('\n');
    }
    out.push_str(line.trim());
    out.push('\n');
    Some(out.into_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn local(dir: &Path) -> Local {
        Local {
            home: dir.to_owned(),
            user: "ana".into(),
            ssh_dir: dir.join(".ssh"),
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
        assert!(k.has_public && !k.encrypted);
        assert_eq!(k.used_by, ["web"]);
        assert_eq!(
            k.fingerprint,
            Some(key.public_key().fingerprint(HashAlg::Sha256).to_string())
        );
    }

    #[test]
    fn authorized_keys_gets_the_line_once() {
        let line = "ssh-ed25519 AAAAC3Nz ana@mac";
        let added = with_authorized(None, line).unwrap();
        assert_eq!(added, b"ssh-ed25519 AAAAC3Nz ana@mac\n");
        let other = b"ssh-rsa AAAAB3 bob";
        let both = with_authorized(Some(other), line).unwrap();
        assert_eq!(both, b"ssh-rsa AAAAB3 bob\nssh-ed25519 AAAAC3Nz ana@mac\n");
        // There already, with options and another comment.
        let there = b"from=\"10.0.0.0/8\" ssh-ed25519 AAAAC3Nz old comment\n";
        assert_eq!(with_authorized(Some(there), line), None);
    }
}
