//! The app as Dart holds it: one opaque [`OpenWard`] per data directory.

use std::path::PathBuf;
use std::sync::Arc;

use flutter_rust_bridge::frb;
use openward_app::vault::proto::{
    Data, Group, Host, Protocol, Settings, Source, System, SystemSource,
};
use openward_app::{App, DEFAULT_SCROLLBACK, RECONNECT_ATTEMPTS};
use openward_import::ssh_config::Warning;

use super::session::{DartSink, PromptAnswer, SessionEvent, TerminalSession};
use super::sftp::{ConflictChoice, SftpBrowser, TransferDirection, TransferView};
use super::vault::VaultError;
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

/// A serial port of this computer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SerialPortView {
    /// What to open: `/dev/cu.usbserial-1410`, `/dev/ttyUSB0`, `COM3`.
    pub path: String,
    /// What it is, when it says ("FT232R USB UART (FTDI)"); empty
    /// otherwise.
    pub description: String,
    /// A cable or an adapter on USB.
    pub usb: bool,
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
                    extra: h.system.take().map(|s| s.extra).unwrap_or_default(),
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
        Warning::Unreadable {
            file,
            denied,
            error,
        } => (
            if denied {
                ImportWarningKind::Denied
            } else {
                ImportWarningKind::Unreadable
            },
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

/// What only the tests may ask for (another home, a Termius key handed
/// in): the generated bindings reach every function, so these cannot be
/// left out of a release build; there they refuse.
pub(crate) fn for_tests(what: &str) -> Result<(), VaultError> {
    if cfg!(debug_assertions) {
        Ok(())
    } else {
        Err(VaultError {
            kind: VaultErrorKind::Invalid,
            message: format!("{what} is only for tests"),
        })
    }
}

impl OpenWard {
    /// Opens or creates the app's data in `data_dir` (the platform's
    /// application support directory).
    pub fn open(data_dir: String) -> Result<OpenWard, VaultError> {
        Ok(Self {
            app: Arc::new(App::open(&PathBuf::from(data_dir))?),
        })
    }

    /// As [`OpenWard::open`], with another `~/.ssh` (tests: the tester's
    /// own keys and `known_hosts` stay out, the system's too). Debug
    /// builds only: see [`for_tests`].
    pub fn open_with_ssh_dir(data_dir: String, ssh_dir: String) -> Result<OpenWard, VaultError> {
        for_tests("open_with_ssh_dir")?;
        let ssh_dir = PathBuf::from(ssh_dir);
        let local = openward_app::Local {
            system_ssh_dir: ssh_dir.join("system"),
            ssh_dir,
            ..openward_app::Local::from_env()
        };
        Ok(Self {
            app: Arc::new(App::open_as(&PathBuf::from(data_dir), local)?),
        })
    }

    /// As [`OpenWard::open`], with another home folder and its `.ssh`
    /// (tests: nothing of the tester's, such as their Termius, is seen).
    /// Debug builds only: see [`for_tests`].
    pub fn open_with_home(data_dir: String, home: String) -> Result<OpenWard, VaultError> {
        for_tests("open_with_home")?;
        let home = PathBuf::from(home);
        let local = openward_app::Local {
            ssh_dir: home.join(".ssh"),
            system_ssh_dir: home.join("etc-ssh"),
            home,
            ..openward_app::Local::from_env()
        };
        Ok(Self {
            app: Arc::new(App::open_as(&PathBuf::from(data_dir), local)?),
        })
    }

    /// Items this version cannot read, written by a newer one: they stay
    /// in the vault as they are, but the app does not show them.
    #[frb(sync)]
    pub fn unreadable_items(&self) -> u32 {
        self.app.vault().unreadable() as u32
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
                        Some(Source::SshConfig { alias, .. }) => Some(alias.clone()),
                        None => None,
                    },
                    environment: EnvironmentView::of(&settings.environment),
                    system: h.system.as_ref().map(SystemView::of),
                    favorite: h.favorite,
                    protocol: ProtocolKind::of(settings.protocol.unwrap_or(Protocol::Ssh)),
                    serial: (settings.protocol == Some(Protocol::Serial))
                        .then(|| settings.serial.as_ref().map(SerialLineSpec::of))
                        .flatten(),
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
    pub fn host(&self, id: String) -> Result<HostDetail, VaultError> {
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

    /// From now on, reads a host's `/etc/os-release` after connecting, and
    /// now over its connection if one is up. False when there is none: it
    /// is read on the next one.
    pub async fn read_os_release(&self, id: String) -> Result<bool, VaultError> {
        Ok(self.app.read_os_release(super::vault::id(&id)?).await?)
    }

    /// Reads `/etc/os-release` after connecting to the hosts that do not
    /// say otherwise, on this device; from Ajustes, at start and on change.
    #[frb(sync)]
    pub fn set_read_os_release_everywhere(&self, enabled: bool) {
        self.app.set_read_os_release_everywhere(enabled);
    }

    /// Records the session log of the hosts that do not say otherwise, and
    /// of addresses typed by hand, on this device; from Ajustes, at start
    /// and on change.
    #[frb(sync)]
    pub fn set_session_log_everywhere(&self, enabled: bool) {
        self.app.set_session_log_everywhere(enabled);
    }

    /// Makes a host a favorite (the last one) or not.
    pub fn set_favorite(&self, id: String, favorite: bool) -> Result<(), VaultError> {
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
    pub fn order_favorites(&self, ids: Vec<String>) -> Result<(), VaultError> {
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
        // All the places at once: a failure leaves the order as it was.
        let mut changes = Vec::new();
        for (at, hid) in order.enumerate() {
            let mut h = vault.host(hid)?.clone();
            if h.favorite == Some(at as u32) {
                continue;
            }
            h.favorite = Some(at as u32);
            let rev = vault.get(hid).map_or(0, |i| i.rev);
            changes.push((hid, rev, Data::Host(h)));
        }
        vault.update_all(changes)?;
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
    ) -> Result<InheritedView, VaultError> {
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
    pub fn group(&self, id: String) -> Result<GroupDetail, VaultError> {
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

    pub fn create_host(&self, spec: HostSpec) -> Result<String, VaultError> {
        let mut vault = self.app.vault();
        let mut h = Host::default();
        apply_host(&spec, &mut h, next_favorite(&vault))?;
        Ok(vault.create(Data::Host(h))?.to_string())
    }

    /// Returns the new revision. Fails if the host changed since `rev`.
    /// Saves `spec` over host `id` as read at `rev`. If it changed
    /// meanwhile (connecting learned its system, another window) and
    /// `base` is the spec as it was read, what this one changed goes over
    /// what is there now: only a field both changed is a conflict.
    pub fn update_host(
        &self,
        id: String,
        rev: u64,
        spec: HostSpec,
        base: Option<HostSpec>,
    ) -> Result<u64, VaultError> {
        let hid = super::vault::id(&id)?;
        let mut vault = self.app.vault();
        let next = next_favorite(&vault);
        let mut h = vault.host(hid)?.clone();
        let now = vault.get(hid).map_or(rev, |i| i.rev);
        let (spec, rev) = match base {
            Some(base) if now != rev => {
                let merged =
                    HostSpec::merge(&base, spec, host_spec(&h)).ok_or_else(|| VaultError {
                        kind: super::vault::VaultErrorKind::Conflict,
                        message: format!(
                            "host {hid} changed since revision {rev} where this edit changed it too"
                        ),
                    })?;
                (merged, now)
            }
            _ => (spec, rev),
        };
        apply_host(&spec, &mut h, next)?;
        Ok(vault.update(hid, rev, Data::Host(h))?)
    }

    pub fn create_group(&self, spec: GroupSpec) -> Result<String, VaultError> {
        let mut g = Group::default();
        apply_group(&spec, &mut g)?;
        Ok(self.app.vault().create(Data::Group(g))?.to_string())
    }

    pub fn update_group(&self, id: String, rev: u64, spec: GroupSpec) -> Result<u64, VaultError> {
        let gid = super::vault::id(&id)?;
        let mut vault = self.app.vault();
        let mut g = vault.group(gid)?.clone();
        apply_group(&spec, &mut g)?;
        Ok(vault.update(gid, rev, Data::Group(g))?)
    }

    /// A host, group or known host. A group's contents move up to its
    /// parent; a host other hosts jump through cannot go.
    pub fn delete(&self, id: String) -> Result<(), VaultError> {
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
    ) -> Result<ImportReport, VaultError> {
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

    /// Trusts a key the user checked, replacing the old one of its type
    /// (after a changed host key).
    pub fn trust_host_key(&self, host: String, port: u16, key: String) -> Result<(), VaultError> {
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
    ) -> Result<(), VaultError> {
        self.app.connect(
            &session.term,
            super::vault::id(&host_id)?,
            Arc::new(DartSink(events)),
        )?;
        Ok(())
    }

    /// As [`OpenWard::connect`], to an address that is not saved, with the
    /// default settings: by SSH or Telnet.
    pub fn connect_address(
        &self,
        session: &TerminalSession,
        address: String,
        user: Option<String>,
        port: Option<u16>,
        protocol: ProtocolKind,
        events: StreamSink<SessionEvent>,
    ) -> Result<(), VaultError> {
        self.app.connect_address(
            &session.term,
            address,
            user,
            port,
            protocol.proto(),
            Arc::new(DartSink(events)),
        )?;
        Ok(())
    }

    /// The serial ports there are now, USB ones (cables, adapters) first.
    pub fn serial_ports(&self) -> Vec<SerialPortView> {
        openward_app::serial_ports()
            .into_iter()
            .map(|p| SerialPortView {
                path: p.path,
                description: p.description,
                usb: p.usb,
            })
            .collect()
    }

    /// Opens the serial port at `path` in `session`. In Dart this returns
    /// the stream of its events, as for a host: connected, or closed with
    /// why.
    pub fn open_serial(
        &self,
        session: &TerminalSession,
        path: String,
        line: SerialLineSpec,
        events: StreamSink<SessionEvent>,
    ) {
        self.app.open_serial(
            &session.term,
            path,
            line.line(None),
            Arc::new(DartSink(events)),
        );
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
    ) -> Result<(), VaultError> {
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
    ) -> Result<(), VaultError> {
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
