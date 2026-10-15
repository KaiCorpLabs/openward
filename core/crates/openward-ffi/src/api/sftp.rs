//! SFTP as Dart sees it: a browser per tab, this machine's files, and the
//! transfer queue the app keeps.
//!
//! Errors are [`FileError`]: a kind the UI words itself, and the path.

use std::path::PathBuf;
use std::sync::Arc;

use flutter_rust_bridge::frb;
use openward_app::files::{
    self, Conflict, Direction, Entry, JobState, JobView, Kind, OnConflict, Request, local,
};
use openward_app::{App, Sftp};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FileKind {
    File,
    Dir,
    Link,
    Other,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileEntry {
    pub name: String,
    pub kind: FileKind,
    /// A link to a folder: it opens like one.
    pub link_dir: bool,
    pub link_target: Option<String>,
    /// Bytes; for a link to a file, the file's.
    pub size: i64,
    /// Seconds since the epoch.
    pub modified: Option<i64>,
    /// Permission bits, when known.
    pub mode: Option<u32>,
    pub owner: Option<String>,
    pub group: Option<String>,
}

impl From<Entry> for FileEntry {
    fn from(e: Entry) -> Self {
        Self {
            name: e.name,
            kind: match e.kind {
                Kind::File => FileKind::File,
                Kind::Dir => FileKind::Dir,
                Kind::Link => FileKind::Link,
                Kind::Other => FileKind::Other,
            },
            link_dir: e.link_dir,
            link_target: e.link_target,
            size: i64::try_from(e.size).unwrap_or(i64::MAX),
            modified: e.modified,
            mode: e.mode,
            owner: e.owner,
            group: e.group,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FileErrorKind {
    NotFound,
    Denied,
    Exists,
    /// The connection is gone; it may come back.
    Lost,
    Changed,
    Other,
}

/// What went wrong with a file; thrown in Dart.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileError {
    pub kind: FileErrorKind,
    /// The file, when there is one.
    pub path: String,
    /// In English, for logs and for errors the UI has no words for.
    pub message: String,
}

impl From<files::Error> for FileError {
    fn from(e: files::Error) -> Self {
        let message = e.to_string();
        let (kind, path) = match e {
            files::Error::NotFound(p) => (FileErrorKind::NotFound, p),
            files::Error::Denied(p) => (FileErrorKind::Denied, p),
            files::Error::Exists(p) => (FileErrorKind::Exists, p),
            files::Error::Lost => (FileErrorKind::Lost, String::new()),
            files::Error::Changed(p) => (FileErrorKind::Changed, p),
            files::Error::Other(_) => (FileErrorKind::Other, String::new()),
        };
        Self {
            kind,
            path,
            message,
        }
    }
}

type Result<T> = std::result::Result<T, FileError>;

fn entries(list: Vec<Entry>) -> Vec<FileEntry> {
    list.into_iter().map(FileEntry::from).collect()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransferDirection {
    Upload,
    Download,
}

impl From<TransferDirection> for Direction {
    fn from(d: TransferDirection) -> Self {
        match d {
            TransferDirection::Upload => Direction::Upload,
            TransferDirection::Download => Direction::Download,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConflictChoice {
    Replace,
    Skip,
    /// Replace only what is older.
    Newer,
    /// Copy under a free name.
    KeepBoth,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConflictView {
    pub source: String,
    pub ours: FileEntry,
    pub theirs: FileEntry,
}

impl From<Conflict> for ConflictView {
    fn from(c: Conflict) -> Self {
        Self {
            source: c.source,
            ours: c.ours.into(),
            theirs: c.theirs.into(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransferState {
    Queued,
    Running,
    Paused,
    Failed,
    Done,
    Cancelled,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TransferView {
    pub id: u64,
    pub direction: TransferDirection,
    pub name: String,
    pub source: String,
    pub dest_dir: String,
    /// The connection's label.
    pub host: String,
    pub is_dir: bool,
    /// Files in it; 0 until counted.
    pub files: u32,
    pub files_done: u32,
    pub skipped: u32,
    /// Bytes; 0 until counted.
    pub total: i64,
    pub done: i64,
    /// Bytes per second, while running.
    pub rate: f64,
    pub state: TransferState,
    pub error: Option<FileError>,
    /// Seconds since the epoch.
    pub ended_at: Option<i64>,
}

impl From<JobView> for TransferView {
    fn from(j: JobView) -> Self {
        Self {
            id: j.id,
            direction: match j.direction {
                Direction::Upload => TransferDirection::Upload,
                Direction::Download => TransferDirection::Download,
            },
            name: j.name,
            source: j.source,
            dest_dir: j.dest_dir,
            host: j.host,
            is_dir: j.is_dir,
            files: j.files,
            files_done: j.files_done,
            skipped: j.skipped,
            total: i64::try_from(j.total).unwrap_or(i64::MAX),
            done: i64::try_from(j.done).unwrap_or(i64::MAX),
            rate: j.rate,
            state: match j.state {
                JobState::Queued => TransferState::Queued,
                JobState::Running => TransferState::Running,
                JobState::Paused => TransferState::Paused,
                JobState::Failed => TransferState::Failed,
                JobState::Done => TransferState::Done,
                JobState::Cancelled => TransferState::Cancelled,
            },
            error: j.error.map(FileError::from),
            ended_at: j.ended_at.map(|t| t as i64),
        }
    }
}

/// A tab's SFTP browser. Closing it leaves its transfers running.
#[frb(opaque)]
pub struct SftpBrowser {
    pub(crate) sftp: Arc<Sftp>,
}

impl SftpBrowser {
    /// The folder the server starts in.
    pub async fn home(&self) -> Result<String> {
        Ok(self.sftp.home().await?)
    }

    /// `path` made absolute, `..` and links resolved.
    pub async fn realpath(&self, path: String) -> Result<String> {
        Ok(self.sftp.realpath(path).await?)
    }

    /// What is in a folder, in no order.
    pub async fn list(&self, path: String) -> Result<Vec<FileEntry>> {
        Ok(entries(self.sftp.list(path).await?))
    }

    pub async fn stat(&self, path: String) -> Result<Option<FileEntry>> {
        Ok(self.sftp.stat(path).await?.map(FileEntry::from))
    }

    pub async fn mkdir(&self, path: String) -> Result<()> {
        Ok(self.sftp.mkdir(path).await?)
    }

    /// Never over something that exists.
    pub async fn rename(&self, from: String, to: String) -> Result<()> {
        Ok(self.sftp.rename(from, to).await?)
    }

    /// Files, links (not what they point to) and folders with all they
    /// hold. There is no undo.
    pub async fn remove(&self, paths: Vec<String>) -> Result<()> {
        Ok(self.sftp.remove(paths).await?)
    }

    /// With `recursive`, files keep execute only if they had it. Returns
    /// how many entries changed.
    pub async fn chmod(&self, path: String, mode: u32, recursive: bool) -> Result<i64> {
        Ok(self.sftp.chmod(path, mode, recursive).await? as i64)
    }

    /// Which of `sources` already exist in `dest_dir` (on the other side).
    pub async fn conflicts(
        &self,
        direction: TransferDirection,
        sources: Vec<String>,
        dest_dir: String,
    ) -> Result<Vec<ConflictView>> {
        let found = self
            .sftp
            .conflicts(direction.into(), sources, dest_dir)
            .await?;
        Ok(found.into_iter().map(ConflictView::from).collect())
    }

    /// Stops connecting or watching the connection.
    #[frb(sync)]
    pub fn close(&self) {
        self.sftp.close();
    }
}

// ------------------------------------------------- this machine's side

/// The user's home folder.
#[frb(sync)]
pub fn local_home() -> String {
    local::home().map_or_else(|| "/".to_owned(), |p| p.display().to_string())
}

/// What is in a folder on this machine, in no order.
pub fn local_list(path: String) -> Result<Vec<FileEntry>> {
    Ok(entries(local::list(&PathBuf::from(path))?))
}

pub fn local_stat(path: String) -> Result<Option<FileEntry>> {
    Ok(local::stat(&PathBuf::from(path))?.map(FileEntry::from))
}

pub fn local_mkdir(path: String) -> Result<()> {
    Ok(local::mkdir(&PathBuf::from(path))?)
}

/// Never over something that exists.
pub fn local_rename(from: String, to: String) -> Result<()> {
    Ok(local::rename(&PathBuf::from(from), &PathBuf::from(to))?)
}

/// Files, links and folders with all they hold. There is no undo.
pub fn local_remove(paths: Vec<String>) -> Result<()> {
    for p in paths {
        local::remove(&PathBuf::from(p))?;
    }
    Ok(())
}

pub fn local_chmod(path: String, mode: u32, recursive: bool) -> Result<i64> {
    Ok(local::chmod(&PathBuf::from(path), mode, recursive)? as i64)
}

pub(crate) fn transfer(
    app: &App,
    browser: &SftpBrowser,
    direction: TransferDirection,
    source: String,
    dest_dir: String,
    on_conflict: ConflictChoice,
) -> u64 {
    let on_conflict = match on_conflict {
        ConflictChoice::Replace => OnConflict::Replace,
        ConflictChoice::Skip => OnConflict::Skip,
        ConflictChoice::Newer => OnConflict::Newer,
        ConflictChoice::KeepBoth => OnConflict::KeepBoth,
    };
    app.transfer(
        &browser.sftp,
        Request {
            direction: direction.into(),
            source,
            dest_dir,
            on_conflict,
        },
    )
}
