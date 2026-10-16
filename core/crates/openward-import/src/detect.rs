//! Which program a file or folder comes from, and what is on this
//! computer already, so the user does not have to say.

use std::fs;
use std::path::{Path, PathBuf};

use crate::bundle::{Bundle, Program};
use crate::{mobaxterm, putty, securecrt, tabby, termius};

/// Something found on this computer that can be imported without
/// exporting anything first.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Found {
    pub program: Program,
    pub path: PathBuf,
}

/// The programs whose data is where they keep it, most common first.
pub fn installed(home: &Path) -> Vec<Found> {
    let mut out = Vec::new();
    if let Some(dir) = termius::find(home) {
        out.push(Found {
            program: Program::Termius,
            path: dir,
        });
    }
    let tabby = tabby::config_path(home);
    if tabby.is_file() {
        out.push(Found {
            program: Program::Tabby,
            path: tabby,
        });
    }
    for dir in putty_dirs(home) {
        if has_files(&dir) {
            out.push(Found {
                program: Program::Putty,
                path: dir,
            });
            break;
        }
    }
    for dir in securecrt_dirs(home) {
        if has_files(&dir) {
            out.push(Found {
                program: Program::SecureCrt,
                path: dir,
            });
            break;
        }
    }
    for file in mobaxterm_files(home) {
        if file.is_file() {
            out.push(Found {
                program: Program::MobaXterm,
                path: file,
            });
            break;
        }
    }
    out
}

/// PuTTY for Linux and macOS: `$PUTTYDIR`, `~/.config/putty` or
/// `~/.putty`, then `sessions`.
fn putty_dirs(home: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Some(dir) = std::env::var_os("PUTTYDIR") {
        out.push(PathBuf::from(dir).join("sessions"));
    }
    out.push(home.join(".config/putty/sessions"));
    out.push(home.join(".putty/sessions"));
    out
}

fn securecrt_dirs(home: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if cfg!(target_os = "macos") {
        out.push(home.join("Library/Application Support/VanDyke/SecureCRT/Config/Sessions"));
    } else if cfg!(windows) {
        if let Some(appdata) = std::env::var_os("APPDATA") {
            out.push(PathBuf::from(appdata).join("VanDyke/Config/Sessions"));
        }
    } else {
        out.push(home.join(".vandyke/SecureCRT/Config/Sessions"));
        out.push(home.join(".vandyke/Config/Sessions"));
    }
    out
}

fn mobaxterm_files(home: &Path) -> Vec<PathBuf> {
    if !cfg!(windows) {
        return Vec::new();
    }
    let mut out = vec![home.join("Documents/MobaXterm/MobaXterm.ini")];
    if let Some(appdata) = std::env::var_os("APPDATA") {
        out.push(PathBuf::from(appdata).join("MobaXterm/MobaXterm.ini"));
    }
    out
}

fn has_files(dir: &Path) -> bool {
    fs::read_dir(dir).is_ok_and(|mut d| d.next().is_some())
}

#[derive(Debug)]
pub enum Error {
    /// Not a file or folder of any program there is an importer for.
    NotRecognized,
    Io(std::io::Error),
    /// The file is that program's, but it could not be read.
    Format {
        program: Program,
        error: String,
    },
    Termius(termius::Error),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotRecognized => f.write_str("not a file of a program OpenWard imports from"),
            Self::Io(e) => write!(f, "{e}"),
            Self::Format { program, error } => write!(f, "{program}: {error}"),
            Self::Termius(e) => write!(f, "Termius: {e}"),
        }
    }
}

impl std::error::Error for Error {}

