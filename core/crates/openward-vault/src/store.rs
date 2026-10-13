//! The SQLite side: one table of items, keyed like the sync format.

use std::path::Path;

use openward_proto::{Item, ItemId, envelope};
use rusqlite::{Connection, OptionalExtension, params};

use crate::{Error, Result};

/// `PRAGMA user_version` this code writes. Older files are migrated at
/// open; newer ones are refused.
const FORMAT: i64 = 1;

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

pub struct Store {
    conn: Connection,
    pub vault_id: ItemId,
}

impl Store {
    pub fn open(path: &Path) -> Result<Self> {
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
        Self::init(conn)
    }

    pub fn open_in_memory() -> Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(mut conn: Connection) -> Result<Self> {
        let format: i64 = conn.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if format > FORMAT {
            return Err(Error::NewerFormat(format));
        }
        if format == 0 {
            let tx = conn.transaction()?;
            tx.execute_batch(SCHEMA)?;
            let id = ItemId::new();
            tx.execute(
                "INSERT INTO meta (key, value) VALUES ('vault_id', ?1), ('device_id', ?2)",
                params![&id.as_bytes()[..], &ItemId::new().as_bytes()[..]],
            )?;
            tx.pragma_update(None, "user_version", FORMAT)?;
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
        Ok(Self { conn, vault_id })
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
