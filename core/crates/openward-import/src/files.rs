//! Reading what an import points at, within bounds. A configuration is
//! small: a file or a folder that is something else (`/dev/zero`, a
//! symlink back to its parent, a disk image) fails instead of taking the
//! app's memory or time.

use std::fs;
use std::io::{self, Read};
use std::path::{Path, PathBuf};

/// The largest file read, far above any configuration or Termius table.
pub const MAX_FILE: u64 = 64 << 20;
/// How deep a folder of sessions is walked.
pub const MAX_DEPTH: usize = 16;
/// How many entries a folder of sessions may have, all levels counted.
pub const MAX_ENTRIES: usize = 20_000;

/// A regular file (or a symlink to one), up to [`MAX_FILE`].
pub fn read(path: &Path) -> io::Result<Vec<u8>> {
    if !fs::metadata(path)?.is_file() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "not a file"));
    }
    let mut out = Vec::new();
    fs::File::open(path)?
        .take(MAX_FILE + 1)
        .read_to_end(&mut out)?;
    if out.len() as u64 > MAX_FILE {
        return Err(io::Error::new(
            io::ErrorKind::FileTooLarge,
            format!("larger than {} MB", MAX_FILE >> 20),
        ));
    }
    Ok(out)
}

/// [`read`], as UTF-8.
pub fn read_to_string(path: &Path) -> io::Result<String> {
    String::from_utf8(read(path)?).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

/// One entry of a folder.
pub struct Entry {
    pub path: PathBuf,
    pub name: String,
    pub dir: bool,
}

/// A folder's entries, sorted by name. A symlink counts as what it points
/// to when that is a file; one to a folder is left out, so a walk never
/// loops. `seen` counts entries across a walk: past [`MAX_ENTRIES`] the
/// rest are left out.
pub fn entries(dir: &Path, seen: &mut usize) -> io::Result<Vec<Entry>> {
    let mut out = Vec::new();
    for e in fs::read_dir(dir)?.flatten() {
        if *seen >= MAX_ENTRIES {
            break;
        }
        let Ok(kind) = e.file_type() else { continue };
        let path = e.path();
        let dir = if kind.is_symlink() {
            if !fs::metadata(&path).is_ok_and(|m| m.is_file()) {
                continue;
            }
            false
        } else {
            kind.is_dir()
        };
        *seen += 1;
        out.push(Entry {
            name: e.file_name().to_string_lossy().into_owned(),
            path,
            dir,
        });
    }
    out.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_files_of_a_sensible_size() {
        let dir = tempfile::tempdir().unwrap();
        let small = dir.path().join("small");
        fs::write(&small, "Host a\n").unwrap();
        assert_eq!(read(&small).unwrap(), b"Host a\n");
        assert!(read(dir.path()).is_err());
        #[cfg(unix)]
        assert!(read(Path::new("/dev/zero")).is_err());

        let big = dir.path().join("big");
        fs::File::create(&big)
            .unwrap()
            .set_len(MAX_FILE + 1)
            .unwrap();
        assert_eq!(read(&big).unwrap_err().kind(), io::ErrorKind::FileTooLarge);
    }

    #[cfg(unix)]
    #[test]
    fn symlinks_to_folders_are_left_out() {
        let dir = tempfile::tempdir().unwrap();
        let sub = dir.path().join("sub");
        fs::create_dir(&sub).unwrap();
        fs::write(sub.join("s"), "x").unwrap();
        std::os::unix::fs::symlink(dir.path(), sub.join("loop")).unwrap();
        std::os::unix::fs::symlink(sub.join("s"), sub.join("link")).unwrap();
        let mut seen = 0;
        let names: Vec<_> = entries(&sub, &mut seen)
            .unwrap()
            .into_iter()
            .map(|e| (e.name, e.dir))
            .collect();
        assert_eq!(names, [("link".into(), false), ("s".into(), false)]);
        assert_eq!(seen, 2);

        let mut full = MAX_ENTRIES;
        assert!(entries(&sub, &mut full).unwrap().is_empty());
    }
}
