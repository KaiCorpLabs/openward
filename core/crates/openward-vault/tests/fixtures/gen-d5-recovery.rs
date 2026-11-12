fn main() {
 use openward_vault::{Vault,proto::{Data,Host}};
 use openward_crypto::{unlock::RecoveryKit,password::KdfParams};
 let dir=tempfile::tempdir().unwrap(); let path=dir.path().join("fixture.db");
 let mut v=Vault::open(&path).unwrap();
 v.create(Data::Host(Host { label:"Public D5 recovery fixture".into(),address:"recovery.invalid".into(), ..Host::default() })).unwrap();
 drop(v);
 let kit=RecoveryKit::from_secret(zeroize::Zeroizing::new([42;32]));
 drop(Vault::migrate_with_recovery(&path,b"Public portability fixture only",KdfParams::new(65536,1).unwrap(),&kit).unwrap());
 std::fs::copy(&path,std::env::args().nth(1).expect("output fixture path")).unwrap();
}
