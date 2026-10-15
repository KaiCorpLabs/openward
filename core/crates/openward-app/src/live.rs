//! Connections more than one thing uses: a terminal and the SFTP browser of
//! the same host go over one, which closes when the last of them lets go.

use std::sync::{Arc, Mutex, Weak};

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
}

impl Live {
    pub fn new(plan: &Plan, sessions: Vec<Session>, runtime: Handle) -> Arc<Self> {
        let target = sessions.last().expect("a plan has hops");
        let hop = plan.hops.last().expect("a plan has hops");
        let info = target.info();
        let connected = Connected {
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
        })
    }

    pub fn target(&self) -> &Session {
        self.sessions.last().expect("a plan has hops")
    }

    pub fn is_closed(&self) -> bool {
        self.sessions.iter().any(Session::is_closed)
    }
}

impl Drop for Live {
    fn drop(&mut self) {
        let sessions = std::mem::take(&mut self.sessions);
        // Last hop first: each one runs inside the one before.
        self.runtime.spawn(async move {
            for s in sessions.iter().rev() {
                s.disconnect().await;
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
