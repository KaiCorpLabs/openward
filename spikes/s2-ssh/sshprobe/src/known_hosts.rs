//! Host key trust, decided in the core and not in the UI (ADR-003).
//!
//! Reads OpenSSH `known_hosts` lines: plain and hashed (`|1|salt|hmac`)
//! host patterns, `[host]:port` for non-standard ports, and
//! `@cert-authority` lines that trust host certificates from a CA.

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
}

impl Verdict {
    pub fn trusted(&self) -> bool {
        matches!(self, Self::Known | Self::Certified { .. } | Self::Learned)
    }
}

#[derive(Clone, Debug)]
struct Entry {
    patterns: Patterns,
    cert_authority: bool,
    key: PublicKey,
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
        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let mut fields = line.split_whitespace();
            let mut first = fields.next().unwrap_or_default();
            let mut cert_authority = false;
            if first.starts_with('@') {
                if first != "@cert-authority" {
                    continue; // @revoked and unknown markers: not handled here
                }
                cert_authority = true;
                first = fields.next().unwrap_or_default();
            }
            let key_text = fields.collect::<Vec<_>>().join(" ");
            let Ok(key) = PublicKey::from_openssh(&key_text) else {
                continue;
            };
            let patterns = if let Some(rest) = first.strip_prefix("|1|") {
                let b64 = data_encoding::BASE64;
                let mut parts = rest.split('|');
                match (
                    parts.next().map(|s| b64.decode(s.as_bytes())),
                    parts.next().map(|s| b64.decode(s.as_bytes())),
                ) {
                    (Some(Ok(salt)), Some(Ok(hash))) => Patterns::Hashed { salt, hash },
                    _ => continue,
                }
            } else {
                Patterns::Plain(first.split(',').map(str::to_owned).collect())
            };
            hosts.entries.push(Entry {
                patterns,
                cert_authority,
                key,
            });
        }
        hosts
    }

    /// Remembers a host key (what TOFU does after the first connection).
    pub fn add(&mut self, host: &str, port: u16, key: PublicKey) {
        self.entries.push(Entry {
            patterns: Patterns::Plain(vec![host_spec(host, port)]),
            cert_authority: false,
            key,
        });
    }

    pub fn check(&mut self, host: &str, port: u16, offered: &PublicKeyOrCertificate) -> Verdict {
        let spec = host_spec(host, port);
        match offered {
            PublicKeyOrCertificate::Certificate(cert) => self.check_certificate(host, &spec, cert),
            PublicKeyOrCertificate::PublicKey { key, .. } => {
                let listed: Vec<&PublicKey> = self
                    .entries
                    .iter()
                    .filter(|e| !e.cert_authority && e.patterns.matches(&spec))
                    .map(|e| &e.key)
                    .collect();
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
            .filter(|e| e.cert_authority && e.patterns.matches(spec))
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
    fn trust_on_first_use_remembers() {
        let mut kh = KnownHosts::new(Unknown::Learn);
        assert_eq!(kh.check("h", 22, &offered(KEY)), Verdict::Learned);
        assert_eq!(kh.check("h", 22, &offered(KEY)), Verdict::Known);
        assert_eq!(kh.check("h", 22, &offered(OTHER)), Verdict::Changed);
    }
}
