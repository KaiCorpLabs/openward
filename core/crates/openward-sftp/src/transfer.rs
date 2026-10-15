//! The transfer queue. Each job copies a file or a folder one way; a few
//! run at once, the rest wait their turn.
//!
//! A file is written under its name plus `.part` and renamed when its size
//! checks out, so the real name never holds half a file. A job that stops
//! (paused, or the connection dropped) keeps that `.part` and the files it
//! finished; resuming goes on from where it was. Uploads rewrite the last
//! [`RESUME_OVERLAP`] bytes they had sent, in case the end of what the
//! server wrote was not what it acknowledged. Copies keep the date the
//! file had.
//!
//! The UI asks for [`Transfers::jobs`] as often as it repaints; nothing is
//! pushed to it.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use tokio::runtime::Handle;
use tokio::task::AbortHandle;

use crate::entry::{Entry, Kind};
use crate::remote::Remote;
use crate::{Error, Result, join, local, pipe};

/// Jobs running at once.
const PARALLEL: usize = 2;
/// Bytes rewritten before where an upload stopped.
pub const RESUME_OVERLAP: u64 = 16 << 20;
/// The suffix of a file being written.
pub const PART: &str = ".part";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Direction {
    Upload,
    Download,
}

/// What to do when the destination already has the name.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OnConflict {
    Replace,
    /// Leave it. A folder is skipped whole.
    Skip,
    /// Replace only files older than the one copied.
    Newer,
    /// Copy under a free name: `name (1).ext`.
    KeepBoth,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum JobState {
    Queued,
    Running,
    Paused,
    /// Stopped by an error; it can be resumed.
    Failed,
    Done,
    Cancelled,
}

impl JobState {
    pub fn finished(self) -> bool {
        matches!(self, Self::Done | Self::Cancelled)
    }
}

/// Where a job reaches the server: the SFTP session of a connection, which
/// is replaced when the connection comes back.
pub struct Link {
    label: String,
    remote: Mutex<Option<Connection>>,
}

/// The session, and whatever must live as long as it (the SSH connection
/// it runs on).
type Connection = (Arc<Remote>, Option<Arc<dyn std::any::Any + Send + Sync>>);

impl Link {
    pub fn new(label: impl Into<String>) -> Arc<Self> {
        Arc::new(Self {
            label: label.into(),
            remote: Mutex::new(None),
        })
    }

    pub fn label(&self) -> &str {
        &self.label
    }

    pub fn get(&self) -> Option<Arc<Remote>> {
        lock(&self.remote).as_ref().map(|(r, _)| Arc::clone(r))
    }

    pub fn set(&self, remote: Option<Arc<Remote>>) {
        *lock(&self.remote) = remote.map(|r| (r, None));
    }

    /// Sets the session and keeps `keep` (its connection) alive with it.
    pub fn set_kept(&self, remote: Arc<Remote>, keep: Arc<dyn std::any::Any + Send + Sync>) {
        *lock(&self.remote) = Some((remote, Some(keep)));
    }
}

/// A name the copy would take that the destination already has.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Conflict {
    pub source: String,
    /// What is copied.
    pub ours: Entry,
    /// What is there now.
    pub theirs: Entry,
}

/// Which of `sources` already exist in `dest_dir`, for the UI to ask about
/// before queueing them.
pub async fn conflicts(
    remote: &Remote,
    direction: Direction,
    sources: &[String],
    dest_dir: &str,
) -> Result<Vec<Conflict>> {
    let mut out = Vec::new();
    for source in sources {
        let (ours, theirs) = match direction {
            Direction::Upload => {
                let path = Path::new(source);
                let Some(ours) = local::stat(path)? else {
                    continue;
                };
                let theirs = remote.stat(&join(dest_dir, &ours.name)).await?;
                (ours, theirs)
            }
            Direction::Download => {
                let Some(ours) = remote.stat(source).await? else {
                    continue;
                };
                let name = crate::file_name(source);
                let theirs = local::stat(&Path::new(dest_dir).join(name))?;
                (ours, theirs)
            }
        };
        if let Some(theirs) = theirs {
            out.push(Conflict {
                source: source.clone(),
                ours,
                theirs,
            });
        }
    }
    Ok(out)
}

