//! What the UI says about a key file: its type, fingerprint and
//! certificate. Only public halves are read (`<key>.pub`, certificates);
//! private keys are never opened here.

use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use openward_ssh::russh::keys::ssh_key::public::KeyData;
use openward_ssh::russh::keys::{Algorithm, Certificate, EcdsaCurve, HashAlg, PublicKey};

use crate::local::{Local, Tokens};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyState {
    /// The key is there, and its `.pub` too.
    Found,
    /// No file at that path on this machine.
    Missing,
    /// The key is there, but not its `.pub`: its type is not known
    /// without opening it.
    NoPublicHalf,
    /// The path names `%h`, `%r`…: a different file for each host.
    PerHost,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CertInfo {
    /// As given in the certificates, or `<key>-cert.pub` (`implicit`).
    pub path: String,
    pub implicit: bool,
    /// `None`: valid forever.
    pub valid_before: Option<SystemTime>,
    pub expired: bool,
    pub principals: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeyInfo {
    pub state: KeyState,
    /// `Ed25519`, `RSA 3072`, `ECDSA P-256`…
    pub algorithm: Option<String>,
    /// `SHA256:…`
    pub fingerprint: Option<String>,
    pub comment: Option<String>,
    pub certificate: Option<CertInfo>,
}

/// What `path` (as written in settings, with `~`) holds on this machine,
/// and which of `certificates` (or `<key>-cert.pub`) goes with it.
pub fn key_info(local: &Local, path: &str, certificates: &[String]) -> KeyInfo {
    let mut info = KeyInfo {
        state: KeyState::Missing,
        algorithm: None,
        fingerprint: None,
        comment: None,
        certificate: None,
    };
    if path.contains('%') {
        info.state = KeyState::PerHost;
        return info;
    }
    let t = Tokens {
        host: "",
        port: 22,
        user: &local.user,
        alias: "",
    };
    let file = local.path(path, &t);
    if !file.is_file() {
        return info;
    }
    let public = PublicKey::read_openssh_file(with_suffix(&file, ".pub")).ok();
    info.state = match &public {
        Some(_) => KeyState::Found,
        None => KeyState::NoPublicHalf,
    };
    if let Some(key) = &public {
        info.algorithm = Some(algorithm(key.key_data()));
        info.fingerprint = Some(key.fingerprint(HashAlg::Sha256).to_string());
        info.comment = Some(key.comment().as_str_lossy().to_owned()).filter(|c| !c.is_empty());
    }
    let implicit = with_suffix(&file, "-cert.pub");
    let candidates = certificates
        .iter()
        .filter(|c| !c.contains('%'))
        .map(|c| (c.clone(), local.path(c, &t), false))
        .chain([(display(path, "-cert.pub"), implicit, true)]);
    for (shown, cert_path, implicit) in candidates {
        let Ok(cert) = Certificate::read_file(&cert_path) else {
            continue;
        };
        // Without the `.pub`, only the certificate named after the key.
        let matches = match &public {
            Some(key) => cert.public_key() == key.key_data(),
            None => implicit,
        };
        if matches {
            let before = cert.valid_before();
            let valid_before =
                (before != u64::MAX).then(|| UNIX_EPOCH + Duration::from_secs(before));
            info.certificate = Some(CertInfo {
                path: shown,
                implicit,
                expired: valid_before.is_some_and(|b| b <= SystemTime::now()),
                valid_before,
                principals: cert.valid_principals().to_vec(),
            });
            break;
        }
    }
    info
}

fn with_suffix(file: &Path, suffix: &str) -> PathBuf {
    let mut name = file.as_os_str().to_owned();
    name.push(suffix);
    PathBuf::from(name)
}

fn display(path: &str, suffix: &str) -> String {
    format!("{path}{suffix}")
}

fn algorithm(key: &KeyData) -> String {
    match key.algorithm() {
        Algorithm::Ed25519 => "Ed25519".into(),
        Algorithm::SkEd25519 => "Ed25519-SK".into(),
        Algorithm::Rsa { .. } => match key.rsa() {
            Some(rsa) => format!("RSA {}", rsa.key_size()),
            None => "RSA".into(),
        },
        Algorithm::Ecdsa { curve } => format!("ECDSA {}", curve_name(curve)),
        Algorithm::SkEcdsaSha2NistP256 => "ECDSA-SK P-256".into(),
        Algorithm::Dsa => "DSA".into(),
        other => other.as_str().to_owned(),
    }
}

fn curve_name(curve: EcdsaCurve) -> &'static str {
    match curve {
        EcdsaCurve::NistP256 => "P-256",
        EcdsaCurve::NistP384 => "P-384",
        EcdsaCurve::NistP521 => "P-521",
    }
}

#[cfg(test)]
mod tests {
    use std::process::Command;

    use super::*;

    fn local(home: &Path) -> Local {
        Local {
            home: home.to_owned(),
            user: "ana".into(),
            ssh_dir: home.join(".ssh"),
            agent: None,
        }
    }

    fn keygen(args: &[&str], dir: &Path) -> bool {
        Command::new("ssh-keygen")
            .args(args)
            .current_dir(dir)
            .output()
            .is_ok_and(|o| o.status.success())
    }

    #[test]
    fn a_key_is_described_by_its_public_half_and_certificate() {
        let home = tempfile::tempdir().unwrap();
        let ssh = home.path().join(".ssh");
        std::fs::create_dir(&ssh).unwrap();
        let made = keygen(
            &[
                "-q",
                "-t",
                "ed25519",
                "-N",
                "",
                "-C",
                "ana@laptop",
                "-f",
                "deploy",
            ],
            &ssh,
        ) && keygen(
            &["-q", "-t", "rsa", "-b", "3072", "-N", "", "-f", "old"],
            &ssh,
        ) && keygen(&["-q", "-t", "ed25519", "-N", "", "-f", "ca"], &ssh)
            && keygen(
                &[
                    "-q",
                    "-s",
                    "ca",
                    "-I",
                    "ana",
                    "-n",
                    "deploy,ops",
                    "-V",
                    "-5m:+1d",
                    "deploy.pub",
                ],
                &ssh,
            );
        if !made {
            eprintln!("skipped: no ssh-keygen");
            return;
        }
        let l = local(home.path());

        let info = key_info(&l, "~/.ssh/deploy", &[]);
        assert_eq!(info.state, KeyState::Found);
        assert_eq!(info.algorithm.as_deref(), Some("Ed25519"));
        assert!(info.fingerprint.unwrap().starts_with("SHA256:"));
        assert_eq!(info.comment.as_deref(), Some("ana@laptop"));
        let cert = info.certificate.unwrap();
        assert_eq!(cert.path, "~/.ssh/deploy-cert.pub");
        assert!(cert.implicit && !cert.expired);
        assert!(cert.valid_before.unwrap() > SystemTime::now());
        assert_eq!(cert.principals, ["deploy", "ops"]);

        // A certificate given by path, found by its key; relative paths
        // are in ~/.ssh as in OpenSSH.
        std::fs::rename(ssh.join("deploy-cert.pub"), ssh.join("deploy.cert")).unwrap();
        let info = key_info(
            &l,
            "deploy",
            &["~/.ssh/old.pub".into(), "~/.ssh/deploy.cert".into()],
        );
        let cert = info.certificate.unwrap();
        assert_eq!(
            (cert.path.as_str(), cert.implicit),
            ("~/.ssh/deploy.cert", false)
        );
        // Not this key's.
        assert_eq!(
            key_info(&l, "old", &["~/.ssh/deploy.cert".into()]).certificate,
            None
        );

        assert_eq!(
            key_info(&l, "old", &[]).algorithm.as_deref(),
            Some("RSA 3072")
        );
        std::fs::remove_file(ssh.join("old.pub")).unwrap();
        assert_eq!(key_info(&l, "old", &[]).state, KeyState::NoPublicHalf);
        assert_eq!(key_info(&l, "~/.ssh/gone", &[]).state, KeyState::Missing);
        assert_eq!(key_info(&l, "~/.ssh/%h", &[]).state, KeyState::PerHost);
    }
}
