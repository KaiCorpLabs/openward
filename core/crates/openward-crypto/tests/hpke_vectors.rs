//! Published S6 vectors, pinned and copied into the production crate tests.
//! Sources and original retrieval commits: docs/spikes/S6-hpke.md §4.
#[path = "support/fixed.rs"]
mod fixed;
use hpke::{Deserializable, Serializable};
use hpke_rs::{
    Hpke, HpkePrivateKey, HpkePublicKey, Mode,
    hpke_types::{AeadAlgorithm, KdfAlgorithm, KemAlgorithm},
};
use hpke_rs_libcrux::HpkeLibcrux;
use serde::Deserialize;

#[derive(Deserialize)]
struct Vector {
    kem_id: u16,
    #[serde(with = "hex::serde")]
    info: Vec<u8>,
    #[serde(rename = "ikmR", with = "hex::serde")]
    ikm_r: Vec<u8>,
    #[serde(rename = "ikmE", with = "hex::serde")]
    ikm_e: Vec<u8>,
    #[serde(rename = "skRm", with = "hex::serde")]
    sk: Vec<u8>,
    #[serde(rename = "pkRm", with = "hex::serde")]
    pk: Vec<u8>,
    #[serde(with = "hex::serde")]
    enc: Vec<u8>,
    encryptions: Vec<Message>,
    exports: Vec<Export>,
}
#[derive(Deserialize)]
struct Message {
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
fn config(k: KemAlgorithm) -> Hpke<HpkeLibcrux> {
    Hpke::new(
        Mode::Base,
        k,
        KdfAlgorithm::HkdfSha256,
        AeadAlgorithm::ChaCha20Poly1305,
    )
}

#[test]
fn published_rfc9180_and_pq_vectors_cover_both_directions_and_exports() {
    for (json, kem, id) in [
        (
            include_str!("vectors/hpke-x25519-rfc9180.json"),
            KemAlgorithm::DhKem25519,
            0x20,
        ),
        (
            include_str!("vectors/hpke-xwing-pq.json"),
            KemAlgorithm::XWingDraft06,
            0x647a,
        ),
    ] {
        let list: Vec<Vector> = serde_json::from_str(json).unwrap();
        assert_eq!(list.len(), 1);
        let v = &list[0];
        assert_eq!(v.kem_id, id);
        let h = config(kem);
        let pair = h.derive_key_pair(&v.ikm_r).unwrap();
        assert_eq!(pair.private_key().as_slice(), v.sk);
        assert_eq!(pair.public_key().as_slice(), v.pk);
        let mut receiver = h
            .setup_receiver(
                &v.enc,
                &HpkePrivateKey::new(v.sk.clone()),
                &v.info,
                None,
                None,
                None,
            )
            .unwrap();
        let mut sender = Hpke::<HpkeLibcrux<fixed::Fixed>>::new_with_rng(
            Mode::Base,
            kem,
            KdfAlgorithm::HkdfSha256,
            AeadAlgorithm::ChaCha20Poly1305,
            fixed::Fixed::new(&v.ikm_e),
        );
        let (enc, mut ctx) = sender
            .setup_sender(&HpkePublicKey::new(v.pk.clone()), &v.info, None, None, None)
            .unwrap();
        assert_eq!(enc, v.enc);
        for e in &v.encryptions {
            assert_eq!(ctx.seal(&e.aad, &e.pt).unwrap(), e.ct);
            assert_eq!(receiver.open(&e.aad, &e.ct).unwrap(), e.pt);
        }
        for e in &v.exports {
            assert_eq!(
                receiver.export(&e.exporter_context, e.len).unwrap(),
                e.exported_value
            );
            assert_eq!(
                ctx.export(&e.exporter_context, e.len).unwrap(),
                e.exported_value
            );
        }
    }
}

#[test]
fn published_xwing_draft11_kem_vectors() {
    let vectors: Vec<serde_json::Value> =
        serde_json::from_str(include_str!("vectors/xwing-draft11.json")).unwrap();
    assert_eq!(vectors.len(), 3);
    for v in vectors {
        let b = |name: &str| hex::decode(v[name].as_str().unwrap()).unwrap();
        let (sk, pk) =
            libcrux_kem::key_gen_derand(libcrux_kem::Algorithm::XWingKemDraft06, &b("seed"))
                .unwrap();
        assert_eq!(sk.encode(), b("sk"));
        assert_eq!(pk.encode(), b("pk"));
        let (ss, ct) = pk.encapsulate_derand(&b("eseed")).unwrap();
        assert_eq!(ct.encode(), b("ct"));
        assert_eq!(ss.encode(), b("ss"));
        let ct =
            libcrux_kem::Ct::decode(libcrux_kem::Algorithm::XWingKemDraft06, &b("ct")).unwrap();
        assert_eq!(ct.decapsulate(&sk).unwrap().encode(), b("ss"));
    }
}

fn interop<K: hpke::Kem>(kem: KemAlgorithm) {
    type A = hpke::aead::ChaCha20Poly1305;
    type D = hpke::kdf::HkdfSha256;
    let h = config(kem);
    let pair = h.derive_key_pair(&[9; 32]).unwrap();
    let pk = K::PublicKey::from_bytes(pair.public_key().as_slice()).unwrap();
    let sk = K::PrivateKey::from_bytes(pair.private_key().as_slice()).unwrap();
    let (enc, ct) =
        hpke::single_shot_seal::<A, D, K>(&hpke::OpModeS::Base, &pk, b"info", b"test key", b"aad")
            .unwrap();
    assert_eq!(
        h.open(
            &enc.to_bytes(),
            pair.private_key(),
            b"info",
            b"aad",
            &ct,
            None,
            None,
            None
        )
        .unwrap(),
        b"test key"
    );
    let (enc, ct) = config(kem)
        .seal(
            pair.public_key(),
            b"info",
            b"aad",
            b"test key",
            None,
            None,
            None,
        )
        .unwrap();
    let enc = K::EncappedKey::from_bytes(&enc).unwrap();
    assert_eq!(
        hpke::single_shot_open::<A, D, K>(&hpke::OpModeR::Base, &sk, &enc, b"info", &ct, b"aad")
            .unwrap(),
        b"test key"
    );
    assert!(
        hpke::single_shot_open::<A, D, K>(
            &hpke::OpModeR::Base,
            &sk,
            &enc,
            b"other info",
            &ct,
            b"aad"
        )
        .is_err()
    );
    let mut bad = ct;
    bad[0] ^= 1;
    assert!(
        hpke::single_shot_open::<A, D, K>(&hpke::OpModeR::Base, &sk, &enc, b"info", &bad, b"aad")
            .is_err()
    );
}
#[test]
fn libcrux_and_rozbb_interoperate_without_changing_persisted_keys() {
    interop::<hpke::kem::XWing>(KemAlgorithm::XWingDraft06);
    interop::<hpke::kem::X25519HkdfSha256>(KemAlgorithm::DhKem25519);
}
