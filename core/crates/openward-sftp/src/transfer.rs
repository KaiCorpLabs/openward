//! The transfer queue. Each job copies a file or a folder one way; a few
//! run at once, the rest wait their turn.
//!
//! A file is written under a `.part` name ([`part_path`]) and renamed when
//! its size checks out, so the real name never holds half a file. A job
//! that stops (paused, or the connection dropped) keeps that `.part` and
//! the files it finished; resuming, or copying the same file again later,
//! goes on from where it was. The part's name says which file it is a copy
//! of, as it was then (its path, size and date): a part of anything else (a
//! browser's `name.part`, an older version of the file) is never resumed
//! nor deleted. Uploads rewrite the last [`RESUME_OVERLAP`] bytes they had
//! sent, in case the end of what the server wrote was not what it
//! acknowledged. Copies keep the date the file had.
//!
//! A job copies [`FILES_AT_ONCE`] of its files at once: with many small
//! ones, what each costs is mostly waiting for the server's answers. A
//! folder is made before anything goes in it. A file in a folder the job
//! has just made asks nothing about its name first (nothing can be there
//! yet, not even a part), and what it wrote is not asked back either: every
//! write was acknowledged. Two names that differ only in case go one after
//! the other, and ask, as with a server (or a Mac) that takes them for one.
//!
//! The names in a download come from the server, and none may lead outside
//! the folder it goes to (`..`; `\` and `:` on Windows).
//!
//! The UI asks for [`Transfers::jobs`] as often as it repaints; nothing is
//! pushed to it.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::task::Poll;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use tokio::runtime::Handle;
use tokio::task::JoinHandle;

use crate::entry::{Entry, Kind};
use crate::remote::Remote;
use crate::{Error, Result, is_name, join, local, pipe};

/// Jobs running at once.
const PARALLEL: usize = 2;
/// Files (and folders) of one job being copied at once.
pub const FILES_AT_ONCE: usize = 8;
/// Bytes rewritten before where an upload stopped.
pub const RESUME_OVERLAP: u64 = 16 << 20;
/// The suffix of a file being written.
pub const PART: &str = ".part";

/// Where a copy of `source` (with this size and date) writes `dest` until
/// it is whole: `dest.ow-<id>.part`, the id naming the source as it is.
pub fn part_path(dest: &str, source: &str, size: u64, modified: Option<i64>) -> String {
    format!("{dest}{}", part_suffix(source, size, modified))
}

