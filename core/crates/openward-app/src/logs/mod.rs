//! Session logs (docs/plan/registros.md): every session leaves an entry
//! (where, when, how long, how it ended) and, where the user turned it on,
//! a recording of what came out on the screen, to watch again, search and
//! export. Never what was typed.
//!
//! In `logs/` beside the vault, per session `<id>`:
//! - `<id>.json`: the entry ([`Entry`]);
//! - `<id>.cast.gz`: the recording, asciicast v2 ([`cast`]);
//! - `<id>.txt.gz`: its text, a line per line with the moment it began
//!   (`seconds\ttext`), for searching ([`text`]).
//!
//! Files of their own per session: nothing is shared between two that
//! write at once, deleting one is deleting its files, and a sudden exit
//! leaves the others whole. Owner-only, like the rest of the data
//! directory: they hold whatever was on screen.

pub mod cast;
mod player;
mod recorder;
mod sink;
mod text;

pub use player::Player;
pub(crate) use sink::LogSink;

use std::collections::{BTreeMap, HashSet};
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{SystemTime, UNIX_EPOCH};

use flate2::read::MultiGzDecoder;
use serde::{Deserialize, Serialize};

use crate::terminal::Waker;
use cast::{Header, Mark, Recording};
use recorder::Recorder;

/// Where a session went.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Place {
    /// A saved host, by id.
    Host(String),
    /// An address typed by hand, `[user@]host[:port]`.
    Address(String),
    /// A terminal on this computer.
    Local,
}

/// How a host was marked when the session began.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Marking {
    pub name: String,
    pub short: String,
    pub color: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum End {
    /// Still going.
    Open,
    /// Closed: the program ended, or the tab closed.
    Closed,
    /// The connection went away and did not come back.
    Lost,
    /// OpenWard closed (or stopped) without ending it.
    AppQuit,
}

/// Kept until the user takes it back: no age or space limit deletes it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Saved {
    #[serde(default)]
    pub note: String,
    pub at_ms: i64,
}

/// A session, recorded or not.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    pub id: String,
    pub place: Place,
    /// The host's name, or the address, when it began.
    pub label: String,
    /// `user@host[:port]` of the target, `~` for a local terminal.
    pub address: String,
    #[serde(default)]
    pub marking: Option<Marking>,
    /// The system's code (`deb`, `ubu`…), if it was known.
    #[serde(default)]
    pub system: Option<String>,
    pub started_ms: i64,
    #[serde(default)]
    pub ended_ms: Option<i64>,
    pub end: End,
    /// The shell ran in a persistent tmux session.
    #[serde(default)]
    pub tmux: bool,
    /// What came out was recorded.
    pub recorded: bool,
    /// The files' size on disk.
    #[serde(default)]
    pub bytes: u64,
    /// Commands marked in the recording.
    #[serde(default)]
    pub commands: u32,
    #[serde(default)]
    pub saved: Option<Saved>,
}

/// What a session that begins is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Begin {
    pub place: Place,
    pub label: String,
    pub address: String,
    pub marking: Option<Marking>,
    pub system: Option<String>,
    pub tmux: bool,
    /// Record what comes out, or keep the entry only.
    pub record: bool,
    pub cols: u16,
    pub rows: u16,
    pub term: String,
}

/// This device's choices.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Config {
    /// Record local terminals too.
    pub record_local: bool,
    /// Entries older than this many days go; 0 keeps them.
    pub keep_days: u32,
    /// Past this many bytes, the oldest go first; 0 for no limit.
    pub max_bytes: u64,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            record_local: false,
            keep_days: 30,
            max_bytes: 2 * 1024 * 1024 * 1024,
        }
    }
}

/// The space the logs take.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Usage {
    pub bytes: u64,
    pub entries: u32,
    pub recorded: u32,
    pub saved: u32,
}

