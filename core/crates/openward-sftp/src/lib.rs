//! SFTP for OpenWard (plan v0.2, B4): browsing and changing files on a
//! server ([`Remote`]) and on this machine ([`local`]) with one model of a
//! listing ([`Entry`]), and a transfer queue ([`Transfers`]) that writes to
//! a `.part` name first, resumes from the offset it reached and checks the
//! size at the end.
//!
//! It drives `russh-sftp`'s raw session itself rather than its file API: it
//! decides how much is in flight from the speed it measures (a fixed number
//! of requests is too little far away and times out on servers with a small
//! window, like Dropbear), and it keeps what listings say of owners. The
//! channel comes from `openward-ssh` (`Session::sftp`).

pub mod entry;
pub mod local;
pub mod remote;
pub mod transfer;

mod flight;
mod pipe;

pub use entry::{Entry, Kind};
pub use remote::Remote;
pub use transfer::{
    Conflict, Direction, JobState, JobView, Link, OnConflict, Request, Transfers, conflicts,
};

/// What went wrong, as the UI words it.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum Error {
    #[error("{0}: not found")]
    NotFound(String),
    #[error("{0}: permission denied")]
    Denied(String),
    #[error("{0}: already exists")]
    Exists(String),
    /// The connection is gone (or never answered): try again once it is back.
    #[error("the connection was lost")]
    Lost,
    /// The file changed while it was being copied.
    #[error("{0}: changed while being copied")]
    Changed(String),
    #[error("{0}")]
    Other(String),
}

pub type Result<T> = std::result::Result<T, Error>;

impl Error {
    /// From an SFTP error about `path`.
    pub(crate) fn sftp(path: &str, e: russh_sftp::client::error::Error) -> Self {
        use russh_sftp::client::error::Error as E;
        use russh_sftp::protocol::StatusCode as C;
        match e {
            E::Status(s) => match s.status_code {
                C::NoSuchFile => Self::NotFound(path.to_owned()),
                C::PermissionDenied => Self::Denied(path.to_owned()),
                C::NoConnection | C::ConnectionLost => Self::Lost,
                _ if s.error_message.is_empty() => {
                    Self::Other(format!("{path}: {}", s.status_code))
                }
                _ => Self::Other(format!("{path}: {}", s.error_message)),
            },
            // The request never got an answer: the channel or the
            // connection under it is gone.
            E::Timeout | E::IO(_) | E::UnexpectedBehavior(_) => Self::Lost,
            other => Self::Other(format!("{path}: {other}")),
        }
    }

    /// From a local file system error about `path`.
    pub(crate) fn local(path: &std::path::Path, e: &std::io::Error) -> Self {
        use std::io::ErrorKind as K;
        let path = path.display().to_string();
        match e.kind() {
            K::NotFound => Self::NotFound(path),
            K::PermissionDenied => Self::Denied(path),
            K::AlreadyExists => Self::Exists(path),
            _ => Self::Other(format!("{path}: {e}")),
        }
    }
}

/// `dir/name` for SFTP paths, which are always `/`-separated.
pub fn join(dir: &str, name: &str) -> String {
    if dir.is_empty() {
        name.to_owned()
    } else if dir.ends_with('/') {
        format!("{dir}{name}")
    } else {
        format!("{dir}/{name}")
    }
}

/// Whether a server's `name` is one name and not a path. A hostile server
/// could list `../../.zshrc` to have a download write outside its folder.
pub(crate) fn is_name(name: &str) -> bool {
    !name.is_empty() && name != "." && name != ".." && !name.contains(['/', '\0'])
}

/// The directory a remote path is in (`/` for `/x`).
pub fn parent(path: &str) -> String {
    let trimmed = path.trim_end_matches('/');
    match trimmed.rfind('/') {
        Some(0) => "/".to_owned(),
        Some(i) => trimmed[..i].to_owned(),
        None => ".".to_owned(),
    }
}

/// The last part of a remote path.
pub fn file_name(path: &str) -> &str {
    let trimmed = path.trim_end_matches('/');
    trimmed.rsplit('/').next().unwrap_or(trimmed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remote_paths() {
        assert_eq!(join("/var/www", "app"), "/var/www/app");
        assert_eq!(join("/", "etc"), "/etc");
        assert_eq!(join("", "a"), "a");
        assert_eq!(parent("/var/www/app"), "/var/www");
        assert_eq!(parent("/var/"), "/");
        assert_eq!(parent("/etc"), "/");
        assert_eq!(parent("rel"), ".");
        assert_eq!(file_name("/var/www/app/"), "app");
        assert_eq!(file_name("deploy.sh"), "deploy.sh");
    }

    #[test]
    fn names_from_a_server() {
        assert!(is_name("deploy.sh"));
        assert!(is_name(".zshrc"));
        assert!(is_name("a\\b:c"));
        for bad in ["", ".", "..", "../../.zshrc", "a/b", "/etc", "a\0b"] {
            assert!(!is_name(bad), "{bad:?}");
        }
    }
}