fn part_suffix(source: &str, size: u64, modified: Option<i64>) -> String {
    // FNV-1a: the same in every version, so a part outlives an upgrade.
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    let bytes = source
        .bytes()
        .chain(size.to_le_bytes())
        .chain(modified.unwrap_or(i64::MIN).to_le_bytes());
    for b in bytes {
        h = (h ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3);
    }
    format!(".ow-{:08x}{PART}", (h ^ (h >> 32)) as u32)
}

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
    /// Items after `next` already finished: they finish out of order.
    ahead: BTreeSet<usize>,
    /// The name it takes at the destination (another with `KeepBoth`).
    dest_name: Option<String>,
    /// Bytes done, updated while running.
    progress: Arc<AtomicU64>,
    /// The `.part` each item being copied writes, by item.
    parts: BTreeMap<usize, Part>,
    task: Option<JoinHandle<()>>,
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
            ahead: BTreeSet::new(),
            dest_name: None,
            progress: Arc::new(AtomicU64::new(0)),
            parts: BTreeMap::new(),
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
            // Kept: a cancel waits for it to have stopped.
            if let Some(t) = &j.task {
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

    /// Stops a job for good, deleting the `.part`s it was writing. What it
    /// finished stays.
    pub fn cancel(&self, id: u64) {
        let mut jobs = lock(&self.inner.jobs);
        if let Some(j) = jobs.iter_mut().find(|j| j.view.id == id)
            && !j.view.state.finished()
        {
            let task = j.task.take();
            if let Some(t) = &task {
                t.abort();
            }
            j.view.state = JobState::Cancelled;
            j.view.ended_at = Some(now_secs());
            let parts = std::mem::take(&mut j.parts);
            if !parts.is_empty() {
                let link = Arc::clone(&j.link);
                self.inner.runtime.spawn(async move {
                    // Once the job has stopped: nothing it had under way
                    // makes a part after it was deleted.
                    if let Some(t) = task {
                        let _ = t.await;
                    }
                    for part in parts.into_values() {
                        delete_part(&link, part).await;
                    }
                });
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
        j.task = Some(task);
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
                    j.parts.clear();
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
    ahead: BTreeSet<usize>,
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
        ahead: j.ahead.clone(),
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
                        j.ahead.clear();
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

    let finished = |i: usize| i < s.next || s.ahead.contains(&i);
    let base = (items.iter().enumerate())
        .filter(|&(i, _)| finished(i))
        .map(|(_, item)| item.size)
        .sum();
    s.progress.store(base, Ordering::Relaxed);
    let job = &JobRun {
        inner,
        id,
        remote: &remote,
        req,
        dest_name: &dest_name,
        progress: &s.progress,
    };
    let mut flight = InFlight::default();
    let mut flow = Flow {
        dirs: HashMap::new(),
        weight: 0,
        moved: 0,
        started: Instant::now(),
    };
    // Every name in lower case, to tell twins: names that a server, or
    // this machine, may take for the same.
    let mut names = HashSet::new();
    for (i, item) in items.iter().enumerate() {
        if finished(i) {
            continue;
        }
        let twin = !names.insert(item.rel.to_lowercase());
        let parent = parent_rel(&item.rel);
        // Room for it, the folder it goes in, and for a twin, all before
        // it finished.
        while !flow.room(flight.len(), weight(item))
            || (twin && flight.len() > 0)
            || parent.is_some_and(|p| flow.dirs.get(p) == Some(&None))
        {
            let (k, done) = flight.next().await.expect("items in flight");
            job.settle(k, &items[k], done?, &mut flow);
        }
        let fresh = !twin && parent.is_some_and(|p| flow.dirs.get(p) == Some(&Some(true)));
        if item.dir {
            flow.dirs.insert(&item.rel, None);
        }
        flow.weight += weight(item);
        flight.push(async move { (i, job.copy(i, item, fresh).await) });
    }
    while let Some((k, done)) = flight.next().await {
        job.settle(k, &items[k], done?, &mut flow);
    }
    Ok(())
}

/// What a run keeps while it hands out its items.
struct Flow<'a> {
    /// The folders this run started: `None` while being made, then whether
    /// it made them (so that they hold only what the job puts there).
    dirs: HashMap<&'a str, Option<bool>>,
    /// What the items in flight may have on their way at once.
    weight: u64,
    /// Bytes sent by the files this run finished, and since when.
    moved: u64,
    started: Instant,
}

impl Flow<'_> {
    /// Whether one more item that may have `weight` bytes on its way goes
    /// along with the `in_flight` ones. Together they have no more on their
    /// way than one file would (its window: about two seconds' worth at the
    /// speed measured so far), so a slow server never has more waiting
    /// than it answers before the request timeout. Alone, any item goes.
    fn room(&self, in_flight: usize, weight: u64) -> bool {
        let budget = pipe::window(self.moved, self.started.elapsed());
        in_flight == 0 || (in_flight < FILES_AT_ONCE && self.weight + weight <= budget)
    }
}

/// What an item may have on its way at once: a file starts with as much
/// as its first window.
fn weight(item: &Item) -> u64 {
    item.size.min(pipe::START_WINDOW)
}

/// What became of an item.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Done {
    /// A folder; `made` if this run made it.
    Dir { made: bool },
    /// Left as it was, by the conflict choice.
    Skipped,
    /// Copied, with `size` bytes as it was then (counted in the progress as
    /// they went), `sent` of them by this run.
    Copied { size: u64, sent: u64 },
}

/// One run of a job: what its items share.
struct JobRun<'a> {
    inner: &'a Inner,
    id: u64,
    remote: &'a Remote,
    req: &'a Request,
    dest_name: &'a str,
    progress: &'a AtomicU64,
}

