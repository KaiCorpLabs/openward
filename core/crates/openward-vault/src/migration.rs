//! D3 install transaction: only encrypted bytes are staged. Replacement is the
//! commit point; errors after it explicitly report the installed state.
use crate::{
    Error, LockedVault, Result,
    store::{self, CRYPTO, PRIVATE, SCHEMA, Store},
};
use cap_fs_ext::{FollowSymlinks, MetadataExt, OpenOptionsFollowExt};
use cap_std::fs::{Dir, OpenOptions};
use openward_crypto::{
    envelope::{Envelope, Header, MAX_PLAINTEXT, Slot},
    hierarchy::{KemSuite, UnlockedKeys, VaultHeader},
    password::KdfParams,
    plaintext,
};
use openward_proto::ItemId;
use rusqlite::{Connection, params};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};
use zeroize::Zeroizing;

pub(crate) fn next_clock(previous: u64) -> Result<u64> {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| Error::Invalid("clock precedes epoch"))?
        .as_millis();
    if millis > u128::from(u64::MAX >> 16) {
        return Err(Error::Invalid("hybrid clock overflow"));
    }
    Ok(((millis as u64) << 16).max(
        previous
            .checked_add(1)
            .ok_or(Error::Invalid("hybrid clock overflow"))?,
    ))
}

/// Protect the literal path before taking a lock or letting SQLite interpret it.
/// Symlink parents are resolved, a symlink/hardlink leaf is refused. Unix
/// parents follow the same trusted/sticky ancestry policy as App::open.
fn path(path: &Path, exists: bool) -> Result<(PathBuf, Option<(u64, u64)>)> {
    let absolute = std::path::absolute(path)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let uid = rustix::process::geteuid().as_raw();
        for p in absolute
            .ancestors()
            .skip(1)
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
        {
            let entry = std::fs::symlink_metadata(p)?;
            let meta = std::fs::metadata(p)?;
            if (entry.uid() != 0 && entry.uid() != uid)
                || !meta.is_dir()
                || (meta.uid() != 0 && meta.uid() != uid)
                || (meta.mode() & 0o022 != 0 && meta.mode() & 0o1000 == 0)
            {
                return Err(Error::Invalid("vault directory is replaceable"));
            }
        }
    }
    let path = store::literal(&absolute)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let parent = std::fs::metadata(path.parent().unwrap())?;
        if parent.uid() != rustix::process::geteuid().as_raw() || parent.mode() & 0o1022 != 0 {
            return Err(Error::Invalid("vault parent must be privately controlled"));
        }
    }
    let dir = Dir::open_ambient_dir(path.parent().unwrap(), cap_std::ambient_authority())?;
    let leaf = path.file_name().unwrap();
    for suffix in [".lock", "-wal", "-shm", "-journal"] {
        let mut name = leaf.to_owned();
        name.push(suffix);
        match dir.symlink_metadata(&name) {
            Ok(_) => {
                regular(&dir, &name)?;
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.into()),
        }
    }
    match dir.symlink_metadata(leaf) {
        Ok(m) if !m.is_file() || m.is_symlink() => {
            Err(Error::Invalid("vault must be an unaliased regular file"))
        }
        Ok(_) => {
            if !exists {
                return Err(Error::Invalid("vault already exists"));
            }
            let identity = regular(&dir, leaf)?;
            Ok((path, Some(identity)))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound && !exists => Ok((path, None)),
        Err(e) => Err(e.into()),
    }
}

fn regular(dir: &Dir, name: &std::ffi::OsStr) -> Result<(u64, u64)> {
    let before = dir.symlink_metadata(name)?;
    if !before.is_file() || before.is_symlink() {
        return Err(Error::Invalid("unsafe vault file or sidecar"));
    }
    let file = dir.open_with(
        name,
        OpenOptions::new().read(true).follow(FollowSymlinks::No),
    )?;
    let meta = file.metadata()?;
    if !meta.is_file() || meta.nlink() != 1 {
        return Err(Error::Invalid("vault files must have one link"));
    }
    let identity = (meta.dev(), meta.ino());
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let m = file.into_std().metadata()?;
        if m.uid() != rustix::process::geteuid().as_raw() || m.mode() & 0o022 != 0 {
            return Err(Error::Invalid("vault file is not privately controlled"));
        }
    }
    Ok(identity)
}

