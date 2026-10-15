//! A file's bytes with many requests in flight. How many bytes may be
//! waiting for an answer follows the speed measured so far: about two
//! seconds' worth, so a far server gets enough to stay busy and a slow one
//! (Dropbear's 24 KiB window) is not given more than it answers before the
//! request timeout.

use std::collections::VecDeque;
use std::io::SeekFrom;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use russh_sftp::client::error::Error as SftpError;
use russh_sftp::protocol::StatusCode;
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};
use tokio::task::{JoinHandle, JoinSet};

use crate::remote::Remote;
use crate::{Error, Result};

const MIN_WINDOW: u64 = 512 << 10;
const START_WINDOW: u64 = 1 << 20;
const MAX_WINDOW: u64 = 32 << 20;
/// What the window holds: this much time at the measured speed.
const WINDOW_TIME: f64 = 2.0;
/// Before this, the speed says little: keep the starting window.
const SETTLE: Duration = Duration::from_millis(250);

/// The window for `bytes` answered in `elapsed`.
fn window(bytes: u64, elapsed: Duration) -> u64 {
    if elapsed < SETTLE || bytes == 0 {
        return START_WINDOW;
    }
    let rate = bytes as f64 / elapsed.as_secs_f64();
    ((rate * WINDOW_TIME) as u64).clamp(MIN_WINDOW, MAX_WINDOW)
}

/// Sends `local` from `offset` up to `end` to the open remote `handle`.
pub(crate) async fn upload(
    remote: &Remote,
    path: &str,
    handle: &str,
    local: &mut tokio::fs::File,
    offset: u64,
    end: u64,
    progress: &AtomicU64,
) -> Result<()> {
    let changed = |_| Error::Changed(path.to_owned());
    local.seek(SeekFrom::Start(offset)).await.map_err(changed)?;
    let chunk = u64::from(remote.write_len);
    let mut set: JoinSet<Result<u64>> = JoinSet::new();
    let (mut at, mut in_flight, mut answered) = (offset, 0u64, 0u64);
    let started = Instant::now();
    loop {
        let cap = window(answered, started.elapsed());
        while at < end && in_flight < cap {
            let n = chunk.min(end - at);
            let mut buf = vec![0u8; n as usize];
            local.read_exact(&mut buf).await.map_err(changed)?;
            let (raw, handle, path) = (Arc::clone(&remote.raw), handle.to_owned(), path.to_owned());
            set.spawn(async move {
                raw.write(handle, at, buf)
                    .await
                    .map(|_| n)
                    .map_err(|e| Error::sftp(&path, e))
            });
            at += n;
            in_flight += n;
        }
        match set.join_next().await {
            None => return Ok(()),
            Some(Ok(Ok(n))) => {
                in_flight -= n;
                answered += n;
                progress.fetch_add(n, Ordering::Relaxed);
            }
            // Dropping the set cancels the requests still out.
            Some(Ok(Err(e))) => return Err(e),
            Some(Err(e)) => return Err(Error::Other(e.to_string())),
        }
    }
}

/// A read on its way: where, how much, and the answer to come.
type Read = (
    u64,
    u32,
    JoinHandle<std::result::Result<Vec<u8>, SftpError>>,
);

/// Reads still out; dropped (on an error, a pause) they are cancelled.
struct Reads(VecDeque<Read>);

impl Reads {
    fn cancel(&mut self) {
        for (_, _, h) in self.0.drain(..) {
            h.abort();
        }
    }
}

impl Drop for Reads {
    fn drop(&mut self) {
        self.cancel();
    }
}

/// Writes the remote `handle` from `offset` up to `end` into `local`,
/// which is already at `offset`. Answers are written in order.
pub(crate) async fn download(
    remote: &Remote,
    path: &str,
    handle: &str,
    local: &mut tokio::fs::File,
    offset: u64,
    end: u64,
    progress: &AtomicU64,
) -> Result<()> {
    let chunk = remote.read_len;
    let mut reads = Reads(VecDeque::new());
    let (mut next, mut written, mut in_flight) = (offset, offset, 0u64);
    let started = Instant::now();
    loop {
        let cap = window(written - offset, started.elapsed());
        while next < end && in_flight < cap {
            let n = (u64::from(chunk)).min(end - next) as u32;
            let (raw, handle, at) = (Arc::clone(&remote.raw), handle.to_owned(), next);
            reads.0.push_back((
                at,
                n,
                tokio::spawn(async move { raw.read(handle, at, n).await.map(|d| d.data) }),
            ));
            next += u64::from(n);
            in_flight += u64::from(n);
        }
        let Some((at, n, h)) = reads.0.pop_front() else {
            return Ok(());
        };
        let data = match h.await {
            Ok(Ok(data)) if !data.is_empty() => data,
            // The file is shorter than it was: it changed.
            Ok(Ok(_)) => return Err(Error::Changed(path.to_owned())),
            Ok(Err(SftpError::Status(s))) if s.status_code == StatusCode::Eof => {
                return Err(Error::Changed(path.to_owned()));
            }
            Ok(Err(e)) => return Err(Error::sftp(path, e)),
            Err(e) => return Err(Error::Other(e.to_string())),
        };
        debug_assert_eq!(at, written);
        local
            .write_all(&data)
            .await
            .map_err(|e| Error::Other(format!("{path}: {e}")))?;
        written += data.len() as u64;
        in_flight -= u64::from(n);
        progress.fetch_add(data.len() as u64, Ordering::Relaxed);
        if data.len() < n as usize {
            // A short read: what was asked after it starts from the wrong
            // place. Ask again from where this one stopped.
            reads.cancel();
            in_flight = 0;
            next = written;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_window_follows_the_speed() {
        // Too early to tell.
        assert_eq!(window(10 << 20, Duration::from_millis(100)), START_WINDOW);
        // 10 MiB/s: two seconds' worth.
        assert_eq!(window(10 << 20, Duration::from_secs(1)), 20 << 20);
        // Very slow and very fast stay within bounds.
        assert_eq!(window(1000, Duration::from_secs(1)), MIN_WINDOW);
        assert_eq!(window(1 << 30, Duration::from_secs(1)), MAX_WINDOW);
    }
}
