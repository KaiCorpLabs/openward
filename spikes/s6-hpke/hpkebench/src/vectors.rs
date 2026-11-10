//! The published vectors, against each candidate: RFC 9180 for
//! DHKEM(X25519), `draft-ietf-hpke-pq` for X-Wing in HPKE, and the X-Wing
//! draft's own for the bare KEM. Where a library lets its randomness be
//! fixed, the sender is checked too; otherwise only the receiver.

use hpke::{Deserializable, OpModeR, OpModeS, Serializable};
use hpke_rs::hpke_types::{AeadAlgorithm, KdfAlgorithm};
use hpke_rs::{Hpke, HpkePrivateKey, HpkePublicKey, Mode};
use hpke_rs_crypto::HpkeCrypto;
use serde::Deserialize;

use crate::fixed::Fixed;
use crate::suites::{self, Kem, RozbbAead, RozbbKdf};

const X25519: &str = include_str!("../../vectors/hpke-x25519-rfc9180.json");
const XWING_HPKE: &str = include_str!("../../vectors/hpke-xwing-pq.json");
const XWING_KEM: &str = include_str!("../../vectors/xwing-draft11.json");

#[derive(Deserialize)]
struct HpkeVector {
    kem_id: u16,
    #[serde(with = "hex::serde")]
    info: Vec<u8>,
    #[serde(rename = "ikmR", with = "hex::serde")]
    ikm_r: Vec<u8>,
    #[serde(rename = "ikmE", with = "hex::serde")]
    ikm_e: Vec<u8>,
    #[serde(rename = "skRm", with = "hex::serde")]
    sk_r: Vec<u8>,
    #[serde(rename = "pkRm", with = "hex::serde")]
    pk_r: Vec<u8>,
    #[serde(with = "hex::serde")]
    enc: Vec<u8>,
    encryptions: Vec<Encryption>,
    exports: Vec<Export>,
}

#[derive(Deserialize)]
struct Encryption {
    #[serde(with = "hex::serde")]
    aad: Vec<u8>,
    #[serde(with = "hex::serde")]
    ct: Vec<u8>,
    #[serde(with = "hex::serde")]
    pt: Vec<u8>,
}

#[derive(Deserialize)]
struct Export {
    #[serde(with = "hex::serde")]
    exporter_context: Vec<u8>,
    #[serde(rename = "L")]
    len: usize,
    #[serde(with = "hex::serde")]
    exported_value: Vec<u8>,
}

#[derive(Deserialize)]
struct XWingVector {
    #[serde(with = "hex::serde")]
    seed: Vec<u8>,
    #[serde(with = "hex::serde")]
    sk: Vec<u8>,
    #[serde(with = "hex::serde")]
    pk: Vec<u8>,
    #[serde(with = "hex::serde")]
    eseed: Vec<u8>,
    #[serde(with = "hex::serde")]
    ct: Vec<u8>,
    #[serde(with = "hex::serde")]
    ss: Vec<u8>,
}

/// One line of the report.
#[derive(Debug, serde::Serialize)]
pub struct Check {
    pub library: String,
    pub what: String,
    pub ok: bool,
    pub detail: String,
}

fn check(out: &mut Vec<Check>, library: &str, what: &str, result: Result<String, String>) {
    let (ok, detail) = match result {
        Ok(d) => (true, d),
        Err(d) => (false, d),
    };
    out.push(Check {
        library: library.into(),
        what: what.into(),
        ok,
        detail,
    });
}

fn same(what: &str, got: &[u8], want: &[u8]) -> Result<(), String> {
    if got == want {
        Ok(())
    } else {
        Err(format!(
            "{what}: got {}…, want {}…",
            hex::encode(&got[..got.len().min(8)]),
            hex::encode(&want[..want.len().min(8)])
        ))
    }
}

fn hpke_vector(json: &str) -> HpkeVector {
    let mut v: Vec<HpkeVector> = serde_json::from_str(json).expect("vector file");
    assert_eq!(v.len(), 1, "one vector per suite");
    v.remove(0)
}

pub fn run() -> Vec<Check> {
    let mut out = Vec::new();
    for (kem, json, source) in [
        (Kem::X25519, X25519, "RFC 9180 A.2"),
        (Kem::XWing, XWING_HPKE, "draft-ietf-hpke-pq"),
    ] {
        let v = hpke_vector(json);
        assert_eq!(v.kem_id, kem.id());
        let what = |side: &str| format!("{} HPKE, {source}, {side}", kem.name());

        // Every candidate derives the vector's key pair and opens what it
        // sealed.
        for s in suites::all(kem) {
            let r = receiver(&*s, &v);
            check(&mut out, s.library(), &what("receiver"), r);
        }
        // Senders, where the randomness can be fixed.
        check(
            &mut out,
            suites::LIBCRUX,
            &what("sender"),
            hpke_rs_sender::<hpke_rs_libcrux::HpkeLibcrux<Fixed>>(kem, &v),
        );
        let rozbb = match kem {
            Kem::X25519 => rozbb_sender::<hpke::kem::X25519HkdfSha256>(&v),
            Kem::XWing => rozbb_sender::<hpke::kem::XWing>(&v),
        };
        check(&mut out, suites::ROZBB, &what("sender"), rozbb);
        out.push(Check {
            library: suites::RUSTCRYPTO.into(),
            what: what("sender"),
            ok: true,
            detail: "not checked: its randomness cannot be fixed from outside".into(),
        });
    }
    xwing_kem(&mut out);
    out
}

