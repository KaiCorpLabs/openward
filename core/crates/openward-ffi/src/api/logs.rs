//! Session logs as Dart sees them: the entries, the search, saving and
//! exporting, and a player for a recording (docs/plan/registros.md).

use std::path::Path;
use std::sync::Arc;

use flutter_rust_bridge::frb;
use openward_app::logs::{self, End, Entry, Place, Player, cast};

use super::app::OpenWard;
use super::session::TerminalSession;
use super::vault::{VaultError, VaultErrorKind};
use crate::frb_generated::StreamSink;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LogPlace {
    Host,
    Address,
    Local,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LogEnd {
    /// Still going.
    Open,
    Closed,
    /// The connection went away and did not come back.
    Lost,
    /// OpenWard closed without ending it.
    AppQuit,
}

/// How the host was marked when the session began.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LogMarking {
    pub name: String,
    pub short: String,
    /// A palette color by name, as in a host's environment.
    pub color: String,
}

/// A session, recorded or not.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LogEntry {
    pub id: String,
    pub place: LogPlace,
    /// With [`LogPlace::Host`].
    pub host_id: Option<String>,
    /// The host's name or the address when it began; a local program's
    /// name, or empty for the shell.
    pub label: String,
    /// `user@host[:port]`, or `~` for a local terminal.
    pub address: String,
    pub marking: Option<LogMarking>,
    /// The system's code, if it was known.
    pub system: Option<String>,
    pub started_ms: i64,
    pub ended_ms: Option<i64>,
    pub end: LogEnd,
    pub tmux: bool,
    /// What came out is recorded, not only the entry.
    pub recorded: bool,
    pub bytes: u64,
    pub commands: u32,
    /// Kept until taken back, whatever the limits.
    pub saved: bool,
    pub note: String,
}

fn entry_view(e: Entry) -> LogEntry {
    let (place, host_id) = match e.place {
        Place::Host(id) => (LogPlace::Host, Some(id)),
        Place::Address(_) => (LogPlace::Address, None),
        Place::Local => (LogPlace::Local, None),
    };
    LogEntry {
        id: e.id,
        place,
        host_id,
        label: e.label,
        address: e.address,
        marking: e.marking.map(|m| LogMarking {
            name: m.name,
            short: m.short,
            color: m.color,
        }),
        system: e.system,
        started_ms: e.started_ms,
        ended_ms: e.ended_ms,
        end: match e.end {
            End::Open => LogEnd::Open,
            End::Closed => LogEnd::Closed,
            End::Lost => LogEnd::Lost,
            End::AppQuit => LogEnd::AppQuit,
        },
        tmux: e.tmux,
        recorded: e.recorded,
        bytes: e.bytes,
        commands: e.commands,
        saved: e.saved.is_some(),
        note: e.saved.map(|s| s.note).unwrap_or_default(),
    }
}

/// A line that matched.
#[derive(Clone, Debug, PartialEq)]
pub struct LogHit {
    /// Seconds from the start, to open the recording there.
    pub at: f64,
    pub line: String,
}

/// A session with matches: the first ones, and how many in all.
#[derive(Clone, Debug, PartialEq)]
pub struct LogFound {
    pub entry: LogEntry,
    pub hits: Vec<LogHit>,
    pub total: u32,
}

/// A line of what was seen, with the moment it began.
#[derive(Clone, Debug, PartialEq)]
pub struct LogLine {
    pub at: f64,
    pub text: String,
}

fn lines_view(lines: Vec<(f64, String)>) -> Vec<LogLine> {
    lines
        .into_iter()
        .map(|(at, text)| LogLine { at, text })
        .collect()
}

