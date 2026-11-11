//! Host key trust, decided in the core and not in the UI (ADR-003).
//!
//! Reads OpenSSH `known_hosts` lines: plain and hashed (`|1|salt|hmac`)
//! host patterns, `[host]:port` for non-standard ports, `@cert-authority`
//! lines that trust host certificates from a CA, and `@revoked` keys that
//! are refused whatever else says. Host names match without regard to case,
//! as OpenSSH lowercases them.

use std::time::{SystemTime, UNIX_EPOCH};

use hmac::{Hmac, KeyInit, Mac};
use russh::keys::ssh_key::certificate::CertType;
use russh::keys::ssh_key::public::{EcdsaPublicKey, KeyData};
use russh::keys::{Algorithm, HashAlg, PublicKey, PublicKeyOrCertificate};
use sha1::Sha1;

/// What to do with a host whose key is not known yet.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Unknown {
    /// Refuse: only listed keys and certified hosts get in.
    Reject,
    /// Trust on first use: accept and remember it.
    Learn,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Verdict {
    /// The key is listed for this host.
    Known,
    /// A certificate signed by a trusted CA, valid now, naming this host.
    Certified { ca: String, key_id: String },
    /// Not listed; accepted and remembered (TOFU).
    Learned,
    /// Not listed and the policy rejects unknown hosts.
    Unknown,
    /// Listed with a different key: possible man in the middle.
    Changed,
    /// Listed only with keys of other types: the server no longer offers
    /// the key that is known, or someone else is answering. Never learned
    /// on its own, not even when new hosts are.
    OtherType,
    /// A certificate that does not check out.
    BadCertificate(CertProblem),
    /// The key, or the CA that signed it, is marked `@revoked`.
    Revoked,
}

/// Why a host certificate does not check out.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CertProblem {
    /// A user's certificate where a host's belongs.
    NotHost,
    /// No `@cert-authority` line covers this host.
    NoAuthority,
    /// Not signed by one of those authorities, or not well signed.
    Untrusted,
    /// Outside its validity window: expired, or not valid yet.
    OutOfDate,
    /// Issued for other names.
    NotForHost,
}

impl std::fmt::Display for CertProblem {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::NotHost => "not a host certificate",
            Self::NoAuthority => "no @cert-authority for this host",
            Self::Untrusted => "not signed by a trusted authority",
            Self::OutOfDate => "expired or not yet valid",
            Self::NotForHost => "this host is not in its principals",
        })
    }
}

impl Verdict {
    pub fn trusted(&self) -> bool {
        matches!(self, Self::Known | Self::Certified { .. } | Self::Learned)
    }
}

#[derive(Clone, Debug)]
struct Entry {
    patterns: Patterns,
    marker: Option<Marker>,
    key: PublicKey,
}

/// What a line's marker says of its key.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Marker {
    /// `@cert-authority`: a CA whose host certificates are trusted.
    CertAuthority,
    /// `@revoked`: refused for the hosts it names.
    Revoked,
}

/// One line of a `known_hosts` file, as a screen lists it.
#[derive(Clone, Debug)]
pub struct Line {
    /// 1-based, as editors count.
    pub number: usize,
    /// The line as written, to make sure it is the same one when removing it.
    pub text: String,
    pub marker: Option<Marker>,
    /// The patterns as written; `None` when the name is hashed.
    pub hosts: Option<String>,
    pub key: PublicKey,
    pub comment: Option<String>,
    patterns: Patterns,
}

impl Line {
    /// The line names `host:port` (a hashed name only says yes or no).
    pub fn matches(&self, host: &str, port: u16) -> bool {
        self.patterns.matches(&host_spec(host, port))
    }
}

#[derive(Clone, Debug)]
enum Patterns {
    Plain(Vec<String>),
    /// `|1|base64(salt)|base64(HMAC-SHA1(salt, host))`
    Hashed {
        salt: Vec<u8>,
        hash: Vec<u8>,
    },
}

#[derive(Clone, Debug)]
pub struct KnownHosts {
    entries: Vec<Entry>,
    pub unknown: Unknown,
}

