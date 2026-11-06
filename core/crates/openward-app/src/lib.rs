//! What the UI asks of the core, and nothing about how it is drawn
//! (ARCHITECTURE §3.2; `arveil-app` in Arveil).
//!
//! [`App`] owns the vault and the runtime SSH runs on. It turns a saved
//! host into a connection plan ([`plan`]), runs it asking the user what it
//! needs through events ([`events`]), and gives back a [`Terminal`] to draw
//! and type into. No secret is kept: passphrases and passwords live as long
//! as the attempt that uses them.

pub mod alive;
pub mod events;
pub mod import;
pub mod keychain;
pub mod keys;
pub mod known;
pub mod local;
pub mod logs;
pub mod plan;
pub mod programs;
pub mod sftp;
pub mod snippets;
pub mod terminal;
pub mod tunnels;

mod connect;
mod live;
mod mosh;
mod system;

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard, Weak};
use std::time::{Duration, Instant};

use openward_import::ssh_config::{Paths, SshConfig};
use openward_pty::Spawn;
use openward_vault::Vault;
use openward_vault::proto::{ItemId, Protocol, SerialLine};

pub use events::{Answer, Event, EventSink, Failure, Prompt};
pub use local::Local;
pub use logs::Logs;
pub use openward_serial::{PortInfo, ports as serial_ports};
pub use openward_sftp as files;
pub use openward_vault as vault;
pub use plan::{Plan, PlanError};
pub use sftp::Sftp;
pub use terminal::{LogState, Terminal};
pub use tunnels::{TunnelError, TunnelState};

