//! Local authority held by a transfer, including across pause/resume.
//!
//! Only acquisition uses ambient paths: the user explicitly selected this
//! file or directory. Descendant I/O always resolves through the retained
//! directory handle, never through a checked-then-reopened absolute path.

use std::io;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use cap_fs_ext::{FollowSymlinks, MetadataExt, OpenOptionsFollowExt, Reopen};
use cap_std::ambient_authority;
use cap_std::fs::{Dir, File, Metadata, OpenOptions};

use crate::{Entry, Error, Kind, Result};

#[derive(Debug)]
enum Authority {
    Directory(Dir),
    File(File),
}

#[derive(Debug)]
pub(crate) struct LocalRoot {
    display: PathBuf,
    authority: Authority,
}

impl LocalRoot {
    pub(crate) fn source(path: &Path) -> Result<Self> {
        let meta = std::fs::metadata(path).map_err(|e| Error::local(path, &e))?;
        let authority = if meta.is_dir() {
            Authority::Directory(
                Dir::open_ambient_dir(path, ambient_authority())
                    .map_err(|e| Error::local(path, &e))?,
            )
        } else if meta.is_file() {
            Authority::File(
                File::open_ambient(path, ambient_authority())
                    .map_err(|e| Error::local(path, &e))?,
            )
        } else {
            return Err(Error::Other(format!(
                "{}: not a regular file",
                path.display()
            )));
        };
        Ok(Self {
            display: path.to_owned(),
            authority,
        })
    }

    pub(crate) fn destination(path: &Path) -> Result<Self> {
        let dir =
            Dir::open_ambient_dir(path, ambient_authority()).map_err(|e| Error::local(path, &e))?;
        Ok(Self {
            display: path.to_owned(),
            authority: Authority::Directory(dir),
        })
    }

    pub(crate) fn display(&self, rel: &Path) -> PathBuf {
        if rel.as_os_str().is_empty() {
            self.display.clone()
        } else {
            self.display.join(rel)
        }
    }

    fn error(&self, rel: &Path, e: io::Error) -> Error {
        Error::local(&self.display(rel), &e)
    }

    fn directory(&self) -> Result<&Dir> {
        match &self.authority {
            Authority::Directory(dir) => Ok(dir),
            Authority::File(_) => Err(Error::Other("not a directory selection".into())),
        }
    }

    pub(crate) fn top(&self) -> Result<Entry> {
        let meta = match &self.authority {
            Authority::Directory(dir) => dir.dir_metadata(),
            Authority::File(file) => file.metadata(),
        }
        .map_err(|e| self.error(Path::new(""), e))?;
        Ok(entry(
            self.display
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned(),
            &meta,
        ))
    }

    /// A nested file link may resolve only inside the selected directory.
    /// An explicitly selected top-level link already granted its target.
    pub(crate) fn open_source(&self, rel: &Path) -> Result<(std::fs::File, Entry)> {
        let file = match &self.authority {
            Authority::Directory(dir) => dir.open(rel),
            Authority::File(file) if rel.as_os_str().is_empty() => {
                file.reopen(OpenOptions::new().read(true))
            }
            Authority::File(_) => return Err(Error::Other("not a directory selection".into())),
        }
        .map_err(|e| self.error(rel, e))?;
        let meta = file.metadata().map_err(|e| self.error(rel, e))?;
        if !meta.is_file() {
            return Err(Error::Other(format!(
                "{}: not a regular file",
                self.display(rel).display()
            )));
        }
        let e = entry(
            rel.file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned(),
            &meta,
        );
        Ok((file.into_std(), e))
    }

    pub(crate) fn walk(&self) -> Result<Vec<(PathBuf, Entry)>> {
        let dir = self.directory()?;
        let mut out = Vec::new();
        let mut stack = vec![PathBuf::new()];
        while let Some(rel) = stack.pop() {
            let path = if rel.as_os_str().is_empty() {
                Path::new(".")
            } else {
                &rel
            };
            let mut names = dir
                .read_dir(path)
                .map_err(|e| self.error(&rel, e))?
                .map(|e| e.map(|e| e.file_name()))
                .collect::<io::Result<Vec<_>>>()
                .map_err(|e| self.error(&rel, e))?;
            names.sort();
            for name in names {
                let r = rel.join(&name);
                let meta = dir.symlink_metadata(&r).map_err(|e| self.error(&r, e))?;
                if meta.is_symlink() {
                    // Resolve from the selection root, not the containing
                    // directory: ../ links within the selection remain useful.
                    let to = dir.metadata(&r).map_err(|e| self.error(&r, e))?;
                    if to.is_file() {
                        out.push((r, entry(name.to_string_lossy().into_owned(), &to)));
                    }
                } else if meta.is_dir() {
                    stack.push(r.clone());
                    out.push((r, entry(name.to_string_lossy().into_owned(), &meta)));
                } else if meta.is_file() {
                    out.push((r, entry(name.to_string_lossy().into_owned(), &meta)));
                }
            }
        }
        Ok(out)
    }