pub(crate) fn open_locked(input: &Path) -> Result<Store> {
    let (path, _) = path(input, true)?;
    let lock = store::locking(&path)?;
    Store::encrypted(store::connect(&path, false)?, path, lock)
}

fn take<'a>(bytes: &mut &'a [u8], n: usize) -> Result<&'a [u8]> {
    if n > bytes.len() {
        return Err(Error::Invalid("invalid private metadata"));
    }
    let (head, tail) = bytes.split_at(n);
    *bytes = tail;
    Ok(head)
}
fn size(bytes: &mut &[u8]) -> Result<usize> {
    Ok(u32::from_be_bytes(take(bytes, 4)?.try_into().unwrap()) as usize)
}
fn metadata_entries<'a>(
    mut bytes: &'a [u8],
    mut visit: impl FnMut(&'a str, &'a [u8]),
) -> Result<()> {
    if bytes.len() > MAX_PLAINTEXT || take(&mut bytes, 5)? != b"OWPM\x01" {
        return Err(Error::Invalid("invalid private metadata"));
    }
    let count = size(&mut bytes)?;
    if count > 65536 {
        return Err(openward_crypto::Error::Limit.into());
    }
    let mut previous = None;
    for _ in 0..count {
        let n = size(&mut bytes)?;
        if n > 4096 {
            return Err(openward_crypto::Error::Limit.into());
        }
        let name = std::str::from_utf8(take(&mut bytes, n)?)
            .map_err(|_| Error::Invalid("invalid metadata name"))?;
        if previous.is_some_and(|p| p >= name) {
            return Err(Error::Invalid("duplicate or unordered metadata"));
        }
        previous = Some(name);
        let n = size(&mut bytes)?;
        let value = take(&mut bytes, n)?;
        visit(name, value);
    }
    if !bytes.is_empty() {
        return Err(Error::Invalid("trailing metadata bytes"));
    }
    Ok(())
}
pub(crate) fn validate_metadata(bytes: &[u8]) -> Result<()> {
    metadata_entries(bytes, |_, _| {})
}
pub(crate) fn metadata_value(bytes: &[u8], name: &str) -> Result<Option<Zeroizing<Vec<u8>>>> {
    let mut out = None;
    metadata_entries(bytes, |key, value| {
        if key == name {
            out = Some(Zeroizing::new(value.to_vec()));
        }
    })?;
    Ok(out)
}
fn private_metadata(source: Option<&Connection>) -> Result<Zeroizing<Vec<u8>>> {
    let mut out = Zeroizing::new(b"OWPM\x01\0\0\0\0".to_vec());
    let mut count = 0u32;
    if let Some(source) = source {
        let mut stmt=source.prepare("SELECT CASE WHEN length(CAST(key AS BLOB))<=4096 THEN key END,CASE WHEN length(value)<=?1 THEN value END FROM meta WHERE key NOT IN ('vault_id','device_id') ORDER BY key")?;
        let mut rows = stmt.query([MAX_PLAINTEXT as i64])?;
        while let Some(r) = rows.next()? {
            let name = Zeroizing::new(
                r.get::<_, Option<String>>(0)?
                    .ok_or(openward_crypto::Error::Limit)?,
            );
            let value = Zeroizing::new(
                r.get::<_, Option<Vec<u8>>>(1)?
                    .ok_or(openward_crypto::Error::Limit)?,
            );
            if name.len() > 4096
                || out
                    .len()
                    .saturating_add(name.len())
                    .saturating_add(value.len())
                    .saturating_add(8)
                    > MAX_PLAINTEXT
                || count == 65536
            {
                return Err(openward_crypto::Error::Limit.into());
            }
            out.extend((name.len() as u32).to_be_bytes());
            out.extend(name.as_bytes());
            out.extend((value.len() as u32).to_be_bytes());
            out.extend(value.as_slice());
            count += 1;
        }
    }
    out[5..9].copy_from_slice(&count.to_be_bytes());
    validate_metadata(&out)?;
    Ok(out)
}

