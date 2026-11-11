//! Saved tunnels, opened over the host's connection: the one a terminal or
//! a browser has up, or one of their own. An open tunnel keeps that
//! connection alive; closing it lets go. When the connection drops the
//! tunnel closes, and one that opens on connect comes back with the next
//! connection to its host.
//!
//! The UI asks for [`Tunnels::states`] when [`Tunnels::set_waker`] says
//! something changed: a state, or a local tunnel's connections. A remote
//! tunnel's connections are counted on the server's side of the session,
//! with no word when they change; a page that shows them asks now and then.

use std::collections::HashMap;
use std::future::Future;
use std::io::ErrorKind;
use std::net::{IpAddr, SocketAddr};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use openward_vault::proto::{ForwardKind, ItemId, PortForward};
use tokio::net::{TcpListener, TcpStream};
use tokio::runtime::Handle;
use tokio::task::{JoinHandle, JoinSet};

use crate::connect::lock;
use crate::events::Failure;
use crate::live::Live;
use crate::terminal::Waker;

/// Tells the UI that a tunnel changed.
#[derive(Clone, Default)]
struct Changes(Arc<Mutex<Option<Waker>>>);

impl Changes {
    fn tell(&self) {
        if let Some(wake) = &*lock(&self.0) {
            wake();
        }
    }
}

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
    /// The opening that made it.
    ticket: u64,
    port: u16,
    active: Arc<AtomicU32>,
    /// One per listener; each holds its connections, which go with it.
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
    /// Each tunnel's latest opening or closing. An opening that is no
    /// longer the latest when it is done (closed meanwhile, or opened
    /// again) lets go of what it opened.
    tickets: HashMap<ItemId, u64>,
    next: u64,
}

impl State {
    fn ticket(&mut self, id: ItemId) -> u64 {
        self.next += 1;
        self.tickets.insert(id, self.next);
        self.next
    }

    fn current(&self, id: ItemId, ticket: u64) -> bool {
        self.tickets.get(&id) == Some(&ticket)
    }
}

pub(crate) struct Tunnels {
    runtime: Handle,
    state: Arc<Mutex<State>>,
    changes: Changes,
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

/// Where a local tunnel listens here: the address, and on loopback the
/// IPv6 one too, which `localhost` may well resolve to first.
fn local_addresses(spec: &PortForward) -> Vec<String> {
    let address = listen_address(spec, false);
    if address == "127.0.0.1" {
        vec![address, "::1".into()]
    } else {
        vec![address]
    }
}

impl Tunnels {
    pub fn new(runtime: Handle) -> Self {
        Self {
            runtime,
            state: Arc::default(),
            changes: Changes::default(),
        }
    }

