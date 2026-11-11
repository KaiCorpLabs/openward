//! Chromium's IndexedDB on top of LevelDB: the database and object store
//! names, and each record's value, unwrapped from Blink's envelope
//! (compressed with Snappy, or kept in a blob file when large) and
//! deserialized from V8's format.
//!
//! Every LevelDB key starts with a prefix: a byte with the widths of three
//! ids (database, object store, index) and the ids, little-endian. Global
//! metadata uses ids 0, 0, 0; a database's metadata, its id and 0, 0; and
//! an object store's records, index 1.

use std::collections::{BTreeMap, HashMap};
use std::io;
use std::path::{Path, PathBuf};

use super::budget::{Budget, invalid};
use super::leveldb::{self, Reader};
use super::v8::{self, Value};

#[derive(Debug)]
pub struct Database {
    pub id: u64,
    pub name: String,
    /// Object store names by id.
    pub stores: BTreeMap<u64, String>,
}

/// A record's primary key. With a key path and a key generator, Chromium
/// keeps the generated key here and not inside the value.
#[derive(Clone, Debug, PartialEq)]
pub enum Key {
    Number(f64),
    String(String),
    /// A date, an array or binary: not used as ids here.
    Other,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Record {
    pub key: Key,
    pub value: Value,
}

#[derive(Debug)]
pub struct Idb {
    pub databases: Vec<Database>,
    /// Records by database and object store id.
    records: HashMap<(u64, u64), Vec<Record>>,
    /// Records whose value could not be read, with why (first of each).
    pub unreadable: BTreeMap<String, usize>,
}

impl Idb {
    pub fn database(&self, name: &str) -> Option<&Database> {
        self.databases.iter().find(|d| d.name == name)
    }

