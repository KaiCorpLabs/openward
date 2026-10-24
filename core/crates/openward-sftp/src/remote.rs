//! A server's files over SFTP (version 3, with OpenSSH's extensions when
//! the server has them).

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use russh_sftp::client::rawsession::Limits;
use russh_sftp::client::{Config, RawSftpSession};
use russh_sftp::protocol::{FileAttributes, OpenFlags, StatusCode};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::task::JoinSet;

use crate::entry::{Entry, Kind, kind};
use crate::{Error, Result, is_name, join};

/// The most a request reads or writes: what OpenSSH's `sftp-server` takes
/// (its `limits@openssh.com` says 255 KiB), within russh-sftp's 256 KiB
/// packets.
const MAX_CHUNK: u32 = 255 * 1024;
/// Without the limits extension: what every server must take.
const SAFE_CHUNK: u32 = 32 * 1024;
/// Seconds a request may wait for its answer. Generous: with a slow link
/// and a full pipeline, the last request waits for all the others.
const REQUEST_TIMEOUT: u64 = 60;

pub struct Remote {
    pub(crate) raw: Arc<RawSftpSession>,
    posix_rename: bool,
    pub(crate) read_len: u32,
    pub(crate) write_len: u32,
    home: String,
}

impl Remote {
    /// Starts SFTP on `stream` (the subsystem channel).
    pub async fn open<S>(stream: S) -> Result<Arc<Self>>
    where
        S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    {
        let lost = |e| Error::sftp("sftp", e);
        let mut raw = RawSftpSession::new_with_config(
            stream,
            Config {
                request_timeout_secs: REQUEST_TIMEOUT,
                ..Config::default()
            },
        );
        let version = raw.init().await.map_err(lost)?;
        let has = |name: &str, v: &str| version.extensions.get(name).is_some_and(|x| x == v);
        let (mut read_len, mut write_len) = (SAFE_CHUNK, SAFE_CHUNK);
        if has(russh_sftp::extensions::LIMITS, "1") {
            let limits = raw.limits().await.map_err(lost)?;
            let cap = |n: u64| {
                if n == 0 {
                    MAX_CHUNK
                } else {
                    n.min(u64::from(MAX_CHUNK)) as u32
                }
            };
            read_len = cap(limits.max_read_len);
            write_len = cap(limits.max_write_len);
            raw.set_limits(Limits::from(limits));
        }
        let home = match raw.realpath(".").await {
            Ok(name) => name.files.into_iter().next().map(|f| f.filename),
            Err(_) => None,
        }
        .unwrap_or_else(|| "/".to_owned());
        Ok(Arc::new(Self {
            raw: Arc::new(raw),
            posix_rename: has("posix-rename@openssh.com", "1"),
            read_len,
            write_len,
            home,
        }))
    }

    /// Where the server starts (the user's home, usually).
    pub fn home(&self) -> &str {
        &self.home
    }

    /// The absolute form of `path`, `..` and links resolved.
    pub async fn realpath(&self, path: &str) -> Result<String> {
        let name = self
            .raw
            .realpath(path)
            .await
            .map_err(|e| Error::sftp(path, e))?;
        name.files
            .into_iter()
            .next()
            .map(|f| f.filename)
            .ok_or_else(|| Error::NotFound(path.to_owned()))
    }

    /// What is in a directory, `.` and `..` left out, in no order. Links
    /// say where they point and whether that is a directory. A name that
    /// is a path (`a/b`, `../x`) is left out too: only a hostile server
    /// sends one.
    pub async fn list(&self, dir: &str) -> Result<Vec<Entry>> {
        let err = |e| Error::sftp(dir, e);
        let handle = self.raw.opendir(dir).await.map_err(err)?.handle;
        let mut out = Vec::new();
        let result = loop {
            match self.raw.readdir(handle.as_str()).await {
                Ok(name) => {
                    for f in name.files {
                        // `.`, `..`, and names no server should send.
                        if !is_name(&f.filename) {
                            continue;
                        }
                        out.push(Entry::remote(f.filename, &f.longname, &f.attrs));
                    }
                }
                Err(russh_sftp::client::error::Error::Status(s))
                    if s.status_code == StatusCode::Eof =>
                {
                    break Ok(());
                }
                Err(e) => break Err(err(e)),
            }
        };
        let _ = self.raw.close(handle).await;
        result?;
        self.follow_links(dir, &mut out).await;
        Ok(out)
    }

