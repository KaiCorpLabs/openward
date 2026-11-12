//! Saved tunnels as Dart sees them: what each is and how it stands.

use flutter_rust_bridge::frb;
use openward_app::vault::proto::{Data, ForwardKind, PortForward};
use openward_app::{TunnelError, TunnelInfo, TunnelState};

use super::app::OpenWard;
use super::session::{FailureView, SessionEvent, failure_view};
use super::vault::VaultError;
use super::vault::id;
use crate::frb_generated::StreamSink;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TunnelKind {
    /// `-L`: a port here that reaches a service the server sees.
    Local,
    /// `-R`: a port on the server that reaches a service here.
    Remote,
    /// `-D`: a SOCKS5 proxy here; connections leave from the server.
    Dynamic,
}

/// What a tunnel is, to create or edit.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TunnelSpec {
    pub label: String,
    pub host_id: String,
    pub kind: TunnelKind,
    pub listen_port: u16,
    /// `None`: this machine only (loopback). `0.0.0.0`: the local network.
    pub listen_address: Option<String>,
    /// For local and remote ones.
    pub dest_host: Option<String>,
    pub dest_port: Option<u16>,
    pub autostart: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TunnelStateKind {
    Closed,
    Opening,
    Open,
    Failed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TunnelErrorKind {
    /// The port is taken (or, on the server, not allowed).
    PortInUse,
    BadAddress,
    /// No connection to the host: see `failure`.
    Connection,
    Lost,
    Other,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TunnelErrorView {
    pub kind: TunnelErrorKind,
    pub port: u16,
    /// The port was on the server.
    pub remote: bool,
    pub failure: Option<FailureView>,
    /// In English, for logs.
    pub message: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TunnelView {
    pub id: String,
    pub rev: u64,
    pub spec: TunnelSpec,
    pub host_label: String,
    /// It came from `~/.ssh/config`.
    pub imported: bool,
    pub state: TunnelStateKind,
    /// While open: where it listens and how many connections go through.
    pub port: u16,
    pub connections: u32,
    pub error: Option<TunnelErrorView>,
    /// The failure happened as its host connected.
    pub on_connect: bool,
}

fn kind_view(k: ForwardKind) -> TunnelKind {
    match k {
        ForwardKind::Local => TunnelKind::Local,
        ForwardKind::Remote => TunnelKind::Remote,
        ForwardKind::Dynamic => TunnelKind::Dynamic,
    }
}

fn spec_view(f: &PortForward) -> TunnelSpec {
    TunnelSpec {
        label: f.label.clone(),
        host_id: f.host.to_string(),
        kind: kind_view(f.kind),
        listen_port: f.listen_port,
        listen_address: f.listen_address.clone(),
        dest_host: f.dest_host.clone(),
        dest_port: f.dest_port,
        autostart: f.autostarts(),
    }
}

/// Writes `spec` over `f`, keeping what OpenWard does not know.
fn apply(spec: &TunnelSpec, f: &mut PortForward) -> anyhow::Result<()> {
    f.label = spec.label.trim().to_owned();
    f.host = id(&spec.host_id)?;
    f.kind = match spec.kind {
        TunnelKind::Local => ForwardKind::Local,
        TunnelKind::Remote => ForwardKind::Remote,
        TunnelKind::Dynamic => ForwardKind::Dynamic,
    };
    f.listen_port = spec.listen_port;
    f.listen_address = spec.listen_address.clone().filter(|a| !a.trim().is_empty());
    let dynamic = f.kind == ForwardKind::Dynamic;
    f.dest_host = spec
        .dest_host
        .clone()
        .filter(|h| !dynamic && !h.trim().is_empty());
    f.dest_port = spec.dest_port.filter(|_| !dynamic);
    f.set_autostart(spec.autostart);
    Ok(())
}

/// What a tunnel forwards, without its name or when it opens.
#[allow(clippy::type_complexity)]
fn forward_of(
    f: &PortForward,
) -> (
    String,
    ForwardKind,
    u16,
    Option<String>,
    Option<String>,
    Option<u16>,
) {
    (
        f.host.to_string(),
        f.kind,
        f.listen_port,
        f.listen_address.clone(),
        f.dest_host.clone(),
        f.dest_port,
    )
}

fn error_view(e: &TunnelError) -> TunnelErrorView {
    let mut v = TunnelErrorView {
        kind: TunnelErrorKind::Other,
        port: 0,
        remote: false,
        failure: None,
        message: e.to_string(),
    };
    match e {
        TunnelError::PortInUse { port, remote } => {
            v.kind = TunnelErrorKind::PortInUse;
            v.port = *port;
            v.remote = *remote;
        }
        TunnelError::BadAddress(_) => v.kind = TunnelErrorKind::BadAddress,
        TunnelError::Connection(f) => {
            v.kind = TunnelErrorKind::Connection;
            v.failure = Some(failure_view(f.clone()));
        }
        TunnelError::Lost => v.kind = TunnelErrorKind::Lost,
        TunnelError::Other(_) => {}
    }
    v
}

fn view(t: TunnelInfo) -> TunnelView {
    let (state, port, connections, error, on_connect) = match &t.state {
        TunnelState::Closed => (TunnelStateKind::Closed, 0, 0, None, false),
        TunnelState::Opening => (TunnelStateKind::Opening, 0, 0, None, false),
        TunnelState::Open { port, connections } => {
            (TunnelStateKind::Open, *port, *connections, None, false)
        }
        TunnelState::Failed { error, on_connect } => (
            TunnelStateKind::Failed,
            0,
            0,
            Some(error_view(error)),
            *on_connect,
        ),
    };
    TunnelView {
        id: t.id.to_string(),
        rev: t.rev,
        spec: spec_view(&t.spec),
        host_label: t.host_label,
        imported: t.spec.source.is_some(),
        state,
        port,
        connections,
        error,
        on_connect,
    }
}

impl OpenWard {
    /// Every saved tunnel with its state now, by name.
    /// An event each time a tunnel opens, closes or fails, or a local
    /// tunnel's connections change: ask [`OpenWard::tunnels`] then. A remote
    /// tunnel's connections change without one.
    pub fn watch_tunnels(&self, changes: StreamSink<bool>) {
        self.app.watch_tunnels(std::sync::Arc::new(move || {
            let _ = changes.add(true);
        }));
    }

    /// An event each time the vault changes, whoever changed it: read
    /// hosts, tunnels, identities, snippets and workspaces again then.
    pub fn watch_vault(&self, changes: StreamSink<bool>) {
        self.app.watch_vault(std::sync::Arc::new(move || {
            let _ = changes.add(true);
        }));
    }

    #[frb(sync)]
    pub fn tunnels(&self) -> Vec<TunnelView> {
        let gate = self.app.security().gate();
        super::security::access(&gate, true, || {
            self.app.tunnels().into_iter().map(view).collect()
        })
        .unwrap_or_default()
    }

    pub fn create_tunnel(&self, spec: TunnelSpec) -> Result<String, VaultError> {
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            let mut f = PortForward {
                label: String::new(),
                host: id(&spec.host_id)?,
                kind: ForwardKind::Local,
                listen_port: 0,
                listen_address: None,
                dest_host: None,
                dest_port: None,
                autostart: false,
                source: None,
                imported: None,
                extra: Default::default(),
            };
            apply(&spec, &mut f)?;
            Ok(self.app.vault().create(Data::PortForward(f))?.to_string())
        })?
    }

    /// Returns the new revision. An open tunnel whose forward changed
    /// closes, to open again as it is now; a new name or "open on connect"
    /// leaves it open.
    pub fn update_tunnel(&self, id: String, rev: u64, spec: TunnelSpec) -> Result<u64, VaultError> {
        let gate = self.app.security().gate();
        super::security::access(&gate, false, || {
            let tid = super::vault::id(&id)?;
            let mut f = self.app.vault().port_forward(tid)?.clone();
            let before = forward_of(&f);
            apply(&spec, &mut f)?;
            let changed = forward_of(&f) != before;
            let rev = self.app.vault().update(tid, rev, Data::PortForward(f))?;
            if changed {
                self.app.close_tunnel(tid);
            }
            Ok(rev)
        })?
    }

    /// Opens a tunnel, connecting to its host if needed. The stream is that
    /// connection's events (questions, and `connected` once it listens).
    pub fn open_tunnel(&self, id: String, events: StreamSink<SessionEvent>) {
        let gate = self.app.security().gate();
        super::security::connection(&gate, None, events, |sink| {
            self.app.open_tunnel(super::vault::id(&id)?, sink)?;
            Ok(())
        })
    }

    /// Closes it (and forgets an error it had).
    #[frb(sync)]
    pub fn close_tunnel(&self, id: String) -> Result<(), VaultError> {
        let gate = self.app.security().gate();
        super::security::access(&gate, true, || {
            self.app.close_tunnel(super::vault::id(&id)?);
            Ok(())
        })?
    }

    /// A free port here after `port`, to offer when that one is taken.
    #[frb(sync)]
    pub fn free_port_near(&self, port: u16) -> Option<u16> {
        let gate = self.app.security().gate();
        super::security::access(&gate, true, || self.app.free_port_near(port)).unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use openward_app::vault::proto::{Body, Imported, ItemId};

    #[test]
    fn legacy_imports_need_editor_approval_but_manual_tunnels_keep_autostart() {
        for kind in [
            ForwardKind::Local,
            ForwardKind::Remote,
            ForwardKind::Dynamic,
        ] {
            let mut f = PortForward {
                label: "Database".into(),
                host: ItemId::new(),
                kind,
                listen_port: 5433,
                listen_address: None,
                dest_host: Some("127.0.0.1".into()),
                dest_port: Some(5432),
                autostart: true,
                source: None,
                imported: None,
                extra: Default::default(),
            };
            assert!(spec_view(&f).autostart, "manual tunnels keep their setting");
            f.imported = Some(Imported {
                from: "termius".into(),
                id: "legacy-tunnel".into(),
                extra: Default::default(),
            });
            assert!(!f.autostarts());
            assert!(
                !spec_view(&f).autostart,
                "the editor must show the effective state"
            );

            let mut spec = spec_view(&f);
            spec.autostart = true;
            apply(&spec, &mut f).unwrap();
            assert!(f.autostarts(), "explicit editor approval enables it");
            let body = Body {
                created: 1,
                modified: 2,
                data: Data::PortForward(f),
            };
            let Data::PortForward(mut restored) = Body::from_cbor(&body.to_cbor()).unwrap().data
            else {
                panic!("expected a tunnel");
            };
            assert!(restored.autostarts(), "approval must survive storage");
            spec.autostart = false;
            apply(&spec, &mut restored).unwrap();
            assert!(!restored.autostarts());
            // Setting only the old bit cannot resurrect a revoked approval.
            restored.autostart = true;
            assert!(!restored.autostarts());
        }
    }
}
