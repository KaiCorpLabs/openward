//! The app as Dart holds it: one opaque [`OpenWard`] per data directory.

use std::path::PathBuf;
use std::sync::Arc;

use flutter_rust_bridge::frb;
use openward_app::vault::proto::{
    Data, Group, Host, Marker, Settings, Source, System, SystemSource,
};
use openward_app::{App, DEFAULT_SCROLLBACK, RECONNECT_ATTEMPTS};
use openward_import::ssh_config::Warning;

use super::session::{DartSink, PromptAnswer, SessionEvent, TerminalSession};
use super::sftp::{ConflictChoice, SftpBrowser, TransferDirection, TransferView};
use super::vault::*;
use crate::frb_generated::StreamSink;

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// The core's version, for «Acerca de» and problem reports.
#[frb(sync)]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

#[frb(opaque)]
pub struct OpenWard {
    pub(crate) app: Arc<App>,
}

fn host_spec(h: &Host) -> HostSpec {
    HostSpec {
        label: h.label.clone(),
        address: h.address.clone(),
        group_id: h.group.map(|g| g.to_string()),
        tags: h.tags.clone(),
        notes: h.notes.clone(),
        settings: SettingsSpec::from_settings(&h.settings),
        favorite: h.favorite.is_some(),
        system_code: h
            .system
            .as_ref()
            .filter(|s| s.source == SystemSource::Manual)
            .map(|s| s.code.clone()),
    }
}

/// `next_favorite`: the place a host that becomes a favorite takes.
fn apply_host(spec: &HostSpec, h: &mut Host, next_favorite: u32) -> anyhow::Result<()> {
    h.label = spec.label.trim().to_owned();
    h.address = spec.address.trim().to_owned();
    h.group = opt_id(&spec.group_id)?;
    h.tags = spec.tags.clone();
    h.notes = spec.notes.clone().filter(|n| !n.is_empty());
    h.favorite = match (spec.favorite, h.favorite) {
        (false, _) => None,
        (true, Some(at)) => Some(at),
        (true, None) => Some(next_favorite),
    };
    let manual = h
        .system
        .as_ref()
        .is_some_and(|s| s.source == SystemSource::Manual);
    match &spec.system_code {
        Some(code) => {
            if !h.system.as_ref().is_some_and(|s| s.code == *code) || !manual {
                h.system = Some(System {
                    code: code.clone(),
                    name: String::new(),
                    source: SystemSource::Manual,
                    evidence: String::new(),
                });
            }
        }
        // Back to what connecting tells, next time.
        None if manual => h.system = None,
        None => {}
    }
    spec.settings.apply(&mut h.settings)
}

/// After the last favorite.
fn next_favorite(vault: &openward_app::vault::Vault) -> u32 {
    vault
        .hosts()
        .iter()
        .filter_map(|(_, h)| h.favorite)
        .max()
        .map_or(0, |m| m + 1)
}

fn apply_group(spec: &GroupSpec, g: &mut Group) -> anyhow::Result<()> {
    g.name = spec.name.trim().to_owned();
    g.parent = opt_id(&spec.parent_id)?;
    spec.settings.apply(&mut g.settings)
}

fn warning(w: Warning) -> ImportWarning {
    let at = |loc: openward_import::ssh_config::Location| {
        (loc.file.display().to_string(), loc.line as u32)
    };
    let (kind, (file, line), subject, detail) = match w {
        Warning::Unsupported { keyword, at: l } => (
            ImportWarningKind::Unsupported,
            at(l),
            keyword,
            String::new(),
        ),
        Warning::Match { at: l } => (
            ImportWarningKind::Match,
            at(l),
            String::new(),
            String::new(),
        ),
        Warning::BadValue {
            keyword,
            value,
            at: l,
        } => (ImportWarningKind::BadValue, at(l), keyword, value),
        Warning::Stricter { at: l } => (
            ImportWarningKind::Stricter,
            at(l),
            String::new(),
            String::new(),
        ),
        Warning::IncludeTooDeep { at: l } => (
            ImportWarningKind::IncludeTooDeep,
            at(l),
            String::new(),
            String::new(),
        ),
        Warning::Unreadable { file, error } => (
            ImportWarningKind::Unreadable,
            (file.display().to_string(), 0),
            error,
            String::new(),
        ),
        Warning::JumpLossy { alias, jump } => (
            ImportWarningKind::JumpLossy,
            (String::new(), 0),
            alias,
            jump,
        ),
    };
    ImportWarning {
        kind,
        file,
        line,
        subject,
        detail,
    }
}

