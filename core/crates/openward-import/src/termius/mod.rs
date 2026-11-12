//! Termius, read from its own data on this computer: it has no export.
//!
//! Termius is an Electron app and keeps its data in Chromium's IndexedDB
//! ([`idb`], on [`leveldb`], values in V8's format: [`v8`]). Some fields
//! are encrypted with NaCl's secretbox under a key Termius keeps in the
//! system keychain ([`crypto`]). Everything here only reads: Termius's
//! files are never opened for writing, and Termius may be running.
//!
//! The format is Termius's own and undocumented, so it may change with any
//! version; what does not parse is an error, never a partial import.

mod budget;
pub mod crypto;
pub mod idb;
pub mod keychain;
pub mod leveldb;
pub mod model;
pub mod v8;

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use v8::Value;

/// Where Termius may keep its data, most likely first: the build from its
/// website, the Mac App Store's, and the Windows, Linux and Snap ones.
pub fn data_dirs(home: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if cfg!(target_os = "macos") {
        out.push(home.join("Library/Application Support/Termius"));
        out.push(
            home.join(
                "Library/Containers/com.termius.mac/Data/Library/Application Support/Termius",
            ),
        );
    } else if cfg!(windows) {
        if let Some(appdata) = std::env::var_os("APPDATA") {
            out.push(PathBuf::from(appdata).join("Termius"));
        }
        out.push(home.join("AppData/Roaming/Termius"));
    } else {
        out.push(home.join(".config/Termius"));
        out.push(home.join("snap/termius-app/current/.config/Termius"));
    }
    out
}

/// The IndexedDB of a Termius data folder, if it has one.
pub fn leveldb_dir(data_dir: &Path) -> Option<PathBuf> {
    let dir = data_dir.join("IndexedDB/file__0.indexeddb.leveldb");
    dir.join("CURRENT").is_file().then_some(dir)
}

/// The first Termius data folder with an IndexedDB.
pub fn find(home: &Path) -> Option<PathBuf> {
    data_dirs(home)
        .into_iter()
        .find(|d| leveldb_dir(d).is_some())
}

#[derive(Debug)]
pub enum Error {
    /// No Termius data in that folder.
    NotFound,
    Io(std::io::Error),
    /// The keychain could not be asked, or said no.
    Keychain(String),
    /// Termius's key is not in the keychain.
    NoKey,
    /// No key in the keychain opens Termius's data.
    WrongKey,
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotFound => f.write_str("no Termius data there"),
            Self::Io(e) => write!(f, "{e}"),
            Self::Keychain(e) => write!(f, "keychain: {e}"),
            Self::NoKey => f.write_str("Termius's key is not in the keychain"),
            Self::WrongKey => f.write_str("the keychain's key does not open Termius's data"),
        }
    }
}

impl std::error::Error for Error {}

/// Reads a Termius data folder. `keys` are tried in turn; `None` asks the
/// keychain, which makes the system ask the user first.
pub fn read(data_dir: &Path, keys: Option<Vec<[u8; 32]>>) -> Result<crate::bundle::Bundle, Error> {
    let leveldb = leveldb_dir(data_dir).ok_or(Error::NotFound)?;
    let mut budget = budget::Budget::default();
    let db = idb::read_with_budget(&leveldb, &mut budget).map_err(Error::Io)?;
    let keys = zeroize::Zeroizing::new(match keys {
        Some(k) => k,
        None => keychain::local_keys().map_err(Error::Keychain)?,
    });
    if keys.is_empty() {
        return Err(Error::NoKey);
    }
    let key = zeroize::Zeroizing::new(if has_encrypted(&db) {
        pick_key(&db, &keys).ok_or(Error::WrongKey)?
    } else {
        keys[0]
    });
    let mut bundle =
        model::bundle_with_budget(&db, &key, &budget).map_err(|e| Error::Io(budget::invalid(e)))?;
    if !db.unreadable.is_empty() {
        let why: Vec<_> = db
            .unreadable
            .iter()
            .map(|(why, count)| format!("{count} × {why}"))
            .collect();
        bundle.warnings.push(crate::bundle::Warning::general(
            crate::bundle::WarningKind::Unreadable {
                count: db.unreadable.values().sum(),
                why: why.join("; "),
            },
        ));
    }
    Ok(bundle)
}

fn has_encrypted(db: &idb::Idb) -> bool {
    db.databases.iter().any(|d| {
        d.stores.values().any(|s| {
            db.records(d, Some(s)).iter().any(|r| match &r.value {
                Value::Object(f) => f
                    .values()
                    .any(|v| v.as_str().is_some_and(crypto::is_encrypted)),
                _ => false,
            })
        })
    })
}

/// What kind of value a field holds, without the value.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Kind {
    Unset,
    Bool,
    Number,
    Text,
    Encrypted,
    Date,
    List,
    Object,
}