/// `host` or `[host]:port`, as OpenSSH writes host names: in lowercase.
fn host_spec(host: &str, port: u16) -> String {
    let host = host.to_ascii_lowercase();
    if port == 22 {
        host
    } else {
        format!("[{host}]:{port}")
    }
}

/// OpenSSH glob: `*` and `?`, with `!` negation handled by the caller.
fn glob(pattern: &str, text: &str) -> bool {
    let (p, t): (Vec<char>, Vec<char>) = (pattern.chars().collect(), text.chars().collect());
    let (mut pi, mut ti, mut star, mut mark) = (0, 0, None, 0);
    while ti < t.len() {
        if pi < p.len() && (p[pi] == '?' || p[pi] == t[ti]) {
            pi += 1;
            ti += 1;
        } else if pi < p.len() && p[pi] == '*' {
            star = Some(pi);
            mark = ti;
            pi += 1;
        } else if let Some(s) = star {
            pi = s + 1;
            mark += 1;
            ti = mark;
        } else {
            return false;
        }
    }
    p[pi..].iter().all(|&c| c == '*')
}

impl Patterns {
    fn matches(&self, spec: &str) -> bool {
        match self {
            Self::Plain(list) => {
                let mut hit = false;
                for p in list {
                    if let Some(neg) = p.strip_prefix('!') {
                        if glob(neg, spec) {
                            return false;
                        }
                    } else if glob(p, spec) {
                        hit = true;
                    }
                }
                hit
            }
            Self::Hashed { salt, hash } => {
                let Ok(mut mac) = Hmac::<Sha1>::new_from_slice(salt) else {
                    return false;
                };
                mac.update(spec.as_bytes());
                mac.verify_slice(hash).is_ok()
            }
        }
    }
}

/// Public-key identity, independent of the SEC1 wire encoding. The signed
/// certificate itself is never rewritten. Security-key applications remain
/// part of the identity, as they are part of what the key authenticates.
pub fn same_key(a: &KeyData, b: &KeyData) -> bool {
    match (a, b) {
        (
            KeyData::Ecdsa(EcdsaPublicKey::NistP256(a)),
            KeyData::Ecdsa(EcdsaPublicKey::NistP256(b)),
        ) => a.compress() == b.compress(),
        (
            KeyData::Ecdsa(EcdsaPublicKey::NistP384(a)),
            KeyData::Ecdsa(EcdsaPublicKey::NistP384(b)),
        ) => a.compress() == b.compress(),
        (
            KeyData::Ecdsa(EcdsaPublicKey::NistP521(a)),
            KeyData::Ecdsa(EcdsaPublicKey::NistP521(b)),
        ) => a.compress() == b.compress(),
        (KeyData::SkEcdsaSha2NistP256(a), KeyData::SkEcdsaSha2NistP256(b)) => {
            a.ec_point().compress() == b.ec_point().compress() && a.application() == b.application()
        }
        _ => a == b,
    }
}

impl KnownHosts {
    pub fn new(unknown: Unknown) -> Self {
        Self {
            entries: Vec::new(),
            unknown,
        }
    }

    /// Parses `known_hosts` text; unparseable lines are skipped, as OpenSSH does.
    pub fn parse(text: &str, unknown: Unknown) -> Self {
        let mut hosts = Self::new(unknown);
        hosts.entries = lines(text)
            .into_iter()
            .map(|l| Entry {
                patterns: l.patterns,
                marker: l.marker,
                key: l.key,
            })
            .collect();
        hosts
    }

    /// Remembers a host key (what TOFU does after the first connection).
    pub fn add(&mut self, host: &str, port: u16, key: PublicKey) {
        self.entries.push(Entry {
            patterns: Patterns::Plain(vec![host_spec(host, port)]),
            marker: None,
            key,
        });
    }

    /// The plain keys listed for `host:port` (not the CAs).
    pub fn listed(&self, host: &str, port: u16) -> Vec<&PublicKey> {
        let spec = host_spec(host, port);
        self.entries
            .iter()
            .filter(|e| e.marker.is_none() && e.patterns.matches(&spec))
            .map(|e| &e.key)
            .collect()
    }

