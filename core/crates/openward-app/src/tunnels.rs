//! Saved tunnels, opened over the host's connection: the one a terminal or
//! a browser has up, or one of their own. An open tunnel keeps that
//! connection alive; closing it lets go. When the connection drops the
//! tunnel closes, and one that opens on connect comes back with the next
//! connection to its host.
//!
//! The UI asks for [`Tunnels::states`] as often as it repaints.

use std::collections::HashMap;
use std::io::ErrorKind;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use openward_vault::proto::{ForwardKind, ItemId, PortForward};
use tokio::net::TcpListener;
use tokio::runtime::Handle;
use tokio::task::JoinHandle;

use crate::connect::lock;
use crate::events::Failure;
use crate::live::Live;

/// How often an open tunnel checks that its connection is still there.
const WATCH: Duration = Duration::from_secs(1);

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TunnelState {
    Closed,
    /// Connecting to its host, or starting to listen.
    Opening,
    Open {
        /// The port it listens on (here, or on the server for a remote one).
        port: u16,
        /// Connections going through it now.
        connections: u32,
    },
    Failed {
        error: TunnelError,
        /// It was opening on its own, as its host connected.
        on_connect: bool,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TunnelError {
    /// The port is taken: here, or on the server for a remote tunnel (or
    /// the server does not allow forwarding).
    PortInUse {
        port: u16,
        remote: bool,
    },
    /// The address to listen on does not exist here.
    BadAddress(String),
    /// No connection to its host.
    Connection(Failure),
    /// The connection went away.
    Lost,
    Other(String),
}

impl std::fmt::Display for TunnelError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::PortInUse {
                port,
                remote: false,
            } => write!(f, "port {port} is in use here"),
            Self::PortInUse { port, remote: true } => {
                write!(f, "the server did not open port {port}")
            }
            Self::BadAddress(a) => write!(f, "cannot listen on {a}"),
            Self::Connection(failure) => write!(f, "{failure}"),
            Self::Lost => write!(f, "the connection was lost"),
            Self::Other(m) => write!(f, "{m}"),
        }
    }
}

/// An open tunnel: what it listens with, and the connection it holds.
struct Running {
    live: Arc<Live>,
    runtime: Handle,
    port: u16,
    active: Arc<AtomicU32>,
    tasks: Vec<JoinHandle<()>>,
    /// A remote tunnel's address and port on the server, to cancel it.
    remote: Option<(String, u32)>,
}

impl Drop for Running {
    fn drop(&mut self) {
        for t in &self.tasks {
            t.abort();
        }
        if let Some((address, port)) = self.remote.take() {
            let live = Arc::clone(&self.live);
            self.runtime
                .spawn(async move { live.target().cancel_remote_forward(&address, port).await });
        }
    }
}

#[derive(Default)]
struct State {
    running: HashMap<ItemId, Running>,
    /// What the others last did: opening, failed, closed.
    other: HashMap<ItemId, TunnelState>,
}

pub(crate) struct Tunnels {
    runtime: Handle,
    state: Arc<Mutex<State>>,
}

/// Where to listen: loopback unless the tunnel says otherwise.
fn listen_address(spec: &PortForward, remote: bool) -> String {
    match spec.listen_address.as_deref().map(str::trim) {
        None | Some("") | Some("localhost") => {
            if remote {
                "localhost".into()
            } else {
                "127.0.0.1".into()
            }
        }
        Some("*") => if remote { "" } else { "0.0.0.0" }.into(),
        Some(a) => a.trim_start_matches('[').trim_end_matches(']').into(),
    }
}

impl Tunnels {
    pub fn new(runtime: Handle) -> Self {
        Self {
            runtime,
            state: Arc::default(),
        }
    }

    /// The state of every tunnel the app has touched; the rest are closed.
    pub fn states(&self) -> HashMap<ItemId, TunnelState> {
        let s = lock(&self.state);
        let mut out = s.other.clone();
        for (id, r) in &s.running {
            out.insert(
                *id,
                TunnelState::Open {
                    port: r.port,
                    connections: r.active.load(Ordering::Relaxed),
                },
            );
        }
        out
    }

