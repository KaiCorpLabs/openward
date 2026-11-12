//! Account → certified device → signed HPKE-wrapped vault generations.
//! All secret-bearing types are Rust-only and deliberately have no Debug/Clone.
use crate::{
    Error, VaultKey, codec,
    envelope::Id,
    password::{KdfParams, PasswordBox},
};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use hpke_rs::{
    Hpke, Mode,
    hpke_types::{AeadAlgorithm, KdfAlgorithm, KemAlgorithm},
};
use hpke_rs_libcrux::HpkeLibcrux;
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KemSuite {
    XWingDraft06Pq05,
    X25519Rfc9180,
}
impl KemSuite {
    fn tag(self) -> u8 {
        match self {
            Self::XWingDraft06Pq05 => 1,
            Self::X25519Rfc9180 => 2,
        }
    }
    fn parse(tag: u8) -> Result<Self, Error> {
        match tag {
            1 => Ok(Self::XWingDraft06Pq05),
            2 => Ok(Self::X25519Rfc9180),
            v => Err(Error::Version(v.into())),
        }
    }
    fn kem(self) -> KemAlgorithm {
        match self {
            Self::XWingDraft06Pq05 => KemAlgorithm::XWingDraft06,
            Self::X25519Rfc9180 => KemAlgorithm::DhKem25519,
        }
    }
    pub fn public_len(self) -> usize {
        match self {
            Self::XWingDraft06Pq05 => 1216,
            Self::X25519Rfc9180 => 32,
        }
    }
    fn enc_len(self) -> usize {
        match self {
            Self::XWingDraft06Pq05 => 1120,
            Self::X25519Rfc9180 => 32,
        }
    }
    fn hpke(self) -> Hpke<HpkeLibcrux> {
        Hpke::new(
            Mode::Base,
            self.kem(),
            KdfAlgorithm::HkdfSha256,
            AeadAlgorithm::ChaCha20Poly1305,
        )
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AccountPublic {
    suite: KemSuite,
    signing: [u8; 32],
    kem: Vec<u8>,
}
impl AccountPublic {
    pub fn suite(&self) -> KemSuite {
        self.suite
    }
    pub fn signing_key(&self) -> Result<VerifyingKey, Error> {
        VerifyingKey::from_bytes(&self.signing).map_err(|_| Error::Signature)
    }
    pub fn kem_key(&self) -> &[u8] {
        &self.kem
    }
    pub fn id(&self) -> [u8; 32] {
        Sha256::digest(self.to_bytes()).into()
    }
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = codec::record(b"OWAP");
        out.push(self.suite.tag());
        out.extend(self.signing);
        out.extend(&self.kem);
        out
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, Error> {
        let mut r = codec::Reader::new(bytes, b"OWAP")?;
        let suite = KemSuite::parse(r.u8()?)?;
        let signing = r.fixed()?;
        let kem = r.take(suite.public_len())?.to_vec();
        r.finish()?;
        let public = Self {
            suite,
            signing,
            kem,
        };
        public.signing_key()?;
        Ok(public)
    }
}
pub struct AccountKey {
    seeds: Zeroizing<[u8; 64]>,
    signing: SigningKey,
    public: AccountPublic,
}
impl AccountKey {
    pub fn generate(suite: KemSuite) -> Result<Self, Error> {
        let mut seeds = Zeroizing::new([0; 64]);
        getrandom::fill(seeds.as_mut()).map_err(|_| Error::Randomness)?;
        Self::from_secret(suite, seeds)
    }
    pub fn from_secret(suite: KemSuite, seeds: Zeroizing<[u8; 64]>) -> Result<Self, Error> {
        let signing = SigningKey::from_bytes(seeds[..32].try_into().unwrap());
        let pair = suite
            .hpke()
            .derive_key_pair(&seeds[32..])
            .map_err(|_| Error::Authentication)?;
        let public = AccountPublic {
            suite,
            signing: signing.verifying_key().to_bytes(),
            kem: pair.public_key().as_slice().to_vec(),
        };
        Ok(Self {
            seeds,
            signing,
            public,
        })
    }
    pub fn public(&self) -> &AccountPublic {
        &self.public
    }
    pub fn secret(&self) -> Zeroizing<[u8; 64]> {
        Zeroizing::new(*self.seeds)
    }
    pub fn certify(&self, device: Id, key: &VerifyingKey) -> DeviceCertificate {
        let mut c = DeviceCertificate {
            account: self.public.id(),
            device,
            kind: 1,
            signing: key.to_bytes(),
            signature: [0; 64],
        };
        c.signature = self.signing.sign(&c.message()).to_bytes();
        c
    }
    pub fn wrap(
        &self,
        vault: Id,
        generation: u32,
        key: &VaultKey,
    ) -> Result<WrappedVaultKey, Error> {
        if generation == 0 {
            return Err(Error::Context);
        }
        let mut w = WrappedVaultKey {
            suite: self.public.suite,
            vault,
            generation,
            account: self.public.id(),
            enc: Vec::new(),
            ct: Vec::new(),
            signature: [0; 64],
        };
        let context = w.context();
        (w.enc, w.ct) = self
            .public
            .suite
            .hpke()
            .seal(
                &hpke_rs::HpkePublicKey::new(self.public.kem.clone()),
                &context,
                &context,
                key.secret(),
                None,
                None,
                None,
            )
            .map_err(|_| Error::Authentication)?;
        w.signature = self.signing.sign(&w.message()).to_bytes();
        Ok(w)
    }
    pub fn unwrap(
        &self,
        w: &WrappedVaultKey,
        vault: Id,
        generation: u32,
    ) -> Result<VaultKey, Error> {
        w.verify(&self.public, vault, generation)?;
        let pair = self
            .public
            .suite
            .hpke()
            .derive_key_pair(&self.seeds[32..])
            .map_err(|_| Error::Authentication)?;
        let context = w.context();
        let opened = Zeroizing::new(
            self.public
                .suite
                .hpke()
                .open(
                    &w.enc,
                    pair.private_key(),
                    &context,
                    &context,
                    &w.ct,
                    None,
                    None,
                    None,
                )
                .map_err(|_| Error::Authentication)?,
        );
        let secret = Zeroizing::new(opened.as_slice().try_into().map_err(|_| Error::Encoding)?);
        Ok(VaultKey::from_secret(secret))
    }
}
pub struct DeviceKey(SigningKey);
impl DeviceKey {
    pub fn generate() -> Result<Self, Error> {
        let mut seed = Zeroizing::new([0; 32]);
        getrandom::fill(seed.as_mut()).map_err(|_| Error::Randomness)?;
        Ok(Self::from_secret(seed))
    }
    pub fn from_secret(seed: Zeroizing<[u8; 32]>) -> Self {
        Self(SigningKey::from_bytes(&seed))
    }
    pub fn secret(&self) -> Zeroizing<[u8; 32]> {
        Zeroizing::new(self.0.to_bytes())
    }
    pub fn signer(&self) -> &SigningKey {
        &self.0
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DeviceCertificate {
    account: [u8; 32],
    device: Id,
    kind: u8,
    signing: [u8; 32],
    signature: [u8; 64],
}
impl DeviceCertificate {
    fn prefix(&self) -> Vec<u8> {
        let mut out = codec::record(b"OWDC");
        out.extend(self.account);
        out.extend(self.device);
        out.push(self.kind);
        out.extend(self.signing);
        out
    }
    fn message(&self) -> Vec<u8> {
        [
            b"openward device certificate v1\0".as_slice(),
            &self.prefix(),
        ]
        .concat()
    }
    pub fn verify(&self, account: &AccountPublic, device: Id) -> Result<VerifyingKey, Error> {
        if self.account != account.id() || self.device != device || self.kind != 1 {
            return Err(Error::Context);
        }
        account
            .signing_key()?
            .verify_strict(&self.message(), &Signature::from_bytes(&self.signature))
            .map_err(|_| Error::Signature)?;
        VerifyingKey::from_bytes(&self.signing).map_err(|_| Error::Signature)
    }
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = self.prefix();
        out.extend(self.signature);
        out
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, Error> {
        let mut r = codec::Reader::new(bytes, b"OWDC")?;
        let c = Self {
            account: r.fixed()?,
            device: r.fixed()?,
            kind: r.u8()?,
            signing: r.fixed()?,
            signature: r.fixed()?,
        };
        r.finish()?;
        if c.kind != 1 {
            return Err(Error::Version(c.kind.into()));
        }
        Ok(c)
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WrappedVaultKey {
    suite: KemSuite,
    vault: Id,
    generation: u32,
    account: [u8; 32],
    enc: Vec<u8>,
    ct: Vec<u8>,
    signature: [u8; 64],
}
impl WrappedVaultKey {
    fn prefix(&self) -> Vec<u8> {
        let mut out = codec::record(b"OWVK");
        out.push(self.suite.tag());
        out.extend(self.vault);
        out.extend(self.generation.to_be_bytes());
        out.extend(self.account);
        out
    }
    fn context(&self) -> Vec<u8> {
        [b"openward vault generation v1\0".as_slice(), &self.prefix()].concat()
    }
    fn message(&self) -> Vec<u8> {
        [self.context(), self.enc.clone(), self.ct.clone()].concat()
    }
    pub fn verify(&self, account: &AccountPublic, vault: Id, generation: u32) -> Result<(), Error> {
        if self.suite != account.suite
            || self.account != account.id()
            || self.vault != vault
            || self.generation != generation
            || generation == 0
        {
            return Err(Error::Context);
        }
        account
            .signing_key()?
            .verify_strict(&self.message(), &Signature::from_bytes(&self.signature))
            .map_err(|_| Error::Signature)
    }
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = self.prefix();
        out.extend(&self.enc);
        out.extend(&self.ct);
        out.extend(self.signature);
        out
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, Error> {
        let mut r = codec::Reader::new(bytes, b"OWVK")?;
        let suite = KemSuite::parse(r.u8()?)?;
        let vault = r.fixed()?;
        let generation = r.u32()?;
        let account = r.fixed()?;
        let enc = r.take(suite.enc_len())?.to_vec();
        let ct = r.take(48)?.to_vec();
        let signature = r.fixed()?;
        r.finish()?;
        if generation == 0 {
            return Err(Error::Context);
        }
        Ok(Self {
            suite,
            vault,
            generation,
            account,
            enc,
            ct,
            signature,
        })
    }
}

pub struct UnlockedKeys {
    pub account: AccountKey,
    pub device: DeviceKey,
    pub vault: VaultKey,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VaultHeader {
    vault: Id,
    device: Id,
    generation: u32,
    account: AccountPublic,
    certificate: DeviceCertificate,
    wrapped: WrappedVaultKey,
    local: PasswordBox,
}
impl VaultHeader {
    fn context(
        vault: Id,
        device: Id,
        generation: u32,
        account: &AccountPublic,
        cert: &DeviceCertificate,
        wrapped: &WrappedVaultKey,
    ) -> Vec<u8> {
        let mut out = codec::record(b"OWVH");
        out.extend(vault);
        out.extend(device);
        out.extend(generation.to_be_bytes());
        codec::blob(&mut out, &account.to_bytes());
        codec::blob(&mut out, &cert.to_bytes());
        codec::blob(&mut out, &wrapped.to_bytes());
        out
    }
    pub fn create(
        vault: Id,
        device: Id,
        password: &[u8],
        params: KdfParams,
        suite: KemSuite,
    ) -> Result<(Self, UnlockedKeys), Error> {
        let keys = UnlockedKeys {
            account: AccountKey::generate(suite)?,
            device: DeviceKey::generate()?,
            vault: VaultKey::generate()?,
        };
        let header = Self::from_keys(vault, device, 1, password, params, &keys)?;
        Ok((header, keys))
    }
    /// Also used for password rewrap/key rotation; never writes raw seeds.
    pub fn from_keys(
        vault: Id,
        device: Id,
        generation: u32,
        password: &[u8],
        params: KdfParams,
        keys: &UnlockedKeys,
    ) -> Result<Self, Error> {
        let account = keys.account.public().clone();
        let certificate = keys
            .account
            .certify(device, &keys.device.signer().verifying_key());
        let wrapped = keys.account.wrap(vault, generation, &keys.vault)?;
        let context = Self::context(vault, device, generation, &account, &certificate, &wrapped);
        let mut secret = Zeroizing::new(Vec::with_capacity(96));
        secret.extend_from_slice(keys.account.secret().as_ref());
        secret.extend_from_slice(keys.device.secret().as_ref());
        let local = PasswordBox::seal(password, params, &context, &secret)?;
        Ok(Self {
            vault,
            device,
            generation,
            account,
            certificate,
            wrapped,
            local,
        })
    }
    pub fn unlock(&self, password: &[u8]) -> Result<UnlockedKeys, Error> {
        let context = Self::context(
            self.vault,
            self.device,
            self.generation,
            &self.account,
            &self.certificate,
            &self.wrapped,
        );
        let secret = self.local.open(password, &context)?;
        self.restore_keys(&secret)
    }
    pub(crate) fn restore_keys(&self, secret: &[u8]) -> Result<UnlockedKeys, Error> {
        if secret.len() != 96 {
            return Err(Error::Encoding);
        }
        let account = AccountKey::from_secret(
            self.account.suite,
            Zeroizing::new(secret[..64].try_into().unwrap()),
        )?;
        let device = DeviceKey::from_secret(Zeroizing::new(secret[64..].try_into().unwrap()));
        if account.public() != &self.account
            || self.certificate.verify(&self.account, self.device)?
                != device.signer().verifying_key()
        {
            return Err(Error::Context);
        }
        let vault = account.unwrap(&self.wrapped, self.vault, self.generation)?;
        Ok(UnlockedKeys {
            account,
            device,
            vault,
        })
    }
    pub fn kdf_params(&self) -> KdfParams {
        self.local.params()
    }
    pub fn vault_id(&self) -> Id {
        self.vault
    }
    pub fn device_id(&self) -> Id {
        self.device
    }
    pub fn generation(&self) -> u32 {
        self.generation
    }
    pub fn account(&self) -> &AccountPublic {
        &self.account
    }
    pub fn certificate(&self) -> &DeviceCertificate {
        &self.certificate
    }
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = Self::context(
            self.vault,
            self.device,
            self.generation,
            &self.account,
            &self.certificate,
            &self.wrapped,
        );
        codec::blob(&mut out, &self.local.to_bytes());
        out
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, Error> {
        if bytes.len() > 16 * 1024 {
            return Err(Error::Limit);
        }
        let mut r = codec::Reader::new(bytes, b"OWVH")?;
        let vault = r.fixed()?;
        let device = r.fixed()?;
        let generation = r.u32()?;
        let account = AccountPublic::from_bytes(r.blob(2048)?)?;
        let certificate = DeviceCertificate::from_bytes(r.blob(256)?)?;
        let wrapped = WrappedVaultKey::from_bytes(r.blob(2048)?)?;
        let local = PasswordBox::from_bytes(r.blob(8192)?)?;
        r.finish()?;
        certificate.verify(&account, device)?;
        wrapped.verify(&account, vault, generation)?;
        Ok(Self {
            vault,
            device,
            generation,
            account,
            certificate,
            wrapped,
            local,
        })
    }
}