fn check_schema(source: &Connection) -> Result<()> {
    let other:i64=source.query_row("SELECT count(*) FROM sqlite_schema WHERE substr(name,1,7) != 'sqlite_' AND NOT(type='table' AND name IN ('meta','items'))",[],|r|r.get(0))?;
    if other != 0 {
        return Err(Error::Invalid("unsupported legacy database objects"));
    }
    for (table, expected) in [
        ("meta", vec!["key", "value"]),
        ("items", vec!["vault_id", "item_id", "head_rev", "envelope"]),
    ] {
        // table_info omits generated/hidden columns and could discard their
        // values while claiming a successful complete migration.
        let mut stmt = source.prepare(&format!("PRAGMA table_xinfo({table})"))?;
        let actual = stmt
            .query_map([], |r| Ok((r.get::<_, String>(1)?, r.get::<_, i64>(6)?)))?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        if actual
            != expected
                .into_iter()
                .map(|name| (name.to_owned(), 0))
                .collect::<Vec<_>>()
        {
            return Err(Error::Invalid("unsupported legacy columns"));
        }
    }
    Ok(())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Phase {
    Staged,
    Verified,
    BeforeInstall,
    Installed,
}
fn checkpoint(source: &Connection) -> Result<()> {
    let (busy, _, _): (i64, i64, i64) =
        source.query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?))
        })?;
    if busy != 0 {
        return Err(Error::Invalid("another SQLite reader prevents migration"));
    }
    let mode: String = source.query_row("PRAGMA journal_mode=DELETE", [], |r| r.get(0))?;
    if mode.to_lowercase() != "delete" {
        return Err(Error::Invalid("cannot close legacy WAL"));
    }
    Ok(())
}
fn sync_parent(path: &Path) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        std::fs::File::open(path.parent().unwrap())?.sync_all()
    }
    #[cfg(not(unix))]
    {
        let _ = path;
        Ok(())
    }
}

pub(crate) fn create(path: &Path, password: &[u8], params: KdfParams) -> Result<LockedVault> {
    install(path, password, params, false, |_| Ok(()))
}
pub(crate) fn migrate(path: &Path, password: &[u8], params: KdfParams) -> Result<LockedVault> {
    install(path, password, params, true, |_| Ok(()))
}

pub(crate) fn install(
    input: &Path,
    password: &[u8],
    params: KdfParams,
    migrate: bool,
    phase: impl FnMut(Phase) -> Result<()>,
) -> Result<LockedVault> {
    install_with_recovery(input, password, params, migrate, None, phase)
}

