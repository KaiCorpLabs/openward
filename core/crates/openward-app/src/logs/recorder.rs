//! Writes one session's recording on a thread of its own: the terminal
//! only queues what came out, under its lock, and never waits for the
//! disk.
//!
//! Two gzip files: the asciicast and the searchable text. Both are
//! flushed every [`FLUSH_EVERY`] while output comes, so a sudden exit
//! loses at most those last seconds.

use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::Path;
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use flate2::Compression;
use flate2::write::GzEncoder;

use super::cast::{self, Header, Mark, Utf8Stream};
use super::text::TextFilter;

/// How often what was written reaches the file.
const FLUSH_EVERY: Duration = Duration::from_secs(2);
/// How long the writer sleeps when nothing comes.
const IDLE_WAIT: Duration = Duration::from_millis(250);
/// The writer is woken early past this much waiting output.
const WAKE_AT: usize = 256 * 1024;
/// Output waiting past this (a disk far slower than the program) is left
/// out, and a marker says so: the terminal never waits.
const MAX_QUEUED: usize = 32 * 1024 * 1024;
/// The most output one recording keeps (before compression).
pub(crate) const MAX_OUTPUT: u64 = 1024 * 1024 * 1024;
/// Two outputs this close are written as one event, up to this size: a
/// shell echoing keys sends many small ones; a flood, big ones that need
/// no joining (and copying again to join).
const COALESCE: f64 = 0.01;
const COALESCE_UP_TO: usize = 16 * 1024;

enum Pending {
    Output(f64, Vec<u8>),
    Resize(f64, u16, u16),
    Marker(f64, String),
}

struct Queue {
    events: Vec<Pending>,
    bytes: usize,
    /// Output left out since the last write.
    omitted: u64,
    /// Output taken so far.
    total: u64,
    paused: bool,
    full: bool,
    done: bool,
    /// The writer stopped on an error.
    failed: Option<String>,
}

struct Shared {
    queue: Mutex<Queue>,
    wake: Condvar,
    start: Instant,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

pub(crate) struct Recorder {
    shared: Arc<Shared>,
    writer: Mutex<Option<JoinHandle<()>>>,
}

impl Recorder {
    /// Creates both files and starts the writer.
    pub(crate) fn start(
        cast_path: &Path,
        text_path: &Path,
        header: &Header,
    ) -> std::io::Result<Self> {
        let result = Self::start_writer(cast_path, text_path, header);
        if result.is_err() {
            // A failed second file, header or thread start must not leave
            // the first recording as an unindexed session on disk.
            let _ = std::fs::remove_file(cast_path);
            let _ = std::fs::remove_file(text_path);
        }
        result
    }

    fn start_writer(cast_path: &Path, text_path: &Path, header: &Header) -> std::io::Result<Self> {
        let mut cast = GzEncoder::new(
            BufWriter::new(super::create(cast_path)?),
            Compression::fast(),
        );
        let text = GzEncoder::new(
            BufWriter::new(super::create(text_path)?),
            Compression::fast(),
        );
        cast.write_all(header.line().as_bytes())?;
        let shared = Arc::new(Shared {
            queue: Mutex::new(Queue {
                events: Vec::new(),
                bytes: 0,
                omitted: 0,
                total: 0,
                paused: false,
                full: false,
                done: false,
                failed: None,
            }),
            wake: Condvar::new(),
            start: Instant::now(),
        });
        let theirs = Arc::clone(&shared);
        let writer = thread::Builder::new()
            .name("openward-log".into())
            .spawn(move || write_loop(&theirs, cast, text))?;
        Ok(Self {
            shared,
            writer: Mutex::new(Some(writer)),
        })
    }

    fn now(&self) -> f64 {
        self.shared.start.elapsed().as_secs_f64()
    }

    /// Output from the program, as the terminal got it.
    pub(crate) fn output(&self, bytes: &[u8]) {
        let t = self.now();
        let mut q = lock(&self.shared.queue);
        if q.paused || q.full || q.done || q.failed.is_some() {
            return;
        }
        let n = bytes.len();
        if q.total + n as u64 > MAX_OUTPUT {
            q.full = true;
            q.events.push(Pending::Marker(t, Mark::Full.label().into()));
            return;
        }
        if q.bytes + n > MAX_QUEUED {
            q.omitted += n as u64;
            return;
        }
        q.total += n as u64;
        q.bytes += n;
        match q.events.last_mut() {
            Some(Pending::Output(t0, buf))
                if t - *t0 < COALESCE && buf.len() + n <= COALESCE_UP_TO =>
            {
                buf.extend_from_slice(bytes)
            }
            _ => q.events.push(Pending::Output(t, bytes.to_vec())),
        }
        if q.bytes >= WAKE_AT {
            self.shared.wake.notify_one();
        }
    }