    /// Called (from any thread) when a tunnel's state or a local tunnel's
    /// connections change.
    pub fn set_waker(&self, wake: Waker) {
        *lock(&self.changes.0) = Some(wake);
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

    /// Starts opening it: the ticket that [`Tunnels::open_on`] needs.
    /// `None` if it is open or opening already.
    pub fn begin(&self, id: ItemId) -> Option<u64> {
        let mut s = lock(&self.state);
        if s.running.contains_key(&id) || s.other.get(&id) == Some(&TunnelState::Opening) {
            return None;
        }
        let ticket = s.ticket(id);
        s.other.insert(id, TunnelState::Opening);
        drop(s);
        self.changes.tell();
        Some(ticket)
    }

    /// The opening `ticket` failed, if it is still the latest.
    pub fn fail(&self, id: ItemId, ticket: u64, error: TunnelError) {
        let mut s = lock(&self.state);
        if s.current(id, ticket) {
            s.other.insert(
                id,
                TunnelState::Failed {
                    error,
                    on_connect: false,
                },
            );
            drop(s);
            self.changes.tell();
        }
    }

    /// Closes it, if open, and forgets it (it was deleted).
    pub fn forget(&self, id: ItemId) {
        let mut s = lock(&self.state);
        let running = s.running.remove(&id);
        s.other.remove(&id);
        s.tickets.remove(&id);
        drop(s);
        drop(running);
        self.changes.tell();
    }

    /// Closes it, if open or opening. The connection goes too, unless
    /// something else uses it.
    pub fn close(&self, id: ItemId) {
        let mut s = lock(&self.state);
        let running = s.running.remove(&id);
        s.ticket(id);
        s.other.insert(id, TunnelState::Closed);
        drop(s);
        drop(running);
        self.changes.tell();
    }

    /// Opens `spec` over `live`, for the opening `ticket` (from
    /// [`Tunnels::begin`]). `on_connect` marks a failure as one of those
    /// opened as the host connected.
    pub async fn open_on(
        &self,
        id: ItemId,
        ticket: u64,
        spec: PortForward,
        live: Arc<Live>,
        on_connect: bool,
    ) {
        // Closed while it connected (a question pending): it does not take
        // the port, not even for the moment that letting it go would last.
        if !lock(&self.state).current(id, ticket) {
            return;
        }
        let result = self.listen(id, ticket, &spec, &live).await;
        let mut s = lock(&self.state);
        if !s.current(id, ticket) {
            // Closed or opened again meanwhile: not to be left open.
            drop(s);
            drop(result);
            return;
        }
        match result {
            Ok(running) => {
                s.other.remove(&id);
                s.running.insert(id, running);
                drop(s);
                self.watch(id, ticket, live);
            }
            Err(error) => {
                s.other
                    .insert(id, TunnelState::Failed { error, on_connect });
                drop(s);
            }
        }
        self.changes.tell();
    }

    /// Opens on `live` those of `forwards` that open on connect and are
    /// not open yet. Their failures stay in their state.
    pub async fn autostart(&self, live: &Arc<Live>, forwards: Vec<(ItemId, PortForward)>) {
        for (id, spec) in forwards {
            if !spec.autostarts() {
                continue;
            }
            let Some(ticket) = self.begin(id) else {
                continue;
            };
            self.open_on(id, ticket, spec, Arc::clone(live), true).await;
        }
    }

    /// Closes the tunnel when its connection goes.
    fn watch(&self, id: ItemId, ticket: u64, live: Arc<Live>) {
        let state = Arc::clone(&self.state);
        let changes = self.changes.clone();
        let weak = Arc::downgrade(&live);
        drop(live);
        self.runtime.spawn(async move {
            loop {
                tokio::time::sleep(WATCH).await;
                let Some(live) = weak.upgrade() else { return };
                let mut s = lock(&state);
                let ours = s.running.get(&id).is_some_and(|r| r.ticket == ticket);
                if !ours {
                    return;
                }
                if live.is_closed() {
                    let running = s.running.remove(&id);
                    s.other.insert(
                        id,
                        TunnelState::Failed {
                            error: TunnelError::Lost,
                            on_connect: false,
                        },
                    );
                    drop(s);
                    drop(running);
                    changes.tell();
                    return;
                }
            }
        });
    }

    /// Marks the opening `ticket` failed when one of its listeners stops
    /// for good.
    fn on_stop(&self, id: ItemId, ticket: u64) -> impl Fn(std::io::Error) + Send + 'static {
        let state = Arc::clone(&self.state);
        let changes = self.changes.clone();
        move |error| {
            let mut s = lock(&state);
            if !s.running.get(&id).is_some_and(|r| r.ticket == ticket) {
                return;
            }
            let running = s.running.remove(&id);
            s.other.insert(
                id,
                TunnelState::Failed {
                    error: TunnelError::Other(error.to_string()),
                    on_connect: false,
                },
            );
            drop(s);
            drop(running);
            changes.tell();
        }
    }

    async fn listen(
        &self,
        id: ItemId,
        ticket: u64,
        spec: &PortForward,
        live: &Arc<Live>,
    ) -> Result<Running, TunnelError> {
        let active = Arc::new(AtomicU32::new(0));
        let mut running = Running {
            live: Arc::clone(live),
            runtime: self.runtime.clone(),
            ticket,
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
                let mut listeners = Vec::new();
                for (i, address) in local_addresses(spec).into_iter().enumerate() {
                    let ip: IpAddr = address
                        .parse()
                        .map_err(|_| TunnelError::BadAddress(address.clone()))?;
                    // The port the first one got, when it was any.
                    let port = listeners
                        .first()
                        .and_then(|l: &TcpListener| l.local_addr().ok())
                        .map_or(spec.listen_port, |a| a.port());
                    match TcpListener::bind(SocketAddr::new(ip, port)).await {
                        Ok(listener) => listeners.push(listener),
                        // Loopback's IPv6 is a bonus: no IPv6, or taken.
                        Err(_) if i > 0 => {}
                        Err(e) => {
                            return Err(match e.kind() {
                                ErrorKind::AddrInUse | ErrorKind::PermissionDenied => {
                                    TunnelError::PortInUse {
                                        port: spec.listen_port,
                                        remote: false,
                                    }
                                }
                                ErrorKind::AddrNotAvailable => TunnelError::BadAddress(address),
                                _ => TunnelError::Other(e.to_string()),
                            });
                        }
                    }
                }
                let counted = Counted {
                    active,
                    changes: self.changes.clone(),
                };
                for listener in listeners {
                    let (live, counted, stop) =
                        (Arc::clone(live), counted.clone(), self.on_stop(id, ticket));
                    let task = if spec.kind == ForwardKind::Local {
                        let host = spec.dest_host.clone().unwrap_or_default();
                        let port = u32::from(spec.dest_port.unwrap_or(0));
                        self.runtime.spawn(async move {
                            stop(
                                serve(listener, counted, |socket, peer| {
                                    local_connection(
                                        socket,
                                        peer,
                                        Arc::clone(&live),
                                        host.clone(),
                                        port,
                                    )
                                })
                                .await,
                            );
                        })
                    } else {
                        self.runtime.spawn(async move {
                            stop(
                                serve(listener, counted, |socket, _| {
                                    let live = Arc::clone(&live);
                                    async move {
                                        let _ =
                                            openward_ssh::forward::socks5(socket, live.target())
                                                .await;
                                    }
                                })
                                .await,
                            );
                        })
                    };
                    running.tasks.push(task);
                }
            }
        }
        Ok(running)
    }
}

