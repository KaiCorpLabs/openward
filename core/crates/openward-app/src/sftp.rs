//! SFTP browsers. A browser goes over the connection of a terminal open to
//! the same host when there is one; otherwise it connects on its own,
//! asking what it needs like a terminal does, and comes back the same way
//! when the connection drops.
//!
//! Transfers are the app's, not the browser's: closing a browser leaves
//! them running, on the connection they had.

use std::collections::HashMap;
use std::future::Future;
use std::sync::{Arc, Mutex, Weak};
use std::time::Duration;

use openward_sftp::{Conflict, Direction, Entry, Link, Remote};
use openward_ssh::client::NoSftp;
use tokio::runtime::Handle;
use tokio::task::JoinHandle;

use crate::alive::{self, Timing};
use crate::connect::{self, Ctx, lock};
use crate::events::{Event, Failure, Stage};
use crate::live::Live;
use crate::plan::Plan;
use crate::{RECONNECT_ATTEMPTS, no_answer, reconnect_delay};

pub use openward_sftp::Error as SftpError;

/// How often a browser checks that its connection is still there.
const WATCH: Duration = Duration::from_secs(1);

pub struct Sftp {
    runtime: Handle,
    link: Mutex<Arc<Link>>,
    task: Mutex<Option<JoinHandle<()>>>,
}

/// The links in use, by plan key: a browser opened again for a host takes
/// up the link its transfers were left on, so they can go on.
#[derive(Default)]
pub(crate) struct Links(Mutex<HashMap<String, Weak<Link>>>);

impl Links {
    pub fn get(&self, key: &str, label: &str) -> Arc<Link> {
        let mut links = lock(&self.0);
        links.retain(|_, w| w.strong_count() > 0);
        if let Some(link) = links.get(key).and_then(Weak::upgrade) {
            return link;
        }
        let link = Link::new(label);
        links.insert(key.to_owned(), Arc::downgrade(&link));
        link
    }
}

impl Sftp {
    pub(crate) fn new(runtime: Handle) -> Arc<Self> {
        Arc::new(Self {
            runtime,
            link: Mutex::new(Link::new("")),
            task: Mutex::new(None),
        })
    }

    /// Where its transfers reach the server.
    pub fn link(&self) -> Arc<Link> {
        Arc::clone(&lock(&self.link))
    }

    fn remote(&self) -> Result<Arc<Remote>, SftpError> {
        self.link().get().ok_or(SftpError::Lost)
    }

    /// Runs `f` on the app's runtime, where SFTP lives, from any caller.
    async fn on_remote<T, F, Fut>(&self, f: F) -> Result<T, SftpError>
    where
        F: FnOnce(Arc<Remote>) -> Fut,
        Fut: Future<Output = Result<T, SftpError>> + Send + 'static,
        T: Send + 'static,
    {
        let remote = self.remote()?;
        self.runtime
            .spawn(f(remote))
            .await
            .map_err(|e| SftpError::Other(e.to_string()))?
    }

    /// The folder the server starts in.
    pub async fn home(&self) -> Result<String, SftpError> {
        self.remote().map(|r| r.home().to_owned())
    }

    pub async fn realpath(&self, path: String) -> Result<String, SftpError> {
        self.on_remote(|r| async move { r.realpath(&path).await })
            .await
    }

    pub async fn list(&self, dir: String) -> Result<Vec<Entry>, SftpError> {
        self.on_remote(|r| async move { r.list(&dir).await }).await
    }

    pub async fn stat(&self, path: String) -> Result<Option<Entry>, SftpError> {
        self.on_remote(|r| async move { r.stat(&path).await }).await
    }

    pub async fn mkdir(&self, path: String) -> Result<(), SftpError> {
        self.on_remote(|r| async move { r.mkdir(&path).await })
            .await
    }

    /// Never over something that exists.
    pub async fn rename(&self, from: String, to: String) -> Result<(), SftpError> {
        self.on_remote(|r| async move { r.rename(&from, &to, false).await })
            .await
    }

    /// Files, links and folders with all they hold.
    pub async fn remove(&self, paths: Vec<String>) -> Result<(), SftpError> {
        self.on_remote(|r| async move {
            for p in paths {
                r.remove(&p).await?;
            }
            Ok(())
        })
        .await
    }

    /// Returns how many entries changed.
    pub async fn chmod(&self, path: String, mode: u32, recursive: bool) -> Result<u64, SftpError> {
        self.on_remote(|r| async move { r.chmod(&path, mode, recursive).await })
            .await
    }

    pub async fn conflicts(
        &self,
        direction: Direction,
        sources: Vec<String>,
        dest_dir: String,
    ) -> Result<Vec<Conflict>, SftpError> {
        self.on_remote(|r| async move {
            openward_sftp::conflicts(&r, direction, &sources, &dest_dir).await
        })
        .await
    }

