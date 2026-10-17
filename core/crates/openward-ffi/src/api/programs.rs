//! Importing from other programs (Termius, PuTTY, KiTTY, MobaXterm,
//! Tabby, SecureCRT) and CSV files of hosts, as Dart sees it: what is on this computer, what a
//! file or folder holds, and the import itself.
//!
//! Reading keeps what was read in a [`ProgramData`], so Termius's key is
//! asked for once: the preview and the import use that.

use std::path::PathBuf;

use flutter_rust_bridge::frb;
use openward_app::programs::{Choice, KeyMatch, Preview, PreviewItem, Read, Report};
use openward_import::bundle::{Program, Warning, WarningKind};
use openward_import::detect;
use openward_import::termius;

use super::app::OpenWard;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProgramKind {
    Termius,
    Putty,
    Kitty,
    MobaXterm,
    Tabby,
    SecureCrt,
    Csv,
}

impl From<Program> for ProgramKind {
    fn from(p: Program) -> Self {
        match p {
            Program::Termius => Self::Termius,
            Program::Putty => Self::Putty,
            Program::Kitty => Self::Kitty,
            Program::MobaXterm => Self::MobaXterm,
            Program::Tabby => Self::Tabby,
            Program::SecureCrt => Self::SecureCrt,
            Program::Csv => Self::Csv,
        }
    }
}

/// A program's data on this computer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FoundProgram {
    pub program: ProgramKind,
    pub path: String,
}

/// What was read, kept for the preview and the import.
#[frb(opaque)]
pub struct ProgramData {
    read: Read,
}