#[derive(Clone, Debug)]
pub struct Request {
    pub direction: Direction,
    /// A file or folder: a local path to upload, or a remote one to
    /// download.
    pub source: String,
    /// The folder it goes into: remote for uploads, local for downloads.
    pub dest_dir: String,
    pub on_conflict: OnConflict,
}

#[derive(Clone, Debug, PartialEq)]
pub struct JobView {
    pub id: u64,
    pub direction: Direction,
    /// The file or folder's name.
    pub name: String,
    pub source: String,
    pub dest_dir: String,
    /// The connection's label.
    pub host: String,
    pub is_dir: bool,
    /// Files in it (1 for a file); 0 until counted.
    pub files: u32,
    pub files_done: u32,
    /// Left as they were because of the conflict choice.
    pub skipped: u32,
    /// Bytes; 0 until counted.
    pub total: u64,
    pub done: u64,
    /// Bytes per second, while running.
    pub rate: f64,
    pub state: JobState,
    pub error: Option<Error>,
    /// Seconds since the epoch when it ended (done, failed, cancelled).
    pub ended_at: Option<u64>,
}

/// One file or folder of a job, relative to the job's own (`""` is the
/// copied item itself).
#[derive(Clone, Debug)]
struct Item {
    rel: String,
    dir: bool,
    size: u64,
    modified: Option<i64>,
    mode: Option<u32>,
}

/// The `.part` being written, to delete when the job is cancelled.
#[derive(Clone)]
enum Part {
    Remote(String),
    Local(PathBuf),
}

struct Job {
    view: JobView,
    request: Request,
    link: Arc<Link>,
    items: Option<Arc<Vec<Item>>>,
    /// The first item not finished.
    next: usize,
    /// The name it takes at the destination (another with `KeepBoth`).
    dest_name: Option<String>,
    /// Bytes done, updated while running.
    progress: Arc<AtomicU64>,
    part: Option<Part>,
    task: Option<AbortHandle>,
    sample: Option<(Instant, u64)>,
}

struct Inner {
    runtime: Handle,
    jobs: Mutex<Vec<Job>>,
    next_id: AtomicU64,
}

/// The queue, shared by every browser: closing one leaves its transfers
/// running.
#[derive(Clone)]
pub struct Transfers {
    inner: Arc<Inner>,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

impl Transfers {
    /// Jobs run on `runtime`.
    pub fn new(runtime: Handle) -> Self {
        Self {
            inner: Arc::new(Inner {
                runtime,
                jobs: Mutex::new(Vec::new()),
                next_id: AtomicU64::new(1),
            }),
        }
    }

    /// Queues a copy; it starts when there is room.
    pub fn add(&self, link: Arc<Link>, request: Request) -> u64 {
        let id = self.inner.next_id.fetch_add(1, Ordering::Relaxed);
        let name = match request.direction {
            Direction::Upload => Path::new(&request.source)
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| request.source.clone()),
            Direction::Download => crate::file_name(&request.source).to_owned(),
        };
        let view = JobView {
            id,
            direction: request.direction,
            name,
            source: request.source.clone(),
            dest_dir: request.dest_dir.clone(),
            host: link.label().to_owned(),
            is_dir: false,
            files: 0,
            files_done: 0,
            skipped: 0,
            total: 0,
            done: 0,
            rate: 0.0,
            state: JobState::Queued,
            error: None,
            ended_at: None,
        };
        lock(&self.inner.jobs).push(Job {
            view,
            request,
            link,
            items: None,
            next: 0,
            dest_name: None,
            progress: Arc::new(AtomicU64::new(0)),
            part: None,
            task: None,
            sample: None,
        });
        pump(&self.inner);
        id
    }