    /// Fills in where links point, asking about all of them at once.
    async fn follow_links(&self, dir: &str, entries: &mut [Entry]) {
        let mut asks = JoinSet::new();
        for (i, e) in entries.iter().enumerate() {
            if e.kind != Kind::Link {
                continue;
            }
            let raw = Arc::clone(&self.raw);
            let path = join(dir, &e.name);
            asks.spawn(async move {
                let target = raw
                    .readlink(path.as_str())
                    .await
                    .ok()
                    .and_then(|n| n.files.into_iter().next())
                    .map(|f| f.filename);
                let to = raw.stat(path.as_str()).await.ok().map(|a| a.attrs);
                (i, target, to)
            });
        }
        while let Some(Ok((i, target, to))) = asks.join_next().await {
            let e = &mut entries[i];
            e.link_target = target;
            if let Some(attrs) = to {
                e.link_dir = kind(&attrs) == Kind::Dir;
                e.size = attrs.size.unwrap_or(0);
            }
        }
    }

    /// The entry at `path`, links followed; `None` if there is nothing.
    pub async fn stat(&self, path: &str) -> Result<Option<Entry>> {
        self.attrs(path, true).await
    }

    /// The entry at `path` itself, links not followed.
    pub async fn lstat(&self, path: &str) -> Result<Option<Entry>> {
        self.attrs(path, false).await
    }

    /// The user and group ids `path` itself belongs to, when the server
    /// says; `None` if there is nothing.
    pub async fn owner_ids(&self, path: &str) -> Result<Option<(u32, u32)>> {
        match self.raw.lstat(path).await {
            Ok(a) => Ok(a.attrs.uid.zip(a.attrs.gid)),
            Err(e) => match Error::sftp(path, e) {
                Error::NotFound(_) => Ok(None),
                e => Err(e),
            },
        }
    }

    async fn attrs(&self, path: &str, follow: bool) -> Result<Option<Entry>> {
        let r = if follow {
            self.raw.stat(path).await
        } else {
            self.raw.lstat(path).await
        };
        match r {
            Ok(a) => Ok(Some(Entry::remote(
                crate::file_name(path).to_owned(),
                "",
                &a.attrs,
            ))),
            Err(e) => match Error::sftp(path, e) {
                Error::NotFound(_) => Ok(None),
                e => Err(e),
            },
        }
    }

    pub async fn mkdir(&self, path: &str) -> Result<()> {
        match self.raw.mkdir(path, FileAttributes::empty()).await {
            Ok(_) => Ok(()),
            // Servers answer a plain "failure" when it exists: say so.
            Err(e) => match self.lstat(path).await {
                Ok(Some(_)) => Err(Error::Exists(path.to_owned())),
                _ => Err(Error::sftp(path, e)),
            },
        }
    }