/// A local tunnel's connection count, and who to tell when it changes.
#[derive(Clone)]
struct Counted {
    active: Arc<AtomicU32>,
    changes: Changes,
}

/// Counts a connection while it lasts.
struct Count(Counted);

impl Count {
    fn new(counted: &Counted) -> Self {
        counted.active.fetch_add(1, Ordering::Relaxed);
        counted.changes.tell();
        Self(counted.clone())
    }
}

impl Drop for Count {
    fn drop(&mut self) {
        self.0.active.fetch_sub(1, Ordering::Relaxed);
        self.0.changes.tell();
    }
}

/// Serves `listener` with `handle` until it stops working, which it
/// returns. The connections are its own: they go with it when the tunnel
/// closes, and the connection to the host with them.
async fn serve<F, C>(listener: TcpListener, counted: Counted, handle: F) -> std::io::Error
where
    F: Fn(TcpStream, SocketAddr) -> C,
    C: Future<Output = ()> + Send + 'static,
{
    let mut connections = JoinSet::new();
    loop {
        let (socket, peer) = match openward_ssh::forward::accept(|| listener.accept()).await {
            Ok(accepted) => accepted,
            Err(e) => return e,
        };
        while connections.try_join_next().is_some() {}
        let count = Count::new(&counted);
        let connection = handle(socket, peer);
        connections.spawn(async move {
            let _count = count;
            connection.await;
        });
    }
}

async fn local_connection(
    mut socket: TcpStream,
    peer: SocketAddr,
    live: Arc<Live>,
    host: String,
    port: u32,
) {
    let Ok(channel) = live
        .target()
        .handle
        .channel_open_direct_tcpip(host, port, peer.ip().to_string(), u32::from(peer.port()))
        .await
    else {
        return;
    };
    let mut stream = channel.into_stream();
    let _ = tokio::io::copy_bidirectional(&mut socket, &mut stream).await;
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
            imported: None,
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
    fn loopback_is_both_families() {
        assert_eq!(local_addresses(&spec(None)), ["127.0.0.1", "::1"]);
        assert_eq!(
            local_addresses(&spec(Some("localhost"))),
            ["127.0.0.1", "::1"]
        );
        assert_eq!(local_addresses(&spec(Some("0.0.0.0"))), ["0.0.0.0"]);
        assert_eq!(local_addresses(&spec(Some("[::1]"))), ["::1"]);
    }

    /// Opening twice is opening once; a closing outdates an opening.
    #[tokio::test]
    async fn an_opening_closed_meanwhile_is_outdated() {
        let tunnels = Tunnels::new(Handle::current());
        let id = ItemId::new();
        let first = tunnels.begin(id).unwrap();
        assert_eq!(tunnels.begin(id), None, "opening already");
        tunnels.close(id);
        assert_eq!(tunnels.states()[&id], TunnelState::Closed);
        tunnels.fail(id, first, TunnelError::Lost);
        assert_eq!(tunnels.states()[&id], TunnelState::Closed, "outdated");
        let second = tunnels.begin(id).unwrap();
        tunnels.fail(id, second, TunnelError::Lost);
        assert!(matches!(
            tunnels.states()[&id],
            TunnelState::Failed {
                error: TunnelError::Lost,
                ..
            }
        ));
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
