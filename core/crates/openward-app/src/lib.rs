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
pub mod local;
pub mod plan;
pub mod terminal;

mod connect;

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};

use openward_import::ssh_config::Paths;
use openward_pty::Spawn;
use openward_ssh::known_hosts::Verdict;
use openward_vault::Vault;
use openward_vault::proto::ItemId;

pub use events::{Answer, Event, EventSink, Failure, Prompt};
pub use local::Local;
pub use openward_vault as vault;
pub use plan::{Plan, PlanError};
pub use terminal::Terminal;

use connect::{Ctx, lock};
use events::{Connected, Prompts, Stage, Trust};

/// Scrollback lines when settings say nothing.
pub const DEFAULT_SCROLLBACK: usize = 10_000;

pub struct App {
    vault: Arc<Mutex<Vault>>,
    local: Local,
    prompts: Arc<Prompts>,
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
        let plan = self.plan(host)?;
        terminal.close();
        let ctx = Ctx {
            vault: Arc::clone(&self.vault),
            local: self.local.clone(),
            prompts: Arc::clone(&self.prompts),
            sink: Arc::clone(&sink),
        };
        let term = Arc::downgrade(terminal);
        let task = self.runtime.spawn(async move {
            let closed = |exit_code, failure| Event::Closed { exit_code, failure };
            let sessions = match connect::run(&plan, &ctx).await {
                Ok(sessions) => sessions,
                Err(failure) => return sink.send(closed(None, Some(failure))),
            };
            let Some(pipe) = term.upgrade().map(|t| t.pipe()) else {
                return;
            };
            let last = plan.hops.len() - 1;
            ctx.sink.send(Event::Stage {
                hop: last,
                hops: plan.hops.len(),
                label: plan.hops[last].label.clone(),
                stage: Stage::OpeningShell,
            });
            let target = sessions.last().expect("a plan has hops");
            let size = pipe.size();
            let channel = match target
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
                    return sink.send(closed(None, Some(failure)));
                }
            };
            let info = target.info();
            sink.send(Event::Connected(Connected {
                post_quantum: info.post_quantum(),
                kex: info.kex,
                cipher: info.cipher,
                host_key_algorithm: info.host_key,
                trust: match info.verdict {
                    Some(Verdict::Certified { ca, .. }) => Trust::Certified { ca },
                    Some(Verdict::Learned) => Trust::New,
                    _ => Trust::Known,
                },
                hops: plan.hops.len(),
                connect_ms: info.connect_ms,
            }));
            let (exit_code, failure) = pipe.pump_ssh(channel, &plan.hops[last].label).await;
            for session in sessions.iter().rev() {
                session.disconnect().await;
            }
            sink.send(closed(exit_code, failure));
        });
        terminal.set_task(task);
        Ok(())
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
    pub fn trust_host_key(&self, host: &str, port: u16, key: &str) -> openward_vault::Result<()> {
        self.vault().trust_host_key(host, port, key).map(|_| ())
    }

    /// Imports `file`, or `~/.ssh/config`.
    pub fn import_ssh_config(&self, file: Option<&Path>) -> openward_vault::Result<import::Report> {
        let paths = Paths {
            home: self.local.home.clone(),
            ssh_dir: self.local.ssh_dir.clone(),
        };
        let file: PathBuf = file.map_or_else(|| paths.user_config(), Path::to_owned);
        import::ssh_config(&mut self.vault(), &file, &paths)
    }
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
