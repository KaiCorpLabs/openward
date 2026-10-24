//! The SQLite side: one table of items, keyed like the sync format.

use std::path::{Path, PathBuf};

use openward_proto::{Item, ItemId, envelope};
use rusqlite::{Connection, OptionalExtension, Transaction, params};

use crate::{Error, Result};

/// One step of a migration: a file of one format to the next.
type Step = fn(&Transaction) -> Result<()>;

/// `STEPS[n - 1]` takes a format-n file to format n + 1, so this code
/// writes format `STEPS.len() + 1` (`PRAGMA user_version`) and refuses a
/// newer one. An older file is migrated at open all the way, in one
/// transaction, after a copy of it as it was: a step that fails leaves it
/// untouched, and going back to the version that wrote it finds it whole.
const STEPS: &[Step] = &[];

const SCHEMA: &str = "
CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value BLOB NOT NULL
) STRICT;
CREATE TABLE items (
    vault_id BLOB NOT NULL,
    item_id  BLOB NOT NULL PRIMARY KEY,
    head_rev INTEGER NOT NULL,
    envelope BLOB NOT NULL
) STRICT;
";

/// Takes `<path>.lock` for this process, or fails if another holds it.
/// The system lets go of it when the process ends, however it ends.
fn lock(path: &Path) -> Result<std::fs::File> {
    let mut name = path.as_os_str().to_owned();
    name.push(".lock");
    let mut options = std::fs::OpenOptions::new();
    options.create(true).truncate(false).write(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let file = options.open(std::path::PathBuf::from(name))?;
    match file.try_lock() {
        Ok(()) => Ok(file),
        Err(std::fs::TryLockError::WouldBlock) => Err(Error::OpenElsewhere),
        Err(std::fs::TryLockError::Error(e)) => Err(e.into()),
    }
}

/// Where the copy of a format-`format` file goes before it is migrated:
/// next to it, never over an earlier copy.
fn backup_path(path: &Path, format: i64) -> PathBuf {
    let with = |suffix: String| {
        let mut name = path.as_os_str().to_owned();
        name.push(suffix);
        PathBuf::from(name)
    };
    let plain = with(format!(".format-{format}.bak"));
    if !plain.exists() {
        return plain;
    }
    (2..)
        .map(|n| with(format!(".format-{format}.{n}.bak")))
        .find(|p| !p.exists())
        .expect("some name is free")
}

/// Takes a format-`from` file to the last format: a copy first (on disk),
/// then every step in one transaction.
fn migrate(conn: &mut Connection, from: i64, steps: &[Step], path: Option<&Path>) -> Result<()> {
    if let Some(path) = path {
        let backup = backup_path(path, from);
        conn.execute("VACUUM INTO ?1", params![backup.to_string_lossy()])?;
    }
    let tx = conn.transaction()?;
    for step in &steps[(from - 1) as usize..] {
        step(&tx)?;
    }
    tx.pragma_update(None, "user_version", steps.len() as i64 + 1)?;
    tx.commit()?;
    Ok(())
}

pub struct Store {
    conn: Connection,
    pub vault_id: ItemId,
    /// Held while the vault is open, on `<file>.lock`: each process has its
    /// own copy of the items in memory, so a second one would write over
    /// what the first changed.
    _lock: Option<std::fs::File>,
}

impl Store {
    pub fn open(path: &Path) -> Result<Self> {
        let lock = lock(path)?;
        #[cfg(unix)]
        if !path.exists() {
            // Created here, owner-only, so SQLite never makes it with the
            // umask's permissions; its WAL files copy these.
            use std::os::unix::fs::OpenOptionsExt;
            std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(path)?;
        }
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "FULL")?;
        let mut store = Self::init(conn, STEPS, Some(path))?;
        store._lock = Some(lock);
        Ok(store)
    }

    pub fn open_in_memory() -> Result<Self> {
        Self::init(Connection::open_in_memory()?, STEPS, None)
    }

    /// Opens `conn`, creating the schema in an empty file or migrating an
    /// older one by `steps` (a copy of it next to `path` first).
    fn init(mut conn: Connection, steps: &[Step], path: Option<&Path>) -> Result<Self> {
        let current = steps.len() as i64 + 1;
        let format: i64 = conn.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if format > current {
            return Err(Error::NewerFormat(format));
        }
        if format > 0 && format < current {
            migrate(&mut conn, format, steps, path)?;
        }
        if format == 0 {
            let tx = conn.transaction()?;
            tx.execute_batch(SCHEMA)?;
            let id = ItemId::new();
            tx.execute(
                "INSERT INTO meta (key, value) VALUES ('vault_id', ?1), ('device_id', ?2)",
                params![&id.as_bytes()[..], &ItemId::new().as_bytes()[..]],
            )?;
            tx.pragma_update(None, "user_version", current)?;
            tx.commit()?;
        }
        let vault_id = conn
            .query_row("SELECT value FROM meta WHERE key = 'vault_id'", [], |r| {
                r.get::<_, Vec<u8>>(0)
            })
            .optional()?
            .and_then(|b| <[u8; 16]>::try_from(b).ok())
            .map(ItemId::from_bytes)
            .ok_or(Error::Invalid("the vault has no id"))?;
        Ok(Self {
            conn,
            vault_id,
            _lock: None,
        })
    }

    /// Every row: id, head revision and envelope.
    pub fn rows(&self) -> Result<Vec<(ItemId, u64, Vec<u8>)>> {
        let mut stmt = self
            .conn
            .prepare("SELECT item_id, head_rev, envelope FROM items WHERE vault_id = ?1")?;
        let rows = stmt.query_map(params![&self.vault_id.as_bytes()[..]], |r| {
            Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, i64>(1)?, r.get(2)?))
        })?;
        let mut out = Vec::new();
        for row in rows {
            let (id, rev, envelope) = row?;
            let Ok(id) = <[u8; 16]>::try_from(id) else {
                continue;
            };
            out.push((ItemId::from_bytes(id), rev as u64, envelope));
        }
        Ok(out)
    }

    /// Writes `items` and deletes `deleted`, in one transaction.
    pub fn write(&mut self, items: &[Item], deleted: &[ItemId]) -> Result<()> {
        let tx = self.conn.transaction()?;
        {
            let mut put = tx.prepare_cached(
                "INSERT INTO items (vault_id, item_id, head_rev, envelope) VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT (item_id) DO UPDATE SET head_rev = excluded.head_rev,
                                                     envelope = excluded.envelope",
            )?;
            for item in items {
                put.execute(params![
                    &self.vault_id.as_bytes()[..],
                    &item.id.as_bytes()[..],
                    item.rev as i64,
                    envelope::seal_plain(&item.body),
                ])?;
            }
            let mut del = tx.prepare_cached("DELETE FROM items WHERE item_id = ?1")?;
            for id in deleted {
                del.execute(params![&id.as_bytes()[..]])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Raw access for tests that play a newer version.
    #[cfg(test)]
    pub fn conn(&self) -> &Connection {
        &self.conn
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A format-1 file as this version writes it, with one row.
    fn format_1(path: &Path) {
        let mut store = Store::init(Connection::open(path).unwrap(), &[], None).unwrap();
        let item = Item {
            id: ItemId::new(),
            rev: 1,
            body: openward_proto::Body {
                created: 1,
                modified: 1,
                data: openward_proto::Data::Snippet(openward_proto::Snippet {
                    label: "uptime".into(),
                    script: "uptime".into(),
                    ..Default::default()
                }),
            },
        };
        store.write(&[item], &[]).unwrap();
    }

    fn format_of(path: &Path) -> i64 {
        Connection::open(path)
            .unwrap()
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap()
    }

    fn adds_a_table(tx: &Transaction) -> Result<()> {
        tx.execute_batch("CREATE TABLE heads (item_id BLOB PRIMARY KEY) STRICT")?;
        Ok(())
    }

    fn fails(tx: &Transaction) -> Result<()> {
        tx.execute_batch("CREATE TABLE half (x INTEGER)")?;
        Err(Error::Invalid("this step fails"))
    }

    /// Every step in one go, after a copy of the file as it was.
    #[test]
    fn a_migration_runs_once_after_a_copy() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        format_1(&path);
        let steps: &[Step] = &[adds_a_table];
        let store = Store::init(Connection::open(&path).unwrap(), steps, Some(&path)).unwrap();
        assert_eq!(store.rows().unwrap().len(), 1);
        drop(store);
        assert_eq!(format_of(&path), 2);
        let backup = dir.path().join("vault.db.format-1.bak");
        assert_eq!(format_of(&backup), 1);
        // At format 2 already: nothing more to do, no other copy.
        Store::init(Connection::open(&path).unwrap(), steps, Some(&path)).unwrap();
        assert!(!dir.path().join("vault.db.format-1.2.bak").exists());
    }

    /// A step that fails leaves the file as it was: all or nothing.
    #[test]
    fn a_migration_that_fails_changes_nothing() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        format_1(&path);
        let steps: &[Step] = &[adds_a_table, fails];
        let opened = Store::init(Connection::open(&path).unwrap(), steps, Some(&path));
        assert!(matches!(opened, Err(Error::Invalid(_))));
        assert_eq!(format_of(&path), 1);
        let conn = Connection::open(&path).unwrap();
        let tables: i64 = conn
            .query_row(
                "SELECT count(*) FROM sqlite_master WHERE name IN ('heads', 'half')",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(tables, 0);
        let store = Store::init(conn, &[], None).unwrap();
        assert_eq!(store.rows().unwrap().len(), 1);
    }
}