    /// Every job, oldest first, with its progress now.
    pub fn jobs(&self) -> Vec<JobView> {
        let now = Instant::now();
        let mut jobs = lock(&self.inner.jobs);
        jobs.iter_mut()
            .map(|j| {
                let done = j.progress.load(Ordering::Relaxed);
                j.view.done = done;
                if j.view.state == JobState::Running {
                    match j.sample {
                        Some((at, before)) if now - at >= Duration::from_millis(500) => {
                            let rate =
                                (done.saturating_sub(before)) as f64 / (now - at).as_secs_f64();
                            j.view.rate = if j.view.rate == 0.0 {
                                rate
                            } else {
                                0.6 * j.view.rate + 0.4 * rate
                            };
                            j.sample = Some((now, done));
                        }
                        Some(_) => {}
                        None => j.sample = Some((now, done)),
                    }
                } else {
                    j.view.rate = 0.0;
                    j.sample = None;
                }
                j.view.clone()
            })
            .collect()
    }

    /// Jobs not finished (running, waiting, paused or failed).
    pub fn active(&self) -> usize {
        lock(&self.inner.jobs)
            .iter()
            .filter(|j| !j.view.state.finished())
            .count()
    }

    /// Stops a job, keeping what it has done.
    pub fn pause(&self, id: u64) {
        let mut jobs = lock(&self.inner.jobs);
        if let Some(j) = jobs.iter_mut().find(|j| j.view.id == id)
            && matches!(j.view.state, JobState::Running | JobState::Queued)
        {
            if let Some(t) = j.task.take() {
                t.abort();
            }
            j.view.state = JobState::Paused;
        }
        drop(jobs);
        pump(&self.inner);
    }

    /// Queues a paused or failed job again, to go on where it stopped.
    pub fn resume(&self, id: u64) {
        let mut jobs = lock(&self.inner.jobs);
        if let Some(j) = jobs.iter_mut().find(|j| j.view.id == id)
            && matches!(j.view.state, JobState::Paused | JobState::Failed)
        {
            j.view.state = JobState::Queued;
            j.view.error = None;
            j.view.ended_at = None;
        }
        drop(jobs);
        pump(&self.inner);
    }

    /// Stops a job for good, deleting the `.part` it was writing. What it
    /// finished stays.
    pub fn cancel(&self, id: u64) {
        let mut jobs = lock(&self.inner.jobs);
        if let Some(j) = jobs.iter_mut().find(|j| j.view.id == id)
            && !j.view.state.finished()
        {
            if let Some(t) = j.task.take() {
                t.abort();
            }
            j.view.state = JobState::Cancelled;
            j.view.ended_at = Some(now_secs());
            if let Some(part) = j.part.take() {
                let link = Arc::clone(&j.link);
                self.inner
                    .runtime
                    .spawn(async move { delete_part(&link, part).await });
            }
        }
        drop(jobs);
        pump(&self.inner);
    }

    /// Takes a job off the list; one not finished is cancelled first.
    pub fn remove(&self, id: u64) {
        self.cancel(id);
        lock(&self.inner.jobs).retain(|j| j.view.id != id);
    }

    /// Takes every finished job off the list.
    pub fn clear_finished(&self) {
        lock(&self.inner.jobs).retain(|j| !j.view.state.finished());
    }

    /// Pauses every running or waiting job.
    pub fn pause_all(&self) {
        let ids: Vec<u64> = lock(&self.inner.jobs)
            .iter()
            .filter(|j| matches!(j.view.state, JobState::Running | JobState::Queued))
            .map(|j| j.view.id)
            .collect();
        for id in ids {
            self.pause(id);
        }
    }

