//! Lossless data backups. Restore re-encrypts under the destination's own
//! account/device/vault keys, and never replaces a populated vault.
use crate::{
    Error, Result, Vault,
    proto::{Body, Data, Item, ItemId},
    store::PRIVATE,
};
use openward_crypto::{
    backup,
    envelope::{Envelope, Header, Slot},
    plaintext,
};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use zeroize::Zeroizing;

const FORMAT: &str = "openward-vault";
const MAX_ITEMS: usize = 100_000;
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Document {
    format: String,
    version: u32,
    private_metadata_hex: Zeroizing<String>,
    items: Vec<Row>,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Row {
    id: String,
    revision: u64,
    body_cbor_hex: Zeroizing<String>,
    /// Informational, checked against the lossless CBOR if present.
    body: Option<Body>,
}
type SnapshotRow = (ItemId, u64, Zeroizing<Vec<u8>>, Option<Body>);
pub struct Snapshot {
    rows: Vec<SnapshotRow>,
    metadata: Zeroizing<Vec<u8>>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Summary {
    pub items: usize,
    pub secrets: usize,
    pub unreadable: usize,
}
pub struct Import {
    header: Vec<u8>,
    before_metadata: Zeroizing<Vec<u8>>,
    rows: Vec<(ItemId, u64, Vec<u8>)>,
    metadata: Vec<u8>,
    items: HashMap<ItemId, Item>,
    unreadable: usize,
    clock: u64,
}
fn hex(bytes: &[u8]) -> Zeroizing<String> {
    const DIGITS: &[u8] = b"0123456789abcdef";
    let mut out = Zeroizing::new(String::with_capacity(bytes.len() * 2));
    for b in bytes {
        out.push(DIGITS[(b >> 4) as usize] as char);
        out.push(DIGITS[(b & 15) as usize] as char);
    }
    out
}
fn unhex(s: &str) -> Result<Zeroizing<Vec<u8>>> {
    if !s.len().is_multiple_of(2) || s.len() > backup::MAX_PAYLOAD {
        return Err(Error::Invalid("invalid backup hex length"));
    }
    let mut out = Zeroizing::new(Vec::with_capacity(s.len() / 2));
    for pair in s.as_bytes().as_chunks::<2>().0 {
        let digit = |b| match b {
            b'0'..=b'9' => Ok(b - b'0'),
            b'a'..=b'f' => Ok(b - b'a' + 10),
            _ => Err(Error::Invalid("invalid backup hex")),
        };
        out.push(digit(pair[0])? * 16 + digit(pair[1])?);
    }
    Ok(out)
}
fn decode_body(raw: &[u8]) -> Result<Option<Body>> {
    let mut reader = std::io::Cursor::new(raw);
    let value: ciborium::Value =
        ciborium::from_reader(&mut reader).map_err(|_| Error::Invalid("invalid backup CBOR"))?;
    if reader.position() != raw.len() as u64 || !matches!(value, ciborium::Value::Map(_)) {
        return Err(Error::Invalid("trailing or invalid backup body"));
    }
    Ok(Body::from_cbor(raw)
        .ok()
        .filter(|b| !matches!(b.data, Data::Unsupported)))
}
impl Snapshot {
    pub fn parse(bytes: &[u8]) -> Result<Self> {
        if bytes.len() > backup::MAX_PAYLOAD {
            return Err(openward_crypto::Error::Limit.into());
        }
        let d: Document =
            serde_json::from_slice(bytes).map_err(|_| Error::Invalid("invalid backup JSON"))?;
        if d.format != FORMAT || d.version != 1 {
            return Err(Error::Invalid("unsupported backup format or version"));
        }
        if d.items.len() > MAX_ITEMS {
            return Err(openward_crypto::Error::Limit.into());
        }
        let metadata = unhex(&d.private_metadata_hex)?;
        crate::migration::validate_metadata(&metadata)?;
        let mut ids = HashSet::new();
        let mut rows = Vec::with_capacity(d.items.len());
        for r in d.items {
            let id: ItemId =
                r.id.parse()
                    .map_err(|_| Error::Invalid("invalid backup item id"))?;
            if id.to_string() != r.id
                || !ids.insert(id)
                || r.revision == 0
                || r.revision > i64::MAX as u64
            {
                return Err(Error::Invalid("duplicate id or invalid backup revision"));
            }
            let raw = unhex(&r.body_cbor_hex)?;
            if raw.len() > openward_crypto::envelope::MAX_PLAINTEXT {
                return Err(openward_crypto::Error::Limit.into());
            }
            let body = decode_body(&raw)?;
            if let Some(preview) = r.body {
                let Some(actual) = &body else {
                    return Err(Error::Invalid("invalid backup preview"));
                };
                let expected = Zeroizing::new(
                    serde_json::to_vec(&preview).map_err(|_| Error::Invalid("invalid preview"))?,
                );
                let encoded = Zeroizing::new(
                    serde_json::to_vec(actual).map_err(|_| Error::Invalid("invalid preview"))?,
                );
                if expected != encoded {
                    return Err(Error::Invalid("backup preview differs from lossless body"));
                }
            }
            rows.push((id, r.revision, raw, body));
        }
        Ok(Self { rows, metadata })
    }
    pub fn open(bytes: &[u8], credential: &[u8], use_kit: bool) -> Result<Self> {
        let clear = backup::open(bytes, credential, use_kit)?;
        Self::parse(&clear)
    }
    pub fn summary(&self) -> Summary {
        Summary {
            items: self.rows.len(),
            secrets: self
                .rows
                .iter()
                .filter(|r| {
                    r.3.as_ref()
                        .is_some_and(|b| matches!(b.data, Data::Secret(_)))
                })
                .count(),
            unreadable: self.rows.iter().filter(|r| r.3.is_none()).count(),
        }
    }
}
impl Vault {
    fn snapshot_json(&mut self) -> Result<Zeroizing<Vec<u8>>> {
        let h = self.store.header.as_ref().ok_or(Error::Locked)?;
        let keys = self.store.keys.as_ref().ok_or(Error::Locked)?;
        let signer = h.certificate().verify(h.account(), h.device_id())?;
        let key = &keys.vault;
        let metadata = self.store.private_metadata()?;
        let mut items = Vec::new();
        let mut total = metadata.len() * 2;
        let (count, size): (i64, i64) = self.store.conn.query_row(
            "SELECT count(*),coalesce(sum(length(envelope)),0) FROM items",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )?;
        if total > backup::MAX_PAYLOAD
            || count > MAX_ITEMS as i64
            || size > backup::MAX_PAYLOAD as i64
        {
            return Err(openward_crypto::Error::Limit.into());
        }
        for (id, revision, bytes) in self.store.rows()? {
            if items.len() == MAX_ITEMS {
                return Err(openward_crypto::Error::Limit.into());
            }
            let envelope = Envelope::from_bytes(&bytes)?;
            if envelope.header().device != h.device_id() {
                return Err(Error::Invalid("unknown backup writer"));
            }
            let clear = Envelope::open_received(
                &bytes,
                Slot {
                    vault: h.vault_id(),
                    item: *id.as_bytes(),
                    key_gen: h.generation(),
                },
                key,
                &signer,
            )?;
            let (_, raw) = plaintext::body(&clear)?;
            total = total.saturating_add(raw.len() * 4 + 256);
            if total > backup::MAX_PAYLOAD {
                return Err(openward_crypto::Error::Limit.into());
            }
            let body = decode_body(raw)?;
            items.push(Row {
                id: id.to_string(),
                revision,
                body_cbor_hex: hex(raw),
                body: body.filter(|b| {
                    serde_json::to_vec(b)
                        .ok()
                        .map(Zeroizing::new)
                        .is_some_and(|encoded| serde_json::from_slice::<Body>(&encoded).is_ok())
                }),
            });
        }
        items.sort_by(|a, b| a.id.cmp(&b.id));
        let d = Document {
            format: FORMAT.into(),
            version: 1,
            private_metadata_hex: hex(&metadata),
            items,
        };
        let bytes = Zeroizing::new(
            serde_json::to_vec_pretty(&d).map_err(|_| Error::Invalid("backup encoding failed"))?,
        );
        if bytes.len() > backup::MAX_PAYLOAD {
            return Err(openward_crypto::Error::Limit.into());
        }
        Snapshot::parse(&bytes)?;
        Ok(bytes)
    }
    /// Cleartext export always requires independent current-password proof.
    pub fn export_json(
        &mut self,
        password: &[u8],
        acknowledged: bool,
    ) -> Result<Zeroizing<Vec<u8>>> {
        if !acknowledged {
            return Err(Error::Invalid("acknowledge plaintext export"));
        }
        self.verify_password(password)?;
        self.snapshot_json()
    }
    pub fn export_backup(&mut self) -> Result<Vec<u8>> {
        let clear = self.snapshot_json()?;
        let recovery = self.verified_backup_recovery()?;
        let header = self.store.header.as_ref().ok_or(Error::Locked)?;
        backup::seal(
            header,
            &recovery,
            &self.store.keys.as_ref().ok_or(Error::Locked)?.vault,
            &clear,
        )
        .map_err(Into::into)
    }
    pub fn empty_for_restore(&self) -> Result<()> {
        if !self.is_encrypted() || self.is_locked() {
            return Err(Error::Locked);
        }
        let count: i64 = self
            .store
            .conn
            .query_row("SELECT count(*) FROM items", [], |r| r.get(0))?;
        let meta = self.store.private_metadata()?;
        if count != 0 || meta.as_slice() != b"OWPM\x01\0\0\0\0" {
            return Err(Error::Invalid(
                "restore requires a new empty encrypted vault",
            ));
        }
        Ok(())
    }
    /// Expensive parsing/cryptography occurs before acquiring a commit lease.
    pub fn prepare_restore(&self, snapshot: Snapshot) -> Result<Import> {
        self.empty_for_restore()?;
        let incoming: HashMap<_, _> = snapshot
            .rows
            .iter()
            .filter_map(|r| r.3.as_ref().map(|b| (r.0, &b.data)))
            .collect();
        for (id, data) in &incoming {
            self.validate(*id, data, &incoming)?;
        }
        let h = self.store.header.as_ref().ok_or(Error::Locked)?;
        let keys = self.store.keys.as_ref().ok_or(Error::Locked)?;
        let mut clock = self.store.clock;
        let mut rows = Vec::new();
        let mut items = HashMap::new();
        let mut unreadable = 0;
        for (id, revision, raw, body) in snapshot.rows {
            clock = crate::migration::next_clock(clock)?;
            let clear = Zeroizing::new(plaintext::snapshot(&raw, clock)?);
            let slot = Slot {
                vault: h.vault_id(),
                item: *id.as_bytes(),
                key_gen: h.generation(),
            };
            let sealed = Envelope::seal(
                Header {
                    vault: slot.vault,
                    item: slot.item,
                    device: h.device_id(),
                    key_gen: slot.key_gen,
                    parents: vec![],
                },
                &clear,
                &keys.vault,
                keys.device.signer(),
            )?
            .to_bytes();
            if *Envelope::open_received(
                &sealed,
                slot,
                &keys.vault,
                &keys.device.signer().verifying_key(),
            )? != *clear
            {
                return Err(Error::Invalid("restore verification failed"));
            }
            rows.push((id, revision, sealed));
            if let Some(body) = body {
                items.insert(
                    id,
                    Item {
                        id,
                        rev: revision,
                        body,
                    },
                );
            } else {
                unreadable += 1;
            }
        }
        clock = crate::migration::next_clock(clock)?;
        let metadata = Envelope::seal(
            Header {
                vault: h.vault_id(),
                item: [0; 16],
                device: h.device_id(),
                key_gen: h.generation(),
                parents: vec![],
            },
            &snapshot.metadata,
            &keys.vault.metadata_key()?,
            keys.device.signer(),
        )?
        .to_bytes();
        if *Envelope::open_received(
            &metadata,
            Slot {
                vault: h.vault_id(),
                item: [0; 16],
                key_gen: h.generation(),
            },
            &keys.vault.metadata_key()?,
            &keys.device.signer().verifying_key(),
        )? != *snapshot.metadata
        {
            return Err(Error::Invalid("metadata restore verification failed"));
        }
        Ok(Import {
            header: h.to_bytes(),
            before_metadata: self.store.private_metadata()?,
            rows,
            metadata,
            items,
            unreadable,
            clock,
        })
    }
    pub fn apply_restore(&mut self, import: Import) -> Result<()> {
        self.empty_for_restore()?;
        if self.store.header.as_ref().ok_or(Error::Locked)?.to_bytes() != import.header
            || *self.store.private_metadata()? != *import.before_metadata
        {
            return Err(Error::Invalid("destination changed during restore"));
        }
        self.store.conn.pragma_update(None, "synchronous", "FULL")?;
        let tx = self.store.conn.transaction()?;
        tx.pragma_update(None, "user_version", 3)?;
        for (id, rev, bytes) in &import.rows {
            tx.execute(
                "INSERT INTO items VALUES (?1,?2,?3,?4)",
                rusqlite::params![
                    self.store.vault_id.as_bytes().as_slice(),
                    id.as_bytes().as_slice(),
                    *rev as i64,
                    bytes
                ],
            )?;
            let saved: Vec<u8> = tx.query_row(
                "SELECT envelope FROM items WHERE item_id=?1",
                [id.as_bytes().as_slice()],
                |r| r.get(0),
            )?;
            if saved != *bytes {
                return Err(Error::Invalid("restore disk verification failed"));
            }
        }
        tx.execute(
            "UPDATE meta SET value=?2 WHERE key=?1",
            rusqlite::params![PRIVATE, &import.metadata],
        )?;
        let saved: Vec<u8> =
            tx.query_row("SELECT value FROM meta WHERE key=?1", [PRIVATE], |r| {
                r.get(0)
            })?;
        if saved != import.metadata {
            return Err(Error::Invalid("metadata disk verification failed"));
        }
        tx.commit()?;
        self.items = import.items;
        self.unreadable = import.unreadable;
        self.store.clock = import.clock;
        if let Some(wake) = &self.on_change {
            wake();
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::{Host, SecretKind};
    use openward_crypto::{password::KdfParams, unlock::RecoveryKit};
    fn fixture(path: &std::path::Path) -> (Vault, RecoveryKit) {
        drop(Vault::open(path).unwrap());
        let kit = RecoveryKit::from_secret(Zeroizing::new([42; 32]));
        let locked = Vault::migrate_with_recovery(
            path,
            b"Public D7 fixture password",
            KdfParams::new(65536, 1).unwrap(),
            &kit,
        )
        .unwrap();
        (locked.unlock(b"Public D7 fixture password").unwrap(), kit)
    }
    #[test]
    fn portable_copy_restores_with_either_factor_under_new_destination_keys() {
        let d = tempfile::tempdir().unwrap();
        let (mut source, kit) = fixture(&d.path().join("source.db"));
        let id = source
            .create(Data::Host(Host {
                label: "private host TEST".into(),
                address: "backup.invalid".into(),
                ..Default::default()
            }))
            .unwrap();
        let secret = source
            .save_secret(
                SecretKind::Password,
                "SSH TEST",
                "server:user:fp",
                "private password TEST",
            )
            .unwrap();
        assert!(source.export_json(b"wrong", true).is_err());
        assert!(
            source
                .export_json(b"Public D7 fixture password", false)
                .is_err()
        );
        let archive = source.export_backup().unwrap();
        assert!(!archive.windows(12).any(|w| w == b"private host"));
        let source_header = source.store.header.as_ref().unwrap().to_bytes();
        let json = source
            .export_json(b"Public D7 fixture password", true)
            .unwrap();
        assert!(
            std::str::from_utf8(&json)
                .unwrap()
                .contains("private password TEST")
        );
        for n in 0..3 {
            let (mut target, _) = fixture(&d.path().join(format!("target-{n}.db")));
            let old_header = target.store.header.as_ref().unwrap().to_bytes();
            assert_ne!(old_header, source_header);
            let data = match n {
                0 => Snapshot::open(&archive, b"Public D7 fixture password", false).unwrap(),
                1 => Snapshot::open(&archive, kit.text().as_bytes(), true).unwrap(),
                _ => Snapshot::parse(&json).unwrap(),
            };
            assert_eq!(
                data.summary(),
                Summary {
                    items: 2,
                    secrets: 1,
                    unreadable: 0
                }
            );
            let prepared = target.prepare_restore(data).unwrap();
            target.apply_restore(prepared).unwrap();
            assert_eq!(target.store.header.as_ref().unwrap().to_bytes(), old_header);
            assert_eq!(target.host(id).unwrap().label, "private host TEST");
            assert_eq!(
                *target.secret(&secret).unwrap().value,
                "private password TEST"
            );
            assert!(
                target
                    .prepare_restore(Snapshot::parse(&json).unwrap())
                    .is_err()
            );
            target.lock_in_place().unwrap();
            target
                .unlock_in_place(b"Public D7 fixture password")
                .unwrap();
            assert_eq!(target.host(id).unwrap().address, "backup.invalid");
        }
        assert!(Snapshot::open(&archive, b"wrong", false).is_err());
        let mut altered = archive.clone();
        *altered.last_mut().unwrap() ^= 1;
        assert!(Snapshot::open(&altered, kit.text().as_bytes(), true).is_err());
        assert!(
            Snapshot::open(&archive[..archive.len() - 1], kit.text().as_bytes(), true).is_err()
        );
        let mut future = archive.clone();
        future[4] = 2;
        assert!(Snapshot::open(&future, kit.text().as_bytes(), true).is_err());
    }
    #[test]
    fn archive_prefix_payload_and_truncation_authentication_and_opaque_cbor_are_preserved() {
        let archive = include_bytes!("../tests/fixtures/vault-d7.owvault");
        let kit = RecoveryKit::from_secret(Zeroizing::new([42; 32]));
        for i in (0..archive.len()).step_by(137) {
            let mut altered = archive.to_vec();
            altered[i] ^= 1;
            assert!(Snapshot::open(&altered, kit.text().as_bytes(), true).is_err());
        }
        for n in [0, 4, 5, 6, 7, 100, archive.len() - 1, archive.len() - 16] {
            assert!(Snapshot::open(&archive[..n], kit.text().as_bytes(), true).is_err());
        }
        let d = tempfile::tempdir().unwrap();
        let (target, _) = fixture(&d.path().join("target.db"));
        let raw = ciborium::Value::Map(vec![
            ("type".into(), "future_item".into()),
            ("created".into(), 1.into()),
            ("modified".into(), 1.into()),
            ("future_blob".into(), ciborium::Value::Bytes(vec![1, 2, 3])),
        ]);
        let mut bytes = Vec::new();
        ciborium::into_writer(&raw, &mut bytes).unwrap();
        let doc = Document {
            format: FORMAT.into(),
            version: 1,
            private_metadata_hex: hex(b"OWPM\x01\0\0\0\0"),
            items: vec![Row {
                id: ItemId::new().to_string(),
                revision: 1,
                body_cbor_hex: hex(&bytes),
                body: None,
            }],
        };
        let json = serde_json::to_vec(&doc).unwrap();
        let snapshot = Snapshot::parse(&json).unwrap();
        assert_eq!(snapshot.summary().unreadable, 1);
        let prepared = target.prepare_restore(snapshot).unwrap();
        let mut target = target;
        target.apply_restore(prepared).unwrap();
        let restored = target
            .export_json(b"Public D7 fixture password", true)
            .unwrap();
        let decoded: Document = serde_json::from_slice(&restored).unwrap();
        assert_eq!(
            unhex(&decoded.items[0].body_cbor_hex).unwrap().as_slice(),
            bytes
        );
        let mut invalid = doc;
        invalid.items[0].body_cbor_hex = hex(b"\xa1");
        assert!(Snapshot::parse(&serde_json::to_vec(&invalid).unwrap()).is_err());
    }

    #[test]
    fn malformed_versions_duplicates_and_disk_failure_never_partially_restore() {
        let d = tempfile::tempdir().unwrap();
        let (mut source, _) = fixture(&d.path().join("source.db"));
        source
            .create(Data::Host(Host {
                label: "fixture".into(),
                address: "fixture.invalid".into(),
                ..Default::default()
            }))
            .unwrap();
        let json = source
            .export_json(b"Public D7 fixture password", true)
            .unwrap();
        let mut bad: serde_json::Value = serde_json::from_slice(&json).unwrap();
        bad["version"] = 2.into();
        assert!(Snapshot::parse(&serde_json::to_vec(&bad).unwrap()).is_err());
        bad["version"] = 1.into();
        let row = bad["items"][0].clone();
        bad["items"].as_array_mut().unwrap().push(row);
        assert!(Snapshot::parse(&serde_json::to_vec(&bad).unwrap()).is_err());
        let (mut target, _) = fixture(&d.path().join("target.db"));
        target.store.conn.execute_batch("CREATE TRIGGER fail_restore BEFORE UPDATE ON meta BEGIN SELECT RAISE(FAIL, 'injected full disk'); END;").unwrap();
        let prepared = target
            .prepare_restore(Snapshot::parse(&json).unwrap())
            .unwrap();
        assert!(target.apply_restore(prepared).is_err());
        assert!(target.hosts().is_empty());
        let count: i64 = target
            .store
            .conn
            .query_row("SELECT count(*) FROM items", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 0);
        target
            .store
            .conn
            .execute_batch("DROP TRIGGER fail_restore")
            .unwrap();
        let prepared = target
            .prepare_restore(Snapshot::parse(&json).unwrap())
            .unwrap();
        target
            .create(Data::Host(Host {
                label: "keep".into(),
                address: "keep.invalid".into(),
                ..Default::default()
            }))
            .unwrap();
        assert!(target.apply_restore(prepared).is_err());
        assert_eq!(target.hosts()[0].1.label, "keep");
    }
}