use alive::Timing;
use connect::{Ctx, lock};
use events::{Persistence, Prompts, Stage};
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
    logs: Arc<Logs>,
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
        let logs = Logs::open(&data_dir.join("logs"), logs::Config::default())?;
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
            logs,
            runtime,
        })
    }

    /// The session logs.
    pub fn logs(&self) -> &Arc<Logs> {
        &self.logs
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
    /// default settings: by SSH or Telnet.
    pub fn connect_address(
        &self,
        terminal: &Arc<Terminal>,
        address: String,
        user: Option<String>,
        port: Option<u16>,
        protocol: Protocol,
        sink: Arc<dyn EventSink>,
    ) -> Result<(), PlanError> {
        if protocol == Protocol::Serial {
            return Err(PlanError::NotSsh(address));
        }
        self.connect_to(
            terminal,
            Target::Address {
                address,
                user,
                port,
                protocol,
            },
            sink,
        )
    }

    /// Opens the serial port at `path` in `terminal`, as a host that is
    /// not saved. Returns at once: the outcome arrives on `sink`.
    pub fn open_serial(
        &self,
        terminal: &Arc<Terminal>,
        path: String,
        line: SerialLine,
        sink: Arc<dyn EventSink>,
    ) {
        let target = Target::Serial { path, line };
        // Only a host can fail to plan; this is not one.
        let _ = self.connect_to(terminal, target, sink);
    }

    fn connect_to(
        &self,
        terminal: &Arc<Terminal>,
        target: Target,
        sink: Arc<dyn EventSink>,
    ) -> Result<(), PlanError> {
        let serial = target.serial(&self.vault())?;
        if let Some(serial) = serial {
            self.open_serial_line(terminal, &target, serial, sink);
            return Ok(());
        }
        // Checked now so that a plan that cannot run fails at once.
        let plan = target.plan(&self.vault(), &self.local)?;
        // A reconnection (by hand, too) leaves the tmux session there to
        // find it again under the same name. Its log is a new one.
        terminal.end_log(logs::End::Closed);
        terminal.detach();
        let hop = plan.hops.last().expect("a plan ends with its target");
        let address = match plan.protocol {
            Protocol::Telnet if hop.port == vault::TELNET_PORT => {
                format!("telnet://{}", hop.address)
            }
            Protocol::Telnet => format!("telnet://{}:{}", hop.address, hop.port),
            _ if hop.port == 22 => format!("{}@{}", hop.user, hop.address),
            _ => format!("{}@{}:{}", hop.user, hop.address, hop.port),
        };
        let begin = self.log_begin(&target, &hop.label, address, &plan.term);
        let sink: Arc<dyn EventSink> = logs::LogSink::new(sink, &self.logs, terminal, begin);
        let ctx = self.ctx(&sink);
        let term = Arc::downgrade(terminal);
        let tmux = terminal.tmux_name(tmux_session_name);
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
                let (exit_code, failure, connected) = match plan.protocol {
                    Protocol::Telnet => telnet_session(&plan, &ctx, &term).await,
                    _ => session(&plan, &ctx, &term, &tmux).await,
                };
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

    /// Opens a serial port (a saved host's, or one picked by hand) in
    /// `terminal`. Nothing comes back by itself if the cable is pulled: the
    /// session closes, saying so.
    fn open_serial_line(
        &self,
        terminal: &Arc<Terminal>,
        target: &Target,
        serial: SerialTarget,
        sink: Arc<dyn EventSink>,
    ) {
        terminal.end_log(logs::End::Closed);
        terminal.detach();
        // A saved host's log names its port; one picked by hand says what
        // it is, for the log to open it again.
        let address = match target {
            Target::Host(_) => serial.path.clone(),
            _ => format!("serial://{}", serial.path),
        };
        let begin = self.log_begin(target, &serial.label, address, "xterm-256color");
        let sink: Arc<dyn EventSink> = logs::LogSink::new(sink, &self.logs, terminal, begin);
        let term = Arc::clone(terminal);
        self.runtime.spawn_blocking(move || {
            let started = Instant::now();
            let SerialTarget { label, path, line } = serial;
            sink.send(Event::Route {
                hops: vec![label.clone()],
            });
            // Opened again (a reconnection): the last reader lets the port
            // go within a read's wait. Until then it is still ours, busy.
            let mut opened = openward_serial::open(&path, &line);
            for _ in 0..5 {
                if !matches!(opened, Err(openward_serial::OpenError::Busy(_))) {
                    break;
                }
                std::thread::sleep(openward_serial::READ_WAIT);
                opened = openward_serial::open(&path, &line);
            }
            let failure = |problem| Failure::Serial {
                port: path.clone(),
                problem,
            };
            let failure = match opened {
                Ok(port) => {
                    let connected = events::Connected {
                        protocol: Protocol::Serial,
                        mosh: false,
                        host: path.clone(),
                        port: 0,
                        kex: String::new(),
                        post_quantum: false,
                        cipher: String::new(),
                        host_key_algorithm: String::new(),
                        fingerprint: String::new(),
                        trust: events::Trust::Known,
                        hops: 1,
                        connect_ms: started.elapsed().as_secs_f64() * 1000.0,
                    };
                    match term.attach_serial(&path, port, connected, Arc::clone(&sink)) {
                        Ok(()) => return,
                        Err(e) => failure(events::SerialProblem::Other(e.to_string())),
                    }
                }
                Err(e) => failure(events::SerialProblem::of(&e)),
            };
            sink.send(Event::Closed {
                exit_code: None,
                failure: Some(failure),
            });
        });
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

    /// Called (from any thread) when a tunnel opens, closes, fails, or a
    /// local tunnel's connections change: when to ask [`App::tunnels`].
    pub fn watch_tunnels(&self, wake: terminal::Waker) {
        self.tunnels.set_waker(wake);
    }

    /// Called (from any thread) whenever the vault changes: from the UI, an
    /// import, or the core itself (a system learned, a key trusted). What
    /// shows items reads them again then.
    pub fn watch_vault(&self, wake: terminal::Waker) {
        self.vault().on_change(move || wake());
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
        let plan = Plan::for_host(&self.vault(), spec.host, &self.local)?.ssh()?;
        let Some(ticket) = self.tunnels.begin(id) else {
            // Open or opening already: nothing to do here.
            sink.send(Event::Closed {
                exit_code: None,
                failure: None,
            });
            return Ok(());
        };
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
                            ctx.learn_systems(&plan, &live);
                            live
                        }
                        Err(failure) => {
                            ctx.tunnels
                                .fail(id, ticket, TunnelError::Connection(failure.clone()));
                            return ctx.sink.send(Event::Closed {
                                exit_code: None,
                                failure: Some(failure),
                            });
                        }
                    }
                }
            };
            ctx.tunnels
                .open_on(id, ticket, spec, Arc::clone(&live), false)
                .await;
            match ctx.tunnels.states().get(&id) {
                Some(TunnelState::Open { .. }) => {
                    ctx.sink.send(Event::Connected(live.connected.clone()));
                }
                Some(TunnelState::Failed { error, .. }) => ctx.sink.send(Event::Closed {
                    exit_code: None,
                    failure: Some(events::Failure::Other(error.to_string())),
                }),
                // Closed meanwhile.
                _ => ctx.sink.send(Event::Closed {
                    exit_code: None,
                    failure: None,
                }),
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

    /// Tells the system of a saved host again over its connection, if one
    /// is up (as when it starts reading `/etc/os-release`), and stores it
    /// if it changed. False when there is no connection: it is told on the
    /// next one.
    async fn learn_system(&self, host: ItemId) -> anyhow::Result<bool> {
        let plan = self.plan(host)?.ssh()?;
        let Some(live) = self.live.find(&plan.key()) else {
            return Ok(false);
        };
        let vault = Arc::clone(&self.vault);
        self.runtime
            .spawn(async move { connect::learn_systems(&vault, &plan, &live).await })
            .await?;
        Ok(true)
    }

    /// From now on, reads a host's `/etc/os-release` after connecting (its
    /// own setting), and now over its connection if one is up. False when
    /// there is none: it is read on the next one.
    pub async fn read_os_release(&self, host: ItemId) -> anyhow::Result<bool> {
        {
            let mut vault = self.vault();
            let mut h = vault.host(host)?.clone();
            if h.settings.read_os_release != Some(true) {
                h.settings.read_os_release = Some(true);
                let rev = vault.get(host).map_or(0, |item| item.rev);
                vault.update(host, rev, vault::proto::Data::Host(h))?;
            }
        }
        self.learn_system(host).await
    }

    /// Reads `/etc/os-release` after connecting to the hosts that do not
    /// say otherwise (their own setting, a group's), on this device only.
    pub fn set_read_os_release_everywhere(&self, on: bool) {
        let mut vault = self.vault();
        let mut device = vault.device_defaults().clone();
        device.read_os_release = on.then_some(true);
        vault.set_device_defaults(device);
    }

    /// Records the session log of the hosts that do not say otherwise
    /// (their own setting, a group's) and of addresses typed by hand, on
    /// this device only.
    pub fn set_session_log_everywhere(&self, on: bool) {
        let mut vault = self.vault();
        let mut device = vault.device_defaults().clone();
        device.session_log = on.then_some(true);
        vault.set_device_defaults(device);
    }

    /// What the log of a connection to `target` (called `label`, at
    /// `address` as the log shows it) begins as.
    fn log_begin(&self, target: &Target, label: &str, address: String, term: &str) -> logs::Begin {
        let vault = self.vault();
        let (place, marking, system, record) = match target {
            Target::Host(id) => {
                let settings = vault.effective(*id).map(|e| e.settings).unwrap_or_default();
                let marking = match settings.environment {
                    Some(vault::proto::Environment::Mark(m)) => Some(logs::Marking {
                        name: m.name,
                        short: m.short,
                        color: m.color,
                    }),
                    _ => None,
                };
                let system = vault
                    .host(*id)
                    .ok()
                    .and_then(|h| h.system.as_ref().map(|s| s.code.clone()));
                (
                    logs::Place::Host(id.to_string()),
                    marking,
                    system,
                    settings.session_log.unwrap_or(false),
                )
            }
            Target::Address { .. } | Target::Serial { .. } => (
                logs::Place::Address(address.clone()),
                None,
                None,
                vault.device_defaults().session_log.unwrap_or(false),
            ),
        };
        logs::Begin {
            place,
            label: label.to_owned(),
            address,
            marking,
            system,
            tmux: false,
            record,
            cols: 0,
            rows: 0,
            term: term.to_owned(),
        }
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
            protocol: Protocol::Ssh,
        };
        self.connect_sftp_to(sftp, target, sink)
    }

    fn connect_sftp_to(
        &self,
        sftp: &Arc<Sftp>,
        target: Target,
        sink: Arc<dyn EventSink>,
    ) -> Result<(), PlanError> {
        let plan = target.plan(&self.vault(), &self.local)?.ssh()?;
        let label = plan.hops.last().map_or("", |h| h.label.as_str());
        let link = self.links.get(&plan.key(), label);
        let (vault, local) = (Arc::clone(&self.vault), self.local.clone());
        let plan_of = move || {
            target
                .plan(&lock(&vault), &local)
                .and_then(Plan::ssh)
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
        let begin = logs::Begin {
            place: logs::Place::Local,
            label: program.clone().unwrap_or_default(),
            address: "~".into(),
            marking: None,
            system: None,
            tmux: false,
            record: self.logs.config().record_local,
            cols: size.cols,
            rows: size.rows,
            term: "xterm-256color".into(),
        };
        let sink = logs::LogSink::new(sink, &self.logs, terminal, begin);
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
        // The vault's part first: the file and the matching go without it.
        let ours = known::Ours::of(&self.vault());
        known::known_hosts(ours, &self.local.known_hosts_file(), query)
    }

    /// How many trusted host keys there are, as [`App::known_hosts`] would
    /// list them with no query: cheap, for a counter.
    pub fn known_host_count(&self) -> usize {
        let ours = known::Ours::of(&self.vault());
        known::known_host_count(&ours, &self.local.known_hosts_file())
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
        // Read before taking the vault: the file and its Includes.
        let config = SshConfig::load(&file, &paths);
        import::preview(&self.vault(), &config)
    }

    /// Imports `file`, or `~/.ssh/config`; with `only`, just those aliases
    /// and the hosts they jump through.
    pub fn import_ssh_config(
        &self,
        file: Option<&Path>,
        only: Option<&[String]>,
    ) -> openward_vault::Result<import::Report> {
        let (paths, file) = self.ssh_config_file(file);
        let config = SshConfig::load(&file, &paths);
        import::ssh_config(&mut self.vault(), &config, only)
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
        protocol: Protocol,
    },
    /// A serial port picked by hand.
    Serial {
        path: String,
        line: SerialLine,
    },
}

