//! What the UI asks of the core, and nothing about how it is drawn
//! (ARCHITECTURE §3.2; `arveil-app` in Arveil).
//!
//! [`App`] owns the vault and the runtime SSH runs on. It turns a saved
//! host into a connection plan ([`plan`]), runs it asking the user what it
//! needs through events ([`events`]), and gives back a [`Terminal`] to draw
//! and type into. No secret is kept: passphrases and passwords live as long
//! as the attempt that uses them.

pub mod events;
pub mod import;
pub mod keychain;
pub mod keys;
pub mod known;
pub mod local;
pub mod plan;
pub mod programs;
pub mod sftp;
pub mod snippets;
pub mod terminal;
pub mod tunnels;

mod connect;
mod live;

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard, Weak};
use std::time::Duration;

use openward_import::ssh_config::Paths;
use openward_pty::Spawn;
use openward_vault::Vault;
use openward_vault::proto::ItemId;

pub use events::{Answer, Event, EventSink, Failure, Prompt};
pub use local::Local;
pub use openward_sftp as files;
pub use openward_vault as vault;
pub use plan::{Plan, PlanError};
pub use sftp::Sftp;
pub use terminal::Terminal;
pub use tunnels::{TunnelError, TunnelState};

use connect::{Ctx, lock};
use events::{Prompts, Stage};
use live::{Live, Registry};
use openward_sftp::{Request, Transfers};
use tunnels::Tunnels;

/// Scrollback lines when settings say nothing.
pub const DEFAULT_SCROLLBACK: usize = 10_000;

pub struct App {
    vault: Arc<Mutex<Vault>>,
    local: Local,
    prompts: Arc<Prompts>,
    live: Arc<Registry>,
    links: sftp::Links,
    transfers: Transfers,
    tunnels: Arc<Tunnels>,
    runtime: tokio::runtime::Runtime,
}

impl App {
    /// Opens (or creates) the app's data in `data_dir`, for the current user.
    pub fn open(data_dir: &Path) -> anyhow::Result<Self> {
        Self::open_as(data_dir, Local::from_env())
    }

    /// As [`App::open`], for a given local user (tests).
    pub fn open_as(data_dir: &Path, local: Local) -> anyhow::Result<Self> {
        create_private_dir(data_dir)?;
        let vault = Vault::open(&data_dir.join("vault.db"))?;
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("openward-net")
            .enable_all()
            .build()?;
        Ok(Self {
            vault: Arc::new(Mutex::new(vault)),
            local,
            prompts: Arc::default(),
            live: Arc::default(),
            links: sftp::Links::default(),
            transfers: Transfers::new(runtime.handle().clone()),
            tunnels: Arc::new(Tunnels::new(runtime.handle().clone())),
            runtime,
        })
    }