impl OpenWard {
    /// Opens or creates the app's data in `data_dir` (the platform's
    /// application support directory).
    pub fn open(data_dir: String) -> anyhow::Result<OpenWard> {
        Ok(Self {
            app: Arc::new(App::open(&PathBuf::from(data_dir))?),
        })
    }

    /// As [`OpenWard::open`], with another `~/.ssh` (tests: the tester's
    /// own keys and `known_hosts` stay out).
    pub fn open_with_ssh_dir(data_dir: String, ssh_dir: String) -> anyhow::Result<OpenWard> {
        let local = openward_app::Local {
            ssh_dir: PathBuf::from(ssh_dir),
            ..openward_app::Local::from_env()
        };
        Ok(Self {
            app: Arc::new(App::open_as(&PathBuf::from(data_dir), local)?),
        })
    }

    /// As [`OpenWard::open`], with another home folder and its `.ssh`
    /// (tests: nothing of the tester's, such as their Termius, is seen).
    pub fn open_with_home(data_dir: String, home: String) -> anyhow::Result<OpenWard> {
        let home = PathBuf::from(home);
        let local = openward_app::Local {
            ssh_dir: home.join(".ssh"),
            home,
            ..openward_app::Local::from_env()
        };
        Ok(Self {
            app: Arc::new(App::open_as(&PathBuf::from(data_dir), local)?),
        })
    }

    #[frb(sync)]
    pub fn hosts(&self) -> Vec<HostView> {
        let vault = self.app.vault();
        let local_user = &self.app.local().user;
        vault
            .hosts()
            .into_iter()
            .map(|(id, h)| {
                let settings = vault.effective(id).map(|e| e.settings).unwrap_or_default();
                HostView {
                    id: id.to_string(),
                    label: h.label.clone(),
                    address: h.address.clone(),
                    group_id: h.group.map(|g| g.to_string()),
                    tags: h.tags.clone(),
                    user: settings.user.unwrap_or_else(|| local_user.clone()),
                    port: settings.port.unwrap_or(22),
                    imported_alias: match &h.source {
                        Some(Source::SshConfig { alias }) => Some(alias.clone()),
                        None => None,
                    },
                    environment: EnvironmentView::of(&settings.environment),
                    system: h.system.as_ref().map(SystemView::of),
                    favorite: h.favorite,
                }
            })
            .collect()
    }

    #[frb(sync)]
    pub fn groups(&self) -> Vec<GroupView> {
        let vault = self.app.vault();
        vault
            .groups()
            .into_iter()
            .map(|(id, g)| GroupView {
                id: id.to_string(),
                name: g.name.clone(),
                parent_id: g.parent.map(|p| p.to_string()),
                environment: vault
                    .inherited(Some(id), None)
                    .ok()
                    .and_then(|e| EnvironmentView::of(&e.settings.environment)),
            })
            .collect()
    }

    /// Ids of the hosts matching every word, sorted by label.
    #[frb(sync)]
    pub fn search(&self, query: String) -> Vec<String> {
        self.app
            .vault()
            .search(&query)
            .into_iter()
            .map(|id| id.to_string())
            .collect()
    }

    #[frb(sync)]
    pub fn tags(&self) -> Vec<TagCount> {
        self.app
            .vault()
            .tags()
            .into_iter()
            .map(|(tag, hosts)| TagCount {
                tag,
                hosts: hosts as u32,
            })
            .collect()
    }