/// Lines of one session that match a search.
#[derive(Clone, Debug, PartialEq)]
pub struct Found {
    pub entry: Entry,
    /// The first matches, in order.
    pub hits: Vec<Hit>,
    /// All of them, past those shown.
    pub total: usize,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Hit {
    /// Seconds from the start.
    pub at: f64,
    pub line: String,
}

/// What the page shows of a recorded session.
#[derive(Clone, Debug, PartialEq)]
pub struct Preview {
    /// The last text lines, `(seconds, line)`.
    pub lines: Vec<(f64, String)>,
    /// Every marker, `(seconds, label)`.
    pub markers: Vec<(f64, String)>,
}

/// Matches shown per session; the rest are counted.
const HITS_SHOWN: usize = 20;

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

pub(crate) fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64)
}

/// A file only its owner reads.
pub(crate) fn create(path: &Path) -> std::io::Result<File> {
    let mut options = fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(path)
}

pub struct Logs {
    dir: PathBuf,
    inner: Mutex<Inner>,
    waker: Mutex<Option<Waker>>,
}

struct Inner {
    config: Config,
    entries: BTreeMap<String, Entry>,
    /// Sessions going on now.
    open: HashSet<String>,
}

impl Logs {
    /// Opens `dir`, making it if needed; sessions left open by a sudden
    /// exit are closed as such, and what is past the limits goes.
    pub fn open(dir: &Path, config: Config) -> std::io::Result<Arc<Self>> {
        crate::create_private_dir(dir)?;
        let mut entries = BTreeMap::new();
        for file in fs::read_dir(dir)? {
            let path = file?.path();
            let Some(id) = path
                .file_name()
                .and_then(|n| n.to_str())
                .and_then(|n| n.strip_suffix(".json"))
            else {
                continue;
            };
            let Ok(mut entry) = fs::read(&path)
                .map_err(drop)
                .and_then(|b| serde_json::from_slice::<Entry>(&b).map_err(drop))
            else {
                continue;
            };
            if entry.id != id {
                continue;
            }
            if entry.end == End::Open {
                let cast = dir.join(format!("{id}.cast.gz"));
                let last = fs::metadata(&cast)
                    .or_else(|_| fs::metadata(&path))
                    .and_then(|m| m.modified())
                    .ok()
                    .and_then(|m| m.duration_since(UNIX_EPOCH).ok())
                    .map(|d| d.as_millis() as i64);
                entry.end = End::AppQuit;
                entry.ended_ms = Some(last.unwrap_or(entry.started_ms).max(entry.started_ms));
                entry.bytes = files_size(dir, id);
                write_entry(dir, &entry)?;
            }
            entries.insert(entry.id.clone(), entry);
        }
        let logs = Arc::new(Self {
            dir: dir.to_owned(),
            inner: Mutex::new(Inner {
                config,
                entries,
                open: HashSet::new(),
            }),
            waker: Mutex::new(None),
        });
        logs.prune();
        Ok(logs)
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// Called (from any thread) when entries come, change or go.
    pub fn watch(&self, wake: Waker) {
        *lock(&self.waker) = Some(wake);
    }

    fn changed(&self) {
        if let Some(wake) = lock(&self.waker).clone() {
            wake();
        }
    }

    pub fn config(&self) -> Config {
        lock(&self.inner).config
    }

    /// New limits apply at once.
    pub fn set_config(&self, config: Config) {
        lock(&self.inner).config = config;
        self.prune();
    }

    /// Every entry, the newest first.
    pub fn list(&self) -> Vec<Entry> {
        let inner = lock(&self.inner);
        let mut list: Vec<Entry> = inner.entries.values().cloned().collect();
        list.sort_by(|a, b| b.started_ms.cmp(&a.started_ms).then(b.id.cmp(&a.id)));
        list
    }

    pub fn entry(&self, id: &str) -> Option<Entry> {
        lock(&self.inner).entries.get(id).cloned()
    }

    pub fn usage(&self) -> Usage {
        let inner = lock(&self.inner);
        let mut usage = Usage::default();
        for e in inner.entries.values() {
            usage.entries += 1;
            usage.bytes += e.bytes;
            usage.recorded += u32::from(e.recorded);
            usage.saved += u32::from(e.saved.is_some());
        }
        usage
    }

    /// Starts a session's entry, and its recording if `begin.record`.
    pub fn begin(self: &Arc<Self>, begin: Begin) -> std::io::Result<Arc<Session>> {
        let id = crate::vault::proto::ItemId::new().to_string();
        let started_ms = now_ms();
        let entry = Entry {
            id: id.clone(),
            place: begin.place,
            label: begin.label,
            address: begin.address,
            marking: begin.marking,
            system: begin.system,
            started_ms,
            ended_ms: None,
            end: End::Open,
            tmux: begin.tmux,
            recorded: begin.record,
            bytes: 0,
            commands: 0,
            saved: None,
        };
        let recorder = if begin.record {
            let header = Header::new(
                begin.cols,
                begin.rows,
                started_ms / 1000,
                &entry.label,
                &begin.term,
            );
            Some(Recorder::start(
                &self.cast_path(&id),
                &self.text_path(&id),
                &header,
            )?)
        } else {
            None
        };
        write_entry(&self.dir, &entry)?;
        {
            let mut inner = lock(&self.inner);
            inner.open.insert(id.clone());
            inner.entries.insert(id.clone(), entry.clone());
        }
        self.changed();
        Ok(Arc::new(Session {
            logs: Arc::clone(self),
            recorder,
            entry: Mutex::new(entry),
        }))
    }

    /// Keeps an entry for good, with a note (or changes the note).
    pub fn save(&self, id: &str, note: &str) -> std::io::Result<()> {
        self.update(id, |e| {
            e.saved = Some(Saved {
                note: note.trim().to_owned(),
                at_ms: e.saved.as_ref().map_or_else(now_ms, |s| s.at_ms),
            });
        })
    }

    /// Lets the limits delete it again.
    pub fn unsave(&self, id: &str) -> std::io::Result<()> {
        self.update(id, |e| e.saved = None)?;
        self.prune();
        Ok(())
    }

    fn update(&self, id: &str, change: impl FnOnce(&mut Entry)) -> std::io::Result<()> {
        let entry = {
            let mut inner = lock(&self.inner);
            let entry = inner
                .entries
                .get_mut(id)
                .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, id.to_owned()))?;
            change(entry);
            entry.clone()
        };
        write_entry(&self.dir, &entry)?;
        self.changed();
        Ok(())
    }

    /// Deletes an entry and its recording; false for a session still
    /// going on, or one that is not there.
    pub fn delete(&self, id: &str) -> std::io::Result<bool> {
        {
            let mut inner = lock(&self.inner);
            if inner.open.contains(id) || inner.entries.remove(id).is_none() {
                return Ok(false);
            }
        }
        self.remove_files(id)?;
        self.changed();
        Ok(true)
    }

    /// Deletes every entry but those of sessions going on, saved ones too.
    /// Returns how many went.
    pub fn delete_all(&self) -> std::io::Result<u32> {
        let ids: Vec<String> = {
            let mut inner = lock(&self.inner);
            let open = inner.open.clone();
            let ids: Vec<String> = inner
                .entries
                .keys()
                .filter(|id| !open.contains(*id))
                .cloned()
                .collect();
            for id in &ids {
                inner.entries.remove(id);
            }
            ids
        };
        for id in &ids {
            self.remove_files(id)?;
        }
        self.changed();
        Ok(ids.len() as u32)
    }

    fn remove_files(&self, id: &str) -> std::io::Result<()> {
        for path in [
            self.cast_path(id),
            self.text_path(id),
            self.dir.join(format!("{id}.json")),
        ] {
            match fs::remove_file(&path) {
                Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(e),
                _ => {}
            }
        }
        Ok(())
    }

    /// Deletes what is past the limits: entries older than the days kept,
    /// then the oldest until the space fits. Never a saved one, nor one
    /// going on.
    pub fn prune(&self) {
        let doomed: Vec<String> = {
            let mut inner = lock(&self.inner);
            let Config {
                keep_days,
                max_bytes,
                ..
            } = inner.config;
            let cutoff = now_ms() - i64::from(keep_days) * 24 * 60 * 60 * 1000;
            let mut oldest_first: Vec<&Entry> = inner
                .entries
                .values()
                .filter(|e| e.saved.is_none() && !inner.open.contains(&e.id))
                .collect();
            oldest_first.sort_by_key(|e| (e.started_ms, e.id.clone()));
            let mut total: u64 = inner.entries.values().map(|e| e.bytes).sum();
            let mut doomed = Vec::new();
            for e in oldest_first {
                let old = keep_days > 0 && e.ended_ms.unwrap_or(e.started_ms) < cutoff;
                let over = max_bytes > 0 && total > max_bytes;
                if old || over {
                    total = total.saturating_sub(e.bytes);
                    doomed.push(e.id.clone());
                }
            }
            for id in &doomed {
                inner.entries.remove(id);
            }
            doomed
        };
        if doomed.is_empty() {
            return;
        }
        for id in &doomed {
            let _ = self.remove_files(id);
        }
        self.changed();
    }

    fn cast_path(&self, id: &str) -> PathBuf {
        self.dir.join(format!("{id}.cast.gz"))
    }

    fn text_path(&self, id: &str) -> PathBuf {
        self.dir.join(format!("{id}.txt.gz"))
    }

    fn recorded(&self, id: &str) -> std::io::Result<Entry> {
        match self.entry(id) {
            Some(e) if e.recorded => Ok(e),
            _ => Err(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("no recording {id}"),
            )),
        }
    }

    /// A recording, as far as it is written.
    pub fn read(&self, id: &str) -> std::io::Result<Recording> {
        self.recorded(id)?;
        let file = File::open(self.cast_path(id))?;
        cast::read(BufReader::new(MultiGzDecoder::new(file)))
    }

    /// Its text lines, `(seconds, line)`, as far as they are written.
    pub fn text(&self, id: &str) -> std::io::Result<Vec<(f64, String)>> {
        self.recorded(id)?;
        let mut lines = Vec::new();
        for_each_line(&self.text_path(id), |t, line| {
            lines.push((t, line.to_owned()));
            true
        })?;
        Ok(lines)
    }

    /// Looks for `query` (ignoring case) in the recordings' text, the
    /// newest first; `found` gets each session with matches, and stops the
    /// search by returning false.
    pub fn search(&self, query: &str, mut found: impl FnMut(Found) -> bool) {
        let needle = query.trim().to_lowercase();
        if needle.is_empty() {
            return;
        }
        for entry in self.list().into_iter().filter(|e| e.recorded) {
            let mut hits = Vec::new();
            let mut total = 0;
            let _ = for_each_line(&self.text_path(&entry.id), |t, line| {
                if line.to_lowercase().contains(&needle) {
                    total += 1;
                    if hits.len() < HITS_SHOWN {
                        hits.push(Hit {
                            at: t,
                            line: line.to_owned(),
                        });
                    }
                }
                true
            });
            if total > 0 && !found(Found { entry, hits, total }) {
                return;
            }
        }
    }

    /// Writes the recording as it is, an asciicast v2 file that asciinema
    /// plays.
    pub fn export_cast(&self, id: &str, to: &Path) -> std::io::Result<()> {
        self.recorded(id)?;
        let mut from = MultiGzDecoder::new(File::open(self.cast_path(id))?);
        let mut out = std::io::BufWriter::new(create(to)?);
        // A recording cut short ends at its last whole line.
        let mut whole = Vec::new();
        let _ = std::io::Read::read_to_end(&mut from, &mut whole);
        let end = whole.iter().rposition(|&b| b == b'\n').map_or(0, |i| i + 1);
        out.write_all(&whole[..end])?;
        out.flush()
    }

    /// Writes what was seen as plain text, a line per line.
    pub fn export_text(&self, id: &str, to: &Path) -> std::io::Result<()> {
        let mut out = std::io::BufWriter::new(create(to)?);
        out.write_all(self.plain_text(id)?.as_bytes())?;
        out.flush()
    }

    /// What was seen as plain text, a line per line: to copy it.
    pub fn plain_text(&self, id: &str) -> std::io::Result<String> {
        let mut out = String::new();
        for (_, line) in self.text(id)? {
            out.push_str(&line);
            out.push('\n');
        }
        Ok(out)
    }

    /// The text lines around a moment: up to `before` that began before
    /// it and `after` from it on. What a search result shows of itself.
    pub fn lines_around(
        &self,
        id: &str,
        at: f64,
        before: usize,
        after: usize,
    ) -> std::io::Result<Vec<(f64, String)>> {
        self.recorded(id)?;
        let mut earlier = std::collections::VecDeque::with_capacity(before + 1);
        let mut later = Vec::new();
        for_each_line(&self.text_path(id), |t, line| {
            if t < at {
                earlier.push_back((t, line.to_owned()));
                if earlier.len() > before {
                    earlier.pop_front();
                }
                true
            } else {
                later.push((t, line.to_owned()));
                later.len() < after
            }
        })?;
        Ok(earlier.into_iter().chain(later).collect())
    }

    /// What the page shows of a session: its last text lines and its
    /// markers (commands and OpenWard's own), without replaying it.
    pub fn preview(&self, id: &str, lines: usize) -> std::io::Result<Preview> {
        self.recorded(id)?;
        let mut last = std::collections::VecDeque::with_capacity(lines + 1);
        for_each_line(&self.text_path(id), |t, line| {
            last.push_back((t, line.to_owned()));
            if last.len() > lines {
                last.pop_front();
            }
            true
        })?;
        Ok(Preview {
            lines: last.into(),
            markers: self.markers(id)?,
        })
    }

    /// A recording's markers, `(seconds, label)`, reading only those.
    pub fn markers(&self, id: &str) -> std::io::Result<Vec<(f64, String)>> {
        self.recorded(id)?;
        let file = File::open(self.cast_path(id))?;
        let mut input = BufReader::new(MultiGzDecoder::new(file));
        let mut line = String::new();
        let mut markers = Vec::new();
        // The header.
        input.read_line(&mut line)?;
        loop {
            line.clear();
            match input.read_line(&mut line) {
                Ok(0) | Err(_) => break,
                Ok(_) if !line.ends_with('\n') => break,
                Ok(_) => {}
            }
            // Output is most of it: only markers are parsed.
            if !line.contains(", \"m\", ") {
                continue;
            }
            if let Ok((t, code, label)) = serde_json::from_str::<(f64, String, String)>(&line)
                && code == "m"
            {
                markers.push((t, label));
            }
        }
        Ok(markers)
    }

    /// The `index`th command (from 0), its line and what came out after
    /// it: what «only the chosen command» exports. Its marker comes at
    /// Enter, so the lines completed from there to the next marker are the
    /// command's; the line being written at the next one (the next prompt)
    /// is not.
    pub fn command_text(&self, id: &str, index: usize) -> std::io::Result<String> {
        let rec = self.read(id)?;
        let mut filter = text::TextFilter::default();
        let mut seen = 0;
        let mut found = false;
        let mut out = String::new();
        for (t, event) in &rec.events {
            match event {
                cast::Event::Output(s) => {
                    let keep = found;
                    filter.feed(*t, s, &mut |_, line| {
                        if keep {
                            out.push_str(line);
                            out.push('\n');
                        }
                    });
                }
                cast::Event::Marker(label) if cast::command_of(label).is_some() => {
                    if found {
                        return Ok(out);
                    }
                    found = seen == index;
                    seen += 1;
                }
                _ => {}
            }
        }
        if found {
            Ok(out)
        } else {
            Err(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("no command {index}"),
            ))
        }
    }

    /// A player for a recording, with a terminal of its own.
    pub fn player(&self, id: &str, scrollback: usize) -> std::io::Result<Arc<Player>> {
        Ok(Player::new(self.read(id)?, scrollback))
    }

    fn finished(&self, entry: Entry) {
        {
            let mut inner = lock(&self.inner);
            inner.open.remove(&entry.id);
            inner.entries.insert(entry.id.clone(), entry);
        }
        self.prune();
        self.changed();
    }
}

