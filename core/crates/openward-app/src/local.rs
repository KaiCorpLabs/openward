//! The local side of a connection: who and where the user is, and the
//! OpenSSH tokens that settings may contain.

use std::path::PathBuf;

#[derive(Clone, Debug)]
pub struct Local {
    pub home: PathBuf,
    /// Local login name: `%u`, and the remote user when nothing sets one.
    pub user: String,
    pub ssh_dir: PathBuf,
    /// The system agent: `SSH_AUTH_SOCK`, or OpenSSH's pipe on Windows.
    pub agent: Option<PathBuf>,
}

/// What `%h`, `%p`, `%r` and `%n` stand for in one hop.
#[derive(Clone, Copy, Debug)]
pub struct Tokens<'a> {
    pub host: &'a str,
    pub port: u16,
    pub user: &'a str,
    /// The host's label: OpenSSH's original host name.
    pub alias: &'a str,
}

impl Local {
    pub fn from_env() -> Self {
        let var = |names: &[&str]| names.iter().find_map(std::env::var_os);
        let home = var(&["HOME", "USERPROFILE"]).map_or_else(|| PathBuf::from("."), PathBuf::from);
        let user = var(&["USER", "USERNAME", "LOGNAME"])
            .and_then(|u| u.into_string().ok())
            .unwrap_or_else(|| "user".into());
        let agent = if cfg!(windows) {
            Some(PathBuf::from(r"\\.\pipe\openssh-ssh-agent"))
        } else {
            std::env::var_os("SSH_AUTH_SOCK").map(PathBuf::from)
        };
        Self {
            ssh_dir: home.join(".ssh"),
            home,
            user,
            agent,
        }
    }

    /// OpenSSH's own `known_hosts`, read but never written.
    pub fn known_hosts_file(&self) -> PathBuf {
        self.ssh_dir.join("known_hosts")
    }

    /// A path setting (`IdentityFile`, `CertificateFile`, `IdentityAgent`):
    /// `~`, `${VAR}` and the `%` tokens. Relative paths are taken from
    /// `~/.ssh`.
    pub fn path(&self, text: &str, t: &Tokens) -> PathBuf {
        let expanded = self.expand(text, t, true);
        let path = if expanded == "~" {
            self.home.clone()
        } else if let Some(rest) = expanded.strip_prefix("~/") {
            self.home.join(rest)
        } else {
            PathBuf::from(expanded)
        };
        if path.is_absolute() {
            path
        } else {
            self.ssh_dir.join(path)
        }
    }

    /// A `ProxyCommand`: only the `%` tokens; the shell does the rest.
    pub fn command(&self, text: &str, t: &Tokens) -> String {
        self.expand(text, t, false)
    }

    /// `%d %u %h %p %r %n %%`, and `${VAR}` when `env` is set. Unknown
    /// tokens are left as written.
    fn expand(&self, text: &str, t: &Tokens, env: bool) -> String {
        let mut out = String::with_capacity(text.len());
        let mut chars = text.chars().peekable();
        while let Some(c) = chars.next() {
            match c {
                '%' => match chars.peek().copied() {
                    Some('%') => out.push('%'),
                    Some('d') => out.push_str(&self.home.to_string_lossy()),
                    Some('u') => out.push_str(&self.user),
                    Some('h') => out.push_str(t.host),
                    Some('p') => out.push_str(&t.port.to_string()),
                    Some('r') => out.push_str(t.user),
                    Some('n') => out.push_str(t.alias),
                    _ => {
                        out.push('%');
                        continue;
                    }
                },
                '$' if env && chars.peek() == Some(&'{') => {
                    let rest: String = chars.clone().skip(1).collect();
                    if let Some(end) = rest.find('}') {
                        let name = &rest[..end];
                        out.push_str(&std::env::var(name).unwrap_or_default());
                        for _ in 0..end + 2 {
                            chars.next();
                        }
                    } else {
                        out.push('$');
                    }
                    continue;
                }
                c => {
                    out.push(c);
                    continue;
                }
            }
            chars.next();
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn local() -> Local {
        Local {
            home: PathBuf::from("/home/ana"),
            user: "ana".into(),
            ssh_dir: PathBuf::from("/home/ana/.ssh"),
            agent: None,
        }
    }

    const T: Tokens = Tokens {
        host: "db.example.com",
        port: 2222,
        user: "deploy",
        alias: "db",
    };

    #[test]
    fn paths() {
        let l = local();
        assert_eq!(
            l.path("~/.ssh/id_%n", &T),
            PathBuf::from("/home/ana/.ssh/id_db")
        );
        assert_eq!(
            l.path("%d/keys/%r@%h", &T),
            PathBuf::from("/home/ana/keys/deploy@db.example.com")
        );
        assert_eq!(
            l.path("id_work", &T),
            PathBuf::from("/home/ana/.ssh/id_work")
        );
        assert_eq!(l.path("/abs/100%%", &T), PathBuf::from("/abs/100%"));
        assert_eq!(l.path("/x/%Z", &T), PathBuf::from("/x/%Z"));
        assert_eq!(
            l.path("${OPENWARD_TEST_UNSET_VAR}/k", &T),
            PathBuf::from("/k")
        );
    }

    #[test]
    fn commands() {
        assert_eq!(
            local().command("ssh -W %h:%p -l %u ${X} ~/x", &T),
            "ssh -W db.example.com:2222 -l ana ${X} ~/x"
        );
    }
}