    #[frb(sync)]
    pub fn host(&self, id: String) -> anyhow::Result<HostDetail> {
        let hid = super::vault::id(&id)?;
        let vault = self.app.vault();
        let h = vault.host(hid)?;
        let rev = vault.get(hid).map_or(0, |i| i.rev);
        let effective = vault.effective(hid)?;
        Ok(HostDetail {
            id,
            rev,
            spec: host_spec(h),
            effective: SettingsSpec::from_settings(&effective.settings),
            origins: Settings::FIELDS
                .iter()
                .map(|f| origin(f, effective.origin(f)))
                .collect(),
            system: h.system.as_ref().map(SystemView::of),
        })
    }

    /// Makes a host a favorite (the last one) or not.
    pub fn set_favorite(&self, id: String, favorite: bool) -> anyhow::Result<()> {
        let hid = super::vault::id(&id)?;
        let mut vault = self.app.vault();
        let next = next_favorite(&vault);
        let mut h = vault.host(hid)?.clone();
        if h.favorite.is_some() == favorite {
            return Ok(());
        }
        h.favorite = favorite.then_some(next);
        let rev = vault.get(hid).map_or(0, |i| i.rev);
        vault.update(hid, rev, Data::Host(h))?;
        Ok(())
    }

    /// Puts the favorites in this order; the ones left out keep theirs,
    /// after these.
    pub fn order_favorites(&self, ids: Vec<String>) -> anyhow::Result<()> {
        let mut vault = self.app.vault();
        let ids = ids
            .iter()
            .map(|i| super::vault::id(i))
            .collect::<anyhow::Result<Vec<_>>>()?;
        let mut rest: Vec<_> = vault
            .hosts()
            .into_iter()
            .filter(|(id, h)| h.favorite.is_some() && !ids.contains(id))
            .map(|(id, h)| (h.favorite, id))
            .collect();
        rest.sort();
        let order = ids
            .iter()
            .copied()
            .chain(rest.into_iter().map(|(_, id)| id));
        for (at, hid) in order.enumerate() {
            let mut h = vault.host(hid)?.clone();
            if h.favorite == Some(at as u32) {
                continue;
            }
            h.favorite = Some(at as u32);
            let rev = vault.get(hid).map_or(0, |i| i.rev);
            vault.update(hid, rev, Data::Host(h))?;
        }
        Ok(())
    }

    /// What a host in `group_id` (none: the top level) gets before its own
    /// settings, and where each value comes from. For editors, so a new
    /// host or a host moved to another group shows what it will inherit;
    /// `identity` is the editor's choice of identity, if it makes one.
    #[frb(sync)]
    pub fn inherited(
        &self,
        group_id: Option<String>,
        identity: Option<IdentityChoice>,
        identity_id: String,
    ) -> anyhow::Result<InheritedView> {
        let vault = self.app.vault();
        let inherited =
            vault.inherited(opt_id(&group_id)?, identity_choice(identity, &identity_id)?)?;
        Ok(InheritedView {
            effective: SettingsSpec::from_settings(&inherited.settings),
            origins: Settings::FIELDS
                .iter()
                .map(|f| origin(f, inherited.origin(f)))
                .collect(),
        })
    }

    #[frb(sync)]
    pub fn group(&self, id: String) -> anyhow::Result<GroupDetail> {
        let gid = super::vault::id(&id)?;
        let vault = self.app.vault();
        let g = vault.group(gid)?;
        Ok(GroupDetail {
            rev: vault.get(gid).map_or(0, |i| i.rev),
            spec: GroupSpec {
                name: g.name.clone(),
                parent_id: g.parent.map(|p| p.to_string()),
                settings: SettingsSpec::from_settings(&g.settings),
            },
            id,
        })
    }

    pub fn create_host(&self, spec: HostSpec) -> anyhow::Result<String> {
        let mut vault = self.app.vault();
        let mut h = Host::default();
        apply_host(&spec, &mut h, next_favorite(&vault))?;
        Ok(vault.create(Data::Host(h))?.to_string())
    }

    /// Returns the new revision. Fails if the host changed since `rev`.
    pub fn update_host(&self, id: String, rev: u64, spec: HostSpec) -> anyhow::Result<u64> {
        let hid = super::vault::id(&id)?;
        let mut vault = self.app.vault();
        let next = next_favorite(&vault);
        let mut h = vault.host(hid)?.clone();
        apply_host(&spec, &mut h, next)?;
        Ok(vault.update(hid, rev, Data::Host(h))?)
    }