pub(crate) fn install_with_recovery(
    input: &Path,
    password: &[u8],
    params: KdfParams,
    migrate: bool,
    recovery: Option<&openward_crypto::unlock::RecoveryKit>,
    mut phase: impl FnMut(Phase) -> Result<()>,
) -> Result<LockedVault> {
    let (path, identity) = path(input, migrate)?;
    let lock = store::locking(&path)?;
    let source = if migrate {
        let c = store::connect(&path, false)?;
        let exclusive: String = c.query_row("PRAGMA locking_mode=EXCLUSIVE", [], |r| r.get(0))?;
        if exclusive.to_lowercase() != "exclusive" {
            return Err(Error::Invalid("cannot exclusively migrate the database"));
        }
        c.execute_batch("BEGIN EXCLUSIVE")?;
        let version: i64 = c.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if version != 1 {
            return Err(if version > 3 {
                Error::NewerFormat(version)
            } else {
                Error::Invalid("migration requires a plaintext format1 vault")
            });
        }
        check_schema(&c)?;
        Some(c)
    } else {
        None
    };
    let vault = match &source {
        Some(c) => store::id(c, "vault_id")?,
        None => ItemId::new(),
    };
    let device = match &source {
        Some(c) => store::id(c, "device_id")?,
        None => ItemId::new(),
    };
    let (header, keys) = VaultHeader::create(
        *vault.as_bytes(),
        *device.as_bytes(),
        password,
        params,
        KemSuite::XWingDraft06Pq05,
    )?;
    let private = private_metadata(source.as_ref())?;
    let stage = tempfile::Builder::new()
        .prefix(".openward-encrypted-")
        .suffix(".tmp")
        .tempfile_in(path.parent().unwrap())?;
    let mut target = store::connect(stage.path(), false)?;
    target.pragma_update(None, "synchronous", "FULL")?;
    let tx = target.transaction()?;
    tx.execute_batch(SCHEMA)?;
    let meta = Envelope::seal(
        Header {
            vault: *vault.as_bytes(),
            item: [0; 16],
            device: *device.as_bytes(),
            key_gen: 1,
            parents: vec![],
        },
        &private,
        &keys.vault.metadata_key()?,
        keys.device.signer(),
    )?;
    tx.execute(
        "INSERT INTO meta VALUES ('vault_id',?1),('device_id',?2),(?3,?4),(?5,?6)",
        params![
            vault.as_bytes().as_slice(),
            device.as_bytes().as_slice(),
            CRYPTO,
            header.to_bytes(),
            PRIVATE,
            meta.to_bytes()
        ],
    )?;
    if let Some(kit) = recovery {
        // All factors, the locally sealed kit and the portable D0-1 package
        // are verified and committed inside the staged encrypted database.
        crate::recovery::CredentialUpdate::prepare(
            header.clone(),
            &keys,
            password,
            params,
            kit,
            false,
        )?
        .write(&tx)?;
    }
    let mut count = 0usize;
    let mut clock = 0;
    if let Some(source) = &source {
        let mut stmt=source.prepare("SELECT CASE WHEN length(vault_id)=16 THEN vault_id END,CASE WHEN length(item_id)=16 THEN item_id END,head_rev,CASE WHEN length(envelope)<=?1 THEN envelope END FROM items")?;
        let mut rows = stmt.query([(MAX_PLAINTEXT + 128) as i64])?;
        while let Some(row) = rows.next()? {
            let v: Option<Vec<u8>> = row.get(0)?;
            let id: Option<Vec<u8>> = row.get(1)?;
            let rev: i64 = row.get(2)?;
            let v = v.ok_or(Error::Invalid("invalid legacy vault id"))?;
            let id = id.ok_or(Error::Invalid("invalid legacy item id"))?;
            if v.as_slice() != vault.as_bytes() || rev < 0 {
                return Err(Error::Invalid("foreign or invalid legacy row"));
            }
            let legacy = Zeroizing::new(
                row.get::<_, Option<Vec<u8>>>(3)?
                    .ok_or(openward_crypto::Error::Limit)?,
            );
            let raw = plaintext::legacy_body(&legacy)?;
            clock = next_clock(clock)?;
            let clear = Zeroizing::new(plaintext::snapshot(raw, clock)?);
            let encrypted = Envelope::seal(
                Header {
                    vault: *vault.as_bytes(),
                    item: id.as_slice().try_into().unwrap(),
                    device: *device.as_bytes(),
                    key_gen: 1,
                    parents: vec![],
                },
                &clear,
                &keys.vault,
                keys.device.signer(),
            )?;
            // Verify each authenticated plaintext byte before it enters the staged database.
            let opened = Envelope::open_received(
                &encrypted.to_bytes(),
                encrypted.header().slot(),
                &keys.vault,
                &keys.device.signer().verifying_key(),
            )?;
            if plaintext::body(&opened)?.1 != raw {
                return Err(Error::Invalid("migration verification mismatch"));
            }
            tx.execute(
                "INSERT INTO items VALUES (?1,?2,?3,?4)",
                params![v, id, rev, encrypted.to_bytes()],
            )?;
            count += 1;
        }
    }
    tx.pragma_update(None, "user_version", 2)?;
    tx.commit()?;
    phase(Phase::Staged)?;
    verify(&target, source.as_ref(), &header, &keys, &private, count)?;
    phase(Phase::Verified)?;
    target.close().map_err(|(_, e)| Error::Sql(e))?;
    stage.as_file().sync_all()?;
    if let Some(source) = source {
        source.execute_batch("ROLLBACK")?;
        checkpoint(&source)?;
        source.close().map_err(|(_, e)| Error::Sql(e))?;
        // A clean DELETE-mode source no longer needs old WAL/PERSIST files.
        // Refuse unsafe aliases before removing any lingering managed entry.
        let dir = Dir::open_ambient_dir(path.parent().unwrap(), cap_std::ambient_authority())?;
        for suffix in ["-wal", "-shm", "-journal"] {
            let mut name = path.file_name().unwrap().to_owned();
            name.push(suffix);
            match dir.symlink_metadata(&name) {
                Ok(_) => {
                    regular(&dir, &name)?;
                    dir.remove_file(name)?;
                }
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                Err(e) => return Err(e.into()),
            }
        }
    }
    phase(Phase::BeforeInstall)?;
    if migrate {
        let (_, fresh) = self::path(&path, true)?;
        if fresh != identity {
            return Err(Error::Invalid("legacy file changed during migration"));
        }
    }
    let persisted = if migrate {
        stage.persist(&path)
    } else {
        stage.persist_noclobber(&path)
    };
    let file = persisted.map_err(|e| e.error)?;
    drop(file);
    phase(Phase::Installed)
        .and_then(|_| sync_parent(&path).map_err(Error::Io))
        .map_err(|e| Error::MigrationInstalled(e.to_string()))?;
    let conn =
        store::connect(&path, false).map_err(|e| Error::MigrationInstalled(e.to_string()))?;
    let store =
        Store::encrypted(conn, path, lock).map_err(|e| Error::MigrationInstalled(e.to_string()))?;
    Ok(LockedVault { store })
}