impl JobRun<'_> {
    /// Copies item `i`; `fresh` if it goes in a folder this run made and
    /// has no twin.
    async fn copy(&self, i: usize, item: &Item, fresh: bool) -> Result<Done> {
        let rel = item.rel.as_str();
        if self.req.direction == Direction::Upload {
            let src = local_join(Path::new(&self.req.source), rel)?;
            let dest = join(&self.req.dest_dir, &rel_join(self.dest_name, rel));
            self.upload(i, item, &src, &dest, fresh).await
        } else {
            let src = rel_join(&self.req.source, rel);
            let dest = local_join(
                Path::new(&self.req.dest_dir),
                &rel_join(self.dest_name, rel),
            )?;
            self.download(i, item, &src, &dest).await
        }
    }

    /// Counts item `i` as finished: in the job's progress (by the size it
    /// was listed with, as its total), its files and where to go on from.
    fn settle<'a>(&self, i: usize, item: &'a Item, done: Done, flow: &mut Flow<'a>) {
        flow.weight -= weight(item);
        let counted = match done {
            Done::Dir { made } => {
                flow.dirs.insert(&item.rel, Some(made));
                0
            }
            Done::Skipped => 0,
            Done::Copied { size, sent } => {
                flow.moved += sent;
                size
            }
        };
        if item.size >= counted {
            self.progress
                .fetch_add(item.size - counted, Ordering::Relaxed);
        } else {
            self.progress
                .fetch_sub(counted - item.size, Ordering::Relaxed);
        }
        with_job(self.inner, self.id, |j| {
            j.parts.remove(&i);
            mark_finished(&mut j.next, &mut j.ahead, i);
            match done {
                Done::Copied { .. } => j.view.files_done += 1,
                Done::Skipped => j.view.skipped += 1,
                Done::Dir { .. } => {}
            }
        });
    }

    /// Notes the `.part` item `i` is about to write, for a cancel to
    /// delete. Fails if the job stopped meanwhile: no part is made that a
    /// cancel did not see.
    fn hold(&self, i: usize, part: Part) -> Result<()> {
        let running = with_job(self.inner, self.id, |j| {
            let running = j.view.state == JobState::Running;
            if running {
                j.parts.insert(i, part);
            }
            running
        });
        match running {
            Some(true) => Ok(()),
            _ => Err(Error::Other("stopped".into())),
        }
    }
}

/// Marks item `i` finished: `next` goes past every finished item.
fn mark_finished(next: &mut usize, ahead: &mut BTreeSet<usize>, i: usize) {
    if i != *next {
        ahead.insert(i);
        return;
    }
    *next += 1;
    while ahead.remove(next) {
        *next += 1;
    }
}

/// The folder `rel` is in, relative to the job's (`""` is the copied item
/// itself); `None` for the item itself.
fn parent_rel(rel: &str) -> Option<&str> {
    (!rel.is_empty()).then(|| rel.rfind('/').map_or("", |k| &rel[..k]))
}

/// Futures polled together on the job's own task, each in turn: when the
/// job stops (paused, cancelled), they stop with it.
struct InFlight<'a, T> {
    futures: Vec<Pin<Box<dyn Future<Output = T> + Send + 'a>>>,
}

impl<T> Default for InFlight<'_, T> {
    fn default() -> Self {
        Self {
            futures: Vec::new(),
        }
    }
}

impl<'a, T> InFlight<'a, T> {
    fn len(&self) -> usize {
        self.futures.len()
    }

    fn push(&mut self, future: impl Future<Output = T> + Send + 'a) {
        self.futures.push(Box::pin(future));
    }

    /// What the next one to finish gives; `None` when there are none.
    async fn next(&mut self) -> Option<T> {
        if self.futures.is_empty() {
            return None;
        }
        std::future::poll_fn(|cx| {
            for k in 0..self.futures.len() {
                if let Poll::Ready(out) = self.futures[k].as_mut().poll(cx) {
                    drop(self.futures.swap_remove(k));
                    return Poll::Ready(Some(out));
                }
            }
            Poll::Pending
        })
        .await
    }
}

/// `base` joined with `rel` (`""` is `base` itself).
fn rel_join(base: &str, rel: &str) -> String {
    if rel.is_empty() {
        base.to_owned()
    } else {
        join(base, rel)
    }
}

