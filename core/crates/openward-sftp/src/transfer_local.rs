//! Local authority held by a transfer, including across pause/resume.
//!
//! Only acquisition uses ambient paths: the user explicitly selected this
//! file or directory. Descendant I/O always resolves through the retained
//! directory handle, never through a checked-then-reopened absolute path.

use std::io;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use cap_fs_ext::{
    DirExt, FollowSymlinks, MetadataExt, OpenOptionsFollowExt, Reopen, SystemTimeSpec,
};
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

/// Only a directory this job created. Hold its identity through restrictive
/// final permissions, pauses and ancestor renames.
#[derive(Debug)]
pub(crate) struct LocalDirectory {
    dir: Dir,
    display: PathBuf,
    #[cfg(unix)]
    allowed: u32,
}

impl LocalDirectory {
    pub(crate) fn finish(&self, mode: Option<u32>, modified: Option<i64>) -> Result<()> {
        let err = |e| Error::local(&self.display, &e);
        if let Some(t) = modified.and_then(|t| u64::try_from(t).ok()) {
            let time = UNIX_EPOCH + std::time::Duration::from_secs(t);
            self.dir
                .set_mtime(
                    ".",
                    SystemTimeSpec::Absolute(cap_std::time::SystemTime::from_std(time)),
                )
                .map_err(err)?;
        }
        #[cfg(unix)]
        {
            use cap_std::fs::{Permissions, PermissionsExt};
            let mode = mode.unwrap_or(0o700) & self.allowed & 0o777;
            self.dir
                .set_permissions(".", Permissions::from_mode(mode))
                .map_err(err)?;
            if self.dir.dir_metadata().map_err(err)?.permissions().mode() & 0o7777 != mode {
                return Err(Error::Other(format!(
                    "{}: permissions could not be applied",
                    self.display.display()
                )));
            }
        }
        #[cfg(not(unix))]
        let _ = mode;
        Ok(())
    }
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

    pub(crate) fn mkdir(&self, rel: &Path) -> Result<LocalDirectory> {
        let parent = self.directory()?;
        let mut builder = cap_std::fs::DirBuilder::new();
        builder.recursive(false);
        #[cfg(unix)]
        {
            use cap_std::fs::DirBuilderExt;
            builder.mode(0o700);
        }
        parent
            .create_dir_with(rel, &builder)
            .map_err(|e| self.error(rel, e))?;
        let prepared = (|| {
            #[cfg(unix)]
            crate::local::set_named_mode(parent, rel, 0o700).map_err(|e| self.error(rel, e))?;
            let dir = parent
                .open_dir_nofollow(rel)
                .map_err(|e| self.error(rel, e))?;
            #[cfg(unix)]
            let allowed = {
                use cap_std::fs::{OpenOptionsExt, PermissionsExt};
                // Measure the actual creation mask inside the private, empty
                // directory. Never change the process-wide umask.
                let probe = ".openward-directory-mode";
                let mut options = OpenOptions::new();
                options.write(true).create_new(true).mode(0o777);
                let file = dir
                    .open_with(probe, &options)
                    .map_err(|e| self.error(rel, e))?;
                let meta = file.metadata().map_err(|e| self.error(rel, e));
                drop(file);
                dir.remove_file(probe).map_err(|e| self.error(rel, e))?;
                meta?.permissions().mode() & 0o777
            };
            Ok(LocalDirectory {
                dir,
                display: self.display(rel),
                #[cfg(unix)]
                allowed,
            })
        })();
        if prepared.is_err() {
            // No content has been copied. Do not adopt a pre-existing folder
            // as ours on a later attempt.
            let _ = parent.remove_dir(rel);
        }
        prepared
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
        #[cfg(unix)]
        {
            use cap_std::fs::PermissionsExt as _;
            use std::os::unix::fs::PermissionsExt as _;
            let mut file = file;
            if let Some(mode) = mode {
                let allowed = 0o600 | (mode & 0o066);
                if meta.permissions().mode() & !allowed & 0o077 != 0 {
                    // chmod cannot revoke an old reader's open descriptor.
                    // Restart in a private inode before adding any new bytes.
                    let dir = self.directory()?;
                    dir.remove_file(rel).map_err(|e| self.error(rel, e))?;
                    options.create_new(true);
                    file = dir
                        .open_with(rel, &options)
                        .map_err(|e| self.error(rel, e))?;
                    let fresh = file.metadata().map_err(|e| self.error(rel, e))?;
                    if !fresh.is_file() || fresh.nlink() != 1 {
                        return Err(Error::Other(format!(
                            "{}: unsafe transfer part",
                            self.display(rel).display()
                        )));
                    }
                }
            }
            let file = file.into_std();
            let meta = file.metadata().map_err(|e| self.error(rel, e))?;
            if let Some(mode) = mode {
                // Retain the effective creation mask; parts are not executable.
                let limited = meta.permissions().mode() & (0o600 | (mode & 0o066));
                if meta.permissions().mode() & 0o7777 != limited {
                    file.set_permissions(std::fs::Permissions::from_mode(limited))
                        .map_err(|e| self.error(rel, e))?;
                }
            }
            Ok((file, meta.len()))
        }
        #[cfg(not(unix))]
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

    #[cfg(unix)]
    #[test]
    fn a_public_part_is_replaced_before_any_private_bytes_are_written() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("private.part");
        std::fs::write(&path, b"old public bytes").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        let mut old_reader = std::fs::File::open(&path).unwrap();
        let old_inode = old_reader.metadata().unwrap().ino();
        let root = LocalRoot::destination(dir.path()).unwrap();
        let (mut file, had) = root
            .open_part(Path::new("private.part"), Some(0o600))
            .unwrap();
        assert_eq!(file.metadata().unwrap().permissions().mode() & 0o777, 0o600);
        assert_eq!(had, 0, "unsafe historical parts must restart");
        assert_ne!(file.metadata().unwrap().ino(), old_inode);
        file.write_all(b"new private bytes").unwrap();
        file.flush().unwrap();
        let mut exposed = Vec::new();
        old_reader.read_to_end(&mut exposed).unwrap();
        assert_eq!(exposed, b"old public bytes");
        assert_eq!(std::fs::read(&path).unwrap(), b"new private bytes");
    }