/// Reads a file or folder, recognizing whose it is. Termius's data asks
/// the keychain for its key unless `termius_keys` gives it.
pub fn read(path: &Path, termius_keys: Option<Vec<[u8; 32]>>) -> Result<(Program, Bundle), Error> {
    if path.is_dir() {
        if termius::leveldb_dir(path).is_some() {
            return termius::read(path, termius_keys)
                .map(|b| (Program::Termius, b))
                .map_err(Error::Termius);
        }
        let sessions = if path.join("Sessions").is_dir() {
            path.join("Sessions")
        } else {
            path.to_owned()
        };
        return read_sessions_dir(&sessions);
    }
    let bytes = fs::read(path).map_err(Error::Io)?;
    let text = crate::text::decode(&bytes);
    let format = |program: Program| move |error: String| Error::Format { program, error };
    if let Some(program) = putty::sniff_reg(&text) {
        return putty::from_reg(&bytes).map_err(format(program));
    }
    if securecrt::sniff_xml(&text) {
        return securecrt::from_xml(&bytes)
            .map(|b| (Program::SecureCrt, b))
            .map_err(format(Program::SecureCrt));
    }
    if mobaxterm::sniff(&text) {
        return Ok((Program::MobaXterm, mobaxterm::parse(&bytes)));
    }
    if tabby::sniff(&text) {
        return tabby::parse(&bytes)
            .map(|b| (Program::Tabby, b))
            .map_err(format(Program::Tabby));
    }
    Err(Error::NotRecognized)
}

/// A folder of session files: SecureCRT's `.ini` files, or PuTTY's (or
/// portable KiTTY's) one file per session.
fn read_sessions_dir(dir: &Path) -> Result<(Program, Bundle), Error> {
    let mut files = Vec::new();
    collect(dir, &mut files);
    if files.is_empty() {
        return Err(Error::NotRecognized);
    }
    if files
        .iter()
        .any(|f| f.extension().is_some_and(|e| e == "ini"))
    {
        return securecrt::from_dir(dir)
            .map(|b| (Program::SecureCrt, b))
            .map_err(Error::Io);
    }
    let sample = fs::read(&files[0])
        .map(|b| crate::text::decode(&b))
        .unwrap_or_default();
    let program = if sample.lines().any(|l| l.starts_with("HostName\\")) {
        Program::Kitty
    } else if sample
        .lines()
        .any(|l| l.starts_with("HostName=") || l.starts_with("Protocol="))
    {
        Program::Putty
    } else {
        return Err(Error::NotRecognized);
    };
    putty::from_dir(dir, program)
        .map(|b| (program, b))
        .map_err(Error::Io)
}

fn collect(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for e in entries.flatten() {
        let p = e.path();
        if p.is_dir() {
            collect(&p, out);
        } else if !e.file_name().to_string_lossy().starts_with('.') {
            out.push(p);
        }
    }
    out.sort();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn files_are_recognized_by_their_contents() {
        let dir = tempfile::tempdir().unwrap();
        let write = |name: &str, text: &str| {
            let p = dir.path().join(name);
            fs::write(&p, text).unwrap();
            p
        };
        let reg = write(
            "x.reg",
            "Windows Registry Editor Version 5.00\n\n[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\a]\n\"HostName\"=\"a.example.com\"\n",
        );
        assert_eq!(read(&reg, None).unwrap().0, Program::Putty);
        let moba = write(
            "x.mxtsessions",
            "[Bookmarks]\nSubRep=\na=#109#0%a.example.com%22%u#x#0# #-1\n",
        );
        assert_eq!(read(&moba, None).unwrap().0, Program::MobaXterm);
        let yaml = write(
            "config.yaml",
            "version: 8\nprofiles:\n  - id: a\n    type: ssh\n    name: a\n    options:\n      host: a.example.com\n",
        );
        assert_eq!(read(&yaml, None).unwrap().0, Program::Tabby);
        let xml = write(
            "x.xml",
            "<?xml version=\"1.0\"?><VanDyke version=\"3.0\"><key name=\"Sessions\"></key></VanDyke>",
        );
        assert_eq!(read(&xml, None).unwrap().0, Program::SecureCrt);
        let other = write("notes.txt", "hello");
        assert!(matches!(read(&other, None), Err(Error::NotRecognized)));

        let sessions = dir.path().join("sessions");
        fs::create_dir(&sessions).unwrap();
        fs::write(sessions.join("box"), "HostName=box.example.com\n").unwrap();
        assert_eq!(read(&sessions, None).unwrap().0, Program::Putty);
    }
}