    /// The records of a database's object store; its first store when
    /// `store` is `None`.
    pub fn records(&self, db: &Database, store: Option<&str>) -> &[Record] {
        let id = match store {
            Some(name) => db
                .stores
                .iter()
                .find(|(_, n)| *n == name)
                .map(|(id, _)| *id),
            None => db.stores.keys().next().copied(),
        };
        id.and_then(|id| self.records.get(&(db.id, id)))
            .map(Vec::as_slice)
            .unwrap_or_default()
    }
}

/// Reads `<origin>.indexeddb.leveldb`; blob files are looked for next to
/// it, in `<origin>.indexeddb.blob`.
pub fn read(dir: &Path) -> io::Result<Idb> {
    read_with_budget(dir, &mut Budget::default())
}

fn read_with_budget(dir: &Path, budget: &mut Budget) -> io::Result<Idb> {
    let entries = leveldb::read_with_budget(dir, budget)?;
    let blobs = blob_dir(dir);
    let mut db_names: Vec<(u64, String)> = Vec::new();
    let mut stores: HashMap<u64, BTreeMap<u64, String>> = HashMap::new();
    let mut data: Vec<(u64, u64, Vec<u8>, Vec<u8>)> = Vec::new();
    // External objects (blobs) of each record, by its key.
    let mut externals: HashMap<(u64, u64, Vec<u8>), Vec<u8>> = HashMap::new();
    for (key, value) in entries {
        // Covers metadata decoding, record keys, map/vector overhead and
        // the temporary lookup key below, before any of those copies.
        budget.allocation(1, 256).map_err(invalid)?;
        budget.buffer(key.len(), 4).map_err(invalid)?;
        budget.buffer(value.len(), 4).map_err(invalid)?;
        let Ok((prefix, rest)) = Prefix::parse(&key) else {
            continue;
        };
        match prefix {
            Prefix {
                db: 0,
                store: 0,
                index: 0,
            } => {
                if let Some((&201, name_key)) = rest.split_first()
                    && let Ok(name) = database_name(name_key)
                {
                    db_names.push((truncated_int(&value), name));
                }
            }
            Prefix {
                db,
                store: 0,
                index: 0,
            } => {
                if let Some((&50, meta)) = rest.split_first() {
                    let mut r = Reader::new(meta);
                    if let (Ok(id), Ok(0)) = (r.varint(), r.byte())
                        && r.done()
                    {
                        stores.entry(db).or_default().insert(id, utf16_be(&value));
                    }
                }
            }
            Prefix {
                db,
                store,
                index: 1,
            } => data.push((db, store, rest.to_vec(), value)),
            Prefix {
                db,
                store,
                index: 3,
            } => {
                externals.insert((db, store, rest.to_vec()), value);
            }
            _ => {}
        }
    }
    let mut records: HashMap<(u64, u64), Vec<Record>> = HashMap::new();
    let mut unreadable: BTreeMap<String, usize> = BTreeMap::new();
    for (db, store, key, value) in data {
        let external = externals.get(&(db, store, key.clone()));
        match record_value_with_budget(
            &value,
            db,
            external.map(Vec::as_slice),
            blobs.as_deref(),
            budget,
        ) {
            Ok(Some(v)) => records.entry((db, store)).or_default().push(Record {
                key: idb_key(&key),
                value: v,
            }),
            Ok(None) => {}
            Err(e) if budget.exhausted => return Err(invalid(e)),
            Err(e) => *unreadable.entry(e).or_default() += 1,
        }
    }
    db_names.sort();
    Ok(Idb {
        databases: db_names
            .into_iter()
            .map(|(id, name)| Database {
                id,
                name,
                stores: stores.remove(&id).unwrap_or_default(),
            })
            .collect(),
        records,
        unreadable,
    })
}

fn blob_dir(leveldb: &Path) -> Option<PathBuf> {
    let name = leveldb.file_name()?.to_str()?;
    let origin = name.strip_suffix(".indexeddb.leveldb")?;
    Some(leveldb.with_file_name(format!("{origin}.indexeddb.blob")))
}

#[derive(Debug, PartialEq)]
struct Prefix {
    db: u64,
    store: u64,
    index: u64,
}

impl Prefix {
    fn parse(key: &[u8]) -> Result<(Self, &[u8]), String> {
        let (&first, rest) = key.split_first().ok_or("empty key")?;
        let widths = [
            ((first >> 5) & 0x07) as usize + 1,
            ((first >> 2) & 0x07) as usize + 1,
            (first & 0x03) as usize + 1,
        ];
        let mut r = Reader::new(rest);
        let mut ids = [0u64; 3];
        for (id, width) in ids.iter_mut().zip(widths) {
            *id = little_endian(r.bytes(width)?);
        }
        Ok((
            Self {
                db: ids[0],
                store: ids[1],
                index: ids[2],
            },
            r.rest(),
        ))
    }
}

fn little_endian(bytes: &[u8]) -> u64 {
    bytes
        .iter()
        .rev()
        .fold(0u64, |acc, &b| (acc << 8) | u64::from(b))
}

/// Metadata integers: little-endian, in as many bytes as needed.
fn truncated_int(bytes: &[u8]) -> u64 {
    little_endian(&bytes[..bytes.len().min(8)])
}

fn utf16_be(bytes: &[u8]) -> String {
    let units: Vec<u16> = bytes
        .as_chunks::<2>()
        .0
        .iter()
        .map(|c| u16::from_be_bytes(*c))
        .collect();
    String::from_utf16_lossy(&units)
}

/// A string with its length in UTF-16 code units, then UTF-16BE.
fn string_with_length(r: &mut Reader) -> Result<String, String> {
    let units = r.len()?;
    Ok(utf16_be(
        r.bytes(units.checked_mul(2).ok_or("length overflow")?)?,
    ))
}

/// An encoded IndexedDB key: a type byte, then a number (8 bytes,
/// little-endian), a string with its length, or something else.
fn idb_key(bytes: &[u8]) -> Key {
    let mut r = Reader::new(bytes);
    match r.byte() {
        Ok(1) => string_with_length(&mut r)
            .map(Key::String)
            .unwrap_or(Key::Other),
        Ok(3) => r
            .bytes(8)
            .map(|b| Key::Number(f64::from_le_bytes(b.try_into().unwrap())))
            .unwrap_or(Key::Other),
        _ => Key::Other,
    }
}

/// The key of a database name: the origin, then the name.
fn database_name(key: &[u8]) -> Result<String, String> {
    let mut r = Reader::new(key);
    let _origin = string_with_length(&mut r)?;
    string_with_length(&mut r)
}

const REQUIRES_PROCESSING: u8 = 0x11;
const REPLACE_WITH_BLOB: u8 = 0x01;
const COMPRESSED_WITH_SNAPPY: u8 = 0x02;

/// A record: its version, then Blink's serialization. `None` for an
/// empty value.
#[cfg(test)]
fn record_value(
    value: &[u8],
    db: u64,
    external: Option<&[u8]>,
    blobs: Option<&Path>,
) -> Result<Option<Value>, String> {
    record_value_with_budget(value, db, external, blobs, &mut Budget::default())
}

fn record_value_with_budget(
    value: &[u8],
    db: u64,
    external: Option<&[u8]>,
    blobs: Option<&Path>,
    budget: &mut Budget,
) -> Result<Option<Value>, String> {
    let mut r = Reader::new(value);
    r.varint()?; // the record's version
    if r.done() {
        return Ok(None);
    }
    unwrap_blink(r.rest(), db, external, blobs, 0, budget).map(Some)
}

fn unwrap_blink(
    data: &[u8],
    db: u64,
    external: Option<&[u8]>,
    blobs: Option<&Path>,
    depth: usize,
    budget: &mut Budget,
) -> Result<Value, String> {
    if depth > 2 {
        return Err("value wrapped too many times".into());
    }
    if let [0xff, REQUIRES_PROCESSING, how, rest @ ..] = data {
        return match *how {
            COMPRESSED_WITH_SNAPPY => {
                let len = snap::raw::decompress_len(rest).map_err(|e| format!("snappy: {e}"))?;
                if len as u64 > crate::files::MAX_FILE {
                    return budget.refuse();
                }
                budget.bytes(len)?;
                let raw = snap::raw::Decoder::new()
                    .decompress_vec(rest)
                    .map_err(|e| format!("snappy: {e}"))?;
                unwrap_blink(&raw, db, external, blobs, depth + 1, budget)
            }
            REPLACE_WITH_BLOB => {
                let mut r = Reader::new(rest);
                r.varint()?; // size
                let index = r.len()?;
                let number = blob_number(external.ok_or("blob value without its blob")?, index)?;
                let dir = blobs.ok_or("blob value without a blob folder")?;
                let path = dir
                    .join(format!("{db:x}"))
                    .join(format!("{:02x}", number >> 8))
                    .join(format!("{number:x}"));
                let raw = budget
                    .read(&path)
                    .map_err(|e| format!("blob {}: {e}", path.display()))?;
                unwrap_blink(&raw, db, None, blobs, depth + 1, budget)
            }
            other => Err(format!("unknown value wrapping {other}")),
        };
    }
    let mut r = Reader::new(data);
    if r.byte()? != 0xff {
        return Err("no Blink version header".into());
    }
    let version = r.varint()?;
    if version >= 21 {
        // Trailer offset: a tag, then where the trailer is and its size.
        if r.byte()? != 0xfe {
            return Err("no Blink trailer offset".into());
        }
        r.bytes(12)?;
    }
    v8::deserialize_with_budget(r.rest(), budget)
}

/// The blob number of a record's `index`th external object.
fn blob_number(list: &[u8], index: usize) -> Result<u64, String> {
    let mut r = Reader::new(list);
    let mut i = 0;
    while !r.done() {
        let kind = r.byte()?;
        let number = r.varint()?;
        string_with_length(&mut r)?; // MIME type
        r.varint()?; // size
        if kind == 1 {
            string_with_length(&mut r)?; // file name
            r.varint()?; // last modified
        }
        if i == index {
            return Ok(number);
        }
        i += 1;
    }
    Err("blob index out of range".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    proptest::proptest! {
        /// IndexedDB keys and records that make no sense are refused.
        #[test]
        fn any_bytes_are_read_or_refused(bytes in proptest::collection::vec(proptest::prelude::any::<u8>(), 0..2048)) {
            let _ = Prefix::parse(&bytes);
            let _ = database_name(&bytes);
            let _ = idb_key(&bytes);
            let _ = record_value(&bytes, 1, None, None);
            let _ = record_value(&bytes, 1, Some(&bytes), None);
        }
    }

    #[test]
    fn a_prefix_with_wider_ids() {
        // db 1 byte, store 2 bytes, index 1 byte: 0b000_001_00.
        let key = [0b0000_0100, 7, 0x2c, 0x01, 1, 0xaa];
        let (p, rest) = Prefix::parse(&key).unwrap();
        assert_eq!(
            p,
            Prefix {
                db: 7,
                store: 300,
                index: 1
            }
        );
        assert_eq!(rest, [0xaa]);
    }

    #[test]
    fn keys_numbers_and_strings() {
        let mut number = vec![3];
        number.extend(7.0f64.to_le_bytes());
        assert_eq!(idb_key(&number), Key::Number(7.0));
        assert_eq!(idb_key(&[1, 2, 0, b'i', 0, b'd']), Key::String("id".into()));
        assert_eq!(idb_key(&[0]), Key::Other);
    }

    #[test]
    fn a_compressed_value() {
        let mut inner = vec![0xff, 20, 0xff, 15, b'"', 2];
        inner.extend_from_slice(b"ok");
        let mut wrapped = vec![0xff, REQUIRES_PROCESSING, COMPRESSED_WITH_SNAPPY];
        wrapped.extend(snap::raw::Encoder::new().compress_vec(&inner).unwrap());
        let mut record = vec![1];
        record.extend(wrapped);
        assert_eq!(
            record_value(&record, 1, None, None).unwrap(),
            Some(Value::String("ok".into()))
        );
    }

    #[test]
    fn a_value_with_a_trailer_offset() {
        let mut record = vec![1, 0xff, 21, 0xfe];
        record.extend([0; 12]);
        record.extend([0xff, 15, b'T']);
        assert_eq!(
            record_value(&record, 1, None, None).unwrap(),
            Some(Value::Bool(true))
        );
    }

    #[test]
    fn compressed_lengths_are_checked_before_reserving_output() {
        // A raw Snappy header declares almost 4 GiB, with no payload.
        let value = [
            1,
            0xff,
            REQUIRES_PROCESSING,
            COMPRESSED_WITH_SNAPPY,
            0xff,
            0xff,
            0xff,
            0xff,
            0x0f,
        ];
        let mut budget = Budget::default();
        assert!(record_value_with_budget(&value, 1, None, None, &mut budget).is_err());
        assert!(budget.exhausted);
    }

    fn database_with_values(values: &[Vec<u8>]) -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        let mut batch = 1u64.to_le_bytes().to_vec();
        batch.extend((values.len() as u32).to_le_bytes());
        for (i, value) in values.iter().enumerate() {
            let key = [0, 1, 1, 1, i as u8];
            assert!(value.len() < 128);
            batch.extend([1, key.len() as u8]);
            batch.extend(key);
            batch.push(value.len() as u8);
            batch.extend(value);
        }
        let mut log = vec![0; 4];
        log.extend((batch.len() as u16).to_le_bytes());
        log.push(1);
        log.extend(batch);
        std::fs::write(dir.path().join("000001.log"), log).unwrap();
        dir
    }

    #[test]
    fn budget_exhaustion_aborts_the_import_instead_of_a_partial_warning() {
        let mut value = vec![1, 0xff, 20, 0xff, 15, b'"', 100];
        value.extend([b'x'; 100]);
        let one = database_with_values(&[value.clone()]);
        assert!(read_with_budget(one.path(), &mut Budget::limited(2500, 10000, 100)).is_ok());
        let many = database_with_values(&[value.clone(), value.clone(), value]);
        let mut budget = Budget::limited(2500, 10000, 100);
        assert!(read_with_budget(many.path(), &mut budget).is_err());
        assert!(budget.exhausted);
        assert_eq!(read(many.path()).unwrap().records[&(1, 1)].len(), 3);

        let sparse = vec![1, 0xff, 20, 0xff, 15, b'a', 0x81, 0x80, 4, b'@', 0, 0];
        let hostile = database_with_values(&[sparse]);
        assert!(read(hostile.path()).is_err());
    }
}
