//! Real cryptographic signatures through the verifier used by KEX and rekey.

use openward_ssh::russh::{
    self,
    keys::{
        Algorithm, HashAlg, PrivateKey,
        signature::{Signer, Verifier},
    },
};

/// Exercise the production KEX state machine too: bare/certified RSA hosts,
/// each supported hash, initial exchange and an explicit client rekey.
#[tokio::test]
async fn rsa_hosts_and_certificates_keep_working_across_rekey() {
    use openward_ssh::known_hosts::{KnownHosts, Unknown};
    use russh::{
        client,
        keys::ssh_key::certificate::{Builder, CertType},
        server,
    };
    use std::{
        borrow::Cow,
        sync::Arc,
        time::{Duration, SystemTime, UNIX_EPOCH},
    };

    struct Client {
        trust: KnownHosts,
        certified: bool,
        exchanges: tokio::sync::mpsc::UnboundedSender<Algorithm>,
    }
    impl client::Handler for Client {
        type Error = russh::Error;
        async fn check_server_key(
            &mut self,
            key: &russh::keys::PublicKeyOrCertificate,
        ) -> Result<bool, Self::Error> {
            assert_eq!(
                matches!(key, russh::keys::PublicKeyOrCertificate::Certificate(_)),
                self.certified
            );
            Ok(self.trust.check("host.example", 22, key).trusted())
        }
        async fn kex_done(
            &mut self,
            _: Option<&[u8]>,
            names: &russh::Names,
            _: &mut client::Session,
        ) -> Result<(), Self::Error> {
            self.exchanges.send(names.key.clone()).unwrap();
            Ok(())
        }
    }
    struct Server;
    impl server::Handler for Server {
        type Error = russh::Error;
        async fn auth_none(&mut self, _: &str) -> Result<server::Auth, Self::Error> {
            Ok(server::Auth::Accept)
        }
    }
    let key = PrivateKey::random(&mut rand::rng(), Algorithm::Rsa { hash: None }).unwrap();
    let ca = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let mut cert = Builder::new(
        [42; 16],
        key.public_key().key_data().clone(),
        now - 60,
        now + 3600,
    )
    .unwrap();
    cert.cert_type(CertType::Host).unwrap();
    cert.valid_principal("host.example").unwrap();
    let cert = cert.sign(&ca).unwrap();
    for hash in [None, Some(HashAlg::Sha256), Some(HashAlg::Sha512)] {
        let algorithm = Algorithm::Rsa { hash };
        for certified in [false, true] {
            let mut config = server::Config::default();
            config.keys.push(key.clone());
            config.preferred.key = Cow::Owned(vec![algorithm.clone()]);
            if certified {
                config.certificates.push(cert.clone());
            }
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let task = tokio::spawn(async move {
                let (socket, _) = listener.accept().await.unwrap();
                server::run_stream(Arc::new(config), socket, Server)
                    .await
                    .unwrap()
                    .await
            });
            let mut config = client::Config::default();
            config.preferred.key = Cow::Owned(vec![algorithm.clone()]);
            config.preferred.host_key_certificates = Cow::Owned(if certified {
                vec![algorithm.clone()]
            } else {
                vec![]
            });
            let line = if certified {
                format!(
                    "@cert-authority host.example {}",
                    ca.public_key().to_openssh().unwrap()
                )
            } else {
                format!("host.example {}", key.public_key().to_openssh().unwrap())
            };
            let (exchanges, mut received) = tokio::sync::mpsc::unbounded_channel();
            let handler = Client {
                trust: KnownHosts::parse(&line, Unknown::Reject),
                certified,
                exchanges,
            };
            let mut session = client::connect(Arc::new(config), addr, handler)
                .await
                .unwrap();
            assert!(session.authenticate_none("user").await.unwrap().success());
            assert_eq!(received.recv().await.unwrap(), algorithm.clone());
            session.rekey_soon().await.unwrap();
            assert_eq!(
                tokio::time::timeout(Duration::from_secs(10), received.recv())
                    .await
                    .unwrap()
                    .unwrap(),
                algorithm.clone()
            );
            session
                .disconnect(russh::Disconnect::ByApplication, "done", "")
                .await
                .unwrap();
            tokio::time::timeout(Duration::from_secs(10), task)
                .await
                .unwrap()
                .unwrap()
                .unwrap();
        }
    }
}

#[test]
fn a_valid_rsa_signature_must_also_match_the_negotiated_hash() {
    let key = PrivateKey::random(&mut rand::rng(), Algorithm::Rsa { hash: None }).unwrap();
    let rsa = key.key_data().rsa().unwrap();
    let algorithms = [None, Some(HashAlg::Sha256), Some(HashAlg::Sha512)];
    for exchange in [
        b"initial exchange hash".as_slice(),
        b"new rekey exchange hash".as_slice(),
    ] {
        for actual in algorithms {
            let signature = (rsa, actual).try_sign(exchange).unwrap();
            // This was the old KEX check: it accepts a valid SHA-1 signature
            // even when SHA-2 was negotiated. Trust in the RSA key is intact.
            Verifier::verify(key.public_key(), exchange, &signature).unwrap();
            for negotiated in algorithms {
                let result = russh::client::verify_server_signature(
                    key.public_key(),
                    &Algorithm::Rsa { hash: negotiated },
                    exchange,
                    &signature,
                );
                assert_eq!(
                    result.is_ok(),
                    actual == negotiated,
                    "received {actual:?}, negotiated {negotiated:?}"
                );
            }
            assert!(
                russh::client::verify_server_signature(
                    key.public_key(),
                    &Algorithm::Rsa { hash: actual },
                    b"tampered exchange",
                    &signature
                )
                .is_err()
            );
            assert!(
                russh::client::verify_server_signature(
                    key.public_key(),
                    &Algorithm::Ed25519,
                    exchange,
                    &signature
                )
                .is_err()
            );
        }
    }
}

#[test]
fn non_rsa_signature_and_key_checks_are_preserved() {
    let key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
    let other = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
    let message = b"exchange hash for a certified or plain host key";
    let signature = key.try_sign(message).unwrap();
    assert!(
        russh::client::verify_server_signature(
            key.public_key(),
            &Algorithm::Ed25519,
            message,
            &signature
        )
        .is_ok()
    );
    assert!(
        russh::client::verify_server_signature(
            other.public_key(),
            &Algorithm::Ed25519,
            message,
            &signature
        )
        .is_err()
    );
    assert!(
        russh::client::verify_server_signature(
            key.public_key(),
            &Algorithm::Rsa {
                hash: Some(HashAlg::Sha512)
            },
            message,
            &signature
        )
        .is_err()
    );
}
