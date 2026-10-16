//! Host key trust, decided in the core and not in the UI (ADR-003).
//!
//! Reads OpenSSH `known_hosts` lines: plain and hashed (`|1|salt|hmac`)
//! host patterns, `[host]:port` for non-standard ports, `@cert-authority`
//! lines that trust host certificates from a CA, and `@revoked` keys that
//! are refused whatever else says.

use std::time::{SystemTime, UNIX_EPOCH};

use hmac::{Hmac, Mac};
use russh::keys::ssh_key::certificate::CertType;
use russh::keys::{HashAlg, PublicKey, PublicKeyOrCertificate};
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
    /// A certificate that does not check out.
    BadCertificate(String),
    /// The key, or the CA that signed it, is marked `@revoked`.
    Revoked,
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

/// `host` or `[host]:port`, as OpenSSH writes host names.
fn host_spec(host: &str, port: u16) -> String {
    if port == 22 {
        host.to_owned()
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

    /// `key` is marked `@revoked` for `spec`.
    fn revoked(&self, spec: &str, key: &russh::keys::ssh_key::public::KeyData) -> bool {
        self.entries.iter().any(|e| {
            e.marker == Some(Marker::Revoked) && e.key.key_data() == key && e.patterns.matches(spec)
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
                if listed.iter().any(|k| k.key_data() == key.key_data()) {
                    Verdict::Known
                } else if listed.iter().any(|k| k.algorithm() == key.algorithm()) {
                    // Same algorithm, different key: the classic warning.
                    Verdict::Changed
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
            return Verdict::BadCertificate("not a host certificate".into());
        }
        let cas: Vec<&PublicKey> = self
            .entries
            .iter()
            .filter(|e| e.marker == Some(Marker::CertAuthority) && e.patterns.matches(spec))
            .map(|e| &e.key)
            .collect();
        if cas.is_empty() {
            return Verdict::BadCertificate("no @cert-authority for this host".into());
        }
        let fingerprints: Vec<_> = cas.iter().map(|k| k.fingerprint(HashAlg::Sha256)).collect();
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or_default();
        // Signature by one of the CAs, and inside the validity window.
        if let Err(e) = cert.validate_at(now, fingerprints.iter()) {
            return Verdict::BadCertificate(format!("{e}"));
        }
        let principals = cert.valid_principals();
        if !principals.is_empty() && !principals.iter().any(|p| p == host) {
            return Verdict::BadCertificate(format!("host {host} not in principals"));
        }
        let ca = cas
            .iter()
            .find(|k| k.key_data() == cert.signature_key())
            .map(|k| k.fingerprint(HashAlg::Sha256).to_string())
            .unwrap_or_default();
        Verdict::Certified {
            ca,
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
                Patterns::Plain(first.split(',').map(str::to_owned).collect()),
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
