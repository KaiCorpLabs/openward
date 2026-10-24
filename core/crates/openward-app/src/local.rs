//! The local side of a connection: who and where the user is, and the
//! OpenSSH tokens that settings may contain.

use std::path::PathBuf;

#[derive(Clone, Debug)]
pub struct Local {
    pub home: PathBuf,
    /// Local login name: `%u`, and the remote user when nothing sets one.
    pub user: String,
    pub ssh_dir: PathBuf,
    /// OpenSSH's system folder, `/etc/ssh`: its `ssh_known_hosts`.
    pub system_ssh_dir: PathBuf,
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
        let system_ssh_dir = if cfg!(windows) {
            var(&["PROGRAMDATA"]).map_or_else(
                || PathBuf::from(r"C:\ProgramData\ssh"),
                |d| PathBuf::from(d).join("ssh"),
            )
        } else {
            PathBuf::from("/etc/ssh")
        };
        Self {
            ssh_dir: home.join(".ssh"),
            system_ssh_dir,
            home,
            user,
            agent,
        }
    }

    /// OpenSSH's own `known_hosts`: read, and written only to remove a line
    /// the user asked to (with a `.old` copy first).
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

    /// A `ProxyCommand`: only the `%` tokens; the shell does the rest. The
    /// host name, the remote user and the alias go in as they are, so one
    /// that a shell would read as more than a name (`a$(…)`, `x;y`) fails
    /// with its token, as in OpenSSH 9.6: it may come from an import or a
    /// shared vault, and would run here.
    pub fn command(&self, text: &str, t: &Tokens) -> Result<String, char> {
        let mut chars = text.chars();
        while let Some(c) = chars.next() {
            if c != '%' {
                continue;
            }
            let token = chars.next();
            let value = match token {
                Some('h') => t.host,
                Some('r') => t.user,
                Some('n') => t.alias,
                _ => continue,
            };
            if !shell_safe(value) {
                return Err(token.unwrap_or('%'));
            }
        }
        Ok(self.expand(text, t, false))
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
                    // Counted in characters: a name may not be ASCII.
                    let name: String = chars.clone().skip(1).take_while(|&c| c != '}').collect();
                    let closed = chars.clone().nth(1 + name.chars().count()) == Some('}');
                    if closed {
                        out.push_str(&std::env::var(&name).unwrap_or_default());
                        for _ in 0..name.chars().count() + 2 {
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

/// Whether a shell (`sh` or `cmd`) reads `value` as one plain word: no
/// quotes, `$`, `\`, `;`, `&`, `|`, `<`, `>`, brackets, `^` or `%`, no
/// spaces or control characters, and no leading `-`.
fn shell_safe(value: &str) -> bool {
    !value.starts_with('-')
        && !value
            .chars()
            .any(|c| c.is_whitespace() || c.is_control() || "'\"`$\\;&|<>(){}^%!*?[]~#".contains(c))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn local() -> Local {
        Local {
            home: PathBuf::from("/home/ana"),
            user: "ana".into(),
            ssh_dir: PathBuf::from("/home/ana/.ssh"),
            system_ssh_dir: PathBuf::from("/etc/ssh"),
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
    fn expansion() {
        let l = local();
        let path = |text| l.expand(text, &T, true);
        // A name that is not ASCII keeps what follows it.
        assert_eq!(path("/a${OPENWARD_TEST_VÁR}/b"), "/a/b");
        assert_eq!(path("${OPENWARD_TEST_ÑÑ}x"), "x");
        // Unclosed, empty or without the brace, it stays as written.
        assert_eq!(path("/a${HOME"), "/a${HOME");
        assert_eq!(path("/a${}b"), "/ab");
        assert_eq!(path("$HOME/x"), "$HOME/x");
        assert_eq!(
            path("${HOME}/k"),
            format!("{}/k", std::env::var("HOME").unwrap_or_default())
        );
        // A `%` at the end, or before an unknown letter, stays.
        assert_eq!(path("100%"), "100%");
        assert_eq!(path("%q%h"), "%qdb.example.com");
        assert_eq!(path("%u@%h:%p"), "ana@db.example.com:2222");
        // Without `env` (a command), `${…}` is the shell's.
        assert_eq!(l.expand("${HOME}", &T, false), "${HOME}");
    }

    #[test]
    fn commands() {
        assert_eq!(
            local().command("ssh -W %h:%p -l %u ${X} ~/x", &T),
            Ok("ssh -W db.example.com:2222 -l ana ${X} ~/x".into())
        );
    }

    /// A name a shell would run part of never reaches it (CVE-2023-51385).
    #[test]
    fn names_that_a_shell_would_run_fail() {
        let l = local();
        let with = |host: &'static str, user: &'static str, alias: &'static str| Tokens {
            host,
            port: 22,
            user,
            alias,
        };
        assert_eq!(
            l.command("nc %h %p", &with("a$(touch x)", "u", "a")),
            Err('h')
        );
        assert_eq!(l.command("nc %h %p", &with("a;b", "u", "a")), Err('h'));
        assert_eq!(
            l.command("ssh -l %r -W %h:%p j", &with("a", "x`id`", "a")),
            Err('r')
        );
        assert_eq!(
            l.command("connect %n", &with("a", "u", "web prod")),
            Err('n')
        );
        assert_eq!(l.command("nc %h %p", &with("-oProxy", "u", "a")), Err('h'));
        // Only the tokens the command uses count, and IPv6 addresses pass.
        assert!(
            l.command("nc %h %p", &with("fe80::1", "u", "web prod"))
                .is_ok()
        );
        assert!(l.command("nc 100%% %p", &with("a b", "u", "a")).is_ok());
    }
}