    /// The types of the keys listed for `host:port`, to ask the server for
    /// those first.
    pub fn algorithms(&self, host: &str, port: u16) -> Vec<Algorithm> {
        let mut out: Vec<Algorithm> = Vec::new();
        for key in self.listed(host, port) {
            if !out.contains(&key.algorithm()) {
                out.push(key.algorithm());
            }
        }
        out
    }

    /// `key` is marked `@revoked` for `spec`.
    fn revoked(&self, spec: &str, key: &KeyData) -> bool {
        self.entries.iter().any(|e| {
            e.marker == Some(Marker::Revoked)
                && same_key(e.key.key_data(), key)
                && e.patterns.matches(spec)
        })
    }

    pub fn check(&mut self, host: &str, port: u16, offered: &PublicKeyOrCertificate) -> Verdict {
        let spec = host_spec(host, port);
        let revoked = match offered {
            PublicKeyOrCertificate::Certificate(cert) => {
                self.revoked(&spec, cert.public_key()) || self.revoked(&spec, cert.signature_key())
            }
            PublicKeyOrCertificate::PublicKey { key, .. } => self.revoked(&spec, key.key_data()),
        };
        if revoked {
            return Verdict::Revoked;
        }
        match offered {
            PublicKeyOrCertificate::Certificate(cert) => self.check_certificate(host, &spec, cert),
            PublicKeyOrCertificate::PublicKey { key, .. } => {
                let listed = self.listed(host, port);
                if listed
                    .iter()
                    .any(|k| same_key(k.key_data(), key.key_data()))
                {
                    Verdict::Known
                } else if listed.iter().any(|k| k.algorithm() == key.algorithm()) {
                    // Same algorithm, different key: the classic warning.
                    Verdict::Changed
                } else if !listed.is_empty() {
                    Verdict::OtherType
                } else if self.unknown == Unknown::Learn {
                    self.add(host, port, key.clone());
                    Verdict::Learned
                } else {
                    Verdict::Unknown
                }
            }
        }
    }

    fn check_certificate(
        &self,
        host: &str,
        spec: &str,
        cert: &russh::keys::Certificate,
    ) -> Verdict {
        if cert.cert_type() != CertType::Host {
            return Verdict::BadCertificate(CertProblem::NotHost);
        }
        let cas: Vec<&PublicKey> = self
            .entries
            .iter()
            .filter(|e| e.marker == Some(Marker::CertAuthority) && e.patterns.matches(spec))
            .map(|e| &e.key)
            .collect();
        if cas.is_empty() {
            return Verdict::BadCertificate(CertProblem::NoAuthority);
        }
        let Some(ca) = cas
            .iter()
            .find(|k| same_key(k.key_data(), cert.signature_key()))
        else {
            return Verdict::BadCertificate(CertProblem::Untrusted);
        };
        // validate_at compares fingerprints of the serialized signature key.
        // Only authorize that representation after checking canonical identity
        // against a listed CA; signature, validity and principals still hold.
        let signer = PublicKey::from(cert.signature_key().clone()).fingerprint(HashAlg::Sha256);
        let fingerprints = [signer];
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or_default();
        // Signature by one of the CAs (checked at a moment inside its
        // window, to tell a bad signature from an old one), and inside the
        // validity window now.
        if cert
            .validate_at(cert.valid_after(), fingerprints.iter())
            .is_err()
        {
            return Verdict::BadCertificate(CertProblem::Untrusted);
        }
        if cert.validate_at(now, fingerprints.iter()).is_err() {
            return Verdict::BadCertificate(CertProblem::OutOfDate);
        }
        let principals = cert.valid_principals();
        if !principals.is_empty() && !principals.iter().any(|p| p.eq_ignore_ascii_case(host)) {
            return Verdict::BadCertificate(CertProblem::NotForHost);
        }
        Verdict::Certified {
            ca: ca.fingerprint(HashAlg::Sha256).to_string(),
            key_id: cert.key_id().to_owned(),
        }
    }
}