/// `base` with `rel` (`/`-separated names) below it. A name that would lead
/// elsewhere fails, so a download never writes outside its folder.
fn local_join(base: &Path, rel: &str) -> Result<PathBuf> {
    let mut path = base.to_owned();
    for name in rel.split('/').filter(|p| !p.is_empty()) {
        // On Windows `\` separates too, and `:` names a drive or a stream.
        if !is_name(name) || (cfg!(windows) && name.contains(['\\', ':'])) {
            return Err(Error::Other(format!("{rel}: not a valid name here")));
        }
        path.push(name);
    }
    Ok(path)
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
            // A big folder takes a while to walk: off the runtime's threads,
            // which every connection shares.
            let path = PathBuf::from(&req.source);
            let source = req.source.clone();
            let walked = tokio::task::spawn_blocking(move || {
                let top = local::stat(&path)?.ok_or(Error::NotFound(source))?;
                let below = if top.kind == Kind::Dir {
                    local::walk(&path)?
                } else {
                    Vec::new()
                };
                Ok::<_, Error>((top, below))
            })
            .await
            .map_err(|e| Error::Other(e.to_string()))??;
            let (top, below) = walked;
            let mut items = vec![item(String::new(), &top)];
            for (rel, e) in below {
                let rel = rel
                    .components()
                    .map(|c| c.as_os_str().to_string_lossy())
                    .collect::<Vec<_>>()
                    .join("/");
                items.push(item(rel, &e));
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

impl JobRun<'_> {
    /// Copies one item up.
    async fn upload(
        &self,
        i: usize,
        item: &Item,
        src: &Path,
        dest: &str,
        fresh: bool,
    ) -> Result<Done> {
        let remote = self.remote;
        if item.dir {
            // In a folder this run made there is nothing yet.
            let there = if fresh {
                None
            } else {
                remote.stat(dest).await?
            };
            if there.is_some_and(|e| e.is_dir()) {
                return Ok(Done::Dir { made: false });
            }
            remote.mkdir(dest).await?;
            return Ok(Done::Dir { made: true });
        }
        let name = src.display().to_string();
        let source = local::stat(src)?;
        let part_of = |dest: &str, s: &Entry| part_path(dest, &name, s.size, s.modified);
        let mut dest = dest.to_owned();
        let (mut existing, mut had) = (None, None);
        if !fresh {
            // What has the name, and the part an earlier copy left: asked
            // together.
            let part = source.as_ref().map(|s| part_of(&dest, s));
            let (there, part_there) = tokio::join!(remote.lstat(&dest), async {
                match &part {
                    Some(part) => remote.lstat(part).await,
                    None => Ok(None),
                }
            });
            let there = there?;
            let link = there.as_ref().is_some_and(|e| e.kind == Kind::Link);
            existing = if link {
                remote.stat(&dest).await?
            } else {
                there
            };
            if let Some(e) = &existing
                && keep_existing(self.req.on_conflict, e, item)
            {
                return Ok(Done::Skipped);
            }
            had = part_there?;
            // A link stays a link: what is replaced is the file it leads to.
            if link && existing.is_some() {
                dest = remote.realpath(&dest).await?;
                had = match &source {
                    Some(s) => remote.lstat(&part_of(&dest, s)).await?,
                    None => None,
                };
            }
        }
        let source = source.ok_or_else(|| Error::NotFound(name.clone()))?;
        let size = source.size;
        let had = had.map(|e| e.size).filter(|&s| s <= size);
        let part = part_of(&dest, &source);
        self.hold(i, Part::Remote(part.clone()))?;
        let offset = had.map_or(0, |s| s.saturating_sub(RESUME_OVERLAP));
        // A replaced file keeps its permissions; a new one gets ours.
        let mode = existing
            .as_ref()
            .and_then(|e| e.mode)
            .or(item.mode)
            .map(|m| m & 0o7777);
        let handle = remote.open_write(&part, had.is_none(), mode).await?;
        // Someone else's file, or another group's: put in its place, ours
        // would be ours. It is written over where it is, as `sftp` does.
        if existing.is_some() {
            let (theirs, ours) = tokio::join!(remote.owner_ids(&dest), remote.owner_ids(&part));
            if theirs? != ours? {
                remote.close(&part, handle).await?;
                remote.remove_file(&part).await?;
                with_job(self.inner, self.id, |j| j.parts.remove(&i));
                return self.upload_in_place(src, &dest, size, item.modified).await;
            }
        }
        self.progress.fetch_add(offset, Ordering::Relaxed);
        let mut file = tokio::fs::File::open(src)
            .await
            .map_err(|e| Error::local(src, &e))?;
        let sent = pipe::upload(
            remote,
            &part,
            &handle,
            &mut file,
            offset,
            size,
            self.progress,
        )
        .await;
        let closed = remote.close(&part, handle).await;
        sent?;
        closed?;
        // Its size is not asked back: every byte from `offset` to `size` was
        // acknowledged, on a part that had at least `offset` bytes and at
        // most `size` (or was emptied). Its date stays the one it had here,
        // so "only if newer" means something next time.
        remote.set_attrs(&part, mode, item.modified).await?;
        remote.rename(&part, &dest, true).await?;
        Ok(Done::Copied {
            size,
            sent: size - offset,
        })
    }

    /// Writes `src` over `dest` where it is, keeping its owner, group and
    /// links. Not resumable, as with `sftp`'s `put`.
    async fn upload_in_place(
        &self,
        src: &Path,
        dest: &str,
        size: u64,
        modified: Option<i64>,
    ) -> Result<Done> {
        let remote = self.remote;
        let handle = remote.open_write(dest, true, None).await?;
        let mut file = tokio::fs::File::open(src)
            .await
            .map_err(|e| Error::local(src, &e))?;
        let sent = pipe::upload(remote, dest, &handle, &mut file, 0, size, self.progress).await;
        let closed = remote.close(dest, handle).await;
        sent?;
        closed?;
        // Its date, where the server lets us set it on someone else's file.
        let _ = remote.set_attrs(dest, None, modified).await;
        Ok(Done::Copied { size, sent: size })
    }

    /// Copies one item down.
    async fn download(&self, i: usize, item: &Item, src: &str, dest: &Path) -> Result<Done> {
        let remote = self.remote;
        let existing = local::stat(dest)?;
        if item.dir {
            return match existing {
                Some(e) if e.is_dir() => Ok(Done::Dir { made: false }),
                _ => {
                    local::mkdir(dest)?;
                    Ok(Done::Dir { made: true })
                }
            };
        }
        if let Some(e) = &existing
            && keep_existing(self.req.on_conflict, e, item)
        {
            return Ok(Done::Skipped);
        }
        // What the file is now, and the file: asked together.
        let (source, handle) = tokio::join!(remote.stat(src), remote.open_read(src));
        let source = match source.and_then(|s| s.ok_or_else(|| Error::NotFound(src.to_owned()))) {
            Ok(source) => source,
            Err(e) => {
                if let Ok(handle) = handle {
                    remote.close_later(handle);
                }
                return Err(e);
            }
        };
        let handle = handle?;
        let size = source.size;
        let mut part = dest.as_os_str().to_owned();
        part.push(part_suffix(src, size, source.modified));
        let part = PathBuf::from(part);
        let got = self.download_part(i, item, src, &handle, &part, size).await;
        remote.close_later(handle);
        let offset = got?;
        let local_err = |e: std::io::Error| Error::local(&part, &e);
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
        Ok(Done::Copied {
            size,
            sent: size - offset,
        })
    }

    /// Writes the open remote `handle` into `part`, going on from what the
    /// part has, until it has `size` bytes; what it had.
    async fn download_part(
        &self,
        i: usize,
        item: &Item,
        src: &str,
        handle: &str,
        part: &Path,
        size: u64,
    ) -> Result<u64> {
        self.hold(i, Part::Local(part.to_owned()))?;
        let offset = std::fs::metadata(part)
            .map(|m| m.len())
            .ok()
            .filter(|&s| s <= size)
            .unwrap_or(0);
        let local_err = |e: std::io::Error| Error::local(part, &e);
        let mut open = std::fs::OpenOptions::new();
        open.create(true).write(true).truncate(false);
        // Born as private as the server's copy: a key is never readable by
        // others here, not even while it downloads.
        #[cfg(unix)]
        std::os::unix::fs::OpenOptionsExt::mode(
            &mut open,
            item.mode.map_or(0o666, |m| 0o600 | (m & 0o066)),
        );
        // Made here, not on a thread of its own: once the job has stopped,
        // nothing it began makes a part after a cancel deleted it.
        let mut file = tokio::fs::File::from_std(open.open(part).map_err(local_err)?);
        file.set_len(offset).await.map_err(local_err)?;
        tokio::io::AsyncSeekExt::seek(&mut file, std::io::SeekFrom::Start(offset))
            .await
            .map_err(local_err)?;
        self.progress.fetch_add(offset, Ordering::Relaxed);
        pipe::download(
            self.remote,
            src,
            handle,
            &mut file,
            offset,
            size,
            self.progress,
        )
        .await?;
        tokio::io::AsyncWriteExt::flush(&mut file)
            .await
            .map_err(local_err)?;
        file.sync_all().await.map_err(local_err)?;
        drop(file);
        if std::fs::metadata(part).map_err(local_err)?.len() != size {
            return Err(Error::Changed(src.to_owned()));
        }
        Ok(offset)
    }
}

/// The local umask, narrowed to what the server's copy lets group and
/// others do (a `.part` resumed from before keeps what it was born with);
/// and a program stays runnable: execute goes wherever reading is, when
/// the server's copy had it.
#[cfg(unix)]
fn set_local_mode(path: &Path, remote_mode: Option<u32>) {
    use std::os::unix::fs::PermissionsExt;
    let Some(remote) = remote_mode else { return };
    if let Ok(meta) = std::fs::metadata(path) {
        let had = meta.permissions().mode() & 0o777;
        let mut mode = had & (0o700 | (remote & 0o077));
        if remote & 0o100 != 0 {
            mode |= (mode & 0o444) >> 2;
        }
        if mode != had {
            let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode));
        }
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
            local_join(Path::new("/tmp/x"), "a/b.txt").unwrap(),
            Path::new("/tmp/x").join("a").join("b.txt")
        );
        assert_eq!(
            local_join(Path::new("/tmp/x"), "").unwrap(),
            Path::new("/tmp/x")
        );
    }

    /// Items finish out of order; a resumed job starts after the first
    /// unfinished one and leaves out those finished after it.
    #[test]
    fn items_finish_out_of_order() {
        let (mut next, mut ahead) = (0, BTreeSet::new());
        for i in [2, 1, 4] {
            mark_finished(&mut next, &mut ahead, i);
        }
        assert_eq!((next, ahead.len()), (0, 3));
        mark_finished(&mut next, &mut ahead, 0);
        assert_eq!((next, ahead), (3, BTreeSet::from([4])));
        let mut ahead = BTreeSet::from([4]);
        mark_finished(&mut next, &mut ahead, 3);
        assert_eq!((next, ahead.is_empty()), (5, true));
    }

    /// Small files go together; a big one goes alone until the speed says
    /// the server takes more.
    #[test]
    fn what_goes_along() {
        let mut flow = Flow {
            dirs: HashMap::new(),
            weight: 0,
            moved: 0,
            started: Instant::now(),
        };
        let small = 4 << 10;
        let big = pipe::START_WINDOW;
        assert!(flow.room(0, big));
        flow.weight = 7 * small;
        assert!(flow.room(7, small));
        assert!(!flow.room(FILES_AT_ONCE, small));
        // A big file in flight, and nothing measured yet.
        flow.weight = big;
        assert!(!flow.room(1, small));
        // 10 MiB in a second: room for two seconds of it, 20 MiB.
        flow.started = Instant::now().checked_sub(Duration::from_secs(1)).unwrap();
        flow.moved = 10 << 20;
        assert!(flow.room(1, big));
        // 50 KiB in a second: one big file at a time, small ones together.
        flow.moved = 50 << 10;
        assert!(!flow.room(1, big));
        assert!(flow.room(0, big));
        flow.weight = 7 * small;
        assert!(flow.room(7, small));
    }

    #[test]
    fn the_folder_an_item_goes_in() {
        assert_eq!(parent_rel(""), None);
        assert_eq!(parent_rel("a"), Some(""));
        assert_eq!(parent_rel("a/b/c.txt"), Some("a/b"));
    }

    /// A server's names never lead out of the folder a download goes to.
    #[test]
    fn downloads_stay_in_their_folder() {
        for rel in ["..", "a/../../.zshrc", "site/./x", "a/\0"] {
            assert!(local_join(Path::new("/tmp/x"), rel).is_err(), "{rel:?}");
        }
        let windows = local_join(Path::new("/tmp/x"), "a\\..\\..\\x");
        assert_eq!(windows.is_err(), cfg!(windows));
        assert_eq!(
            local_join(Path::new("/tmp/x"), "c:x").is_err(),
            cfg!(windows)
        );
    }

    /// The part names its source: another file, size or date, another part.
    /// The value is fixed so a part left by this version resumes in the next.
    #[test]
    fn parts_name_their_source() {
        let part = |source, size, modified| part_path("/srv/big.bin", source, size, modified);
        let mine = part("/home/me/big.bin", 10, Some(1_700_000_000));
        assert_eq!(mine, part("/home/me/big.bin", 10, Some(1_700_000_000)));
        assert!(mine.starts_with("/srv/big.bin.ow-") && mine.ends_with(PART));
        assert_ne!(mine, part("/home/me/big.bin", 11, Some(1_700_000_000)));
        assert_ne!(mine, part("/home/me/big.bin", 10, Some(1_700_000_001)));
        assert_ne!(mine, part("/home/you/big.bin", 10, Some(1_700_000_000)));
        assert_ne!(mine, part("/home/me/big.bin", 10, None));
        assert_eq!(part_suffix("a", 1, None), ".ow-3a363c90.part");
    }
}