/// What any library can show: the key pair from `ikmR`, and the vector's
/// messages opened in order, through the context each library keeps.
fn receiver(s: &dyn suites::Suite, v: &HpkeVector) -> Result<String, String> {
    let (sk, pk) = s.derive(&v.ikm_r);
    // RFC 9180 §7.1.2 says an X25519 private key is serialized clamped;
    // its vectors are not. Both are the same key: a note, not a failure.
    let mut note = "";
    if s.kem() == Kem::X25519 && sk != v.sk_r && sk == clamp(&v.sk_r) {
        note = " (its private key comes out clamped, as §7.1.2 says)";
    } else {
        same("skRm", &sk, &v.sk_r)?;
    }
    same("pkRm", &pk, &v.pk_r)?;
    let opened = match (s.library(), s.kem()) {
        (suites::LIBCRUX, kem) => hpke_rs_receiver(
            suites::hpke_rs_config::<hpke_rs_libcrux::HpkeLibcrux>(kem),
            v,
        )?,
        (suites::RUSTCRYPTO, kem) => hpke_rs_receiver(
            suites::hpke_rs_config::<hpke_rs_rust_crypto::HpkeRustCrypto>(kem),
            v,
        )?,
        (_, Kem::X25519) => rozbb_receiver::<hpke::kem::X25519HkdfSha256>(v)?,
        (_, Kem::XWing) => rozbb_receiver::<hpke::kem::XWing>(v)?,
    };
    Ok(format!(
        "key pair, {opened} messages and {} exports{note}",
        v.exports.len()
    ))
}

/// An X25519 private key as RFC 7748 uses it.
fn clamp(sk: &[u8]) -> Vec<u8> {
    let mut k = sk.to_vec();
    k[0] &= 248;
    k[31] &= 127;
    k[31] |= 64;
    k
}

fn hpke_rs_receiver<C: HpkeCrypto + 'static>(
    hpke: Hpke<C>,
    v: &HpkeVector,
) -> Result<usize, String> {
    let sk = HpkePrivateKey::new(v.sk_r.clone());
    let mut ctx = hpke
        .setup_receiver(&v.enc, &sk, &v.info, None, None, None)
        .map_err(|e| format!("setup_receiver: {e:?}"))?;
    for (i, e) in v.encryptions.iter().enumerate() {
        let pt = ctx
            .open(&e.aad, &e.ct)
            .map_err(|err| format!("open #{i}: {err:?}"))?;
        same(&format!("pt #{i}"), &pt, &e.pt)?;
    }
    for (i, x) in v.exports.iter().enumerate() {
        let got = ctx
            .export(&x.exporter_context, x.len)
            .map_err(|e| format!("export #{i}: {e:?}"))?;
        same(&format!("export #{i}"), &got, &x.exported_value)?;
    }
    Ok(v.encryptions.len())
}

fn hpke_rs_sender<C: HpkeCrypto<HpkePrng = Fixed> + 'static>(
    kem: Kem,
    v: &HpkeVector,
) -> Result<String, String> {
    let mut hpke = Hpke::<C>::new_with_rng(
        Mode::Base,
        kem.hpke_rs(),
        KdfAlgorithm::HkdfSha256,
        AeadAlgorithm::ChaCha20Poly1305,
        Fixed::new(&v.ikm_e),
    );
    let pk = HpkePublicKey::new(v.pk_r.clone());
    let (enc, mut ctx) = hpke
        .setup_sender(&pk, &v.info, None, None, None)
        .map_err(|e| format!("setup_sender: {e:?}"))?;
    same("enc", &enc, &v.enc)?;
    for (i, e) in v.encryptions.iter().enumerate() {
        let ct = ctx
            .seal(&e.aad, &e.pt)
            .map_err(|err| format!("seal #{i}: {err:?}"))?;
        same(&format!("ct #{i}"), &ct, &e.ct)?;
    }
    Ok(format!(
        "enc from ikmE ({} bytes) and {} messages",
        v.ikm_e.len(),
        v.encryptions.len()
    ))
}