    /// The vault, locked while the guard lives: keep it short.
    pub fn vault(&self) -> MutexGuard<'_, Vault> {
        lock(&self.vault)
    }

    pub fn local(&self) -> &Local {
        &self.local
    }

    pub fn plan(&self, host: ItemId) -> Result<Plan, PlanError> {
        Plan::for_host(&self.vault(), host, &self.local)
    }

    /// A new terminal, not connected to anything yet.
    pub fn terminal(&self, cols: u16, rows: u16, scrollback: usize) -> Arc<Terminal> {
        Terminal::new(cols, rows, scrollback)
    }

    /// Connects `terminal` to a saved host; on a terminal that was
    /// connected before, it reconnects and keeps the screen. Returns at once:
    /// progress, questions and the outcome arrive on `sink`.
    pub fn connect(
        &self,
        terminal: &Arc<Terminal>,
        host: ItemId,
        sink: Arc<dyn EventSink>,
    ) -> Result<(), PlanError> {
        self.connect_to(terminal, Target::Host(host), sink)
    }

    /// As [`App::connect`], to an address that is not saved, with the
    /// default settings.
    pub fn connect_address(
        &self,
        terminal: &Arc<Terminal>,
        address: String,
        user: Option<String>,
        port: Option<u16>,
        sink: Arc<dyn EventSink>,
    ) -> Result<(), PlanError> {
        self.connect_to(
            terminal,
            Target::Address {
                address,
                user,
                port,
            },
            sink,
        )
    }

    fn connect_to(
        &self,
        terminal: &Arc<Terminal>,
        target: Target,
        sink: Arc<dyn EventSink>,
    ) -> Result<(), PlanError> {
        // Checked now so that a plan that cannot run fails at once.
        target.plan(&self.vault(), &self.local)?;
        terminal.close();
        let ctx = self.ctx(&sink);
        let term = Arc::downgrade(terminal);
        let task = self.runtime.spawn(async move {
            let mut attempt = 0;
            loop {
                // Again on every attempt: the host may have been edited.
                let plan = match target.plan(&lock(&ctx.vault), &ctx.local) {
                    Ok(plan) => plan,
                    Err(e) => {
                        return sink.send(Event::Closed {
                            exit_code: None,
                            failure: Some(Failure::Other(e.to_string())),
                        });
                    }
                };
                let (exit_code, failure, connected) = session(&plan, &ctx, &term).await;
                if connected {
                    attempt = 0;
                }
                // Only a connection that was up and then went away is
                // tried again, and only while the network is the problem.
                let lost =
                    matches!(failure, Some(Failure::Network { .. })) && (connected || attempt > 0);
                if !lost || attempt >= RECONNECT_ATTEMPTS || term.strong_count() == 0 {
                    return sink.send(Event::Closed { exit_code, failure });
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
        terminal.set_task(task);
        Ok(())
    }

    fn ctx(&self, sink: &Arc<dyn EventSink>) -> Ctx {
        Ctx {
            vault: Arc::clone(&self.vault),
            local: self.local.clone(),
            prompts: Arc::clone(&self.prompts),
            sink: Arc::clone(sink),
            live: Arc::clone(&self.live),
            tunnels: Arc::clone(&self.tunnels),
            runtime: self.runtime.handle().clone(),
        }
    }

    /// Every saved tunnel with its host's label and its state now, by
    /// label.
    pub fn tunnels(&self) -> Vec<TunnelInfo> {
        let states = self.tunnels.states();
        let vault = self.vault();
        vault
            .port_forwards()
            .into_iter()
            .map(|(id, f)| TunnelInfo {
                id,
                rev: vault.get(id).map_or(0, |i| i.rev),
                host_label: vault
                    .host(f.host)
                    .map(|h| h.label.clone())
                    .unwrap_or_default(),
                spec: f.clone(),
                state: states.get(&id).cloned().unwrap_or(TunnelState::Closed),
            })
            .collect()
    }

    /// Opens a saved tunnel over its host's connection, connecting if none
    /// is up (questions and the outcome of that arrive on `sink`, which
    /// gets `Connected` once it listens). Returns at once.
    pub fn open_tunnel(&self, id: ItemId, sink: Arc<dyn EventSink>) -> Result<(), PlanError> {
        let spec = self.vault().port_forward(id)?.clone();
        let plan = Plan::for_host(&self.vault(), spec.host, &self.local)?;
        self.tunnels.set_state(id, TunnelState::Opening);
        let ctx = self.ctx(&sink);
        self.runtime.spawn(async move {
            let key = plan.key();
            let live = match ctx.live.find(&key) {
                Some(live) => live,
                None => {
                    ctx.sink.send(Event::Route {
                        hops: plan.hops.iter().map(|h| h.label.clone()).collect(),
                    });
                    match connect::run(&plan, &ctx).await {
                        Ok(sessions) => {
                            let live = Live::new(&plan, sessions, ctx.runtime.clone());
                            ctx.live.add(key, &live);
                            live
                        }
                        Err(failure) => {
                            ctx.tunnels.set_state(
                                id,
                                TunnelState::Failed {
                                    error: TunnelError::Connection(failure.clone()),
                                    on_connect: false,
                                },
                            );
                            return ctx.sink.send(Event::Closed {
                                exit_code: None,
                                failure: Some(failure),
                            });
                        }
                    }
                }
            };
            ctx.tunnels
                .open_on(id, spec, Arc::clone(&live), false)
                .await;
            match ctx.tunnels.states().get(&id) {
                Some(TunnelState::Open { .. }) => {
                    ctx.sink.send(Event::Connected(live.connected.clone()));
                }
                Some(TunnelState::Failed { error, .. }) => ctx.sink.send(Event::Closed {
                    exit_code: None,
                    failure: Some(events::Failure::Other(error.to_string())),
                }),
                _ => {}
            }
        });
        Ok(())
    }

    /// Deletes an item from the vault. A tunnel, or a host's tunnels (they
    /// go with it), close first.
    pub fn delete(&self, id: ItemId) -> vault::Result<()> {
        let tunnels: Vec<ItemId> = self
            .vault()
            .port_forwards()
            .into_iter()
            .filter(|(fid, f)| *fid == id || f.host == id)
            .map(|(fid, _)| fid)
            .collect();
        self.vault().delete(id)?;
        for t in tunnels {
            self.tunnels.forget(t);
        }
        Ok(())
    }

    /// Closes a tunnel; its connection goes too unless something else uses
    /// it.
    pub fn close_tunnel(&self, id: ItemId) {
        self.tunnels.close(id);
    }

    /// A free port here near `port`, to offer when that one is taken.
    pub fn free_port_near(&self, port: u16) -> Option<u16> {
        tunnels::free_port_near(port)
    }

    /// A new SFTP browser, not connected yet.
    pub fn sftp(&self) -> Arc<Sftp> {
        Sftp::new(self.runtime.handle().clone())
    }

    /// Connects an SFTP browser to a saved host: over a terminal's
    /// connection to it if one is up, otherwise on its own. Events as for
    /// [`App::connect`]; `Connected` means it can browse.
    pub fn connect_sftp(
        &self,
        sftp: &Arc<Sftp>,
        host: ItemId,
        sink: Arc<dyn EventSink>,
    ) -> Result<(), PlanError> {
        self.connect_sftp_to(sftp, Target::Host(host), sink)
    }

    /// As [`App::connect_sftp`], to an address that is not saved.
    pub fn connect_sftp_address(
        &self,
        sftp: &Arc<Sftp>,
        address: String,
        user: Option<String>,
        port: Option<u16>,
        sink: Arc<dyn EventSink>,
    ) -> Result<(), PlanError> {
        let target = Target::Address {
            address,
            user,
            port,
        };
        self.connect_sftp_to(sftp, target, sink)
    }

    fn connect_sftp_to(
        &self,
        sftp: &Arc<Sftp>,
        target: Target,
        sink: Arc<dyn EventSink>,
    ) -> Result<(), PlanError> {
        let plan = target.plan(&self.vault(), &self.local)?;
        let label = plan.hops.last().map_or("", |h| h.label.as_str());
        let link = self.links.get(&plan.key(), label);
        let (vault, local) = (Arc::clone(&self.vault), self.local.clone());
        let plan_of = move || {
            target
                .plan(&lock(&vault), &local)
                .map_err(|e| events::Failure::Other(e.to_string()))
        };
        sftp::start(sftp, plan_of, link, self.ctx(&sink));
        Ok(())
    }

    /// The transfer queue, every browser's.
    pub fn transfers(&self) -> &Transfers {
        &self.transfers
    }

    /// Queues a copy over `sftp`'s connection; it goes on if the browser
    /// closes.
    pub fn transfer(&self, sftp: &Sftp, request: Request) -> u64 {
        self.transfers.add(sftp.link(), request)
    }

    /// Runs the user's shell (`program` `None`) or a program on this
    /// machine in `terminal`.
    pub fn open_local(
        &self,
        terminal: &Arc<Terminal>,
        program: Option<String>,
        sink: Arc<dyn EventSink>,
    ) -> anyhow::Result<()> {
        terminal.close();
        let size = terminal.size();
        terminal.attach_pty(
            Spawn {
                program,
                cols: size.cols,
                rows: size.rows,
                cwd: Some(self.local.home.clone()),
                ..Spawn::default()
            },
            sink,
        )
    }

    /// Answers a [`Prompt`]; false if nothing waits for it any more.
    pub fn answer(&self, prompt: u64, answer: Answer) -> bool {
        self.prompts.answer(prompt, answer)
    }

    /// Trusts a host key the user has checked, as after a
    /// [`Failure::HostKeyChanged`]. It replaces the old key of the same type.
    /// The trusted host keys, OpenWard's and those of `~/.ssh/known_hosts`,
    /// that match `query` (all of them when it is empty).
    pub fn known_hosts(&self, query: &str) -> Vec<known::KnownEntry> {
        known::known_hosts(&self.vault(), &self.local.known_hosts_file(), query)
    }

    /// Forgets a trusted key: OpenWard's, or the line of `~/.ssh/known_hosts`
    /// that still reads `text` (keeping a copy in `known_hosts.old`).
    pub fn forget_known_host(&self, source: known::KnownSource, text: &str) -> anyhow::Result<()> {
        match source {
            known::KnownSource::OpenWard { id, .. } => self.vault().delete(id)?,
            known::KnownSource::File { line } => {
                known::forget_line(&self.local.known_hosts_file(), line, text)?
            }
        }
        Ok(())
    }

    pub fn trust_host_key(&self, host: &str, port: u16, key: &str) -> openward_vault::Result<()> {
        self.vault().trust_host_key(host, port, key).map(|_| ())
    }

    /// What importing `file` (or `~/.ssh/config`) would bring.
    pub fn preview_ssh_config(&self, file: Option<&Path>) -> Vec<import::Preview> {
        let (paths, file) = self.ssh_config_file(file);
        import::preview(&self.vault(), &file, &paths)
    }

    /// Imports `file`, or `~/.ssh/config`; with `only`, just those aliases
    /// and the hosts they jump through.
    pub fn import_ssh_config(
        &self,
        file: Option<&Path>,
        only: Option<&[String]>,
    ) -> openward_vault::Result<import::Report> {
        let (paths, file) = self.ssh_config_file(file);
        import::ssh_config(&mut self.vault(), &file, &paths, only)
    }

    /// Other programs' data on this computer, ready to import.
    pub fn installed_programs(&self) -> Vec<openward_import::detect::Found> {
        openward_import::detect::installed(&self.local.home)
    }

    /// Reads another program's file or folder, recognizing whose it is.
    /// Termius's data asks the keychain for its key unless `termius_keys`
    /// gives it (tests).
    pub fn read_program(
        &self,
        path: &Path,
        termius_keys: Option<Vec<[u8; 32]>>,
    ) -> Result<programs::Read, openward_import::detect::Error> {
        let (program, bundle) = openward_import::detect::read(path, termius_keys)?;
        Ok(programs::read(program, bundle, &self.local))
    }

    pub fn preview_program(&self, read: &programs::Read) -> programs::Preview {
        programs::preview(&self.vault(), read)
    }

    pub fn import_program(
        &self,
        read: &programs::Read,
        choice: &programs::Choice,
    ) -> Result<programs::Report, programs::Error> {
        programs::apply(&mut self.vault(), &self.local, read, choice)
    }

    fn ssh_config_file(&self, file: Option<&Path>) -> (Paths, PathBuf) {
        let paths = Paths {
            home: self.local.home.clone(),
            ssh_dir: self.local.ssh_dir.clone(),
        };
        let file = file.map_or_else(|| paths.user_config(), Path::to_owned);
        (paths, file)
    }
}

/// A saved tunnel as the UI lists it.
#[derive(Clone, Debug, PartialEq)]
pub struct TunnelInfo {
    pub id: ItemId,
    pub rev: u64,
    pub spec: vault::proto::PortForward,
    pub host_label: String,
    pub state: TunnelState,
}

/// What a connection goes to.
enum Target {
    Host(ItemId),
    Address {
        address: String,
        user: Option<String>,
        port: Option<u16>,
    },
}

impl Target {
    fn plan(&self, vault: &Vault, local: &Local) -> Result<Plan, PlanError> {
        match self {
            Self::Host(id) => Plan::for_host(vault, *id, local),
            Self::Address {
                address,
                user,
                port,
            } => Ok(Plan::for_address(address, user.clone(), *port, local)),
        }
    }
}

/// Tries after losing a connection, before giving up.
pub const RECONNECT_ATTEMPTS: u32 = 8;

/// 1, 2, 4, 8, 16 and then 30 seconds.
pub(crate) fn reconnect_delay(attempt: u32) -> Duration {
    Duration::from_secs((1u64 << attempt.saturating_sub(1).min(5)).min(30))
}

/// One connection, from the first hop to the shell closing. Returns the
/// exit code, why it ended if not normally, and whether it got as far as
/// the shell.
async fn session(
    plan: &Plan,
    ctx: &Ctx,
    term: &Weak<Terminal>,
) -> (Option<u32>, Option<Failure>, bool) {
    let sink = &ctx.sink;
    sink.send(Event::Route {
        hops: plan.hops.iter().map(|h| h.label.clone()).collect(),
    });
    let live = match connect::run(plan, ctx).await {
        Ok(sessions) => Live::new(plan, sessions, ctx.runtime.clone()),
        Err(failure) => return (None, Some(failure), false),
    };
    // An SFTP browser for the same host can go over it.
    ctx.live.add(plan.key(), &live);
    ctx.autostart(plan, &live).await;
    let Some(pipe) = term.upgrade().map(|t| t.pipe()) else {
        return (None, None, false);
    };
    let last = plan.hops.len() - 1;
    let target_hop = &plan.hops[last];
    sink.send(Event::Stage {
        hop: last,
        hops: plan.hops.len(),
        label: target_hop.label.clone(),
        stage: Stage::OpeningShell,
    });
    let size = pipe.size();
    let channel = match live
        .target()
        .shell_with(
            &plan.term,
            u32::from(size.cols),
            u32::from(size.rows),
            &plan.env,
            plan.agent_forward,
        )
        .await
    {
        Ok(channel) => channel,
        Err(e) => {
            let failure = Failure::Other(format!("opening the shell: {e:#}"));
            return (None, Some(failure), false);
        }
    };
    // Input goes to the shell before anyone hears it is connected.
    let pump = pipe.pump_ssh(channel, &target_hop.label);
    drop(pipe);
    sink.send(Event::Connected(live.connected.clone()));
    let (exit_code, failure) = pump.await;
    // The connection closes now, unless a browser still uses it.
    drop(live);
    (exit_code, failure, true)
}

/// The data directory, readable by its owner only on Unix.
fn create_private_dir(dir: &Path) -> std::io::Result<()> {
    if dir.is_dir() {
        return Ok(());
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        std::fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(dir)
    }
    #[cfg(not(unix))]
    std::fs::create_dir_all(dir)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reconnect_delays_grow_to_half_a_minute() {
        let secs: Vec<u64> = (1..=8).map(|a| reconnect_delay(a).as_secs()).collect();
        assert_eq!(secs, [1, 2, 4, 8, 16, 30, 30, 30]);
    }
}