/// What the page shows of a recorded session, without opening it.
#[derive(Clone, Debug, PartialEq)]
pub struct LogPreview {
    /// The last lines.
    pub lines: Vec<LogLine>,
    pub markers: Vec<LogMarker>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LogsUsage {
    pub bytes: u64,
    pub entries: u32,
    pub recorded: u32,
    pub saved: u32,
}

/// This device's choices for the logs, from Ajustes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LogsConfig {
    /// Record local terminals too.
    pub record_local: bool,
    /// Days kept; 0 keeps them.
    pub keep_days: u32,
    /// The most the logs take; 0 for no limit.
    pub max_bytes: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LogFormat {
    /// asciicast v2, what asciinema plays.
    Cast,
    /// What was seen, as plain text.
    Text,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LogMarkerKind {
    Command,
    /// The user paused the recording: nothing was kept until `Resume`.
    Pause,
    Resume,
    /// The connection stopped answering.
    Lost,
    Back,
    /// Some output was left out (it came faster than the disk took it).
    Omitted,
    /// The recording reached its most: nothing after this.
    Full,
    Other,
}

#[derive(Clone, Debug, PartialEq)]
pub struct LogMarker {
    pub at: f64,
    pub kind: LogMarkerKind,
    /// With [`LogMarkerKind::Command`].
    pub command: String,
}

fn marker_view((at, label): (f64, String)) -> LogMarker {
    if let Some(command) = cast::command_of(&label) {
        return LogMarker {
            at,
            kind: LogMarkerKind::Command,
            command: command.to_owned(),
        };
    }
    let kind = match cast::Mark::from_label(&label) {
        Some(cast::Mark::Pause) => LogMarkerKind::Pause,
        Some(cast::Mark::Resume) => LogMarkerKind::Resume,
        Some(cast::Mark::Lost) => LogMarkerKind::Lost,
        Some(cast::Mark::Back) => LogMarkerKind::Back,
        Some(cast::Mark::Omitted) => LogMarkerKind::Omitted,
        Some(cast::Mark::Full) => LogMarkerKind::Full,
        None => LogMarkerKind::Other,
    };
    LogMarker {
        at,
        kind,
        command: String::new(),
    }
}

impl From<std::io::Error> for VaultError {
    fn from(e: std::io::Error) -> Self {
        Self {
            kind: if e.kind() == std::io::ErrorKind::NotFound {
                VaultErrorKind::NotFound
            } else {
                VaultErrorKind::Storage
            },
            message: e.to_string(),
        }
    }
}

impl OpenWard {
    /// Every session, the newest first.
    #[frb(sync)]
    pub fn logs(&self) -> Vec<LogEntry> {
        self.app.logs().list().into_iter().map(entry_view).collect()
    }

    #[frb(sync)]
    pub fn log(&self, id: String) -> Option<LogEntry> {
        self.app.logs().entry(&id).map(entry_view)
    }

    /// An event each time sessions begin, end, change or go: read them
    /// again then.
    pub fn watch_logs(&self, changes: StreamSink<bool>) {
        self.app.logs().watch(Arc::new(move || {
            let _ = changes.add(true);
        }));
    }

    #[frb(sync)]
    pub fn logs_usage(&self) -> LogsUsage {
        let u = self.app.logs().usage();
        LogsUsage {
            bytes: u.bytes,
            entries: u.entries,
            recorded: u.recorded,
            saved: u.saved,
        }
    }

    #[frb(sync)]
    pub fn logs_config(&self) -> LogsConfig {
        let c = self.app.logs().config();
        LogsConfig {
            record_local: c.record_local,
            keep_days: c.keep_days,
            max_bytes: c.max_bytes,
        }
    }

    /// From Ajustes, at start and on change; the limits apply at once.
    #[frb(sync)]
    pub fn set_logs_config(&self, config: LogsConfig) {
        self.app.logs().set_config(logs::Config {
            record_local: config.record_local,
            keep_days: config.keep_days,
            max_bytes: config.max_bytes,
        });
    }

    /// The folder the logs are in, to show it.
    #[frb(sync)]
    pub fn logs_dir(&self) -> String {
        self.app.logs().dir().to_string_lossy().into_owned()
    }

    /// Looks for `query` (ignoring case) in what was seen, the newest
    /// sessions first; each one with matches comes on the stream as it is
    /// found, and the stream ends with the search.
    pub fn search_logs(&self, query: String, found: StreamSink<LogFound>) {
        self.app.logs().search(&query, |f| {
            found
                .add(LogFound {
                    entry: entry_view(f.entry),
                    hits: f
                        .hits
                        .into_iter()
                        .map(|h| LogHit {
                            at: h.at,
                            line: h.line,
                        })
                        .collect(),
                    total: f.total as u32,
                })
                // Nobody listens any more: stop.
                .is_ok()
        });
    }

    /// Keeps a session for good with a note, or changes its note.
    pub fn save_log(&self, id: String, note: String) -> Result<(), VaultError> {
        Ok(self.app.logs().save(&id, &note)?)
    }

    /// Lets the limits delete it again.
    pub fn unsave_log(&self, id: String) -> Result<(), VaultError> {
        Ok(self.app.logs().unsave(&id)?)
    }

    /// False for a session still going on.
    pub fn delete_log(&self, id: String) -> Result<bool, VaultError> {
        Ok(self.app.logs().delete(&id)?)
    }

    /// Every session but those going on, saved ones too; how many went.
    pub fn delete_all_logs(&self) -> Result<u32, VaultError> {
        Ok(self.app.logs().delete_all()?)
    }

    pub fn export_log(
        &self,
        id: String,
        path: String,
        format: LogFormat,
    ) -> Result<(), VaultError> {
        let logs = self.app.logs();
        let to = Path::new(&path);
        match format {
            LogFormat::Cast => logs.export_cast(&id, to)?,
            LogFormat::Text => logs.export_text(&id, to)?,
        }
        Ok(())
    }

    /// The `index`th command (from 0) of a recording, with what came out
    /// of it, as text.
    pub fn log_command_text(&self, id: String, index: u32) -> Result<String, VaultError> {
        Ok(self.app.logs().command_text(&id, index as usize)?)
    }

    /// The last `lines` lines of a recording and its markers.
    pub fn log_preview(&self, id: String, lines: u32) -> Result<LogPreview, VaultError> {
        let p = self.app.logs().preview(&id, lines as usize)?;
        Ok(LogPreview {
            lines: lines_view(p.lines),
            markers: p.markers.into_iter().map(marker_view).collect(),
        })
    }

    /// The lines around a moment (a search's match): `before` lines that
    /// began earlier and `after` from it on.
    pub fn log_lines_around(
        &self,
        id: String,
        at: f64,
        before: u32,
        after: u32,
    ) -> Result<Vec<LogLine>, VaultError> {
        let lines = self
            .app
            .logs()
            .lines_around(&id, at, before as usize, after as usize)?;
        Ok(lines_view(lines))
    }

    /// What was seen as plain text, to copy.
    pub fn log_text(&self, id: String) -> Result<String, VaultError> {
        Ok(self.app.logs().plain_text(&id)?)
    }

    /// A player for a recording, at its start.
    pub fn open_log(&self, id: String, scrollback: u32) -> Result<LogPlayer, VaultError> {
        let player = self.app.logs().player(&id, scrollback as usize)?;
        Ok(LogPlayer { player })
    }
}

/// A recording played back into a terminal of its own.
#[frb(opaque)]
pub struct LogPlayer {
    player: Arc<Player>,
}

impl LogPlayer {
    /// Its terminal, to draw like any other (never to type into).
    #[frb(sync)]
    pub fn session(&self) -> TerminalSession {
        TerminalSession {
            term: self.player.terminal(),
        }
    }

    #[frb(sync)]
    pub fn duration(&self) -> f64 {
        self.player.duration()
    }

    /// False when it stops short (OpenWard closed suddenly).
    #[frb(sync)]
    pub fn complete(&self) -> bool {
        self.player.complete()
    }

    #[frb(sync)]
    pub fn markers(&self) -> Vec<LogMarker> {
        self.player.markers().into_iter().map(marker_view).collect()
    }

    #[frb(sync)]
    pub fn position(&self) -> f64 {
        self.player.position()
    }

    #[frb(sync)]
    pub fn playing(&self) -> bool {
        self.player.playing()
    }

    /// The screen as it was at `at` seconds. Off the UI thread: going back
    /// plays everything before again.
    pub fn seek(&self, at: f64) {
        self.player.seek(at);
    }

    /// Plays on, `speed` times as fast (from the start, if at the end).
    #[frb(sync)]
    pub fn play(&self, speed: f64) {
        self.player.play(speed);
    }

    #[frb(sync)]
    pub fn pause(&self) {
        self.player.pause();
    }
}
