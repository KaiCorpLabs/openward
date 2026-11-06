//! Connections more than one thing uses: a terminal and the SFTP browser of
//! the same host go over one, which closes when the last of them lets go.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, Weak};
use std::time::Duration;

use openward_ssh::client::Session;
use openward_ssh::known_hosts::Verdict;
use tokio::runtime::Handle;

use crate::connect::lock;
use crate::events::{Connected, Trust};
use crate::plan::Plan;

pub(crate) struct Live {
    /// Jumps first, the target last: each runs over the one before.
    sessions: Vec<Session>,
    /// What the status bar says about it.
    pub connected: Connected,
    runtime: Handle,
    /// The server stopped answering: nothing should use it any more.
    lost: AtomicBool,
}

impl Live {
    pub fn new(plan: &Plan, sessions: Vec<Session>, runtime: Handle) -> Arc<Self> {
        let target = sessions.last().expect("a plan has hops");
        let hop = plan.hops.last().expect("a plan has hops");
        let info = target.info();
        let connected = Connected {
            protocol: crate::events::Protocol::Ssh,
            mosh: false,
            host: hop.address.clone(),
            port: hop.port,
            post_quantum: info.post_quantum(),
            kex: info.kex,
            cipher: info.cipher,
            host_key_algorithm: info.host_key,
            fingerprint: info.host_key_fingerprint,
            trust: match info.verdict {
                Some(Verdict::Certified { ca, .. }) => Trust::Certified { ca },
                Some(Verdict::Learned) => Trust::New,
                _ => Trust::Known,
            },
            hops: plan.hops.len(),
            connect_ms: info.connect_ms,
        };
        Arc::new(Self {
            sessions,
            connected,
            runtime,
            lost: AtomicBool::new(false),
        })
    }

    pub fn target(&self) -> &Session {
        self.sessions.last().expect("a plan has hops")
    }

    /// Jumps first, the target last, as in the plan.
    pub fn sessions(&self) -> &[Session] {
        &self.sessions
    }

    /// Whether it goes through jump hosts.
    pub fn has_jumps(&self) -> bool {
        self.sessions.len() > 1
    }

    /// The round trip to each jump host, one after the other; None for one
    /// that does not answer `within`.
    pub async fn jump_rtts(&self, within: Duration) -> Vec<Option<u32>> {
        let mut rtts = Vec::with_capacity(self.sessions.len() - 1);
        for jump in &self.sessions[..self.sessions.len() - 1] {
            let sent = tokio::time::Instant::now();
            let answered = tokio::time::timeout(within, jump.ping()).await;
            rtts.push(matches!(answered, Ok(true)).then(|| {
                let rtt = tokio::time::Instant::now().saturating_duration_since(sent);
                rtt.as_millis().min(u128::from(u32::MAX)) as u32
            }));
        }
        rtts
    }

    pub fn is_closed(&self) -> bool {
        self.lost.load(Ordering::Relaxed) || self.sessions.iter().any(Session::is_closed)
    }

    /// Gives up on a server that stopped answering: its channels close,
    /// so the terminal and the SFTP browser on it reconnect, and the
    /// registry hands it to no one.
    pub fn mark_lost(self: &Arc<Self>) {
        self.lost.store(true, Ordering::Relaxed);
        let me = Arc::clone(self);
        self.runtime.spawn(async move {
            for s in me.sessions.iter().rev() {
                // Its loop may be stuck writing to a peer that is gone.
                let _ = tokio::time::timeout(DISCONNECT, s.disconnect()).await;
            }
        });
    }

    pub fn runtime(&self) -> &Handle {
        &self.runtime
    }
}

/// How long saying goodbye to a server may take.
const DISCONNECT: Duration = Duration::from_secs(2);

impl Drop for Live {
    fn drop(&mut self) {
        let sessions = std::mem::take(&mut self.sessions);
        // Last hop first: each one runs inside the one before. A loop stuck
        // on a peer that is gone lets go of the sessions all the same.
        self.runtime.spawn(async move {
            for s in sessions.iter().rev() {
                let _ = tokio::time::timeout(DISCONNECT, s.disconnect()).await;
            }
        });
    }
}

/// The connections that are up, by plan key.
#[derive(Default)]
pub(crate) struct Registry {
    live: Mutex<Vec<(String, Weak<Live>)>>,
}

impl Registry {
    /// A connection up for `key`, if any.
    pub fn find(&self, key: &str) -> Option<Arc<Live>> {
        let mut live = lock(&self.live);
        live.retain(|(_, w)| w.strong_count() > 0);
        live.iter()
            .filter(|(k, _)| k == key)
            .filter_map(|(_, w)| w.upgrade())
            .find(|l| !l.is_closed())
    }

    pub fn add(&self, key: String, conn: &Arc<Live>) {
        lock(&self.live).push((key, Arc::downgrade(conn)));
    }
}