fn verify(
    target: &Connection,
    source: Option<&Connection>,
    header: &VaultHeader,
    keys: &UnlockedKeys,
    private: &[u8],
    count: usize,
) -> Result<()> {
    let check: String = target.query_row("PRAGMA integrity_check", [], |r| r.get(0))?;
    if check != "ok" {
        return Err(Error::Invalid("staged database integrity check failed"));
    }
    let bytes: Vec<u8> =
        target.query_row("SELECT value FROM meta WHERE key=?1", [PRIVATE], |r| {
            r.get(0)
        })?;
    let actual = Envelope::open_received(
        &bytes,
        Slot {
            vault: header.vault_id(),
            item: [0; 16],
            key_gen: 1,
        },
        &keys.vault.metadata_key()?,
        &keys.device.signer().verifying_key(),
    )?;
    if actual.as_slice() != private {
        return Err(Error::Invalid("private metadata verification mismatch"));
    }
    let target_count: i64 = target.query_row("SELECT count(*) FROM items", [], |r| r.get(0))?;
    if target_count as usize != count {
        return Err(Error::Invalid("migration row count mismatch"));
    }
    let mut stmt = target.prepare("SELECT item_id,head_rev,envelope FROM items")?;
    let mut rows = stmt.query([])?;
    while let Some(r) = rows.next()? {
        let id: Vec<u8> = r.get(0)?;
        let rev: i64 = r.get(1)?;
        let bytes: Vec<u8> = r.get(2)?;
        let clear = Envelope::open_received(
            &bytes,
            Slot {
                vault: header.vault_id(),
                item: id
                    .as_slice()
                    .try_into()
                    .map_err(|_| Error::Invalid("invalid staged id"))?,
                key_gen: 1,
            },
            &keys.vault,
            &keys.device.signer().verifying_key(),
        )?;
        let (old_rev, legacy): (i64, Vec<u8>) = source
            .ok_or(Error::Invalid("unexpected item in new vault"))?
            .query_row(
                "SELECT head_rev,envelope FROM items WHERE item_id=?1",
                [id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )?;
        let legacy = Zeroizing::new(legacy);
        if rev != old_rev || plaintext::body(&clear)?.1 != plaintext::legacy_body(&legacy)? {
            return Err(Error::Invalid("staged row verification mismatch"));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests;
