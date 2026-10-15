//! The app as Dart holds it: one opaque [`OpenWard`] per data directory.

use std::path::PathBuf;
use std::sync::Arc;

use flutter_rust_bridge::frb;
use openward_app::vault::proto::{Data, Group, Host, Marker, Settings, Source};
use openward_app::{App, DEFAULT_SCROLLBACK, RECONNECT_ATTEMPTS};
use openward_import::ssh_config::Warning;

use super::session::{DartSink, PromptAnswer, SessionEvent, TerminalSession};
use super::vault::*;
use crate::frb_generated::StreamSink;

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[frb(opaque)]
pub struct OpenWard {
    app: Arc<App>,
}

fn host_spec(h: &Host) -> HostSpec {
    HostSpec {
        label: h.label.clone(),
        address: h.address.clone(),
        group_id: h.group.map(|g| g.to_string()),
        tags: h.tags.clone(),
        notes: h.notes.clone(),
        settings: SettingsSpec::from_settings(&h.settings),
    }
}

fn apply_host(spec: &HostSpec, h: &mut Host) -> anyhow::Result<()> {
    h.label = spec.label.trim().to_owned();
    h.address = spec.address.trim().to_owned();
    h.group = opt_id(&spec.group_id)?;
    h.tags = spec.tags.clone();
    h.notes = spec.notes.clone().filter(|n| !n.is_empty());
    spec.settings.apply(&mut h.settings)
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
                }
            })
            .collect()
    }

    #[frb(sync)]
    pub fn groups(&self) -> Vec<GroupView> {
        self.app
            .vault()
            .groups()
            .into_iter()
            .map(|(id, g)| GroupView {
                id: id.to_string(),
                name: g.name.clone(),
                parent_id: g.parent.map(|p| p.to_string()),
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
        })
    }

    /// What a host in `group_id` (none: the top level) gets before its own
    /// settings, and where each value comes from. For editors, so a new
    /// host or a host moved to another group shows what it will inherit.
    #[frb(sync)]
    pub fn inherited(&self, group_id: Option<String>) -> anyhow::Result<InheritedView> {
        let vault = self.app.vault();
        let inherited = vault.inherited(opt_id(&group_id)?)?;
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
        let mut h = Host::default();
        apply_host(&spec, &mut h)?;
        Ok(self.app.vault().create(Data::Host(h))?.to_string())
    }

    /// Returns the new revision. Fails if the host changed since `rev`.
    pub fn update_host(&self, id: String, rev: u64, spec: HostSpec) -> anyhow::Result<u64> {
        let hid = super::vault::id(&id)?;
        let mut vault = self.app.vault();
        let mut h = vault.host(hid)?.clone();
        apply_host(&spec, &mut h)?;
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
        self.app.vault().delete(super::vault::id(&id)?)?;
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
}