fn write_entry(dir: &Path, entry: &Entry) -> std::io::Result<()> {
    let path = dir.join(format!("{}.json", entry.id));
    let tmp = dir.join(format!("{}.json.tmp", entry.id));
    let mut file = create(&tmp)?;
    file.write_all(&serde_json::to_vec_pretty(entry).map_err(std::io::Error::other)?)?;
    file.sync_all()?;
    fs::rename(tmp, path)
}

fn files_size(dir: &Path, id: &str) -> u64 {
    ["cast.gz", "txt.gz"]
        .iter()
        .filter_map(|ext| fs::metadata(dir.join(format!("{id}.{ext}"))).ok())
        .map(|m| m.len())
        .sum()
}

/// Calls `f` with each whole line of a text file until it returns false.
fn for_each_line(path: &Path, mut f: impl FnMut(f64, &str) -> bool) -> std::io::Result<()> {
    let mut input = BufReader::new(MultiGzDecoder::new(File::open(path)?));
    let mut line = String::new();
    loop {
        line.clear();
        match input.read_line(&mut line) {
            Ok(0) | Err(_) => return Ok(()),
            Ok(_) if !line.ends_with('\n') => return Ok(()),
            Ok(_) => {}
        }
        let Some((t, text)) = line.trim_end_matches('\n').split_once('\t') else {
            continue;
        };
        let Ok(t) = t.parse() else { continue };
        if !f(t, text) {
            return Ok(());
        }
    }
}