    pub(crate) fn stat(&self, rel: &Path) -> Result<Option<Entry>> {
        self.entry_at(rel, true)
    }

    pub(crate) fn lstat(&self, rel: &Path) -> Result<Option<Entry>> {
        self.entry_at(rel, false)
    }

    fn entry_at(&self, rel: &Path, follow: bool) -> Result<Option<Entry>> {
        let dir = self.directory()?;
        match if follow {
            dir.metadata(rel)
        } else {
            dir.symlink_metadata(rel)
        } {
            Ok(meta) => Ok(Some(entry(
                rel.file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .into_owned(),
                &meta,
            ))),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(self.error(rel, e)),
        }
    }

    pub(crate) fn exists(&self, rel: &Path) -> Result<bool> {
        match self.directory()?.symlink_metadata(rel) {
            Ok(_) => Ok(true),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(false),
            Err(e) => Err(self.error(rel, e)),
        }
    }

    pub(crate) fn mkdir(&self, rel: &Path) -> Result<()> {
        self.directory()?
            .create_dir(rel)
            .map_err(|e| self.error(rel, e))
    }

    /// No truncation or writes before inspecting the opened object. A
    /// hardlink is as dangerous as a symlink for a predictable part name.
    pub(crate) fn open_part(&self, rel: &Path, mode: Option<u32>) -> Result<(std::fs::File, u64)> {
        let mut options = OpenOptions::new();
        options
            .create(true)
            .write(true)
            .truncate(false)
            .follow(FollowSymlinks::No);
        #[cfg(unix)]
        {
            use cap_std::fs::OpenOptionsExt;
            options.mode(mode.map_or(0o666, |m| 0o600 | (m & 0o066)));
        }
        #[cfg(not(unix))]
        let _ = mode;
        let file = self
            .directory()?
            .open_with(rel, &options)
            .map_err(|e| self.error(rel, e))?;
        let meta = file.metadata().map_err(|e| self.error(rel, e))?;
        if !meta.is_file() || meta.nlink() != 1 {
            return Err(Error::Other(format!(
                "{}: unsafe transfer part",
                self.display(rel).display()
            )));
        }
        Ok((file.into_std(), meta.len()))
    }

    pub(crate) fn install(&self, part: &Path, dest: &Path) -> Result<()> {
        let dir = self.directory()?;
        if cfg!(windows) && self.exists(dest)? {
            dir.remove_file(dest).map_err(|e| self.error(dest, e))?;
        }
        dir.rename(part, dir, dest).map_err(|e| self.error(part, e))
    }

    pub(crate) fn remove_part(&self, rel: &Path) -> Result<()> {
        self.directory()?
            .remove_file(rel)
            .map_err(|e| self.error(rel, e))
    }
}