impl ProgramData {
    #[frb(sync, getter)]
    pub fn program(&self) -> ProgramKind {
        self.read.program.into()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReadFailureKind {
    /// Not a file of any program OpenWard imports from.
    NotRecognized,
    /// The file or folder could not be read.
    Unreadable,
    /// The program's file, but not as expected (`message` says how).
    Format,
    /// No Termius data there.
    TermiusNotFound,
    /// The keychain was not asked, or said no.
    TermiusKeychain,
    /// Termius's key is not in the keychain.
    TermiusNoKey,
    /// The keychain's key does not open Termius's data.
    TermiusWrongKey,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReadFailure {
    pub kind: ReadFailureKind,
    pub program: Option<ProgramKind>,
    pub message: String,
}

pub struct ProgramRead {
    pub data: Option<ProgramData>,
    pub failure: Option<ReadFailure>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProgramItem {
    pub id: String,
    pub is_group: bool,
    pub label: String,
    /// `user@address`, for hosts.
    pub address: String,
    pub parent: Option<String>,
    /// Imported before: it stays as it is.
    pub existing: bool,
    /// Why it cannot come (`telnet`, `rdp`…).
    pub unsupported: Option<String>,
    pub jumps: Vec<String>,
    pub tunnels: u32,
    pub tags: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProgramKey {
    pub id: String,
    pub label: String,
    pub algorithm: Option<String>,
    pub fingerprint: Option<String>,
    /// The same key in `~/.ssh`.
    pub found: Option<String>,
    /// Where saving it would write it.
    pub save_as: String,
    pub used_by: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProgramWarningKind {
    /// Mosh: it comes in as SSH.
    Mosh,
    /// A command run on connect.
    StartupCommand,
    /// Something OpenWard does not have; `detail` names it.
    Unsupported,
    /// `detail` is `field=value`.
    BadValue,
    /// Items of a team's shared vault; `detail` is how many.
    Shared,
    /// Termius's host chains.
    HostChain,
    /// Part of the data could not be read; `detail` says why.
    Unreadable,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProgramWarning {
    pub subject: Option<String>,
    pub kind: ProgramWarningKind,
    pub detail: String,
}

fn warning(w: &Warning) -> ProgramWarning {
    let (kind, detail) = match &w.kind {
        WarningKind::Mosh => (ProgramWarningKind::Mosh, String::new()),
        WarningKind::StartupCommand => (ProgramWarningKind::StartupCommand, String::new()),
        WarningKind::Unsupported(what) => (ProgramWarningKind::Unsupported, what.clone()),
        WarningKind::BadValue { field, value } => {
            (ProgramWarningKind::BadValue, format!("{field}={value}"))
        }
        WarningKind::Shared { count } => (ProgramWarningKind::Shared, count.to_string()),
        WarningKind::HostChain => (ProgramWarningKind::HostChain, String::new()),
        WarningKind::Unreadable(why) => (ProgramWarningKind::Unreadable, why.clone()),
    };
    ProgramWarning {
        subject: w.subject.clone(),
        kind,
        detail,
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProgramPreview {
    pub program: ProgramKind,
    /// The group an earlier import made, which this one goes into.
    pub group: Option<String>,
    /// Groups (parents first), then hosts, in the program's order.
    pub items: Vec<ProgramItem>,
    pub identities: u32,
    pub new_identities: u32,
    pub new_tunnels: u32,
    pub new_snippets: u32,
    pub new_known_hosts: u32,
    pub keys: Vec<ProgramKey>,
    pub warnings: Vec<ProgramWarning>,
    /// Saved passwords and key passphrases, never imported.
    pub passwords: u32,
    pub passphrases: u32,
}

fn item(i: PreviewItem) -> ProgramItem {
    ProgramItem {
        id: i.id,
        is_group: i.is_group,
        label: i.label,
        address: i.address,
        parent: i.parent,
        existing: i.existing,
        unsupported: i.unsupported,
        jumps: i.jumps,
        tunnels: i.tunnels as u32,
        tags: i.tags,
    }
}

fn key(k: KeyMatch) -> ProgramKey {
    ProgramKey {
        id: k.id,
        label: k.label,
        algorithm: k.algorithm,
        fingerprint: k.fingerprint,
        found: k.found,
        save_as: k.save_as,
        used_by: k.used_by as u32,
    }
}

impl From<Preview> for ProgramPreview {
    fn from(p: Preview) -> Self {
        Self {
            program: p.program.into(),
            group: p.group,
            items: p.items.into_iter().map(item).collect(),
            identities: p.identities as u32,
            new_identities: p.new_identities as u32,
            new_tunnels: p.new_tunnels as u32,
            new_snippets: p.new_snippets as u32,
            new_known_hosts: p.new_known_hosts as u32,
            keys: p.keys.into_iter().map(key).collect(),
            warnings: p.warnings.iter().map(warning).collect(),
            passwords: p.passwords as u32,
            passphrases: p.passphrases as u32,
        }
    }
}

/// What the user picked.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProgramChoice {
    /// Hosts to bring, by the program's id; the hosts they jump through
    /// come along.
    pub hosts: Vec<String>,
    /// The top-level group's name, if it is made now.
    pub group_name: String,
    /// Stored keys to write to `~/.ssh`, by id.
    pub save_keys: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProgramReport {
    pub group_id: Option<String>,
    pub hosts: u32,
    pub groups: u32,
    pub identities: u32,
    pub tunnels: u32,
    pub snippets: u32,
    pub known_hosts: u32,
    pub skipped: u32,
    pub saved_keys: Vec<String>,
    pub without_key: Vec<String>,
    pub warnings: Vec<ProgramWarning>,
}

impl From<Report> for ProgramReport {
    fn from(r: Report) -> Self {
        Self {
            group_id: r.group.map(|g| g.to_string()),
            hosts: r.hosts as u32,
            groups: r.groups as u32,
            identities: r.identities as u32,
            tunnels: r.tunnels as u32,
            snippets: r.snippets as u32,
            known_hosts: r.known_hosts as u32,
            skipped: r.skipped as u32,
            saved_keys: r.saved_keys,
            without_key: r.without_key,
            warnings: r.warnings.iter().map(warning).collect(),
        }
    }
}

fn failure(e: detect::Error) -> ReadFailure {
    let message = e.to_string();
    let (kind, program) = match e {
        detect::Error::NotRecognized => (ReadFailureKind::NotRecognized, None),
        detect::Error::Io(_) => (ReadFailureKind::Unreadable, None),
        detect::Error::Format { program, .. } => (ReadFailureKind::Format, Some(program.into())),
        detect::Error::Termius(t) => (
            match t {
                termius::Error::NotFound => ReadFailureKind::TermiusNotFound,
                termius::Error::Io(_) => ReadFailureKind::Unreadable,
                termius::Error::Keychain(_) => ReadFailureKind::TermiusKeychain,
                termius::Error::NoKey => ReadFailureKind::TermiusNoKey,
                termius::Error::WrongKey => ReadFailureKind::TermiusWrongKey,
            },
            Some(ProgramKind::Termius),
        ),
    };
    ReadFailure {
        kind,
        program,
        message,
    }
}

impl OpenWard {
    /// Other programs' data on this computer: Termius, Tabby, PuTTY's
    /// sessions, SecureCRT's, MobaXterm's.
    #[frb(sync)]
    pub fn installed_programs(&self) -> Vec<FoundProgram> {
        self.app
            .installed_programs()
            .into_iter()
            .map(|f| FoundProgram {
                program: f.program.into(),
                path: f.path.display().to_string(),
            })
            .collect()
    }

    /// Reads a file or folder of another program, recognizing whose it
    /// is. For Termius's data the system asks the user first, to let
    /// OpenWard use Termius's key from the keychain.
    pub fn read_program(&self, path: String) -> ProgramRead {
        self.read(path, None)
    }

    /// As [`Self::read_program`], with Termius's key given (tests).
    pub fn read_program_with_key(&self, path: String, termius_key: Vec<u8>) -> ProgramRead {
        let key: Option<[u8; 32]> = termius_key.try_into().ok();
        self.read(path, Some(key.into_iter().collect()))
    }

    fn read(&self, path: String, keys: Option<Vec<[u8; 32]>>) -> ProgramRead {
        match self.app.read_program(&PathBuf::from(path), keys) {
            Ok(read) => ProgramRead {
                data: Some(ProgramData { read }),
                failure: None,
            },
            Err(e) => ProgramRead {
                data: None,
                failure: Some(failure(e)),
            },
        }
    }

    /// What importing it would bring, and what is there already.
    #[frb(sync)]
    pub fn preview_program(&self, data: &ProgramData) -> ProgramPreview {
        self.app.preview_program(&data.read).into()
    }

    pub fn import_program(
        &self,
        data: &ProgramData,
        choice: ProgramChoice,
    ) -> anyhow::Result<ProgramReport> {
        let choice = Choice {
            hosts: choice.hosts,
            group_name: choice.group_name,
            save_keys: choice.save_keys,
        };
        Ok(self.app.import_program(&data.read, &choice)?.into())
    }
}