/// The shape of Termius's data, with no values: to check a version's
/// format without reading anyone's hosts.
#[derive(Debug, Default)]
pub struct Shape {
    pub tables: usize,
    pub logs: usize,
    /// Database name → store name → (records, field → kinds seen, with
    /// how many records had each; for objects, their own field names).
    pub databases: BTreeMap<String, BTreeMap<String, StoreShape>>,
    pub unreadable: BTreeMap<String, usize>,
}

#[derive(Debug, Default)]
pub struct StoreShape {
    pub records: usize,
    pub fields: BTreeMap<String, BTreeMap<Kind, usize>>,
    /// Field names inside object-valued fields (`group` → `id`, `local_id`).
    pub nested: BTreeMap<String, std::collections::BTreeSet<String>>,
    /// With a key: what encrypted fields hold once decrypted. Text that is
    /// a JSON object shows its own fields and their kinds (`port: number`);
    /// other text shows as `(text)`, or `(empty)`.
    pub decrypted: BTreeMap<String, BTreeMap<String, std::collections::BTreeSet<&'static str>>>,
    /// Encrypted fields the key did not open.
    pub undecryptable: usize,
}

fn json_kind(v: &serde_json::Value) -> &'static str {
    match v {
        serde_json::Value::Null => "null",
        serde_json::Value::Bool(_) => "bool",
        serde_json::Value::Number(_) => "number",
        serde_json::Value::String(s) if s.is_empty() => "empty text",
        serde_json::Value::String(_) => "text",
        serde_json::Value::Array(_) => "list",
        serde_json::Value::Object(_) => "object",
    }
}

/// The first of `keys` that opens one of the encrypted fields.
pub fn pick_key(db: &idb::Idb, keys: &[[u8; 32]]) -> Option<[u8; 32]> {
    let sample = db.databases.iter().find_map(|d| {
        d.stores.values().find_map(|s| {
            db.records(d, Some(s)).iter().find_map(|r| match &r.value {
                Value::Object(f) => f.values().find_map(|v| {
                    v.as_str()
                        .filter(|s| crypto::is_encrypted(s))
                        .map(str::to_owned)
                }),
                _ => None,
            })
        })
    })?;
    keys.iter()
        .copied()
        .find(|k| crypto::decrypt(k, &sample).is_ok())
}

fn kind(v: &Value) -> Kind {
    match v {
        Value::Undefined | Value::Null => Kind::Unset,
        Value::Bool(_) => Kind::Bool,
        Value::Int(_) | Value::Double(_) => Kind::Number,
        Value::String(s) if crypto::is_encrypted(s) => Kind::Encrypted,
        Value::String(_) => Kind::Text,
        Value::Date(_) => Kind::Date,
        Value::Array(_) => Kind::List,
        Value::Object(_) => Kind::Object,
    }
}

/// The shape of the data; with a key, also of what its encrypted fields
/// hold.
pub fn shape(leveldb: &Path, keys: &[[u8; 32]]) -> std::io::Result<Shape> {
    let (tables, logs) = leveldb::file_counts(leveldb)?;
    let db = idb::read(leveldb)?;
    let secret = pick_key(&db, keys);
    let mut out = Shape {
        tables,
        logs,
        unreadable: db.unreadable.clone(),
        ..Shape::default()
    };
    for d in &db.databases {
        let stores = out.databases.entry(d.name.clone()).or_default();
        for name in d.stores.values() {
            let s = stores.entry(name.clone()).or_default();
            for record in db.records(d, Some(name)) {
                s.records += 1;
                let key = match record.key {
                    idb::Key::Number(_) => Kind::Number,
                    idb::Key::String(_) => Kind::Text,
                    idb::Key::Other => Kind::Object,
                };
                *s.fields
                    .entry("(primary key)".into())
                    .or_default()
                    .entry(key)
                    .or_default() += 1;
                let record = &record.value;
                let Value::Object(fields) = record else {
                    *s.fields
                        .entry("(not an object)".into())
                        .or_default()
                        .entry(kind(record))
                        .or_default() += 1;
                    continue;
                };
                for (field, value) in fields {
                    *s.fields
                        .entry(field.clone())
                        .or_default()
                        .entry(kind(value))
                        .or_default() += 1;
                    if let Value::Object(inner) = value {
                        s.nested
                            .entry(field.clone())
                            .or_default()
                            .extend(inner.keys().cloned());
                    }
                    let (Some(secret), Some(text)) = (secret, value.as_str()) else {
                        continue;
                    };
                    if !crypto::is_encrypted(text) {
                        continue;
                    }
                    let Ok(plain) = crypto::decrypt(&secret, text) else {
                        s.undecryptable += 1;
                        continue;
                    };
                    let seen = s.decrypted.entry(field.clone()).or_default();
                    match serde_json::from_str::<serde_json::Value>(&plain) {
                        Ok(serde_json::Value::Object(map)) => {
                            for (k, v) in map {
                                seen.entry(k).or_default().insert(json_kind(&v));
                            }
                        }
                        _ if plain.is_empty() => {
                            seen.entry("(empty)".into()).or_default();
                        }
                        _ => {
                            seen.entry("(text)".into()).or_default();
                        }
                    }
                }
            }
        }
    }
    Ok(out)
}