/// A serial port to open: a host's, or one picked by hand.
struct SerialTarget {
    label: String,
    path: String,
    line: SerialLine,
}

impl Target {
    fn plan(&self, vault: &Vault, local: &Local) -> Result<Plan, PlanError> {
        match self {
            Self::Host(id) => Plan::for_host(vault, *id, local),
            Self::Address {
                address,
                user,
                port,
                protocol,
            } => Ok(Plan::for_address(
                address,
                user.clone(),
                *port,
                *protocol,
                local,
            )),
            Self::Serial { path, .. } => Err(PlanError::NotSsh(path.clone())),
        }
    }

    /// The serial port it is, if it is one.
    fn serial(&self, vault: &Vault) -> Result<Option<SerialTarget>, PlanError> {
        Ok(match self {
            Self::Host(id) => {
                let settings = vault.effective(*id)?.settings;
                if settings.protocol != Some(Protocol::Serial) {
                    return Ok(None);
                }
                let host = vault.host(*id)?;
                Some(SerialTarget {
                    label: host.label.clone(),
                    path: host.address.clone(),
                    line: settings.serial.unwrap_or_default(),
                })
            }
            Self::Serial { path, line } => Some(SerialTarget {
                label: path.clone(),
                path: path.clone(),
                line: line.clone(),
            }),
            Self::Address { .. } => None,
        })
    }
}