    /// Waits until the job stops (finished, paused or failed): for tests
    /// and the command line.
    pub async fn wait(&self, id: u64) -> Option<JobView> {
        loop {
            let view = self.jobs().into_iter().find(|j| j.id == id)?;
            if !matches!(view.state, JobState::Queued | JobState::Running) {
                return Some(view);
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    }
}

async fn delete_part(link: &Link, part: Part) {
    match part {
        Part::Remote(path) => {
            if let Some(remote) = link.get() {
                let _ = remote.remove_file(&path).await;
            }
        }
        Part::Local(path) => {
            let _ = std::fs::remove_file(path);
        }
    }
}

/// Starts waiting jobs while there is room.
fn pump(inner: &Arc<Inner>) {
    let mut jobs = lock(&inner.jobs);
    let mut running = jobs
        .iter()
        .filter(|j| j.view.state == JobState::Running)
        .count();
    for j in jobs.iter_mut() {
        if running >= PARALLEL {
            break;
        }
        if j.view.state != JobState::Queued {
            continue;
        }
        j.view.state = JobState::Running;
        let (id, task_inner) = (j.view.id, Arc::clone(inner));
        let task = inner.runtime.spawn(async move {
            let result = run(&task_inner, id).await;
            finish(&task_inner, id, result);
        });
        j.task = Some(task.abort_handle());
        running += 1;
    }
}

fn finish(inner: &Arc<Inner>, id: u64, result: Result<()>) {
    {
        let mut jobs = lock(&inner.jobs);
        if let Some(j) = jobs.iter_mut().find(|j| j.view.id == id)
            && j.view.state == JobState::Running
        {
            j.task = None;
            j.view.ended_at = Some(now_secs());
            match result {
                Ok(()) => {
                    j.view.state = JobState::Done;
                    j.part = None;
                }
                Err(e) => {
                    j.view.state = JobState::Failed;
                    j.view.error = Some(e);
                }
            }
        }
    }
    pump(inner);
}

/// What `run` needs of a job, taken under the lock.
struct Snapshot {
    request: Request,
    link: Arc<Link>,
    items: Option<Arc<Vec<Item>>>,
    next: usize,
    dest_name: Option<String>,
    progress: Arc<AtomicU64>,
}

fn with_job<T>(inner: &Inner, id: u64, f: impl FnOnce(&mut Job) -> T) -> Option<T> {
    lock(&inner.jobs)
        .iter_mut()
        .find(|j| j.view.id == id)
        .map(f)
}

async fn run(inner: &Arc<Inner>, id: u64) -> Result<()> {
    let Some(s) = with_job(inner, id, |j| Snapshot {
        request: j.request.clone(),
        link: Arc::clone(&j.link),
        items: j.items.clone(),
        next: j.next,
        dest_name: j.dest_name.clone(),
        progress: Arc::clone(&j.progress),
    }) else {
        return Ok(());
    };
    let remote = s.link.get().ok_or(Error::Lost)?;
    let req = &s.request;
    let up = req.direction == Direction::Upload;

    let items = match s.items {
        Some(items) => items,
        None => {
            let items = Arc::new(expand(&remote, req).await?);
            let files = items.iter().filter(|i| !i.dir).count() as u32;
            let total = items.iter().map(|i| i.size).sum();
            with_job(inner, id, |j| {
                j.items = Some(Arc::clone(&items));
                j.view.is_dir = items.first().is_some_and(|i| i.dir);
                j.view.files = files;
                j.view.total = total;
            });
            items
        }
    };

    let dest_name = match s.dest_name {
        Some(name) => name,
        None => {
            let name = with_job(inner, id, |j| j.view.name.clone()).unwrap_or_default();
            let top_dir = items.first().is_some_and(|i| i.dir);
            let exists = dest_exists(&remote, up, &req.dest_dir, &name).await?;
            let name = match (exists, req.on_conflict) {
                (true, OnConflict::KeepBoth) => {
                    free_name(&remote, up, &req.dest_dir, &name).await?
                }
                (true, OnConflict::Skip) if top_dir => {
                    let files = items.iter().filter(|i| !i.dir).count() as u32;
                    with_job(inner, id, |j| {
                        j.view.skipped = files;
                        j.next = items.len();
                    });
                    s.progress
                        .store(items.iter().map(|i| i.size).sum(), Ordering::Relaxed);
                    return Ok(());
                }
                _ => name,
            };
            with_job(inner, id, |j| j.dest_name = Some(name.clone()));
            name
        }
    };

    let mut base: u64 = items[..s.next].iter().map(|i| i.size).sum();
    for (i, item) in items.iter().enumerate().skip(s.next) {
        let src_rel = item.rel.as_str();
        let skipped = if up {
            let src = local_join(Path::new(&req.source), src_rel);
            let dest = join(&req.dest_dir, &rel_join(&dest_name, src_rel));
            upload_item(
                inner,
                id,
                &remote,
                item,
                &src,
                &dest,
                req.on_conflict,
                base,
                &s.progress,
            )
            .await?
        } else {
            let src = rel_join(&req.source, src_rel);
            let dest = local_join(&Path::new(&req.dest_dir).join(&dest_name), src_rel);
            download_item(
                inner,
                id,
                &remote,
                item,
                &src,
                &dest,
                req.on_conflict,
                base,
                &s.progress,
            )
            .await?
        };
        base += item.size;
        s.progress.store(base, Ordering::Relaxed);
        with_job(inner, id, |j| {
            j.next = i + 1;
            j.part = None;
            if !item.dir {
                if skipped {
                    j.view.skipped += 1;
                } else {
                    j.view.files_done += 1;
                }
            }
        });
    }
    Ok(())
}

/// `base` joined with `rel` (`""` is `base` itself).
fn rel_join(base: &str, rel: &str) -> String {
    if rel.is_empty() {
        base.to_owned()
    } else {
        join(base, rel)
    }
}

fn local_join(base: &Path, rel: &str) -> PathBuf {
    rel.split('/')
        .filter(|p| !p.is_empty())
        .fold(base.to_owned(), |p, part| p.join(part))
}

/// The files and folders a request copies, the item itself first.
async fn expand(remote: &Remote, req: &Request) -> Result<Vec<Item>> {
    let item = |rel: String, e: &Entry| Item {
        rel,
        dir: e.kind == Kind::Dir,
        size: if e.kind == Kind::Dir { 0 } else { e.size },
        modified: e.modified,
        mode: e.mode,
    };
    match req.direction {
        Direction::Upload => {
            let path = Path::new(&req.source);
            let top = local::stat(path)?.ok_or_else(|| Error::NotFound(req.source.clone()))?;
            let mut items = vec![item(String::new(), &top)];
            if top.kind == Kind::Dir {
                for (rel, e) in local::walk(path)? {
                    let rel = rel
                        .components()
                        .map(|c| c.as_os_str().to_string_lossy())
                        .collect::<Vec<_>>()
                        .join("/");
                    items.push(item(rel, &e));
                }
            }
            Ok(items)
        }
        Direction::Download => {
            let top = remote
                .stat(&req.source)
                .await?
                .ok_or_else(|| Error::NotFound(req.source.clone()))?;
            let mut items = vec![item(String::new(), &top)];
            if top.kind == Kind::Dir {
                for (rel, e) in remote.walk(&req.source).await? {
                    items.push(item(rel, &e));
                }
            }
            Ok(items)
        }
    }
}

async fn dest_exists(remote: &Remote, up: bool, dir: &str, name: &str) -> Result<bool> {
    if up {
        Ok(remote.lstat(&join(dir, name)).await?.is_some())
    } else {
        Ok(Path::new(dir).join(name).symlink_metadata().is_ok())
    }
}

/// `name (1).ext`, `name (2).ext`… whichever is free.
async fn free_name(remote: &Remote, up: bool, dir: &str, name: &str) -> Result<String> {
    let (stem, ext) = match name.rfind('.') {
        Some(i) if i > 0 => (&name[..i], &name[i..]),
        _ => (name, ""),
    };
    for n in 1.. {
        let candidate = format!("{stem} ({n}){ext}");
        if !dest_exists(remote, up, dir, &candidate).await? {
            return Ok(candidate);
        }
    }
    unreachable!("some name is free")
}

/// Whether `existing` stays, by the conflict choice.
fn keep_existing(on_conflict: OnConflict, existing: &Entry, item: &Item) -> bool {
    match on_conflict {
        OnConflict::Skip => true,
        OnConflict::Newer => match (item.modified, existing.modified) {
            (Some(ours), Some(theirs)) => ours <= theirs,
            _ => true,
        },
        OnConflict::Replace | OnConflict::KeepBoth => false,
    }
}

/// Copies one item up; true if it was left as it was.
#[allow(clippy::too_many_arguments)]
async fn upload_item(
    inner: &Inner,
    id: u64,
    remote: &Remote,
    item: &Item,
    src: &Path,
    dest: &str,
    on_conflict: OnConflict,
    base: u64,
    progress: &AtomicU64,
) -> Result<bool> {
    let existing = remote.stat(dest).await?;
    if item.dir {
        match existing {
            Some(e) if e.is_dir() => {}
            _ => remote.mkdir(dest).await?,
        }
        return Ok(false);
    }
    if let Some(e) = &existing
        && keep_existing(on_conflict, e, item)
    {
        return Ok(true);
    }
    let part = format!("{dest}{PART}");
    with_job(inner, id, |j| j.part = Some(Part::Remote(part.clone())));
    let size = std::fs::metadata(src)
        .map_err(|e| Error::local(src, &e))?
        .len();
    let had = remote
        .lstat(&part)
        .await?
        .map(|e| e.size)
        .filter(|&s| s <= size);
    let offset = had.map_or(0, |s| s.saturating_sub(RESUME_OVERLAP));
    // A replaced file keeps its permissions; a new one gets ours.
    let mode = existing
        .as_ref()
        .and_then(|e| e.mode)
        .or(item.mode)
        .map(|m| m & 0o7777);
    let handle = remote.open_write(&part, had.is_none(), mode).await?;
    progress.store(base + offset, Ordering::Relaxed);
    let mut file = tokio::fs::File::open(src)
        .await
        .map_err(|e| Error::local(src, &e))?;
    let sent = pipe::upload(remote, &part, &handle, &mut file, offset, size, progress).await;
    let closed = remote.close(&part, handle).await;
    sent?;
    closed?;
    let got = remote.lstat(&part).await?.map(|e| e.size);
    if got != Some(size) {
        return Err(Error::Changed(src.display().to_string()));
    }
    // Its date stays the one it had here, so "only if newer" means
    // something next time.
    remote.set_attrs(&part, mode, item.modified).await?;
    remote.rename(&part, dest, true).await?;
    Ok(false)
}

/// Copies one item down; true if it was left as it was.
#[allow(clippy::too_many_arguments)]
async fn download_item(
    inner: &Inner,
    id: u64,
    remote: &Remote,
    item: &Item,
    src: &str,
    dest: &Path,
    on_conflict: OnConflict,
    base: u64,
    progress: &AtomicU64,
) -> Result<bool> {
    let existing = local::stat(dest)?;
    if item.dir {
        match existing {
            Some(e) if e.is_dir() => {}
            _ => local::mkdir(dest)?,
        }
        return Ok(false);
    }
    if let Some(e) = &existing
        && keep_existing(on_conflict, e, item)
    {
        return Ok(true);
    }
    let mut part = dest.as_os_str().to_owned();
    part.push(PART);
    let part = PathBuf::from(part);
    with_job(inner, id, |j| j.part = Some(Part::Local(part.clone())));
    let size = remote
        .stat(src)
        .await?
        .ok_or_else(|| Error::NotFound(src.to_owned()))?
        .size;
    let offset = std::fs::metadata(&part)
        .map(|m| m.len())
        .ok()
        .filter(|&s| s <= size)
        .unwrap_or(0);
    let local_err = |e: std::io::Error| Error::local(&part, &e);
    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(&part)
        .await
        .map_err(local_err)?;
    file.set_len(offset).await.map_err(local_err)?;
    tokio::io::AsyncSeekExt::seek(&mut file, std::io::SeekFrom::Start(offset))
        .await
        .map_err(local_err)?;
    progress.store(base + offset, Ordering::Relaxed);
    let handle = remote.open_read(src).await?;
    let got = pipe::download(remote, src, &handle, &mut file, offset, size, progress).await;
    let _ = remote.close(src, handle).await;
    got?;
    tokio::io::AsyncWriteExt::flush(&mut file)
        .await
        .map_err(local_err)?;
    file.sync_all().await.map_err(local_err)?;
    drop(file);
    let len = std::fs::metadata(&part).map_err(local_err)?.len();
    if len != size {
        return Err(Error::Changed(src.to_owned()));
    }
    set_local_mode(&part, item.mode);
    if let Some(t) = item.modified.and_then(|t| u64::try_from(t).ok()) {
        let file = std::fs::File::options()
            .write(true)
            .open(&part)
            .map_err(local_err)?;
        file.set_modified(UNIX_EPOCH + Duration::from_secs(t))
            .map_err(local_err)?;
    }
    if cfg!(windows) && dest.exists() {
        std::fs::remove_file(dest).map_err(|e| Error::local(dest, &e))?;
    }
    std::fs::rename(&part, dest).map_err(|e| Error::local(dest, &e))?;
    Ok(false)
}

/// A downloaded program stays runnable: execute goes wherever reading is,
/// when the server's copy had it. The rest is left to the local umask.
#[cfg(unix)]
fn set_local_mode(path: &Path, remote_mode: Option<u32>) {
    use std::os::unix::fs::PermissionsExt;
    if remote_mode.unwrap_or(0) & 0o100 == 0 {
        return;
    }
    if let Ok(meta) = std::fs::metadata(path) {
        let mode = meta.permissions().mode();
        let mode = mode | ((mode & 0o444) >> 2);
        let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode));
    }
}