    /// Puts a public key in the server's `~/.ssh/authorized_keys`, as
    /// `ssh-copy-id` does: `~/.ssh` made (700) if missing, the line added
    /// once, the file written whole and then put in place (600). False
    /// when the key was there already.
    pub async fn install_public_key(&self, line: String) -> Result<bool, SftpError> {
        self.on_remote(|r| async move {
            let dir = openward_sftp::join(r.home(), ".ssh");
            if r.stat(&dir).await?.is_none() {
                r.mkdir(&dir).await?;
                r.chmod(&dir, 0o700, false).await?;
            }
            let path = openward_sftp::join(&dir, "authorized_keys");
            let existing = r.read_small(&path, 1 << 20).await?;
            let Some(bytes) = crate::keychain::with_authorized(existing.as_deref(), &line) else {
                return Ok(false);
            };
            let next = format!("{path}.openward");
            r.write_all(&next, &bytes, 0o600).await?;
            r.rename(&next, &path, true).await?;
            Ok(true)
        })
        .await
    }

    pub(crate) fn set_task(&self, task: JoinHandle<()>) {
        if let Some(old) = lock(&self.task).replace(task) {
            old.abort();
        }
    }

    /// Stops connecting or watching. Transfers on its link go on.
    pub fn close(&self) {
        if let Some(task) = lock(&self.task).take() {
            task.abort();
        }
    }
}

impl Drop for Sftp {
    fn drop(&mut self) {
        self.close();
    }
}

/// Connects `sftp` by `plan`, again after a drop, until it gives up or the
/// browser goes away. Runs on the app's runtime.
pub(crate) fn start(
    sftp: &Arc<Sftp>,
    plan_of: impl Fn() -> Result<Plan, Failure> + Send + 'static,
    link: Arc<Link>,
    ctx: Ctx,
) {
    *lock(&sftp.link) = Arc::clone(&link);
    let weak = Arc::downgrade(sftp);
    let task = sftp.runtime.spawn(async move {
        let sink = Arc::clone(&ctx.sink);
        let mut attempt = 0;
        loop {
            let plan = match plan_of() {
                Ok(plan) => plan,
                Err(failure) => {
                    return sink.send(Event::Closed {
                        exit_code: None,
                        failure: Some(failure),
                    });
                }
            };
            let (failure, connected) = session(&plan, &ctx, &link).await;
            if connected {
                attempt = 0;
            }
            let lost =
                matches!(failure, Some(Failure::Network { .. })) && (connected || attempt > 0);
            if !lost || attempt >= RECONNECT_ATTEMPTS || weak.strong_count() == 0 {
                return sink.send(Event::Closed {
                    exit_code: None,
                    failure,
                });
            }
            attempt += 1;
            let delay = reconnect_delay(attempt);
            sink.send(Event::Reconnecting {
                attempt,
                delay_ms: delay.as_millis() as u64,
                reason: failure.expect("a lost connection has a reason"),
            });
            tokio::time::sleep(delay).await;
        }
    });
    sftp.set_task(task);
}

/// One connection: reused or made, SFTP started on it, then watched until
/// it drops. Returns why it ended and whether SFTP got going.
async fn session(plan: &Plan, ctx: &Ctx, link: &Link) -> (Option<Failure>, bool) {
    let sink = &ctx.sink;
    sink.send(Event::Route {
        hops: plan.hops.iter().map(|h| h.label.clone()).collect(),
    });
    let key = plan.key();
    let live = match ctx.live.find(&key) {
        Some(live) => live,
        None => match connect::run(plan, ctx).await {
            Ok(sessions) => {
                let live = Live::new(plan, sessions, ctx.runtime.clone());
                ctx.live.add(key, &live);
                ctx.autostart(plan, &live).await;
                live
            }
            Err(failure) => return (Some(failure), false),
        },
    };
    let last = plan.hops.len() - 1;
    let label = plan.hops[last].label.clone();
    ctx.stage(plan, last, Stage::OpeningSftp);
    let stream = match live.target().sftp().await {
        Ok(stream) => stream,
        Err(e) if e.is::<NoSftp>() => return (Some(Failure::NoSftp { label }), false),
        Err(e) => {
            let failure = Failure::Network {
                label,
                message: format!("{e:#}"),
            };
            return (Some(failure), false);
        }
    };
    let remote = match Remote::open(stream).await {
        Ok(remote) => remote,
        Err(e) => return (Some(Failure::Other(format!("starting SFTP: {e}"))), false),
    };
    link.set_kept(
        remote,
        Arc::clone(&live) as Arc<dyn std::any::Any + Send + Sync>,
    );
    sink.send(Event::Connected(live.connected.clone()));
    // Closed under it (by the terminal's watcher, say), or not answering.
    let closed = async {
        while !live.is_closed() {
            tokio::time::sleep(WATCH).await;
        }
    };
    let watching = async {
        match Timing::from_keepalive(plan.hops[last].keepalive) {
            Some(t) => {
                alive::watch(
                    || live.target().ping(),
                    None,
                    t,
                    |h| sink.send(Event::Health(h)),
                )
                .await
            }
            None => std::future::pending().await,
        }
    };
    let message = tokio::select! {
        () = closed => "connection lost".to_owned(),
        silent = watching => {
            live.mark_lost();
            no_answer(silent)
        }
    };
    link.set(None);
    (Some(Failure::Network { label, message }), true)
}