/// Tries after losing a connection, before giving up.
pub const RECONNECT_ATTEMPTS: u32 = 8;

/// Why a connection was given up when the server stopped answering.
pub(crate) fn no_answer(silent: Duration) -> String {
    format!("no answer for {} s", silent.as_secs())
}

/// A terminal's tmux session: `ow-` and eight hex digits.
fn tmux_session_name() -> String {
    format!("ow-{:08x}", rand::random::<u32>())
}

/// Whether `session` can be found again: no tmux, found or new. Through
/// `sh`, whatever the login shell is. A server that does not answer in
/// [`TMUX_CHECK`] is taken for one without tmux: an ordinary shell rather
/// than a connection that hangs.
async fn tmux_state(target: &openward_ssh::client::Session, session: &str) -> Persistence {
    let check = format!(
        "sh -c 'command -v tmux >/dev/null 2>&1 || exit 3; tmux has-session -t {session} 2>/dev/null'"
    );
    match tokio::time::timeout(TMUX_CHECK, target.exec_short(&check)).await {
        Ok(Ok(o)) if o.status == Some(0) => Persistence::Resumed,
        Ok(Ok(o)) if o.status == Some(1) => Persistence::New,
        _ => Persistence::NoTmux,
    }
}

const TMUX_CHECK: Duration = Duration::from_secs(5);