#[cfg(not(unix))]
fn set_local_mode(_: &Path, _: Option<u32>) {}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(modified: Option<i64>) -> Entry {
        Entry {
            name: "x".into(),
            kind: Kind::File,
            link_dir: false,
            link_target: None,
            size: 1,
            modified,
            mode: None,
            owner: None,
            group: None,
        }
    }

    fn item(modified: Option<i64>) -> Item {
        Item {
            rel: String::new(),
            dir: false,
            size: 1,
            modified,
            mode: None,
        }
    }

    #[test]
    fn conflict_choices() {
        let theirs = entry(Some(100));
        assert!(!keep_existing(
            OnConflict::Replace,
            &theirs,
            &item(Some(50))
        ));
        assert!(keep_existing(OnConflict::Skip, &theirs, &item(Some(500))));
        assert!(!keep_existing(OnConflict::Newer, &theirs, &item(Some(101))));
        assert!(keep_existing(OnConflict::Newer, &theirs, &item(Some(100))));
        // Without dates, "newer" cannot be told: nothing is replaced.
        assert!(keep_existing(
            OnConflict::Newer,
            &entry(None),
            &item(Some(1))
        ));
    }

    #[test]
    fn relative_paths() {
        assert_eq!(rel_join("/srv/app", ""), "/srv/app");
        assert_eq!(rel_join("/srv/app", "a/b.txt"), "/srv/app/a/b.txt");
        assert_eq!(
            local_join(Path::new("/tmp/x"), "a/b.txt"),
            Path::new("/tmp/x").join("a").join("b.txt")
        );
        assert_eq!(local_join(Path::new("/tmp/x"), ""), Path::new("/tmp/x"));
    }
}