    #[test]
    fn regular_parts_resume_and_install_without_changing_their_names() {
        let dir = tempfile::tempdir().unwrap();
        let root = LocalRoot::destination(dir.path()).unwrap();
        let part = Path::new("file.ow-example.part");
        std::fs::write(dir.path().join(part), b"first").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(
                dir.path().join(part),
                std::fs::Permissions::from_mode(0o600),
            )
            .unwrap();
        }
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
    #[cfg(unix)]
    #[test]
    fn new_transfer_directories_are_private_before_contents_are_copied() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = tempfile::tempdir().unwrap();
        let root = LocalRoot::destination(tmp.path()).unwrap();
        root.mkdir(Path::new("copy")).unwrap();
        assert_eq!(
            std::fs::metadata(tmp.path().join("copy"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o700
        );
    }

    #[cfg(unix)]
    #[test]
    fn directory_finalization_respects_each_process_umask() {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(mask) = std::env::var("OPENWARD_TEST_DIRECTORY_UMASK") {
            let tmp = tempfile::tempdir().unwrap();
            let root = LocalRoot::destination(tmp.path()).unwrap();
            let mask = u32::from_str_radix(&mask, 8).unwrap();
            rustix::process::umask(rustix::fs::Mode::from_bits_truncate(
                mask.try_into().unwrap(),
            ));
            let created = root.mkdir(Path::new("copy")).unwrap();
            let path = tmp.path().join("copy");
            let mode = || std::fs::metadata(&path).unwrap().permissions().mode() & 0o7777;
            assert_eq!(mode(), 0o700);
            assert!(std::fs::read_dir(&path).unwrap().next().is_none());
            created.finish(Some(0o4755), Some(1_577_836_800)).unwrap();
            assert_eq!(mode(), 0o755 & !mask);
            assert_eq!(
                std::fs::metadata(&path)
                    .unwrap()
                    .modified()
                    .unwrap()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs(),
                1_577_836_800
            );
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o700)).unwrap();
            return;
        }
        for mask in ["000", "027", "077", "777"] {
            let output = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "transfer_local::tests::directory_finalization_respects_each_process_umask",
                    "--test-threads=1",
                    "--nocapture",
                ])
                .env("OPENWARD_TEST_DIRECTORY_UMASK", mask)
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "umask {mask}: {}{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
        }
    }

    #[cfg(unix)]
    #[test]
    fn final_directory_metadata_uses_the_held_identity() {
        use std::os::unix::fs::{PermissionsExt, symlink};
        let tmp = tempfile::tempdir().unwrap();
        let root = LocalRoot::destination(tmp.path()).unwrap();
        let created = root.mkdir(Path::new("copy")).unwrap();
        std::fs::rename(tmp.path().join("copy"), tmp.path().join("original")).unwrap();
        let outside = tempfile::tempdir().unwrap();
        std::fs::set_permissions(outside.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        symlink(outside.path(), tmp.path().join("copy")).unwrap();
        created.finish(Some(0o500), None).unwrap();
        assert_eq!(
            std::fs::metadata(tmp.path().join("original"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o500
        );
        assert_eq!(
            std::fs::metadata(outside.path())
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o700
        );
    }
}