/// tmux attaching to `session` or making it, without its status bar and
/// with the wheel scrolling its history (those of this session only).
fn tmux_command(session: &str) -> String {
    format!(
        "sh -c 'exec tmux new-session -A -s {session} \\; set-option -q status off \\; set-option -q mouse on'"
    )
}

/// 1, 2, 4, 8, 16 and then 30 seconds.
pub(crate) fn reconnect_delay(attempt: u32) -> Duration {
    Duration::from_secs((1u64 << attempt.saturating_sub(1).min(5)).min(30))
}

/// One connection, from the first hop to the shell closing. Returns the
/// exit code, why it ended if not normally, and whether it got as far as
/// the shell.
/// A Telnet session: the jumps by SSH, the target's plain stream, and
/// nothing to watch but the stream itself (Telnet has no keepalive of its
/// own).
async fn telnet_session(
    plan: &Plan,
    ctx: &Ctx,
    term: &Weak<Terminal>,
) -> (Option<u32>, Option<Failure>, bool) {
    let sink = &ctx.sink;
    sink.send(Event::Route {
        hops: plan.hops.iter().map(|h| h.label.clone()).collect(),
    });
    let started = Instant::now();
    let (jumps, stream) = match connect::telnet(plan, ctx).await {
        Ok(opened) => opened,
        Err(failure) => return (None, Some(failure), false),
    };
    let Some(pipe) = term.upgrade().map(|t| t.pipe()) else {
        return (None, None, false);
    };
    let target = plan.hops.last().expect("a plan ends with its target");
    // Input goes to the server before anyone hears it is connected.
    let pump = pipe.pump_telnet(Box::new(stream), &plan.term, &target.label);
    drop(pipe);
    sink.send(Event::Connected(events::Connected {
        protocol: Protocol::Telnet,
        mosh: false,
        host: target.address.clone(),
        port: target.port,
        kex: String::new(),
        post_quantum: false,
        cipher: String::new(),
        host_key_algorithm: String::new(),
        fingerprint: String::new(),
        trust: events::Trust::Known,
        hops: plan.hops.len(),
        connect_ms: started.elapsed().as_secs_f64() * 1000.0,
    }));
    let (exit_code, failure) = pump.await;
    // The jumps carried it: they go now.
    drop(jumps);
    (exit_code, failure, true)
}

async fn session(
    plan: &Plan,
    ctx: &Ctx,
    term: &Weak<Terminal>,
    tmux: &str,
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
    ctx.learn_systems(plan, &live);
    ctx.autostart(plan, &live).await;
    if let Some(server) = &plan.mosh {
        return mosh_session(plan, ctx, term, tmux, live, server).await;
    }
    shell(plan, ctx, term, tmux, live, plan.persistent).await
}