fn rozbb_receiver<K: hpke::Kem>(v: &HpkeVector) -> Result<usize, String> {
    let sk = K::PrivateKey::from_bytes(&v.sk_r).map_err(|e| format!("skRm: {e:?}"))?;
    let enc = K::EncappedKey::from_bytes(&v.enc).map_err(|e| format!("enc: {e:?}"))?;
    let mut ctx =
        hpke::setup_receiver::<RozbbAead, RozbbKdf, K>(&OpModeR::Base, &sk, &enc, &v.info)
            .map_err(|e| format!("setup_receiver: {e:?}"))?;
    for (i, e) in v.encryptions.iter().enumerate() {
        let pt = ctx
            .open(&e.ct, &e.aad)
            .map_err(|err| format!("open #{i}: {err:?}"))?;
        same(&format!("pt #{i}"), &pt, &e.pt)?;
    }
    for (i, x) in v.exports.iter().enumerate() {
        let mut got = vec![0; x.len];
        ctx.export(&x.exporter_context, &mut got)
            .map_err(|e| format!("export #{i}: {e:?}"))?;
        same(&format!("export #{i}"), &got, &x.exported_value)?;
    }
    Ok(v.encryptions.len())
}

fn rozbb_sender<K: hpke::Kem>(v: &HpkeVector) -> Result<String, String> {
    let pk = K::PublicKey::from_bytes(&v.pk_r).map_err(|e| format!("pkRm: {e:?}"))?;
    let mut rng = Fixed::new(&v.ikm_e);
    let (enc, mut ctx) = hpke::setup_sender_with_rng::<RozbbAead, RozbbKdf, K>(
        &OpModeS::Base,
        &pk,
        &v.info,
        &mut rng,
    )
    .map_err(|e| format!("setup_sender: {e:?}"))?;
    same("enc", &enc.to_bytes(), &v.enc)?;
    if !rng.used_up() {
        return Err("drew less randomness than ikmE".into());
    }
    for (i, e) in v.encryptions.iter().enumerate() {
        let ct = ctx
            .seal(&e.pt, &e.aad)
            .map_err(|err| format!("seal #{i}: {err:?}"))?;
        same(&format!("ct #{i}"), &ct, &e.ct)?;
    }
    Ok(format!(
        "enc from ikmE ({} bytes) and {} messages",
        v.ikm_e.len(),
        v.encryptions.len()
    ))
}

/// The bare X-Wing KEM, against the vectors of draft 11: whether the
/// draft-06 code of the libraries still gives what the latest draft says.
fn xwing_kem(out: &mut Vec<Check>) {
    let vectors: Vec<XWingVector> = serde_json::from_str(XWING_KEM).expect("vector file");
    let what = "X-Wing KEM, draft 11 vectors";
    let n = vectors.len();

    let libcrux = (|| -> Result<String, String> {
        use libcrux_kem::{Algorithm, Ct, key_gen_derand};
        let alg = Algorithm::XWingKemDraft06;
        for (i, v) in vectors.iter().enumerate() {
            let (sk, pk) =
                key_gen_derand(alg, &v.seed).map_err(|e| format!("#{i} keygen: {e:?}"))?;
            same(&format!("#{i} sk"), &sk.encode(), &v.sk)?;
            same(&format!("#{i} pk"), &pk.encode(), &v.pk)?;
            let (ss, ct) = pk
                .encapsulate_derand(&v.eseed)
                .map_err(|e| format!("#{i} encaps: {e:?}"))?;
            same(&format!("#{i} ct"), &ct.encode(), &v.ct)?;
            same(&format!("#{i} ss"), &ss.encode(), &v.ss)?;
            let ct = Ct::decode(alg, &v.ct).map_err(|e| format!("#{i} ct: {e:?}"))?;
            let ss = ct
                .decapsulate(&sk)
                .map_err(|e| format!("#{i} decaps: {e:?}"))?;
            same(&format!("#{i} decaps"), &ss.encode(), &v.ss)?;
        }
        Ok(format!(
            "{n} vectors: keys, encapsulation and decapsulation"
        ))
    })();
    check(out, "libcrux-kem 0.0.10", what, libcrux);

    let rustcrypto = (|| -> Result<String, String> {
        use x_wing::{Decapsulate, Decapsulator, KeyExport};
        for (i, v) in vectors.iter().enumerate() {
            let seed: [u8; 32] = v.seed.as_slice().try_into().map_err(|_| "seed")?;
            let dk = x_wing::DecapsulationKey::from(seed);
            same(&format!("#{i} sk"), dk.as_bytes(), &v.sk)?;
            let ek = dk.encapsulation_key();
            same(&format!("#{i} pk"), &ek.to_bytes(), &v.pk)?;
            let eseed: [u8; 64] = v.eseed.as_slice().try_into().map_err(|_| "eseed")?;
            let (ct, ss) = ek.encapsulate_deterministic(&eseed.into());
            same(&format!("#{i} ct"), &ct, &v.ct)?;
            same(&format!("#{i} ss"), &ss, &v.ss)?;
            let ct: [u8; 1120] = v.ct.as_slice().try_into().map_err(|_| "ct")?;
            let ss = dk.decapsulate(&ct.into());
            same(&format!("#{i} decaps"), &ss, &v.ss)?;
        }
        Ok(format!(
            "{n} vectors: keys, encapsulation and decapsulation"
        ))
    })();
    check(out, "x-wing 0.1.1 (RustCrypto)", what, rustcrypto);
}
