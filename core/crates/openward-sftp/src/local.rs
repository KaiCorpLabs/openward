//! This machine's files, with the same [`Entry`] as the server's, so both
//! sides of the browser read alike.

use std::path::{Path, PathBuf};

use crate::entry::{Entry, Kind, local_mode};
use crate::{Error, Result};

fn err(path: &Path) -> impl Fn(std::io::Error) -> Error + '_ {
    move |e| Error::local(path, &e)
}

/// What is in a directory, in no order. Links say where they point and
/// whether that is a directory.
pub fn list(dir: &Path) -> Result<Vec<Entry>> {
    let mut out = Vec::new();
    for item in std::fs::read_dir(dir).map_err(err(dir))? {
        let Ok(item) = item else { continue };
        let Ok(meta) = item.metadata() else { continue };
        let mut e = Entry::local(item.file_name().to_string_lossy().into_owned(), &meta);
        if e.kind == Kind::Link {
            let path = item.path();
            e.link_target = std::fs::read_link(&path)
                .ok()
                .map(|t| t.display().to_string());
            if let Ok(to) = std::fs::metadata(&path) {
                e.link_dir = to.is_dir();
                e.size = if to.is_file() { to.len() } else { 0 };
            }
        }
        out.push(e);
    }
    Ok(out)
}

/// The entry at `path`, links followed; `None` if there is nothing.
pub fn stat(path: &Path) -> Result<Option<Entry>> {
    match std::fs::metadata(path) {
        Ok(meta) => Ok(Some(Entry::local(name_of(path), &meta))),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(Error::local(path, &e)),
    }
}

fn name_of(path: &Path) -> String {
    path.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.display().to_string())
}

pub fn mkdir(path: &Path) -> Result<()> {
    std::fs::create_dir(path).map_err(err(path))
}

/// Renames `from` to `to`, never over something that exists.
pub fn rename(from: &Path, to: &Path) -> Result<()> {
    if to.symlink_metadata().is_ok() {
        return Err(Error::Exists(to.display().to_string()));
    }
    std::fs::rename(from, to).map_err(err(from))
}

/// Removes a file, a link (not what it points to) or a directory with
/// everything in it.
pub fn remove(path: &Path) -> Result<()> {
    let meta = match path.symlink_metadata() {
        Ok(m) => m,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(Error::local(path, &e)),
    };
    if meta.is_dir() {
        std::fs::remove_dir_all(path).map_err(err(path))
    } else {
        std::fs::remove_file(path).map_err(err(path))
    }
}

/// As `Remote::chmod`: files keep execute only if they had it.
#[cfg(unix)]
pub fn chmod(path: &Path, mode: u32, recursive: bool) -> Result<u64> {
    chmod_with_options(path, mode, recursive, false)
}

/// A checkbox/rwx edit keeps each object's own special bits. An explicit
/// four-digit mode can change the selected root's bits; never inherit
/// that root's setuid/setgid/sticky bits into its descendants.
#[cfg(unix)]
pub fn chmod_with_options(
    path: &Path,
    mode: u32,
    recursive: bool,
    preserve_special: bool,
) -> Result<u64> {
    use cap_std::{ambient_authority, fs::Dir};
    // Following the explicitly selected root link is intentional. Descendants
    // stay confined to held directories; observed links are skipped.
    let root = std::fs::canonicalize(path).map_err(err(path))?;
    let parent = root.parent().unwrap_or(&root);
    let name = Path::new(root.file_name().unwrap_or(std::ffi::OsStr::new(".")));
    let parent = Dir::open_ambient_dir(parent, ambient_authority()).map_err(err(path))?;
    chmod_entry(
        &parent,
        name,
        path,
        mode,
        recursive,
        preserve_special,
        false,
    )
}