/// The session over Mosh, on a connection that is up: SSH starts the
/// server, then `mosh-client` takes over in the terminal's PTY and the
/// connection goes. Without Mosh here or there, or without UDP, the
/// session goes on over this same connection, in tmux.
async fn mosh_session(
    plan: &Plan,
    ctx: &Ctx,
    term: &Weak<Terminal>,
    tmux: &str,
    live: Arc<Live>,
    server: &str,
) -> (Option<u32>, Option<Failure>, bool) {
    use events::MoshFallback;
    let sink = &ctx.sink;
    let last = plan.hops.len() - 1;
    let target_hop = &plan.hops[last];
    sink.send(Event::Stage {
        hop: last,
        hops: plan.hops.len(),
        label: target_hop.label.clone(),
        stage: Stage::OpeningShell,
    });
    let over_ssh = |reason| {
        sink.send(Event::MoshFallback { reason });
        shell(plan, ctx, term, tmux, Arc::clone(&live), true)
    };
    let Some(client) = openward_ssh::client::find_program("mosh-client").await else {
        return over_ssh(MoshFallback::NoClient).await;
    };
    // Straight to the server: it listens where SSH came in. Through
    // jumps, everywhere (the packets come from outside).
    let command = mosh::server_command(server, plan.hops.len() == 1);
    let started = tokio::time::timeout(
        mosh::SERVER_START,
        live.target()
            .exec_until(&command, |out| mosh::connect_line(out).is_some()),
    )
    .await;
    let (port, key) = match started {
        Ok(Ok(out)) => match mosh::connect_line(&out.text()) {
            Some(found) => found,
            None => return over_ssh(mosh::server_problem(&out.text(), out.status)).await,
        },
        Ok(Err(e)) => return over_ssh(MoshFallback::Other(format!("{e:#}"))).await,
        Err(_) => {
            let silent = no_answer(mosh::SERVER_START);
            return over_ssh(MoshFallback::Other(silent)).await;
        }
    };
    let ip = match tokio::net::lookup_host((target_hop.address.as_str(), port)).await {
        Ok(mut found) => match found.next() {
            Some(addr) => addr.ip(),
            None => return over_ssh(MoshFallback::NoUdp).await,
        },
        Err(_) => return over_ssh(MoshFallback::NoUdp).await,
    };
    let Some(t) = term.upgrade() else {
        return (None, None, false);
    };
    let size = t.size();
    let run = t.run_program(
        Spawn {
            program: Some(client.display().to_string()),
            args: vec![ip.to_string(), port.to_string()],
            env: vec![("MOSH_KEY".into(), key)],
            cols: size.cols,
            rows: size.rows,
            ..Spawn::default()
        },
        mosh::NOTHING_RECEIVED,
    );
    drop(t);
    let mut program = match run {
        Ok(program) => program,
        Err(e) => return over_ssh(MoshFallback::Other(format!("{e:#}"))).await,
    };
    let mut connected = live.connected.clone();
    connected.mosh = true;
    sink.send(Event::Connected(connected));
    // The connection stays while the first packets may still not come:
    // without them, the session goes on over it.
    let first = tokio::time::timeout(mosh::UDP_WAIT, async {
        tokio::select! {
            ended = &mut program.exited => Some(ended.ok().flatten()),
            // Only when it was seen: the program's end closes it too.
            Ok(()) = &mut program.seen => None,
        }
    })
    .await;
    match first {
        // It ended early (it could not start, or the user left at once).
        Ok(Some(exit_code)) => return (exit_code, None, true),
        // Nothing came back over UDP.
        Ok(None) => {
            // Not detach: that would end this very session.
            if let Some(t) = term.upgrade() {
                t.end_program();
            }
            return over_ssh(MoshFallback::NoUdp).await;
        }
        Err(_) => {}
    }
    // Mosh has it now: the connection goes, unless a browser uses it.
    drop(live);
    let exit_code = program.exited.await.ok().flatten();
    (exit_code, None, true)
}