    /// Renames `from` to `to`. With `overwrite`, an existing `to` is
    /// replaced, at once where the server can (`posix-rename`).
    pub async fn rename(&self, from: &str, to: &str, overwrite: bool) -> Result<()> {
        if overwrite && self.posix_rename {
            let mut data = Vec::with_capacity(8 + from.len() + to.len());
            for s in [from, to] {
                data.extend_from_slice(&(s.len() as u32).to_be_bytes());
                data.extend_from_slice(s.as_bytes());
            }
            let reply = self
                .raw
                .extended("posix-rename@openssh.com", data)
                .await
                .map_err(|e| Error::sftp(to, e))?;
            return match reply {
                russh_sftp::protocol::Packet::Status(s) if s.status_code == StatusCode::Ok => {
                    Ok(())
                }
                russh_sftp::protocol::Packet::Status(s) => {
                    Err(Error::sftp(to, russh_sftp::client::error::Error::Status(s)))
                }
                _ => Err(Error::Other(format!("{to}: unexpected answer to rename"))),
            };
        }
        let rename = |from: String, to: String| async move {
            self.raw
                .rename(from.clone(), to)
                .await
                .map(|_| ())
                .map_err(|e| Error::sftp(&from, e))
        };
        if self.lstat(to).await?.is_none() {
            return rename(from.into(), to.into()).await;
        }
        if !overwrite {
            return Err(Error::Exists(to.to_owned()));
        }
        // Without `posix-rename`: the old one is set aside, not deleted,
        // until the new one is in its place, and comes back if it cannot be.
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos());
        let aside = format!("{to}.ow-{nanos:x}.old");
        rename(to.into(), aside.clone()).await?;
        match rename(from.into(), to.into()).await {
            Ok(()) => {
                let _ = self.remove_file(&aside).await;
                Ok(())
            }
            Err(e) => {
                let _ = rename(aside, to.into()).await;
                Err(e)
            }
        }
    }

    pub async fn remove_file(&self, path: &str) -> Result<()> {
        self.raw
            .remove(path)
            .await
            .map(|_| ())
            .map_err(|e| Error::sftp(path, e))
    }

    /// Removes `path`: a file, a link (not what it points to) or a
    /// directory with everything in it.
    pub async fn remove(&self, path: &str) -> Result<()> {
        match self.lstat(path).await? {
            None => Ok(()),
            Some(e) if e.kind == Kind::Dir => {
                for child in self.list(path).await? {
                    Box::pin(self.remove(&join(path, &child.name))).await?;
                }
                self.raw
                    .rmdir(path)
                    .await
                    .map(|_| ())
                    .map_err(|e| Error::sftp(path, e))
            }
            Some(_) => self.remove_file(path).await,
        }
    }

    /// Sets the permission bits of `path`. With `recursive`, also of all it
    /// holds; files keep execute only if they had it (`chmod -R` with `X`).
    pub async fn chmod(&self, path: &str, mode: u32, recursive: bool) -> Result<u64> {
        let Some(top) = self.lstat(path).await? else {
            return Err(Error::NotFound(path.to_owned()));
        };
        let mut changed = 0;
        self.set_mode(path, mode).await?;
        changed += 1;
        if recursive && top.kind == Kind::Dir {
            changed += Box::pin(self.chmod_inside(path, mode)).await?;
        }
        Ok(changed)
    }

    async fn chmod_inside(&self, dir: &str, mode: u32) -> Result<u64> {
        let mut changed = 0;
        for e in self.list(dir).await? {
            let path = join(dir, &e.name);
            match e.kind {
                Kind::Dir => {
                    self.set_mode(&path, mode).await?;
                    changed += 1 + Box::pin(self.chmod_inside(&path, mode)).await?;
                }
                Kind::File => {
                    let had_x = e.mode.unwrap_or(0) & 0o111 != 0;
                    let m = if had_x { mode } else { mode & !0o111 };
                    self.set_mode(&path, m).await?;
                    changed += 1;
                }
                // Links have no permissions of their own.
                Kind::Link | Kind::Other => {}
            }
        }
        Ok(changed)
    }

    /// Sets the permission bits and the modification time (seconds since
    /// the epoch; access time too, as SFTP sets them together) in one go.
    pub(crate) async fn set_attrs(
        &self,
        path: &str,
        mode: Option<u32>,
        modified: Option<i64>,
    ) -> Result<()> {
        let time = modified.and_then(|t| u32::try_from(t).ok());
        if mode.is_none() && time.is_none() {
            return Ok(());
        }
        self.raw
            .setstat(
                path,
                FileAttributes {
                    permissions: mode.map(|m| m & 0o7777),
                    atime: time,
                    mtime: time,
                    ..FileAttributes::empty()
                },
            )
            .await
            .map(|_| ())
            .map_err(|e| Error::sftp(path, e))
    }

    pub(crate) async fn set_mode(&self, path: &str, mode: u32) -> Result<()> {
        self.raw
            .setstat(
                path,
                FileAttributes {
                    permissions: Some(mode & 0o7777),
                    ..FileAttributes::empty()
                },
            )
            .await
            .map(|_| ())
            .map_err(|e| Error::sftp(path, e))
    }

    /// Everything under `dir`, depth first: (path relative to `dir`, entry),
    /// directories before what they hold. Links to directories are not
    /// followed (they could loop); links to files count as the file.
    pub async fn walk(&self, dir: &str) -> Result<Vec<(String, Entry)>> {
        let mut out = Vec::new();
        let mut stack = vec![String::new()];
        while let Some(rel) = stack.pop() {
            let abs = if rel.is_empty() {
                dir.to_owned()
            } else {
                join(dir, &rel)
            };
            let mut entries = self.list(&abs).await?;
            entries.sort_by(|a, b| a.name.cmp(&b.name));
            for e in entries {
                let r = join(&rel, &e.name);
                match e.kind {
                    Kind::Dir => {
                        stack.push(r.clone());
                        out.push((r, e));
                    }
                    Kind::File => out.push((r, e)),
                    Kind::Link if !e.link_dir => out.push((r, e)),
                    _ => {}
                }
            }
        }
        Ok(out)
    }

    /// A small file, all of it; `None` when it is not there. One larger
    /// than `limit` bytes is an error, not read.
    pub async fn read_small(&self, path: &str, limit: u64) -> Result<Option<Vec<u8>>> {
        let handle = match self.open_read(path).await {
            Ok(h) => h,
            Err(Error::NotFound(_)) => return Ok(None),
            Err(e) => return Err(e),
        };
        let mut out = Vec::new();
        let result = loop {
            match self
                .raw
                .read(handle.clone(), out.len() as u64, self.read_len)
                .await
            {
                Ok(d) if d.data.is_empty() => break Ok(()),
                Ok(d) => {
                    out.extend_from_slice(&d.data);
                    if out.len() as u64 > limit {
                        break Err(Error::Other(format!("{path}: larger than {limit} bytes")));
                    }
                }
                Err(russh_sftp::client::error::Error::Status(s))
                    if s.status_code == StatusCode::Eof =>
                {
                    break Ok(());
                }
                Err(e) => break Err(Error::sftp(path, e)),
            }
        };
        let closed = self.close(path, handle).await;
        result?;
        closed?;
        Ok(Some(out))
    }

    /// Writes `data` as the whole of `path`, created with `mode` if new.
    pub async fn write_all(&self, path: &str, data: &[u8], mode: u32) -> Result<()> {
        let handle = self.open_write(path, true, Some(mode)).await?;
        let mut at = 0u64;
        let mut result = Ok(());
        for chunk in data.chunks(self.write_len as usize) {
            if let Err(e) = self.raw.write(handle.clone(), at, chunk.to_vec()).await {
                result = Err(Error::sftp(path, e));
                break;
            }
            at += chunk.len() as u64;
        }
        let closed = self.close(path, handle).await;
        result?;
        closed
    }

    pub(crate) async fn open_read(&self, path: &str) -> Result<String> {
        self.raw
            .open(path, OpenFlags::READ, FileAttributes::empty())
            .await
            .map(|h| h.handle)
            .map_err(|e| Error::sftp(path, e))
    }

    /// Opens `path` for writing, created with `mode` if new; `truncate`
    /// empties it, otherwise writing goes on from an offset.
    pub(crate) async fn open_write(
        &self,
        path: &str,
        truncate: bool,
        mode: Option<u32>,
    ) -> Result<String> {
        let mut flags = OpenFlags::WRITE | OpenFlags::CREATE;
        if truncate {
            flags |= OpenFlags::TRUNCATE;
        }
        let attrs = FileAttributes {
            permissions: mode.map(|m| m & 0o7777),
            ..FileAttributes::empty()
        };
        self.raw
            .open(path, flags, attrs)
            .await
            .map(|h| h.handle)
            .map_err(|e| Error::sftp(path, e))
    }

    pub(crate) async fn close(&self, path: &str, handle: String) -> Result<()> {
        self.raw
            .close(handle)
            .await
            .map(|_| ())
            .map_err(|e| Error::sftp(path, e))
    }
}