fn entry(name: String, meta: &Metadata) -> Entry {
    let kind = if meta.is_symlink() {
        Kind::Link
    } else if meta.is_dir() {
        Kind::Dir
    } else if meta.is_file() {
        Kind::File
    } else {
        Kind::Other
    };
    #[cfg(unix)]
    let mode = {
        use cap_std::fs::PermissionsExt;
        Some(meta.permissions().mode() & 0o7777)
    };
    #[cfg(not(unix))]
    let mode = None;
    Entry {
        name,
        kind,
        link_dir: false,
        link_target: None,
        size: if kind == Kind::File { meta.len() } else { 0 },
        modified: meta
            .modified()
            .ok()
            .and_then(|t| t.into_std().duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64),
        mode,
        owner: None,
        group: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Seek, SeekFrom, Write};

    #[test]
    fn regular_parts_resume_and_install_without_changing_their_names() {
        let dir = tempfile::tempdir().unwrap();
        let root = LocalRoot::destination(dir.path()).unwrap();
        let part = Path::new("file.ow-example.part");
        std::fs::write(dir.path().join(part), b"first").unwrap();
        let (mut file, had) = root.open_part(part, Some(0o600)).unwrap();
        assert_eq!(had, 5);
        file.seek(SeekFrom::Start(had)).unwrap();
        file.write_all(b" second").unwrap();
        drop(file);
        root.install(part, Path::new("file")).unwrap();
        assert_eq!(
            std::fs::read(dir.path().join("file")).unwrap(),
            b"first second"
        );
        assert!(!root.exists(part).unwrap());
    }

    #[test]
    fn a_part_hardlink_is_rejected_before_writing_or_truncating() {
        let dir = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        let sentinel = outside.path().join("keep");
        std::fs::write(&sentinel, b"outside sentinel").unwrap();
        let before = std::fs::metadata(&sentinel).unwrap();
        std::fs::hard_link(&sentinel, dir.path().join("file.part")).unwrap();
        let root = LocalRoot::destination(dir.path()).unwrap();
        assert!(root.open_part(Path::new("file.part"), Some(0o600)).is_err());
        let after = std::fs::metadata(&sentinel).unwrap();
        assert_eq!(std::fs::read(&sentinel).unwrap(), b"outside sentinel");
        assert_eq!(before.modified().unwrap(), after.modified().unwrap());
        assert_eq!(before.permissions(), after.permissions());
    }

    #[test]
    fn a_selected_file_retains_its_authority_and_original_part_hash_input() {
        let dir = tempfile::tempdir().unwrap();
        let selected = dir.path().join("selected");
        std::fs::write(&selected, b"selected bytes").unwrap();
        let root = LocalRoot::source(&selected).unwrap();
        assert_eq!(root.display(Path::new("")), selected);
        let (mut file, e) = root.open_source(Path::new("")).unwrap();
        assert_eq!(e.size, 14);
        let mut data = String::new();
        file.read_to_string(&mut data).unwrap();
        assert_eq!(data, "selected bytes");
        // Independent offsets are essential when a paused copy resumes.
        let (mut again, _) = root.open_source(Path::new("")).unwrap();
        let mut data = String::new();
        again.read_to_string(&mut data).unwrap();
        assert_eq!(data, "selected bytes");
    }

    #[cfg(unix)]
    #[test]
    fn uploads_reject_outside_links_at_expansion_and_again_at_the_actual_open() {
        use std::os::unix::fs::symlink;
        let selected = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        std::fs::write(outside.path().join("secret"), b"not selected").unwrap();
        std::fs::write(selected.path().join("safe"), b"selected").unwrap();
        std::fs::create_dir(selected.path().join("sub")).unwrap();
        symlink("../safe", selected.path().join("sub/internal")).unwrap();
        let root = LocalRoot::source(selected.path()).unwrap();
        let items = root.walk().unwrap();
        assert!(items.iter().any(|(p, _)| p == Path::new("sub/internal")));
        let (mut internal, _) = root.open_source(Path::new("sub/internal")).unwrap();
        let mut text = String::new();
        internal.read_to_string(&mut text).unwrap();
        assert_eq!(text, "selected");
        // A source replaced after expansion (or while paused) cannot escape.
        std::fs::remove_file(selected.path().join("safe")).unwrap();
        symlink(outside.path().join("secret"), selected.path().join("safe")).unwrap();
        assert!(root.open_source(Path::new("safe")).is_err());
        assert!(root.walk().is_err());
        // Selecting that top-level link explicitly is an authorized action.
        let explicit = LocalRoot::source(&selected.path().join("safe")).unwrap();
        let (mut file, _) = explicit.open_source(Path::new("")).unwrap();
        let mut text = String::new();
        file.read_to_string(&mut text).unwrap();
        assert_eq!(text, "not selected");
    }

    #[cfg(unix)]
    #[test]
    fn downloads_never_follow_prepared_file_or_directory_links() {
        use std::os::unix::fs::symlink;
        let selected = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        let sentinel = outside.path().join("keep");
        std::fs::write(&sentinel, b"outside sentinel").unwrap();
        let before = std::fs::metadata(&sentinel).unwrap();
        let root = LocalRoot::destination(selected.path()).unwrap();
        symlink(&sentinel, selected.path().join("file.part")).unwrap();
        symlink(outside.path(), selected.path().join("folder")).unwrap();
        assert!(root.open_part(Path::new("file.part"), Some(0o700)).is_err());
        assert!(
            root.open_part(Path::new("folder/keep"), Some(0o700))
                .is_err()
        );
        assert!(root.mkdir(Path::new("folder/new")).is_err());
        assert!(root.remove_part(Path::new("folder/keep")).is_err());
        assert!(root.stat(Path::new("folder")).is_err());
        let after = std::fs::metadata(&sentinel).unwrap();
        assert_eq!(std::fs::read(&sentinel).unwrap(), b"outside sentinel");
        assert_eq!(before.modified().unwrap(), after.modified().unwrap());
        assert_eq!(before.permissions(), after.permissions());
        assert!(!outside.path().join("new").exists());
    }

    #[cfg(unix)]
    #[test]
    fn replacing_an_ambient_parent_does_not_redirect_writes_or_cancellation() {
        use std::os::unix::fs::symlink;
        let base = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        let selected = base.path().join("selected");
        std::fs::create_dir(&selected).unwrap();
        std::fs::write(outside.path().join("file.part"), b"keep outside").unwrap();
        let root = LocalRoot::destination(&selected).unwrap();
        std::fs::rename(&selected, base.path().join("original")).unwrap();
        symlink(outside.path(), &selected).unwrap();
        let (mut file, _) = root.open_part(Path::new("file.part"), None).unwrap();
        file.write_all(b"download").unwrap();
        drop(file);
        root.remove_part(Path::new("file.part")).unwrap();
        assert!(!base.path().join("original/file.part").exists());
        assert_eq!(
            std::fs::read(outside.path().join("file.part")).unwrap(),
            b"keep outside"
        );
        // A directory selected through a top-level link remains supported.
        let explicit = LocalRoot::destination(&selected).unwrap();
        assert!(explicit.exists(Path::new("file.part")).unwrap());
    }
}