    pub fn is_open(&self, id: ItemId) -> bool {
        lock(&self.state).running.contains_key(&id)
    }

    pub fn set_state(&self, id: ItemId, state: TunnelState) {
        let mut s = lock(&self.state);
        s.running.remove(&id);
        s.other.insert(id, state);
    }

    /// Closes it, if open, and forgets it (it was deleted).
    pub fn forget(&self, id: ItemId) {
        let mut s = lock(&self.state);
        s.running.remove(&id);
        s.other.remove(&id);
    }

    /// Closes it, if open. The connection goes too, unless something else
    /// uses it.
    pub fn close(&self, id: ItemId) {
        let mut s = lock(&self.state);
        s.running.remove(&id);
        s.other.insert(id, TunnelState::Closed);
    }

    /// Opens `spec` over `live`. `on_connect` marks a failure as one of
    /// those opened as the host connected.
    pub async fn open_on(&self, id: ItemId, spec: PortForward, live: Arc<Live>, on_connect: bool) {
        let result = self.listen(&spec, &live).await;
        let mut s = lock(&self.state);
        match result {
            Ok(running) => {
                s.other.remove(&id);
                s.running.insert(id, running);
                drop(s);
                self.watch(id, live);
            }
            Err(error) => {
                s.running.remove(&id);
                s.other
                    .insert(id, TunnelState::Failed { error, on_connect });
            }
        }
    }

    /// Opens on `live` those of `forwards` that open on connect and are
    /// not open yet. Their failures stay in their state.
    pub async fn autostart(&self, live: &Arc<Live>, forwards: Vec<(ItemId, PortForward)>) {
        for (id, spec) in forwards {
            if !spec.autostart || self.is_open(id) {
                continue;
            }
            self.open_on(id, spec, Arc::clone(live), true).await;
        }
    }

    /// Closes the tunnel when its connection goes.
    fn watch(&self, id: ItemId, live: Arc<Live>) {
        let state = Arc::clone(&self.state);
        let weak = Arc::downgrade(&live);
        drop(live);
        self.runtime.spawn(async move {
            loop {
                tokio::time::sleep(WATCH).await;
                let Some(live) = weak.upgrade() else { return };
                let mut s = lock(&state);
                let ours = s
                    .running
                    .get(&id)
                    .is_some_and(|r| Arc::ptr_eq(&r.live, &live));
                if !ours {
                    return;
                }
                if live.is_closed() {
                    s.running.remove(&id);
                    s.other.insert(
                        id,
                        TunnelState::Failed {
                            error: TunnelError::Lost,
                            on_connect: false,
                        },
                    );
                    return;
                }
            }
        });
    }

    async fn listen(&self, spec: &PortForward, live: &Arc<Live>) -> Result<Running, TunnelError> {
        let active = Arc::new(AtomicU32::new(0));
        let mut running = Running {
            live: Arc::clone(live),
            runtime: self.runtime.clone(),
            port: spec.listen_port,
            active: Arc::clone(&active),
            tasks: Vec::new(),
            remote: None,
        };
        match spec.kind {
            ForwardKind::Remote => {
                let address = listen_address(spec, true);
                let dest = spec.dest_host.clone().unwrap_or_default();
                let dest_port = spec.dest_port.unwrap_or(0);
                live.target()
                    .remote_forward_on(
                        &address,
                        u32::from(spec.listen_port),
                        (&dest, dest_port),
                        active,
                    )
                    .await
                    .map_err(|_| TunnelError::PortInUse {
                        port: spec.listen_port,
                        remote: true,
                    })?;
                running.remote = Some((address, u32::from(spec.listen_port)));
            }
            ForwardKind::Local | ForwardKind::Dynamic => {
                let address = listen_address(spec, false);
                let ip = address
                    .parse()
                    .map_err(|_| TunnelError::BadAddress(address.clone()))?;
                let listener = TcpListener::bind(SocketAddr::new(ip, spec.listen_port))
                    .await
                    .map_err(|e| match e.kind() {
                        ErrorKind::AddrInUse | ErrorKind::PermissionDenied => {
                            TunnelError::PortInUse {
                                port: spec.listen_port,
                                remote: false,
                            }
                        }
                        ErrorKind::AddrNotAvailable => TunnelError::BadAddress(address.clone()),
                        _ => TunnelError::Other(e.to_string()),
                    })?;
                let task = if spec.kind == ForwardKind::Local {
                    self.runtime.spawn(serve_local(
                        listener,
                        Arc::clone(live),
                        spec.clone(),
                        active,
                    ))
                } else {
                    self.runtime
                        .spawn(serve_dynamic(listener, Arc::clone(live), active))
                };
                running.tasks.push(task);
            }
        }
        Ok(running)
    }
}

