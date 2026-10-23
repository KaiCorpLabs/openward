//! The trusted host keys as Dart lists them.

use flutter_rust_bridge::frb;
use openward_app::known::{KnownEntry, KnownSource, Marker};
use openward_app::vault::proto::ItemId;

use super::app::OpenWard;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KnownSourceKind {
    OpenWard,
    /// `~/.ssh/known_hosts`.
    File,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KnownMarkerKind {
    CertAuthority,
    Revoked,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KnownHostRow {
    pub source: KnownSourceKind,
    /// The vault item, for OpenWard's.
    pub id: String,
    /// The line, from 1, for the file's.
    pub line: u32,
    /// When OpenWard trusted it (ms since the epoch).
    pub added_ms: Option<i64>,
    /// As written; pass it back to `forget_known_host`.
    pub text: String,
    pub marker: Option<KnownMarkerKind>,
    /// The patterns; none when the name is hashed.
    pub hosts: Option<String>,
    /// For a hashed name: a host it stands for.
    pub revealed: Option<String>,
    pub algorithm: String,
    pub fingerprint: String,
    pub comment: Option<String>,
    /// Labels of the saved hosts it is for.
    pub saved: Vec<String>,
}

fn row(e: KnownEntry, label: impl Fn(ItemId) -> Option<String>) -> KnownHostRow {
    let (source, id, line, added_ms) = match e.source {
        KnownSource::OpenWard { id, added } => {
            (KnownSourceKind::OpenWard, id.to_string(), 0, Some(added))
        }
        KnownSource::File { line } => (KnownSourceKind::File, String::new(), line as u32, None),
    };
    KnownHostRow {
        source,
        id,
        line,
        added_ms,
        text: e.text,
        marker: e.marker.map(|m| match m {
            Marker::CertAuthority => KnownMarkerKind::CertAuthority,
            Marker::Revoked => KnownMarkerKind::Revoked,
        }),
        hosts: e.hosts,
        revealed: e.revealed,
        algorithm: e.algorithm,
        fingerprint: e.fingerprint,
        comment: e.comment,
        saved: e.saved.into_iter().filter_map(label).collect(),
    }
}

impl OpenWard {
    /// OpenWard's trusted keys and then `~/.ssh/known_hosts`', those that
    /// match `query` (all of them when empty). Off the UI thread: it reads
    /// the file and works out which hashed names are saved hosts.
    pub fn known_host_rows(&self, query: String) -> Vec<KnownHostRow> {
        let entries = self.app.known_hosts(&query);
        let vault = self.app.vault();
        entries
            .into_iter()
            .map(|e| row(e, |id| vault.host(id).ok().map(|h| h.label.clone())))
            .collect()
    }

    /// How many rows [`OpenWard::known_host_rows`] would list with no
    /// query, without working out their hosts: for a counter.
    pub fn known_host_count(&self) -> u32 {
        self.app.known_host_count() as u32
    }

    /// The `known_hosts` file OpenWard reads, as the UI names it.
    #[frb(sync)]
    pub fn known_hosts_file(&self) -> String {
        self.app.local().known_hosts_file().display().to_string()
    }

    /// Forgets a key: OpenWard's, or the line of the file if it still reads
    /// `text` (a copy of the file goes to `known_hosts.old` first).
    pub fn forget_known_host(&self, row: KnownHostRow) -> anyhow::Result<()> {
        let source = match row.source {
            KnownSourceKind::OpenWard => KnownSource::OpenWard {
                id: super::vault::id(&row.id)?,
                added: 0,
            },
            KnownSourceKind::File => KnownSource::File {
                line: row.line as usize,
            },
        };
        self.app.forget_known_host(source, &row.text)
    }
}