    pub fn create_group(&self, spec: GroupSpec) -> anyhow::Result<String> {
        let mut g = Group::default();
        apply_group(&spec, &mut g)?;
        Ok(self.app.vault().create(Data::Group(g))?.to_string())
    }

    pub fn update_group(&self, id: String, rev: u64, spec: GroupSpec) -> anyhow::Result<u64> {
        let gid = super::vault::id(&id)?;
        let mut vault = self.app.vault();
        let mut g = vault.group(gid)?.clone();
        apply_group(&spec, &mut g)?;
        Ok(vault.update(gid, rev, Data::Group(g))?)
    }

    /// A host, group or known host. A group's contents move up to its
    /// parent; a host other hosts jump through cannot go.
    pub fn delete(&self, id: String) -> anyhow::Result<()> {
        self.app.delete(super::vault::id(&id)?)?;
        Ok(())
    }

    /// What importing `~/.ssh/config` (or `file`) would bring, in the
    /// file's order. An empty list: no file, or no hosts in it.
    pub fn preview_ssh_config(&self, file: Option<String>) -> Vec<ImportPreview> {
        self.app
            .preview_ssh_config(file.map(PathBuf::from).as_deref())
            .into_iter()
            .map(|p| ImportPreview {
                alias: p.alias,
                address: p.address,
                user: p.user,
                port: p.port,
                jumps: p.jumps,
                existing: p.existing,
                tunnels: p.tunnels as u32,
            })
            .collect()
    }

    /// Imports `~/.ssh/config` (or `file`); with `only`, just those aliases
    /// and the hosts they jump through. Aliases imported before stay as
    /// they are.
    pub fn import_ssh_config(
        &self,
        file: Option<String>,
        only: Option<Vec<String>>,
    ) -> anyhow::Result<ImportReport> {
        let report = self
            .app
            .import_ssh_config(file.map(PathBuf::from).as_deref(), only.as_deref())?;
        Ok(ImportReport {
            group_id: report.group.to_string(),
            created: report.created as u32,
            skipped: report.skipped as u32,
            tunnels: report.tunnels as u32,
            warnings: report.warnings.into_iter().map(warning).collect(),
        })
    }

    #[frb(sync)]
    pub fn known_hosts(&self) -> Vec<KnownHostView> {
        self.app
            .vault()
            .known_hosts()
            .into_iter()
            .map(|(id, k)| KnownHostView {
                id: id.to_string(),
                hosts: k.hosts.clone(),
                algorithm: k
                    .key
                    .split_whitespace()
                    .next()
                    .unwrap_or_default()
                    .to_owned(),
                key: k.key.clone(),
                cert_authority: k.marker == Some(Marker::CertAuthority),
            })
            .collect()
    }

    /// Trusts a key the user checked, replacing the old one of its type
    /// (after a changed host key).
    pub fn trust_host_key(&self, host: String, port: u16, key: String) -> anyhow::Result<()> {
        Ok(self.app.trust_host_key(&host, port, &key)?)
    }

    /// A new terminal tab, connected to nothing yet: pass it to
    /// [`OpenWard::connect`] or [`OpenWard::open_local`].
    /// `scrollback` lines of history; 0 for the default.
    #[frb(sync)]
    pub fn terminal(&self, cols: u16, rows: u16, scrollback: u32) -> TerminalSession {
        let lines = if scrollback == 0 {
            DEFAULT_SCROLLBACK
        } else {
            scrollback as usize
        };
        TerminalSession {
            term: self.app.terminal(cols, rows, lines),
        }
    }

    /// Connects `session` to a saved host; again on the same session, it
    /// reconnects and keeps the screen. In Dart this returns the stream of
    /// the connection's events: progress, questions and the outcome.
    pub fn connect(
        &self,
        session: &TerminalSession,
        host_id: String,
        events: StreamSink<SessionEvent>,
    ) -> anyhow::Result<()> {
        self.app.connect(
            &session.term,
            super::vault::id(&host_id)?,
            Arc::new(DartSink(events)),
        )?;
        Ok(())
    }

