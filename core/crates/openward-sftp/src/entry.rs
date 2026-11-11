//! What a listing shows of each file, on a server or on this machine.

use std::time::UNIX_EPOCH;

use russh_sftp::protocol::{FileAttributes, FileType};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    File,
    Dir,
    Link,
    /// Devices, sockets, pipes.
    Other,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    pub name: String,
    pub kind: Kind,
    /// A link that leads to a directory: it opens like one.
    pub link_dir: bool,
    /// Where a link points, as written.
    pub link_target: Option<String>,
    /// Bytes; for a link to a file, the file's.
    pub size: u64,
    /// Seconds since the epoch.
    pub modified: Option<i64>,
    /// Permission bits (`0o7777`), when known.
    pub mode: Option<u32>,
    pub owner: Option<String>,
    pub group: Option<String>,
}

impl Entry {
    /// Copy metadata of a link's target, preserving its link identity.
    pub(crate) fn follow_target(&mut self, attrs: Option<&FileAttributes>) {
        self.link_dir = attrs.is_some_and(|a| kind(a) == Kind::Dir);
        self.size = attrs.and_then(|a| a.size).unwrap_or(0);
        self.mode = attrs.and_then(|a| a.permissions).map(|m| m & 0o7777);
        self.modified = attrs.and_then(|a| a.mtime).map(i64::from);
    }
    /// Opens as a folder: a directory, or a link to one.
    pub fn is_dir(&self) -> bool {
        self.kind == Kind::Dir || self.link_dir
    }

    /// From an SFTP name entry; `longname` is `ls -l`'s line, where the
    /// owner's and group's names are (attributes only carry numbers).
    pub(crate) fn remote(name: String, longname: &str, attrs: &FileAttributes) -> Self {
        let (owner, group) = owners(longname);
        Self {
            name,
            kind: kind(attrs),
            link_dir: false,
            link_target: None,
            size: attrs.size.unwrap_or(0),
            modified: attrs.mtime.map(i64::from),
            mode: attrs.permissions.map(|p| p & 0o7777),
            owner,
            group,
        }
    }

    /// From this machine's metadata of the entry itself (not followed).
    pub(crate) fn local(name: String, meta: &std::fs::Metadata) -> Self {
        let ft = meta.file_type();
        let kind = if ft.is_symlink() {
            Kind::Link
        } else if ft.is_dir() {
            Kind::Dir
        } else if ft.is_file() {
            Kind::File
        } else {
            Kind::Other
        };
        Self {
            name,
            kind,
            link_dir: false,
            link_target: None,
            size: if kind == Kind::File { meta.len() } else { 0 },
            modified: meta
                .modified()
                .ok()
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map(|d| d.as_secs() as i64),
            mode: local_mode(meta),
            owner: None,
            group: None,
        }
    }
}

pub(crate) fn kind(attrs: &FileAttributes) -> Kind {
    if attrs.permissions.is_none() {
        // Without a mode there is no type: most likely a plain file.
        return Kind::File;
    }
    match attrs.file_type() {
        FileType::Dir => Kind::Dir,
        FileType::File => Kind::File,
        FileType::Symlink => Kind::Link,
        FileType::Other => Kind::Other,
    }
}

#[cfg(unix)]
pub(crate) fn local_mode(meta: &std::fs::Metadata) -> Option<u32> {
    use std::os::unix::fs::PermissionsExt;
    Some(meta.permissions().mode() & 0o7777)
}

#[cfg(not(unix))]
pub(crate) fn local_mode(_: &std::fs::Metadata) -> Option<u32> {
    None
}

/// Owner and group from an `ls -l` line, if it is one.
fn owners(longname: &str) -> (Option<String>, Option<String>) {
    let mut fields = longname.split_whitespace();
    let mode = fields.next().unwrap_or_default();
    let looks_like_ls =
        mode.len() >= 10 && mode.chars().next().is_some_and(|c| "-dlcbps".contains(c));
    if !looks_like_ls {
        return (None, None);
    }
    let _links = fields.next();
    let owner = fields.next().map(str::to_owned);
    let group = fields.next().map(str::to_owned);
    (owner, group)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn followed_links_use_the_targets_permissions_and_date() {
        let link = FileAttributes {
            permissions: Some(0o120777),
            mtime: Some(300),
            size: Some(12),
            ..FileAttributes::empty()
        };
        let target = FileAttributes {
            permissions: Some(0o100600),
            mtime: Some(100),
            size: Some(40),
            ..FileAttributes::empty()
        };
        let mut entry = Entry::remote("link".into(), "", &link);
        entry.link_target = Some("private".into());
        entry.follow_target(Some(&target));
        assert_eq!(
            (entry.mode, entry.modified, entry.size),
            (Some(0o600), Some(100), 40)
        );
        assert_eq!(entry.kind, Kind::Link);
        assert_eq!(entry.link_target.as_deref(), Some("private"));
        entry.follow_target(Some(&FileAttributes {
            permissions: Some(0o040750),
            mtime: Some(200),
            ..FileAttributes::empty()
        }));
        assert!(entry.link_dir);
        assert_eq!((entry.mode, entry.modified), (Some(0o750), Some(200)));
        entry.follow_target(None);
        assert_eq!(
            (entry.mode, entry.modified, entry.size, entry.link_dir),
            (None, None, 0, false)
        );
    }

    #[test]
    fn owners_from_ls_lines() {
        assert_eq!(
            owners("drwxr-xr-x    2 deploy   www-data     4096 Oct 14 18:40 releases"),
            (Some("deploy".into()), Some("www-data".into()))
        );
        assert_eq!(
            owners("-rw-r--r--+ 1 ana staff 5 Oct 1 2025 a.txt"),
            (Some("ana".into()), Some("staff".into()))
        );
        // Servers that leave it empty, or put something else there.
        assert_eq!(owners(""), (None, None));
        assert_eq!(owners("a.txt"), (None, None));
    }

    #[test]
    fn kinds_from_modes() {
        let attrs = |mode| FileAttributes {
            permissions: Some(mode),
            ..FileAttributes::empty()
        };
        assert_eq!(kind(&attrs(0o040755)), Kind::Dir);
        assert_eq!(kind(&attrs(0o100644)), Kind::File);
        assert_eq!(kind(&attrs(0o120777)), Kind::Link);
        assert_eq!(kind(&attrs(0o020666)), Kind::Other);
        assert_eq!(kind(&FileAttributes::empty()), Kind::File);
        let e = Entry::remote("x".into(), "", &attrs(0o100754));
        assert_eq!(e.mode, Some(0o754));
    }
}
