//! Literal-path SQLite storage. Format2 only writes authenticated ciphertext.
use crate::{Error, Result};
use openward_crypto::{
    envelope::{Envelope, Header, Slot},
    hierarchy::{UnlockedKeys, VaultHeader},
    plaintext,
};
use openward_proto::{Item, ItemId, envelope};
use rusqlite::{Connection, OpenFlags, params};
use std::path::{Path, PathBuf};
use zeroize::Zeroizing;
pub(crate) const SCHEMA:&str="CREATE TABLE meta (key TEXT PRIMARY KEY,value BLOB NOT NULL) STRICT;
CREATE TABLE items (vault_id BLOB NOT NULL,item_id BLOB NOT NULL PRIMARY KEY,head_rev INTEGER NOT NULL,envelope BLOB NOT NULL) STRICT;";
pub(crate) const CRYPTO: &str = "crypto_header_v1";
pub(crate) const PRIVATE: &str = "private_metadata_v1";
pub(crate) fn connect(path: &Path, create: bool) -> Result<Connection> {
    let mut flags = OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_NO_MUTEX;
    if create {
        flags |= OpenFlags::SQLITE_OPEN_CREATE;
    }
    Ok(Connection::open_with_flags(path, flags)?)
}
pub(crate) struct ProcessLock(std::fs::File);
impl Drop for ProcessLock {
    fn drop(&mut self) {
        // A concurrent fork can temporarily inherit the open file description.
        // Release explicitly so a clean close does not depend on its exec/exit.
        let _ = self.0.unlock();
    }
}
pub(crate) fn locking(path: &Path) -> Result<ProcessLock> {
    let mut name = path.as_os_str().to_owned();
    name.push(".lock");
    use cap_fs_ext::{FollowSymlinks, MetadataExt, OpenOptionsFollowExt};
    let parent =
        cap_std::fs::Dir::open_ambient_dir(path.parent().unwrap(), cap_std::ambient_authority())?;
    let mut options = cap_std::fs::OpenOptions::new();
    options.create(true).truncate(false).write(true);
    #[cfg(unix)]
    {
        use cap_std::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.follow(FollowSymlinks::No);
    let name = PathBuf::from(name);
    let file = parent.open_with(name.file_name().unwrap(), &options)?;
    if !file.metadata()?.is_file() || file.metadata()?.nlink() != 1 {
        return Err(Error::Invalid("invalid vault process lock"));
    }
    let file = file.into_std();
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let m = file.metadata()?;
        if m.uid() != rustix::process::geteuid().as_raw() || m.mode() & 0o022 != 0 {
            return Err(Error::Invalid("unsafe vault process lock"));
        }
    }
    match file.try_lock() {
        Ok(()) => Ok(ProcessLock(file)),
        Err(std::fs::TryLockError::WouldBlock) => Err(Error::OpenElsewhere),
        Err(std::fs::TryLockError::Error(e)) => Err(e.into()),
    }
}
pub(crate) fn literal(path: &Path) -> Result<PathBuf> {
    let absolute = std::path::absolute(path)?;
    Ok(std::fs::canonicalize(
        absolute
            .parent()
            .ok_or(Error::Invalid("vault needs a parent directory"))?,
    )?
    .join(
        absolute
            .file_name()
            .ok_or(Error::Invalid("vault needs a filename"))?,
    ))
}
pub(crate) fn id(conn: &Connection, name: &str) -> Result<ItemId> {
    let b: Option<Vec<u8>> = conn.query_row(
        "SELECT CASE WHEN length(value)=16 THEN value END FROM meta WHERE key=?1",
        [name],
        |r| r.get(0),
    )?;
    let b = b.ok_or(Error::Invalid("invalid vault/device id"))?;
    Ok(ItemId::from_bytes(
        b.try_into()
            .map_err(|_| Error::Invalid("invalid vault/device id"))?,
    ))
}
pub(crate) fn configure(conn: &Connection) -> Result<()> {
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "synchronous", "FULL")?;
    Ok(())
}
pub struct Store {
    pub(crate) conn: Connection,
    pub vault_id: ItemId,
    pub(crate) path: Option<PathBuf>,
    pub(crate) lock: Option<ProcessLock>,
    pub(crate) header: Option<VaultHeader>,
    pub(crate) keys: Option<UnlockedKeys>,
    pub(crate) clock: u64,
}
impl Store {
    pub fn open(path: &Path) -> Result<Self> {
        let path = literal(path)?;
        let lock = locking(&path)?;
        #[cfg(unix)]
        if !path.exists() {
            use std::os::unix::fs::OpenOptionsExt;
            std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(&path)?;
        }
        let conn = connect(&path, true)?;
        let mut store = Self::plain(conn)?;
        configure(&store.conn)?;
        store.path = Some(path);
        store.lock = Some(lock);
        Ok(store)
    }
    pub fn open_in_memory() -> Result<Self> {
        Self::plain(Connection::open_in_memory()?)
    }
    fn plain(mut conn: Connection) -> Result<Self> {
        let format: i64 = conn.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if (2..=4).contains(&format) {
            return Err(Error::Locked);
        }
        if format > 1 {
            return Err(Error::NewerFormat(format));
        }
        if format == 0 {
            let tx = conn.transaction()?;
            tx.execute_batch(SCHEMA)?;
            tx.execute(
                "INSERT INTO meta VALUES ('vault_id',?1),('device_id',?2)",
                params![
                    ItemId::new().as_bytes().as_slice(),
                    ItemId::new().as_bytes().as_slice()
                ],
            )?;
            tx.pragma_update(None, "user_version", 1)?;
            tx.commit()?;
        }
        let vault_id = id(&conn, "vault_id")?;
        Ok(Self {
            conn,
            vault_id,
            path: None,
            lock: None,
            header: None,
            keys: None,
            clock: 0,
        })
    }
    pub(crate) fn encrypted(conn: Connection, path: PathBuf, lock: ProcessLock) -> Result<Self> {
        let format: i64 = conn.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if !(2..=4).contains(&format) {
            return Err(if format > 4 {
                Error::NewerFormat(format)
            } else {
                Error::Invalid("the vault is not encrypted")
            });
        }
        let bytes: Option<Vec<u8>> = conn.query_row(
            "SELECT CASE WHEN length(value)<=16384 THEN value END FROM meta WHERE key=?1",
            [CRYPTO],
            |r| r.get(0),
        )?;
        let bytes = bytes.ok_or(openward_crypto::Error::Limit)?;
        let header = VaultHeader::from_bytes(&bytes)?;
        let vault_id = id(&conn, "vault_id")?;
        if header.vault_id() != *vault_id.as_bytes()
            || header.device_id() != *id(&conn, "device_id")?.as_bytes()
        {
            return Err(Error::Invalid("encrypted header identity mismatch"));
        }
        configure(&conn)?;
        Ok(Self {
            conn,
            vault_id,
            path: Some(path),
            lock: Some(lock),
            header: Some(header),
            keys: None,
            clock: 0,
        })
    }
    pub(crate) fn unlock(&mut self, password: &[u8]) -> Result<()> {
        self.keys = Some(
            self.header
                .as_ref()
                .ok_or(Error::Locked)?
                .unlock(password)?,
        );
        self.private_metadata()?;
        Ok(())
    }
    pub(crate) fn lock_keys(&mut self) {
        self.keys.take();
        self.clock = 0;
    }
    pub fn rows(&self) -> Result<Vec<(ItemId, u64, Vec<u8>)>> {
        let mut stmt = self
            .conn
            .prepare("SELECT CASE WHEN length(vault_id)=16 THEN vault_id END,CASE WHEN length(item_id)=16 THEN item_id END,head_rev,CASE WHEN length(envelope)<=?1 THEN envelope END FROM items")?;
        let limit = if self.header.is_some() {
            openward_crypto::envelope::MAX_ENVELOPE as i64
        } else {
            i64::MAX
        };
        let mut cursor = stmt.query([limit])?;
        let mut rows = Vec::new();
        while let Some(r) = cursor.next()? {
            let vault: Option<Vec<u8>> = r.get(0)?;
            let id: Option<Vec<u8>> = r.get(1)?;
            let rev: i64 = r.get(2)?;
            if self.header.is_some()
                && (vault.as_deref() != Some(self.vault_id.as_bytes().as_slice())
                    || id.is_none()
                    || rev < 0)
            {
                return Err(Error::Invalid("invalid encrypted row routing"));
            }
            if vault.as_deref() != Some(self.vault_id.as_bytes().as_slice()) {
                continue;
            }
            let Some(id) = id else {
                continue;
            };
            let Ok(id) = <[u8; 16]>::try_from(id) else {
                continue;
            };
            let bytes: Option<Vec<u8>> = r.get(3)?;
            rows.push((
                ItemId::from_bytes(id),
                rev as u64,
                bytes.ok_or(openward_crypto::Error::Limit)?,
            ));
        }
        Ok(rows)
    }
    pub(crate) fn body(&mut self, id: ItemId, bytes: &[u8]) -> Result<Option<Zeroizing<Vec<u8>>>> {
        let Some(header) = &self.header else {
            return Ok(None);
        };
        let keys = self.keys.as_ref().ok_or(Error::Locked)?;
        let e = Envelope::from_bytes(bytes)?;
        if e.header().device != header.device_id() {
            return Err(Error::Invalid("unknown encrypted writer"));
        }
        let clear = e.open(
            Slot {
                vault: *self.vault_id.as_bytes(),
                item: *id.as_bytes(),
                key_gen: header.generation(),
            },
            &keys.vault,
        )?;
        let (clock, body) = plaintext::body(&clear)?;
        self.clock = self.clock.max(clock);
        Ok(Some(Zeroizing::new(body.to_vec())))
    }
    pub(crate) fn private_metadata(&self) -> Result<Zeroizing<Vec<u8>>> {
        let header = self.header.as_ref().ok_or(Error::Locked)?;
        let keys = self.keys.as_ref().ok_or(Error::Locked)?;
        let bytes: Option<Vec<u8>> = self.conn.query_row(
            "SELECT CASE WHEN length(value)<=?2 THEN value END FROM meta WHERE key=?1",
            params![PRIVATE, openward_crypto::envelope::MAX_ENVELOPE as i64],
            |r| r.get(0),
        )?;
        let bytes = bytes.ok_or(openward_crypto::Error::Limit)?;
        let e = Envelope::from_bytes(&bytes)?;
        let clear = e.open(
            Slot {
                vault: *self.vault_id.as_bytes(),
                item: [0; 16],
                key_gen: header.generation(),
            },
            &keys.vault.metadata_key()?,
        )?;
        crate::migration::validate_metadata(&clear)?;
        Ok(clear)
    }
    pub(crate) fn metadata(&self, name: &str) -> Result<Option<Zeroizing<Vec<u8>>>> {
        if self.header.is_some() && name != "vault_id" && name != "device_id" {
            return crate::migration::metadata_value(&self.private_metadata()?, name);
        }
        use rusqlite::OptionalExtension;
        Ok(self
            .conn
            .query_row("SELECT value FROM meta WHERE key=?1", [name], |r| {
                r.get::<_, Vec<u8>>(0)
            })
            .optional()?
            .map(Zeroizing::new))
    }
    pub fn write(&mut self, items: &[Item], deleted: &[ItemId]) -> Result<()> {
        if self.header.is_some() && self.keys.is_none() {
            return Err(Error::Locked);
        }
        let stores_secret = items
            .iter()
            .any(|i| matches!(i.body.data, openward_proto::Data::Secret(_)));
        if stores_secret {
            self.conn.pragma_update(None, "synchronous", "FULL")?;
        }
        let mut next = self.clock;
        let tx = self.conn.transaction()?;
        if stores_secret {
            let version: i64 = tx.pragma_query_value(None, "user_version", |r| r.get(0))?;
            tx.pragma_update(None, "user_version", version.max(3))?;
        }

        {
            let mut put=tx.prepare_cached("INSERT INTO items (vault_id,item_id,head_rev,envelope) VALUES (?1,?2,?3,?4) ON CONFLICT(item_id) DO UPDATE SET head_rev=excluded.head_rev,envelope=excluded.envelope")?;
            for item in items {
                if self.header.is_none()
                    && matches!(item.body.data, openward_proto::Data::Secret(_))
                {
                    return Err(Error::Invalid("encrypt the vault before storing a secret"));
                }
                let encoded = if let Some(header) = &self.header {
                    let keys = self.keys.as_ref().ok_or(Error::Locked)?;
                    let old: Option<Vec<u8>> = {
                        use rusqlite::OptionalExtension;
                        tx.query_row(
                            "SELECT envelope FROM items WHERE item_id=?1",
                            [item.id.as_bytes().as_slice()],
                            |r| r.get(0),
                        )
                        .optional()?
                    };
                    let parents = old
                        .map(|b| Envelope::from_bytes(&b).map(|e| vec![e.revision()]))
                        .transpose()?
                        .unwrap_or_default();
                    next = crate::migration::next_clock(next)?;
                    let body = Zeroizing::new(item.body.to_cbor());
                    let clear = Zeroizing::new(plaintext::snapshot(&body, next)?);
                    Envelope::seal(
                        Header {
                            vault: *self.vault_id.as_bytes(),
                            item: *item.id.as_bytes(),
                            device: header.device_id(),
                            key_gen: header.generation(),
                            parents,
                        },
                        &clear,
                        &keys.vault,
                        keys.device.signer(),
                    )?
                    .to_bytes()
                } else {
                    envelope::seal_plain(&item.body)
                };
                put.execute(params![
                    self.vault_id.as_bytes().as_slice(),
                    item.id.as_bytes().as_slice(),
                    item.rev as i64,
                    encoded
                ])?;
            }
            for id in deleted {
                tx.execute(
                    "DELETE FROM items WHERE item_id=?1",
                    [id.as_bytes().as_slice()],
                )?;
            }
        }
        tx.commit()?;
        self.clock = next;
        Ok(())
    }
    #[cfg(test)]
    pub fn conn(&self) -> &Connection {
        &self.conn
    }
}
