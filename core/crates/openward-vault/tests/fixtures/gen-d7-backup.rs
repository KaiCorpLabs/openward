//! Public fixture generator: copy into examples/gen-d7-backup.rs and run it
//! from core with `cargo run -p openward-vault --example gen-d7-backup`.
use openward_vault::{Vault,SecretKind,proto::{Data,Host}};
use openward_crypto::{password::KdfParams,unlock::RecoveryKit};
use zeroize::Zeroizing;
fn main() {
 let d=tempfile::tempdir().unwrap(); let path=d.path().join("vault.db");drop(Vault::open(&path).unwrap());
 let kit=RecoveryKit::from_secret(Zeroizing::new([42;32]));
 let mut v=Vault::migrate_with_recovery(&path,b"Public D7 fixture password",KdfParams::new(65536,1).unwrap(),&kit).unwrap().unlock(b"Public D7 fixture password").unwrap();
 v.create(Data::Host(Host {label:"Public D7 backup fixture".into(),address:"backup.invalid".into(),..Default::default()})).unwrap();
 v.save_secret(SecretKind::Password,"Public fixture secret","fixture:binding","public D7 test secret").unwrap();
 let dir=std::path::Path::new("crates/openward-vault/tests/fixtures");
 std::fs::write(dir.join("vault-d7.owvault"),v.export_backup().unwrap()).unwrap();
 std::fs::write(dir.join("vault-d7.json"),v.export_json(b"Public D7 fixture password",true).unwrap().as_slice()).unwrap();
}