/// Counts a connection while it lasts.
struct Count(Arc<AtomicU32>);

impl Count {
    fn new(active: &Arc<AtomicU32>) -> Self {
        active.fetch_add(1, Ordering::Relaxed);
        Self(Arc::clone(active))
    }
}

impl Drop for Count {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::Relaxed);
    }
}

async fn serve_local(
    listener: TcpListener,
    live: Arc<Live>,
    spec: PortForward,
    active: Arc<AtomicU32>,
) {
    let host = spec.dest_host.unwrap_or_default();
    let port = u32::from(spec.dest_port.unwrap_or(0));
    while let Ok((mut socket, peer)) = listener.accept().await {
        let (live, host, active) = (Arc::clone(&live), host.clone(), Arc::clone(&active));
        tokio::spawn(async move {
            let _count = Count::new(&active);
            let Ok(channel) = live
                .target()
                .handle
                .channel_open_direct_tcpip(
                    host,
                    port,
                    peer.ip().to_string(),
                    u32::from(peer.port()),
                )
                .await
            else {
                return;
            };
            let mut stream = channel.into_stream();
            let _ = tokio::io::copy_bidirectional(&mut socket, &mut stream).await;
        });
    }
}

async fn serve_dynamic(listener: TcpListener, live: Arc<Live>, active: Arc<AtomicU32>) {
    while let Ok((socket, _)) = listener.accept().await {
        let (live, active) = (Arc::clone(&live), Arc::clone(&active));
        tokio::spawn(async move {
            let _count = Count::new(&active);
            let _ = openward_ssh::forward::socks5(socket, live.target()).await;
        });
    }
}

/// A port near `port` that is free here, to suggest when it is taken.
pub fn free_port_near(port: u16) -> Option<u16> {
    (1..=100u16)
        .filter_map(|d| port.checked_add(d))
        .find(|p| std::net::TcpListener::bind(("127.0.0.1", *p)).is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;
    use openward_vault::proto::Extra;

    fn spec(address: Option<&str>) -> PortForward {
        PortForward {
            label: "t".into(),
            host: ItemId::new(),
            kind: ForwardKind::Local,
            listen_port: 1,
            listen_address: address.map(str::to_owned),
            dest_host: None,
            dest_port: None,
            autostart: false,
            source: None,
            extra: Extra::new(),
        }
    }

    #[test]
    fn listen_addresses_as_openssh_reads_them() {
        assert_eq!(listen_address(&spec(None), false), "127.0.0.1");
        assert_eq!(listen_address(&spec(Some("localhost")), false), "127.0.0.1");
        assert_eq!(listen_address(&spec(None), true), "localhost");
        assert_eq!(listen_address(&spec(Some("*")), false), "0.0.0.0");
        assert_eq!(listen_address(&spec(Some("*")), true), "");
        assert_eq!(listen_address(&spec(Some("[::1]")), false), "::1");
        assert_eq!(listen_address(&spec(Some("0.0.0.0")), false), "0.0.0.0");
    }

    #[test]
    fn a_free_port_after_a_taken_one() {
        let taken = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = taken.local_addr().unwrap().port();
        let free = free_port_near(port).unwrap();
        assert!(free > port);
        assert!(std::net::TcpListener::bind(("127.0.0.1", free)).is_ok());
    }
}