    pub(crate) fn resize(&self, cols: u16, rows: u16) {
        let t = self.now();
        let mut q = lock(&self.shared.queue);
        if !q.done {
            q.events.push(Pending::Resize(t, cols, rows));
        }
    }

    pub(crate) fn marker(&self, label: String) {
        let t = self.now();
        let mut q = lock(&self.shared.queue);
        if !q.done && !q.full {
            q.events.push(Pending::Marker(t, label));
        }
    }

    /// A command's marker, unless paused: what runs in a pause is not
    /// kept, not even its name. False if it was left out.
    pub(crate) fn command(&self, label: String) -> bool {
        let t = self.now();
        let mut q = lock(&self.shared.queue);
        if q.paused || q.done || q.full {
            return false;
        }
        q.events.push(Pending::Marker(t, label));
        true
    }

    /// Stops keeping output, or starts again; a marker notes each. False
    /// if it already was so.
    pub(crate) fn pause(&self, paused: bool) -> bool {
        let t = self.now();
        let mut q = lock(&self.shared.queue);
        if q.paused == paused || q.done {
            return false;
        }
        q.paused = paused;
        let mark = if paused { Mark::Pause } else { Mark::Resume };
        q.events.push(Pending::Marker(t, mark.label().into()));
        true
    }

    pub(crate) fn paused(&self) -> bool {
        lock(&self.shared.queue).paused
    }

    /// Why it stopped writing, if it did.
    pub(crate) fn failed(&self) -> Option<String> {
        lock(&self.shared.queue).failed.clone()
    }

    /// Writes what is left and closes the files. Once; later calls return
    /// at once.
    pub(crate) fn finish(&self) {
        lock(&self.shared.queue).done = true;
        self.shared.wake.notify_one();
        if let Some(writer) = lock(&self.writer).take() {
            let _ = writer.join();
        }
    }
}

impl Drop for Recorder {
    fn drop(&mut self) {
        self.finish();
    }
}

type Gz = GzEncoder<BufWriter<File>>;

fn write_loop(shared: &Shared, mut cast: Gz, mut text: Gz) {
    let mut utf8 = Utf8Stream::default();
    let mut filter = TextFilter::default();
    let mut out = String::new();
    let mut lines = String::new();
    let mut stamp = (f64::NAN, String::new());
    let mut last_flush = Instant::now();
    let mut dirty = false;
    loop {
        let (events, omitted, done) = {
            let q = lock(&shared.queue);
            let (mut q, _) = shared
                .wake
                .wait_timeout_while(q, IDLE_WAIT, |q| q.events.is_empty() && !q.done)
                .unwrap_or_else(|e| e.into_inner());
            q.bytes = 0;
            (
                std::mem::take(&mut q.events),
                std::mem::take(&mut q.omitted),
                q.done,
            )
        };
        // Lines that began with the same output share its moment: it is
        // written out once.
        let mut emit = |t: f64, line: &str| {
            use std::fmt::Write as _;
            if t != stamp.0 {
                stamp.1.clear();
                let _ = write!(stamp.1, "{t:.3}\t");
                stamp.0 = t;
            }
            lines.push_str(&stamp.1);
            lines.push_str(line);
            lines.push('\n');
        };
        for event in &events {
            match event {
                Pending::Output(t, bytes) => {
                    let s = utf8.decode(bytes);
                    filter.feed(*t, &s, &mut emit);
                    cast::push_event(&mut out, *t, 'o', &s);
                }
                Pending::Resize(t, cols, rows) => {
                    cast::push_event(&mut out, *t, 'r', &cast::size_data(*cols, *rows));
                }
                Pending::Marker(t, label) => cast::push_event(&mut out, *t, 'm', label),
            }
        }
        if omitted > 0 {
            let t = shared.start.elapsed().as_secs_f64();
            cast::push_event(&mut out, t, 'm', Mark::Omitted.label());
        }
        if done {
            filter.finish(&mut emit);
        }
        let wrote = !out.is_empty() || !lines.is_empty();
        let result = (|| -> std::io::Result<()> {
            cast.write_all(out.as_bytes())?;
            text.write_all(lines.as_bytes())?;
            if done {
                cast.try_finish()?;
                text.try_finish()?;
                cast.get_mut().flush()?;
                text.get_mut().flush()?;
            } else if (dirty || wrote) && last_flush.elapsed() >= FLUSH_EVERY {
                // A sync flush: what is in the file so far reads back.
                cast.flush()?;
                text.flush()?;
                last_flush = Instant::now();
                dirty = false;
            } else if wrote {
                dirty = true;
            }
            Ok(())
        })();
        out.clear();
        lines.clear();
        if let Err(e) = result {
            let mut q = lock(&shared.queue);
            q.failed = Some(e.to_string());
            q.events.clear();
            return;
        }
        if done {
            return;
        }
    }
}
