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
    use std::os::unix::fs::PermissionsExt;
    let set = |p: &Path, m: u32| {
        std::fs::set_permissions(p, std::fs::Permissions::from_mode(m & 0o7777)).map_err(err(p))
    };
    let meta = path.symlink_metadata().map_err(err(path))?;
    set(path, mode)?;
    let mut changed = 1;
    if recursive && meta.is_dir() {
        for (rel, e) in walk(path)? {
            let p = path.join(&rel);
            match e.kind {
                Kind::Dir => set(&p, mode)?,
                Kind::File => {
                    let had_x = e.mode.unwrap_or(0) & 0o111 != 0;
                    set(&p, if had_x { mode } else { mode & !0o111 })?;
                }
                _ => continue,
            }
            changed += 1;
        }
    }
    Ok(changed)
}

#[cfg(not(unix))]
pub fn chmod(path: &Path, _mode: u32, _recursive: bool) -> Result<u64> {
    Err(Error::Other(format!(
        "{}: permissions are Unix only",
        path.display()
    )))
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