/// The shell on a connection that is up, in tmux when `persistent`.
async fn shell(
    plan: &Plan,
    ctx: &Ctx,
    term: &Weak<Terminal>,
    tmux: &str,
    live: Arc<Live>,
    persistent: bool,
) -> (Option<u32>, Option<Failure>, bool) {
    let sink = &ctx.sink;
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
    let (cols, rows) = (u32::from(size.cols), u32::from(size.rows));
    let target = live.target();
    let persistence = if persistent {
        let state = tmux_state(target, tmux).await;
        sink.send(Event::Persistent {
            session: tmux.to_owned(),
            state,
        });
        Some(state)
    } else {
        None
    };
    let in_tmux = matches!(persistence, Some(Persistence::New | Persistence::Resumed));
    let opened = if in_tmux {
        target
            .command_with(
                &tmux_command(tmux),
                &plan.term,
                cols,
                rows,
                &plan.env,
                plan.agent_forward,
            )
            .await
    } else {
        target
            .shell_with(&plan.term, cols, rows, &plan.env, plan.agent_forward)
            .await
    };
    let channel = match opened {
        Ok(channel) => channel,
        Err(e) => {
            let failure = Failure::Other(format!("opening the shell: {e:#}"));
            return (None, Some(failure), false);
        }
    };
    // Closing the tab ends the tmux session too; a cut does not.
    if in_tmux && let Some(t) = term.upgrade() {
        let weak = Arc::downgrade(&live);
        let name = tmux.to_owned();
        t.set_closer(move || {
            if let Some(live) = weak.upgrade() {
                live.runtime().clone().spawn(async move {
                    let kill = format!("tmux kill-session -t {name}");
                    let _ = tokio::time::timeout(
                        Duration::from_secs(3),
                        live.target().exec_short(&kill),
                    )
                    .await;
                });
            }
        });
    }
    // Input goes to the shell before anyone hears it is connected.
    let pump = pipe.pump_ssh(channel, &target_hop.label);
    let activity = pipe.activity();
    drop(pipe);
    sink.send(Event::Connected(live.connected.clone()));
    let watching = async {
        match Timing::from_keepalive(target_hop.keepalive) {
            Some(t) => {
                let health = alive::watch(
                    || live.target().ping(),
                    Some(&activity),
                    t,
                    |h| sink.send(Event::Health(h)),
                );
                // Each jump host is asked as often, to tell which part of
                // the route is slow.
                let hops = async {
                    if !live.has_jumps() {
                        return std::future::pending().await;
                    }
                    let mut every = tokio::time::interval(t.every);
                    every.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
                    loop {
                        every.tick().await;
                        let rtt_ms = live.jump_rtts(t.stalled_after).await;
                        sink.send(Event::Hops { rtt_ms });
                    }
                };
                tokio::select! {
                    silent = health => silent,
                    never = hops => never,
                }
            }
            None => std::future::pending().await,
        }
    };
    let (exit_code, failure) = tokio::select! {
        ended = pump => ended,
        silent = watching => {
            live.mark_lost();
            let failure = Failure::silent(target_hop.label.clone(), silent);
            (None, Some(failure))
        }
    };
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

    /// Each of this device's defaults is set on its own: turning one on
    /// or off leaves the other as it was.
    #[test]
    fn device_defaults_are_set_one_by_one() {
        let dir = tempfile::tempdir().unwrap();
        let app = App::open_as(&dir.path().join("data"), Local::from_env()).unwrap();
        app.set_session_log_everywhere(true);
        app.set_read_os_release_everywhere(true);
        app.set_session_log_everywhere(false);
        let device = app.vault().device_defaults().clone();
        assert_eq!(device.read_os_release, Some(true));
        assert_eq!(device.session_log, None);
        app.set_session_log_everywhere(true);
        app.set_read_os_release_everywhere(false);
        let device = app.vault().device_defaults().clone();
        assert_eq!(device.read_os_release, None);
        assert_eq!(device.session_log, Some(true));
    }
}