#[cfg(unix)]
fn chmod_entry(
    parent: &cap_std::fs::Dir,
    name: &Path,
    display: &Path,
    requested: u32,
    recursive: bool,
    preserve_special: bool,
    child: bool,
) -> Result<u64> {
    use cap_fs_ext::{DirExt, MetadataExt};
    use cap_std::fs::{Permissions, PermissionsExt};
    let meta = parent.symlink_metadata(name).map_err(err(display))?;
    if meta.is_symlink() {
        return if child {
            Ok(0)
        } else {
            Err(Error::Changed(display.display().to_string()))
        };
    }
    if child && !meta.is_dir() && !meta.is_file() {
        return Ok(0);
    }
    let had = meta.permissions().mode() & 0o7777;
    let mut mode = (requested & 0o777)
        | if child || preserve_special {
            had & 0o7000
        } else {
            requested & 0o7000
        };
    if child && meta.is_file() && had & 0o111 == 0 {
        mode &= !0o111;
    }
    if recursive && meta.is_dir() {
        // Make only owner access explicitly requested by this operation
        // available for traversal. Restrictive final modes apply bottom up.
        let temporary = had | (mode & 0o700);
        if temporary != had {
            set_named_mode(parent, name, temporary).map_err(err(display))?;
        }
        let dir = parent.open_dir_nofollow(name).map_err(err(display))?;
        let opened = dir.dir_metadata().map_err(err(display))?;
        if (opened.dev(), opened.ino()) != (meta.dev(), meta.ino()) {
            return Err(Error::Changed(display.display().to_string()));
        }
        let mut names = dir
            .entries()
            .map_err(err(display))?
            .map(|e| e.map(|e| e.file_name()))
            .collect::<std::io::Result<Vec<_>>>()
            .map_err(err(display))?;
        names.sort();
        let mut changed = 1;
        for name in names {
            changed += chmod_entry(
                &dir,
                Path::new(&name),
                &display.join(&name),
                requested,
                true,
                true,
                true,
            )?;
        }
        dir.set_permissions(".", Permissions::from_mode(mode))
            .map_err(err(display))?;
        if dir
            .dir_metadata()
            .map_err(err(display))?
            .permissions()
            .mode()
            & 0o7777
            != mode
        {
            return Err(Error::Other(format!(
                "{}: permissions could not be applied",
                display.display()
            )));
        }
        Ok(changed)
    } else {
        set_named_mode(parent, name, mode).map_err(err(display))?;
        let after = parent.symlink_metadata(name).map_err(err(display))?;
        if (after.dev(), after.ino()) != (meta.dev(), meta.ino()) || after.is_symlink() {
            return Err(Error::Changed(display.display().to_string()));
        }
        if after.permissions().mode() & 0o7777 != mode {
            return Err(Error::Other(format!(
                "{}: permissions could not be applied",
                display.display()
            )));
        }
        Ok(1)
    }
}

#[cfg(unix)]
fn set_named_mode(parent: &cap_std::fs::Dir, name: &Path, mode: u32) -> std::io::Result<()> {
    use cap_std::fs::{Permissions, PermissionsExt};
    // rustix's Linux chmodat rejects SYMLINK_NOFOLLOW. Its confined
    // setter uses an O_PATH descriptor instead. On macOS the no-follow
    // setter also permits chmod of owned objects with no read/write access.
    #[cfg(target_os = "linux")]
    return parent.set_permissions(name, Permissions::from_mode(mode));
    #[cfg(not(target_os = "linux"))]
    {
        use cap_fs_ext::DirExt;
        parent.set_symlink_permissions(name, Permissions::from_mode(mode))
    }
}

#[cfg(not(unix))]
pub fn chmod(path: &Path, _mode: u32, _recursive: bool) -> Result<u64> {
    Err(Error::Other(format!(
        "{}: permissions are Unix only",
        path.display()
    )))
}

#[cfg(not(unix))]
pub fn chmod_with_options(
    path: &Path,
    mode: u32,
    recursive: bool,
    _preserve_special: bool,
) -> Result<u64> {
    chmod(path, mode, recursive)
}

/// Everything under `dir`, directories before what they hold, as paths
/// relative to it. Links to directories are not followed; links to files
/// count as the file.
pub fn walk(dir: &Path) -> Result<Vec<(PathBuf, Entry)>> {
    let mut out = Vec::new();
    let mut stack = vec![PathBuf::new()];
    while let Some(rel) = stack.pop() {
        let mut entries = list(&dir.join(&rel))?;
        entries.sort_by(|a, b| a.name.cmp(&b.name));
        for mut e in entries {
            let r = rel.join(&e.name);
            match e.kind {
                Kind::Dir => {
                    stack.push(r.clone());
                    out.push((r, e));
                }
                Kind::File => out.push((r, e)),
                Kind::Link if !e.link_dir => {
                    // What is copied is the file it points to.
                    if let Ok(meta) = std::fs::metadata(dir.join(&r)) {
                        e.mode = local_mode(&meta);
                    }
                    out.push((r, e));
                }
                _ => {}
            }
        }
    }
    Ok(out)
}