    /// As [`OpenWard::connect`], to an address that is not saved, with the
    /// default settings.
    pub fn connect_address(
        &self,
        session: &TerminalSession,
        address: String,
        user: Option<String>,
        port: Option<u16>,
        events: StreamSink<SessionEvent>,
    ) -> anyhow::Result<()> {
        self.app.connect_address(
            &session.term,
            address,
            user,
            port,
            Arc::new(DartSink(events)),
        )?;
        Ok(())
    }

    /// Tries after losing a connection, before giving up.
    #[frb(sync)]
    pub fn reconnect_attempts(&self) -> u32 {
        RECONNECT_ATTEMPTS
    }

    /// Runs the user's shell on this machine in `session`. In Dart this
    /// returns the stream of its events (the end, with its exit code).
    pub fn open_local(
        &self,
        session: &TerminalSession,
        events: StreamSink<SessionEvent>,
    ) -> anyhow::Result<()> {
        self.app
            .open_local(&session.term, None, Arc::new(DartSink(events)))
    }

    /// Answers a prompt; false if nothing waits for it any more.
    #[frb(sync)]
    pub fn answer(&self, prompt_id: u64, answer: PromptAnswer) -> bool {
        self.app.answer(prompt_id, answer.into_answer())
    }

    /// A new SFTP browser, not connected yet.
    #[frb(sync)]
    pub fn sftp(&self) -> SftpBrowser {
        SftpBrowser {
            sftp: self.app.sftp(),
        }
    }

    /// Connects a browser to a saved host, over a terminal's connection to
    /// it when one is up. The stream is the connection's events, as for
    /// terminals; `connected` means it can browse.
    pub fn connect_sftp(
        &self,
        browser: &SftpBrowser,
        host_id: String,
        events: StreamSink<SessionEvent>,
    ) -> anyhow::Result<()> {
        self.app.connect_sftp(
            &browser.sftp,
            super::vault::id(&host_id)?,
            Arc::new(DartSink(events)),
        )?;
        Ok(())
    }

    /// As [`OpenWard::connect_sftp`], to an address that is not saved.
    pub fn connect_sftp_address(
        &self,
        browser: &SftpBrowser,
        address: String,
        user: Option<String>,
        port: Option<u16>,
        events: StreamSink<SessionEvent>,
    ) -> anyhow::Result<()> {
        self.app.connect_sftp_address(
            &browser.sftp,
            address,
            user,
            port,
            Arc::new(DartSink(events)),
        )?;
        Ok(())
    }

    /// Queues a copy of a file or folder over `browser`'s connection;
    /// returns its id. It goes on if the browser closes.
    #[frb(sync)]
    pub fn transfer(
        &self,
        browser: &SftpBrowser,
        direction: TransferDirection,
        source: String,
        dest_dir: String,
        on_conflict: ConflictChoice,
    ) -> u64 {
        super::sftp::transfer(&self.app, browser, direction, source, dest_dir, on_conflict)
    }

    /// Every transfer, oldest first, with its progress now.
    #[frb(sync)]
    pub fn transfers(&self) -> Vec<TransferView> {
        self.app
            .transfers()
            .jobs()
            .into_iter()
            .map(TransferView::from)
            .collect()
    }

    #[frb(sync)]
    pub fn pause_transfer(&self, id: u64) {
        self.app.transfers().pause(id);
    }

    #[frb(sync)]
    pub fn resume_transfer(&self, id: u64) {
        self.app.transfers().resume(id);
    }

    /// Stops it for good, deleting the file it was writing.
    #[frb(sync)]
    pub fn cancel_transfer(&self, id: u64) {
        self.app.transfers().cancel(id);
    }

    /// Takes it off the list (cancelling it if it was not finished).
    #[frb(sync)]
    pub fn remove_transfer(&self, id: u64) {
        self.app.transfers().remove(id);
    }

    #[frb(sync)]
    pub fn pause_transfers(&self) {
        self.app.transfers().pause_all();
    }

    #[frb(sync)]
    pub fn clear_finished_transfers(&self) {
        self.app.transfers().clear_finished();
    }
}