/// The lines of `known_hosts` text that hold a key, numbered from 1.
/// Comments and lines that do not parse are left out, as OpenSSH does.
pub fn lines(text: &str) -> Vec<Line> {
    let mut out = Vec::new();
    for (i, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split_whitespace();
        let mut first = fields.next().unwrap_or_default();
        let marker = match first {
            "@cert-authority" => Some(Marker::CertAuthority),
            "@revoked" => Some(Marker::Revoked),
            m if m.starts_with('@') => continue, // unknown markers
            _ => None,
        };
        if marker.is_some() {
            first = fields.next().unwrap_or_default();
        }
        let (Some(algorithm), Some(data)) = (fields.next(), fields.next()) else {
            continue;
        };
        let Ok(key) = PublicKey::from_openssh(&format!("{algorithm} {data}")) else {
            continue;
        };
        let comment = Some(fields.collect::<Vec<_>>().join(" ")).filter(|c| !c.is_empty());
        let (patterns, hosts) = if let Some(rest) = first.strip_prefix("|1|") {
            let b64 = data_encoding::BASE64;
            let mut parts = rest.split('|');
            match (
                parts.next().map(|s| b64.decode(s.as_bytes())),
                parts.next().map(|s| b64.decode(s.as_bytes())),
            ) {
                (Some(Ok(salt)), Some(Ok(hash))) => (Patterns::Hashed { salt, hash }, None),
                _ => continue,
            }
        } else {
            (
                Patterns::Plain(first.split(',').map(str::to_ascii_lowercase).collect()),
                Some(first.to_owned()),
            )
        };
        out.push(Line {
            number: i + 1,
            text: raw.to_owned(),
            marker,
            hosts,
            key,
            comment,
            patterns,
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn compressed(key: &PublicKey) -> PublicKey {
        use russh::keys::ssh_key::public::{EcdsaPublicKey, KeyData, SkEcdsaSha2NistP256};
        let data = match key.key_data() {
            KeyData::Ecdsa(EcdsaPublicKey::NistP256(p)) => {
                KeyData::Ecdsa(EcdsaPublicKey::NistP256(p.compress()))
            }
            KeyData::Ecdsa(EcdsaPublicKey::NistP384(p)) => {
                KeyData::Ecdsa(EcdsaPublicKey::NistP384(p.compress()))
            }
            KeyData::Ecdsa(EcdsaPublicKey::NistP521(p)) => {
                KeyData::Ecdsa(EcdsaPublicKey::NistP521(p.compress()))
            }
            KeyData::SkEcdsaSha2NistP256(k) => KeyData::SkEcdsaSha2NistP256(
                SkEcdsaSha2NistP256::new(k.ec_point().compress(), k.application()),
            ),
            other => other.clone(),
        };
        PublicKey::from(data)
    }

    #[test]
    fn equivalent_ecdsa_encodings_cannot_evade_revocation_or_change_a_pin() {
        use russh::keys::PrivateKey;
        use russh::keys::ssh_key::EcdsaCurve;
        for curve in [
            EcdsaCurve::NistP256,
            EcdsaCurve::NistP384,
            EcdsaCurve::NistP521,
        ] {
            let private = PrivateKey::random(&mut rand::rng(), Algorithm::Ecdsa { curve }).unwrap();
            let plain = private.public_key().clone();
            let compact = compressed(&plain);
            assert_ne!(
                plain.key_data(),
                compact.key_data(),
                "different wire encodings"
            );
            for (listed, offered) in [(&plain, &compact), (&compact, &plain)] {
                let key = PublicKeyOrCertificate::PublicKey {
                    key: offered.clone(),
                    hash_alg: None,
                };
                let line = listed.to_openssh().unwrap();
                let mut revoked = KnownHosts::parse(
                    &format!(
                        "host {}\n@revoked * {line}\n",
                        offered.to_openssh().unwrap()
                    ),
                    Unknown::Learn,
                );
                assert_eq!(revoked.check("host", 22, &key), Verdict::Revoked);
                let mut known = KnownHosts::parse(&format!("host {line}\n"), Unknown::Reject);
                assert_eq!(known.check("host", 22, &key), Verdict::Known);
            }
        }
    }

    #[test]
    fn security_key_points_are_canonical_but_applications_remain_distinct() {
        use russh::keys::PrivateKey;
        use russh::keys::ssh_key::{
            EcdsaCurve,
            public::{EcdsaPublicKey, SkEcdsaSha2NistP256},
        };
        let private = PrivateKey::random(
            &mut rand::rng(),
            Algorithm::Ecdsa {
                curve: EcdsaCurve::NistP256,
            },
        )
        .unwrap();
        let EcdsaPublicKey::NistP256(point) = private.public_key().key_data().ecdsa().unwrap()
        else {
            unreachable!()
        };
        let key = PublicKey::from(SkEcdsaSha2NistP256::new(*point, "ssh:one"));
        let compact = compressed(&key);
        let other = PublicKey::from(SkEcdsaSha2NistP256::new(point.compress(), "ssh:two"));
        let mut known = KnownHosts::parse(
            &format!(
                "host {}\n@revoked * {}\n",
                compact.to_openssh().unwrap(),
                key.to_openssh().unwrap()
            ),
            Unknown::Reject,
        );
        let offered = |key| PublicKeyOrCertificate::PublicKey {
            key,
            hash_alg: None,
        };
        assert_eq!(known.check("host", 22, &offered(compact)), Verdict::Revoked);
        assert_ne!(known.check("host", 22, &offered(other)), Verdict::Revoked);
    }

    #[tokio::test]
    async fn a_compressed_server_key_obeys_the_same_pin_and_revocation_over_ssh() {
        use crate::client::{self, Hop, Options, Target, UntrustedHost};
        use russh::keys::{
            PrivateKey,
            ssh_key::{EcdsaCurve, private::EcdsaKeypair},
        };
        use std::sync::{Arc, Mutex};
        use std::time::Duration;
        struct Server;
        impl russh::server::Handler for Server {
            type Error = russh::Error;
        }
        for curve in [
            EcdsaCurve::NistP256,
            EcdsaCurve::NistP384,
            EcdsaCurve::NistP521,
        ] {
            let plain = PrivateKey::random(&mut rand::rng(), Algorithm::Ecdsa { curve }).unwrap();
            let pair = match plain.key_data().ecdsa().unwrap() {
                EcdsaKeypair::NistP256 { public, private } => EcdsaKeypair::NistP256 {
                    public: public.compress(),
                    private: private.clone(),
                },
                EcdsaKeypair::NistP384 { public, private } => EcdsaKeypair::NistP384 {
                    public: public.compress(),
                    private: private.clone(),
                },
                EcdsaKeypair::NistP521 { public, private } => EcdsaKeypair::NistP521 {
                    public: public.compress(),
                    private: private.clone(),
                },
            };
            let compact = PrivateKey::from(pair);
            assert_ne!(
                plain.public_key().key_data(),
                compact.public_key().key_data()
            );
            for revoked in [false, true] {
                let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
                let port = listener.local_addr().unwrap().port();
                let config = Arc::new(russh::server::Config {
                    keys: vec![compact.clone()],
                    ..Default::default()
                });
                let server = tokio::spawn(async move {
                    let (stream, _) = listener.accept().await.unwrap();
                    if let Ok(session) = russh::server::run_stream(config, stream, Server).await {
                        let _ = session.await;
                    }
                });
                let key = plain.public_key().to_openssh().unwrap();
                let text = format!(
                    "[127.0.0.1]:{port} {key}\n{}",
                    if revoked {
                        format!("@revoked * {key}\n")
                    } else {
                        String::new()
                    }
                );
                let opts = Options {
                    user: "test".into(),
                    known_hosts: Arc::new(Mutex::new(KnownHosts::parse(&text, Unknown::Reject))),
                    host_certificates: false,
                    legacy_host_keys: false,
                    connect_timeout: Some(Duration::from_secs(3)),
                    keepalive: None,
                    agent_forward: None,
                    on_untrusted: None,
                };
                let result = client::open(&Target::new("127.0.0.1", port), Hop::Tcp, &opts).await;
                if revoked {
                    let error = result.err().expect("a revoked encoding must not connect");
                    assert!(
                        matches!(
                            error.downcast_ref::<UntrustedHost>(),
                            Some(UntrustedHost(Verdict::Revoked))
                        ),
                        "{error:#}"
                    );
                } else {
                    let session = result.unwrap();
                    assert_eq!(session.info().verdict, Some(Verdict::Known));
                    session.disconnect().await;
                }
                server.abort();
                let _ = server.await;
            }
        }
    }

    #[test]
    fn certificates_check_canonical_subjects_and_authorities_without_changing_signed_bytes() {
        use russh::keys::PrivateKey;
        use russh::keys::ssh_key::{EcdsaCurve, certificate::Builder};
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let private = || {
            PrivateKey::random(
                &mut rand::rng(),
                Algorithm::Ecdsa {
                    curve: EcdsaCurve::NistP256,
                },
            )
            .unwrap()
        };
        let (ca, subject) = (private(), private());
        let compact_ca = compressed(ca.public_key());
        let compact_subject = compressed(subject.public_key());
        let mut builder = Builder::new(
            [7; 16],
            subject.public_key().key_data().clone(),
            now - 60,
            now + 3600,
        )
        .unwrap();
        builder.cert_type(CertType::Host).unwrap();
        builder.valid_principal("host").unwrap();
        let cert = PublicKeyOrCertificate::Certificate(builder.sign(&ca).unwrap());
        let authority = format!(
            "@cert-authority host {}\n",
            compact_ca.to_openssh().unwrap()
        );
        let mut known = KnownHosts::parse(&authority, Unknown::Reject);
        assert!(matches!(
            known.check("host", 22, &cert),
            Verdict::Certified { .. }
        ));
        for revoked in [&compact_ca, &compact_subject] {
            let mut known = KnownHosts::parse(
                &format!(
                    "{authority}@revoked host {}\n",
                    revoked.to_openssh().unwrap()
                ),
                Unknown::Learn,
            );
            assert_eq!(known.check("host", 22, &cert), Verdict::Revoked);
        }
        let stranger = private();
        let mut known = KnownHosts::parse(
            &format!(
                "@cert-authority host {}\n",
                stranger.public_key().to_openssh().unwrap()
            ),
            Unknown::Reject,
        );
        assert_eq!(
            known.check("host", 22, &cert),
            Verdict::BadCertificate(CertProblem::Untrusted)
        );
    }

    mod hostile {
        use super::*;
        use proptest::collection::vec;
        use proptest::prelude::*;
        use proptest::sample::select;

        proptest! {
            /// Any text as `known_hosts` (hashed names, markers, patterns,
            /// keys that do not decode): read line by line, never a panic.
            #[test]
            fn any_text_is_read(text in vec(
                prop_oneof![
                    select(&[
                        "|1|", "@cert-authority ", "@revoked ", "*", "?", "!", ",", "[", "]:2222",
                        " ssh-ed25519 ", " ssh-rsa ", "AAAAC3NzaC1lZDI1NTE5AAAAI", "=", "\n", " ",
                    ][..]).prop_map(str::to_owned),
                    "[ -~]{0,16}",
                    "[\\u{0}-\\u{ffff}]{0,3}",
                ],
                0..48,
            ).prop_map(|p| p.concat())) {
                let _ = lines(&text);
                let known = KnownHosts::parse(&text, Unknown::Reject);
                for (host, port) in [("db.example.com", 22), ("10.0.0.1", 2222), ("", 0)] {
                    let _ = known.listed(host, port);
                    let _ = known.algorithms(host, port);
                }
            }
        }
    }

    const KEY: &str =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg+ccEU+buKk8f5ORMPyzCAzWM04Omv+MOaI8CvGd7f";
    const OTHER: &str =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJON9ypgHeCkesivXcy8heayyTUCM9gTjTKSUZit/91";

    fn offered(k: &str) -> PublicKeyOrCertificate {
        PublicKeyOrCertificate::PublicKey {
            key: PublicKey::from_openssh(k).unwrap(),
            hash_alg: None,
        }
    }

    #[test]
    fn a_bad_certificate_says_what_is_wrong() {
        use russh::keys::PrivateKey;
        use russh::keys::ssh_key::certificate::Builder;
        use russh::keys::ssh_key::private::Ed25519Keypair;

        let key = |seed| PrivateKey::from(Ed25519Keypair::from_seed(&[seed; 32]));
        let (ca, stranger, server) = (key(1), key(2), key(3));
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let signed = |by: &PrivateKey, kind, valid: std::ops::Range<u64>, name: &str| {
            let mut b = Builder::new(
                [7; 16],
                server.public_key().key_data().clone(),
                valid.start,
                valid.end,
            )
            .unwrap();
            b.cert_type(kind).unwrap();
            b.valid_principal(name).unwrap();
            PublicKeyOrCertificate::Certificate(b.sign(by).unwrap())
        };
        let today = now - 60..now + 3600;
        let ca_line = format!(
            "@cert-authority *.example.org {}\n",
            ca.public_key().to_openssh().unwrap()
        );
        let mut kh = KnownHosts::parse(&ca_line, Unknown::Reject);
        let host = "db.example.org";
        let bad = |p| Verdict::BadCertificate(p);
        assert!(matches!(
            kh.check(host, 22, &signed(&ca, CertType::Host, today.clone(), host)),
            Verdict::Certified { .. }
        ));
        assert_eq!(
            kh.check(host, 22, &signed(&ca, CertType::User, today.clone(), host)),
            bad(CertProblem::NotHost)
        );
        assert_eq!(
            kh.check(
                "other.net",
                22,
                &signed(&ca, CertType::Host, today.clone(), host)
            ),
            bad(CertProblem::NoAuthority)
        );
        assert_eq!(
            kh.check(
                host,
                22,
                &signed(&stranger, CertType::Host, today.clone(), host)
            ),
            bad(CertProblem::Untrusted)
        );
        assert_eq!(
            kh.check(
                host,
                22,
                &signed(&ca, CertType::Host, now - 7200..now - 3600, host)
            ),
            bad(CertProblem::OutOfDate)
        );
        assert_eq!(
            kh.check(
                host,
                22,
                &signed(&ca, CertType::Host, today, "web.example.org")
            ),
            bad(CertProblem::NotForHost)
        );
    }

    #[test]
    fn plain_patterns_ports_and_negation() {
        let mut kh = KnownHosts::parse(
            &format!("[127.0.0.1]:2222,*.example.org,!bad.example.org {KEY}\n"),
            Unknown::Reject,
        );
        assert_eq!(kh.check("127.0.0.1", 2222, &offered(KEY)), Verdict::Known);
        assert_eq!(kh.check("a.example.org", 22, &offered(KEY)), Verdict::Known);
        assert_eq!(
            kh.check("bad.example.org", 22, &offered(KEY)),
            Verdict::Unknown
        );
        assert_eq!(kh.check("127.0.0.1", 22, &offered(KEY)), Verdict::Unknown);
        assert_eq!(
            kh.check("127.0.0.1", 2222, &offered(OTHER)),
            Verdict::Changed
        );
    }

    const ECDSA: &str = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBMIZhRFAgWfopKyt4kiX10TmV5mtEHg5naGWD4vZbxbMtJ1QP8QXWI2/WkTTQ2HTk7ehoQLsA34iYt/4+YlPX0A=";

    /// A host known only by a key of another type is neither new nor
    /// learned: its server should have offered the key that is known.
    #[test]
    fn keys_of_another_type_are_not_new() {
        let mut kh = KnownHosts::parse(&format!("h {ECDSA}\n"), Unknown::Learn);
        assert_eq!(
            kh.algorithms("h", 22),
            [PublicKey::from_openssh(ECDSA).unwrap().algorithm()]
        );
        assert_eq!(kh.check("h", 22, &offered(KEY)), Verdict::OtherType);
        assert!(!Verdict::OtherType.trusted());
        assert!(kh.algorithms("h", 22).len() == 1, "not learned");
        assert_eq!(kh.check("h", 22, &offered(ECDSA)), Verdict::Known);
        assert_eq!(kh.check("new", 22, &offered(KEY)), Verdict::Learned);
    }

    /// Names match whatever their case, as OpenSSH lowercases them.
    #[test]
    fn host_names_ignore_case() {
        let mut kh = KnownHosts::parse(&format!("Web.Example.COM {KEY}\n"), Unknown::Reject);
        assert_eq!(
            kh.check("web.example.com", 22, &offered(KEY)),
            Verdict::Known
        );
        assert_eq!(
            kh.check("WEB.example.com", 22, &offered(KEY)),
            Verdict::Known
        );
        let salt = b"0123456789abcdefghij";
        let mut mac = Hmac::<Sha1>::new_from_slice(salt).unwrap();
        mac.update(b"web.example.com");
        let b64 = data_encoding::BASE64;
        let line = format!(
            "|1|{}|{} {KEY}",
            b64.encode(salt),
            b64.encode(&mac.finalize().into_bytes())
        );
        let mut kh = KnownHosts::parse(&line, Unknown::Reject);
        assert_eq!(
            kh.check("Web.Example.com", 22, &offered(KEY)),
            Verdict::Known
        );
    }

    #[test]
    fn hashed_host_names() {
        // ssh-keygen -H style entry for [127.0.0.1]:2222.
        let salt = b"0123456789abcdefghij";
        let mut mac = Hmac::<Sha1>::new_from_slice(salt).unwrap();
        mac.update(b"[127.0.0.1]:2222");
        let b64 = data_encoding::BASE64;
        let line = format!(
            "|1|{}|{} {KEY}",
            b64.encode(salt),
            b64.encode(&mac.finalize().into_bytes())
        );
        let mut kh = KnownHosts::parse(&line, Unknown::Reject);
        assert_eq!(kh.check("127.0.0.1", 2222, &offered(KEY)), Verdict::Known);
        assert_eq!(kh.check("127.0.0.2", 2222, &offered(KEY)), Verdict::Unknown);
    }

    #[test]
    fn revoked_keys_are_refused_even_if_listed() {
        let text = format!("h {KEY}\n@revoked * {KEY}\n");
        let mut kh = KnownHosts::parse(&text, Unknown::Learn);
        assert_eq!(kh.check("h", 22, &offered(KEY)), Verdict::Revoked);
        assert_eq!(kh.check("other", 22, &offered(KEY)), Verdict::Revoked);
        assert_eq!(kh.check("h", 22, &offered(OTHER)), Verdict::Changed);
        assert!(!Verdict::Revoked.trusted());
    }

    #[test]
    fn lines_are_numbered_with_their_marker_and_comment() {
        let salt = b"0123456789abcdefghij";
        let mut mac = Hmac::<Sha1>::new_from_slice(salt).unwrap();
        mac.update(b"bastion.example.com");
        let b64 = data_encoding::BASE64;
        let text = format!(
            "# mine\nweb,10.0.0.1 {KEY} ana@laptop\n\nnot a key line\n|1|{}|{} {OTHER}\n@cert-authority *.example.com {KEY}\n",
            b64.encode(salt),
            b64.encode(&mac.finalize().into_bytes())
        );
        let all = lines(&text);
        let numbers: Vec<usize> = all.iter().map(|l| l.number).collect();
        assert_eq!(numbers, [2, 5, 6]);
        assert_eq!(all[0].hosts.as_deref(), Some("web,10.0.0.1"));
        assert_eq!(all[0].comment.as_deref(), Some("ana@laptop"));
        assert!(all[0].matches("10.0.0.1", 22) && !all[0].matches("10.0.0.1", 2222));
        assert_eq!(all[1].hosts, None);
        assert!(all[1].matches("bastion.example.com", 22));
        assert!(!all[1].matches("web", 22));
        assert_eq!(all[2].marker, Some(Marker::CertAuthority));
        assert!(all[2].text.starts_with("@cert-authority"));
    }

    #[test]
    fn trust_on_first_use_remembers() {
        let mut kh = KnownHosts::new(Unknown::Learn);
        assert_eq!(kh.check("h", 22, &offered(KEY)), Verdict::Learned);
        assert_eq!(kh.check("h", 22, &offered(KEY)), Verdict::Known);
        assert_eq!(kh.check("h", 22, &offered(OTHER)), Verdict::Changed);
    }
}