/// A session going on: what its terminal tells, to its entry and its
/// recording.
pub struct Session {
    logs: Arc<Logs>,
    recorder: Option<Recorder>,
    entry: Mutex<Entry>,
}

impl Session {
    pub fn id(&self) -> String {
        lock(&self.entry).id.clone()
    }

    pub fn recording(&self) -> bool {
        self.recorder.is_some()
    }

    pub(crate) fn output(&self, bytes: &[u8]) {
        if let Some(r) = &self.recorder {
            r.output(bytes);
        }
    }

    pub(crate) fn resize(&self, cols: u16, rows: u16) {
        if let Some(r) = &self.recorder {
            r.resize(cols, rows);
        }
    }

    pub(crate) fn mark(&self, mark: Mark) {
        if let Some(r) = &self.recorder {
            r.marker(mark.label().into());
        }
    }

    /// A command that ran: a marker to jump to.
    pub(crate) fn command(&self, command: &str) {
        let command = command.trim();
        if command.is_empty() {
            return;
        }
        if let Some(r) = &self.recorder {
            r.marker(cast::command_label(command));
            lock(&self.entry).commands += 1;
        }
    }

    pub(crate) fn set_tmux(&self, tmux: bool) {
        lock(&self.entry).tmux = tmux;
    }

    /// Stops recording what comes out, or starts again. False when there
    /// is no recording, or it already was so.
    pub(crate) fn pause(&self, paused: bool) -> bool {
        self.recorder.as_ref().is_some_and(|r| r.pause(paused))
    }

    pub fn paused(&self) -> bool {
        self.recorder.as_ref().is_some_and(Recorder::paused)
    }

    /// Why the recording stopped, if writing failed.
    pub fn failed(&self) -> Option<String> {
        self.recorder.as_ref().and_then(Recorder::failed)
    }

    /// Ends the session: the recording is closed and the entry says how
    /// it ended. Once; later calls do nothing.
    pub(crate) fn finish(&self, end: End) {
        let entry = {
            let mut entry = lock(&self.entry);
            if entry.end != End::Open {
                return;
            }
            if let Some(r) = &self.recorder {
                r.finish();
            }
            entry.end = end;
            entry.ended_ms = Some(now_ms().max(entry.started_ms));
            entry.bytes = files_size(&self.logs.dir, &entry.id);
            entry.clone()
        };
        let _ = write_entry(&self.logs.dir, &entry);
        self.logs.finished(entry);
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.finish(End::Closed);
    }
}

#[cfg(test)]
mod tests;