/// The user's home folder.
pub fn home() -> Option<PathBuf> {
    std::env::var_os(if cfg!(windows) { "USERPROFILE" } else { "HOME" }).map(PathBuf::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn explicitly_selected_directory_links_recurse_without_propagating_special_bits() {
        use std::os::unix::fs::{PermissionsExt, symlink};
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path().join("root");
        std::fs::create_dir_all(root.join("child")).unwrap();
        std::fs::write(root.join("child/file"), b"").unwrap();
        // Some macOS temp roots inherit wheel rather than the test user's
        // primary group; that would make the kernel silently strip setgid.
        for path in [root.join("child"), root.join("child/file")] {
            rustix::fs::chown(path, None, Some(rustix::process::getegid())).unwrap();
        }
        std::fs::set_permissions(root.join("child"), std::fs::Permissions::from_mode(0o2775))
            .unwrap();
        std::fs::set_permissions(
            root.join("child/file"),
            std::fs::Permissions::from_mode(0o4755),
        )
        .unwrap();
        let outside = tmp.path().join("outside");
        std::fs::write(&outside, b"untouched").unwrap();
        std::fs::set_permissions(&outside, std::fs::Permissions::from_mode(0o640)).unwrap();
        symlink(&outside, root.join("skip-link")).unwrap();
        let selected = tmp.path().join("selected");
        symlink(&root, &selected).unwrap();
        let mode = |path: &Path| std::fs::metadata(path).unwrap().permissions().mode() & 0o7777;
        assert_eq!(mode(&root.join("child")), 0o2775);
        assert_eq!(mode(&root.join("child/file")), 0o4755);
        assert_eq!(chmod(&selected, 0o750, true).unwrap(), 3);
        assert_eq!(mode(&root), 0o750);
        assert_eq!(mode(&root.join("child")), 0o2750);
        assert_eq!(mode(&root.join("child/file")), 0o4750);
        assert_eq!(mode(&outside), 0o640);
    }

    #[cfg(unix)]
    #[test]
    fn rwx_edits_keep_current_special_bits_and_explicit_modes_only_change_the_root() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path().join("root");
        std::fs::create_dir(&root).unwrap();
        let plain = root.join("plain");
        std::fs::write(&plain, b"private").unwrap();
        std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o1777)).unwrap();
        std::fs::set_permissions(&plain, std::fs::Permissions::from_mode(0o4640)).unwrap();
        let mode = |path: &Path| std::fs::metadata(path).unwrap().permissions().mode() & 0o7777;
        assert_eq!(chmod_with_options(&root, 0o750, true, true).unwrap(), 2);
        assert_eq!(mode(&root), 0o1750);
        assert_eq!(mode(&plain), 0o4640); // No execute added to a non-executable child.
        assert_eq!(chmod(&root, 0o700, true).unwrap(), 2);
        assert_eq!(mode(&root), 0o700);
        assert_eq!(mode(&plain), 0o4600); // The root's explicit clearing is not inherited.
        assert_eq!(chmod(&root, 0o000, true).unwrap(), 2);
        assert_eq!(mode(&root), 0o000);
        // Owner access requested by the operation permits traversal again.
        assert_eq!(chmod(&root, 0o700, true).unwrap(), 2);
        assert_eq!(mode(&plain), 0o4600);
    }

    #[test]
    fn lists_walks_renames_and_removes() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir_all(root.join("a/b")).unwrap();
        std::fs::write(root.join("a/b/f.txt"), b"hola").unwrap();
        std::fs::write(root.join("top.txt"), b"x").unwrap();

        let mut names: Vec<_> = list(root).unwrap().into_iter().map(|e| e.name).collect();
        names.sort();
        assert_eq!(names, ["a", "top.txt"]);

        let walked: Vec<_> = walk(root)
            .unwrap()
            .into_iter()
            .map(|(p, e)| (p.display().to_string().replace('\\', "/"), e.kind))
            .collect();
        assert_eq!(
            walked,
            [
                ("a".to_owned(), Kind::Dir),
                ("top.txt".to_owned(), Kind::File),
                ("a/b".to_owned(), Kind::Dir),
                ("a/b/f.txt".to_owned(), Kind::File),
            ]
        );

        assert_eq!(
            rename(&root.join("top.txt"), &root.join("a")),
            Err(Error::Exists(root.join("a").display().to_string()))
        );
        rename(&root.join("top.txt"), &root.join("moved.txt")).unwrap();
        assert!(stat(&root.join("moved.txt")).unwrap().is_some());
        assert_eq!(
            mkdir(&root.join("a")),
            Err(Error::Exists(root.join("a").display().to_string()))
        );
        remove(&root.join("a")).unwrap();
        assert!(stat(&root.join("a")).unwrap().is_none());
    }

    #[cfg(unix)]
    #[test]
    fn chmod_recursive_keeps_execute_only_where_it_was() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("r");
        std::fs::create_dir_all(root.join("d")).unwrap();
        let mode = |p: &Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o777;
        for (name, m) in [("d/run.sh", 0o755), ("d/data.txt", 0o644)] {
            std::fs::write(root.join(name), b"").unwrap();
            std::fs::set_permissions(root.join(name), std::fs::Permissions::from_mode(m)).unwrap();
        }
        assert_eq!(chmod(&root, 0o750, true).unwrap(), 4);
        assert_eq!(mode(&root), 0o750);
        assert_eq!(mode(&root.join("d")), 0o750);
        assert_eq!(mode(&root.join("d/run.sh")), 0o750);
        assert_eq!(mode(&root.join("d/data.txt")), 0o640);
    }
}
