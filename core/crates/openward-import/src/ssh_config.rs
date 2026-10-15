//! OpenSSH's `~/.ssh/config`, read the way `ssh` reads it.
//!
//! Every concrete alias of a `Host` line (no `*`, `?` or `!`) becomes a
//! host. Its settings are what `ssh <alias>` would use: the lines of every
//! block that matches the alias, wildcard blocks included, with the first
//! value obtained winning. So each host carries its full configuration and
//! nothing depends on how the file was laid out.
//!
//! What is read: `Host`, `Match all`, `Include` (with globs, relative to
//! `~/.ssh`, scoped to the block it appears in), `HostName`, `User`, `Port`,
//! `IdentityFile`, `CertificateFile`, `IdentitiesOnly`, `IdentityAgent`,
//! `ProxyJump`, `ProxyCommand`, `ServerAliveInterval`, `ForwardAgent`,
//! `SetEnv`, `StrictHostKeyChecking` and the TCP forwards (`LocalForward`,
//! `RemoteForward`, `DynamicForward`), which become saved tunnels that open
//! on connect, as `ssh` opens them. Anything else is reported once as
//! a [`Warning`], as are the other `Match` blocks, whose lines are skipped.

use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

use openward_proto::{
    Agent, Extra, ForwardKind, Host, HostKeyPolicy, ItemId, Jump, PortForward, Route, Settings,
    Source,
};

/// OpenSSH's limit on nested `Include`s.
const MAX_DEPTH: usize = 16;

/// Where `~` and relative `Include` paths point.
#[derive(Clone, Debug)]
pub struct Paths {
    pub home: PathBuf,
    pub ssh_dir: PathBuf,
}

impl Paths {
    pub fn new(home: impl Into<PathBuf>) -> Self {
        let home = home.into();
        Self {
            ssh_dir: home.join(".ssh"),
            home,
        }
    }

    /// The current user's: `HOME`, or `USERPROFILE` on Windows.
    pub fn from_env() -> Option<Self> {
        std::env::var_os("HOME")
            .or_else(|| std::env::var_os("USERPROFILE"))
            .map(Self::new)
    }

    /// `~/.ssh/config`.
    pub fn user_config(&self) -> PathBuf {
        self.ssh_dir.join("config")
    }

    fn expand(&self, path: &str) -> PathBuf {
        let path = if path == "~" {
            self.home.clone()
        } else if let Some(rest) = path.strip_prefix("~/") {
            self.home.join(rest)
        } else {
            PathBuf::from(path)
        };
        if path.is_absolute() {
            path
        } else {
            self.ssh_dir.join(path)
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Location {
    pub file: PathBuf,
    pub line: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Warning {
    /// A keyword that is not imported; reported where it first appears.
    Unsupported {
        keyword: String,
        at: Location,
    },
    /// A `Match` other than `Match all`: its lines were skipped.
    Match {
        at: Location,
    },
    BadValue {
        keyword: String,
        value: String,
        at: Location,
    },
    /// `StrictHostKeyChecking no`: imported as `accept-new`, because a
    /// changed key is never accepted.
    Stricter {
        at: Location,
    },
    IncludeTooDeep {
        at: Location,
    },
    Unreadable {
        file: PathBuf,
        error: String,
    },
    /// A jump through a name that is not an imported host, or that
    /// overrides its user or port: it is kept as a bare address, and the
    /// identity files or route that name has in the file are not used.
    JumpLossy {
        alias: String,
        jump: String,
    },
}

#[derive(Clone, Debug)]
enum Cond {
    /// Lowercased patterns of a `Host` line.
    Host(Vec<String>),
    Always,
    Never,
}

#[derive(Clone, Debug)]
enum Value {
    HostName(String),
    User(String),
    Port(u16),
    IdentityFile(String),
    CertificateFile(String),
    IdentitiesOnly(bool),
    IdentityAgent(Agent),
    Route(RouteSpec),
    KeepAlive(u32),
    ForwardAgent(bool),
    SetEnv(BTreeMap<String, String>),
    Strict(HostKeyPolicy),
    Forward(ForwardSpec),
}

/// A `LocalForward`, `RemoteForward` or `DynamicForward` line.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ForwardSpec {
    pub kind: ForwardKind,
    /// The listen address, when the line gives one (`*`, an IP, a name).
    pub bind: Option<String>,
    pub port: u16,
    /// Where it leads; none for a dynamic forward.
    pub dest: Option<(String, u16)>,
}

/// A route as written, before jump names are matched to hosts.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RouteSpec {
    Direct,
    Jump(Vec<JumpSpec>),
    Command(String),
}

/// One `[user@]host[:port]` of a `ProxyJump`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct JumpSpec {
    pub user: Option<String>,
    pub host: String,
    pub port: Option<u16>,
}

#[derive(Clone, Debug)]
struct Line {
    /// Every condition must hold: the blocks of the `Include`s that led
    /// here, then the block the line is in.
    conds: Vec<usize>,
    value: Value,
}

/// What `ssh <alias>` would use, for the settings OpenWard imports.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Resolved {
    pub hostname: Option<String>,
    pub user: Option<String>,
    pub port: Option<u16>,
    pub identity_files: Vec<String>,
    pub certificate_files: Vec<String>,
    pub identities_only: Option<bool>,
    pub agent: Option<Agent>,
    pub route: Option<RouteSpec>,
    pub keepalive_secs: Option<u32>,
    pub agent_forward: Option<bool>,
    pub env: Option<BTreeMap<String, String>>,
    pub host_key_policy: Option<HostKeyPolicy>,
    /// Every forward of every matching block: they add up, as in `ssh`.
    pub forwards: Vec<ForwardSpec>,
}

#[derive(Debug, Default)]
pub struct SshConfig {
    conds: Vec<Cond>,
    lines: Vec<Line>,
    aliases: Vec<String>,
    pub warnings: Vec<Warning>,
    unsupported: HashSet<String>,
}

impl SshConfig {
    /// Reads `path` and what it includes. A missing file reads as empty.
    pub fn load(path: &Path, paths: &Paths) -> Self {
        let mut config = Self::default();
        config.read_file(path, &[], 0, paths);
        config
    }

    /// Parses `text` as if it were `file`; `Include`s are read from disk.
    pub fn parse(text: &str, file: &Path, paths: &Paths) -> Self {
        let mut config = Self::default();
        config.parse_text(text, file, &[], 0, paths);
        config
    }

    /// The concrete `Host` aliases, in file order.
    pub fn aliases(&self) -> &[String] {
        &self.aliases
    }

    pub fn resolve(&self, alias: &str) -> Resolved {
        let name = alias.to_lowercase();
        let mut r = Resolved::default();
        for line in &self.lines {
            if !line.conds.iter().all(|&c| self.matches(c, &name)) {
                continue;
            }
            match &line.value {
                Value::HostName(h) => {
                    r.hostname.get_or_insert_with(|| expand_hostname(h, alias));
                }
                Value::User(u) => {
                    r.user.get_or_insert_with(|| u.clone());
                }
                Value::Port(p) => {
                    r.port.get_or_insert(*p);
                }
                Value::IdentityFile(f) => r.identity_files.push(f.clone()),
                Value::CertificateFile(f) => r.certificate_files.push(f.clone()),
                Value::IdentitiesOnly(b) => {
                    r.identities_only.get_or_insert(*b);
                }
                Value::IdentityAgent(a) => {
                    r.agent.get_or_insert_with(|| a.clone());
                }
                Value::Route(route) => {
                    r.route.get_or_insert_with(|| route.clone());
                }
                Value::KeepAlive(s) => {
                    r.keepalive_secs.get_or_insert(*s);
                }
                Value::ForwardAgent(b) => {
                    r.agent_forward.get_or_insert(*b);
                }
                Value::SetEnv(env) => {
                    r.env.get_or_insert_with(|| env.clone());
                }
                Value::Strict(p) => {
                    r.host_key_policy.get_or_insert(*p);
                }
                Value::Forward(f) => {
                    if !r.forwards.contains(f) {
                        r.forwards.push(f.clone());
                    }
                }
            }
        }
        r
    }

    fn matches(&self, cond: usize, name: &str) -> bool {
        match &self.conds[cond] {
            Cond::Always => true,
            Cond::Never => false,
            Cond::Host(patterns) => {
                let mut hit = false;
                for p in patterns {
                    if let Some(negated) = p.strip_prefix('!') {
                        if glob(negated, name) {
                            return false;
                        }
                    } else if glob(p, name) {
                        hit = true;
                    }
                }
                hit
            }
        }
    }

    fn read_file(&mut self, path: &Path, prefix: &[usize], depth: usize, paths: &Paths) {
        match std::fs::read_to_string(path) {
            Ok(text) => self.parse_text(&text, path, prefix, depth, paths),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => self.warnings.push(Warning::Unreadable {
                file: path.to_owned(),
                error: e.to_string(),
            }),
        }
    }

    fn parse_text(
        &mut self,
        text: &str,
        file: &Path,
        prefix: &[usize],
        depth: usize,
        paths: &Paths,
    ) {
        let mut block: Option<usize> = None;
        for (n, line) in text.lines().enumerate() {
            let Some((keyword, raw)) = split_keyword(line) else {
                continue;
            };
            let at = Location {
                file: file.to_owned(),
                line: n + 1,
            };
            let args = split_args(raw);
            let mut conds = prefix.to_vec();
            conds.extend(block);
            match keyword.to_ascii_lowercase().as_str() {
                "host" => {
                    let patterns: Vec<String> = args.iter().map(|a| a.to_lowercase()).collect();
                    for alias in &args {
                        let concrete = !alias.contains(['*', '?', '!']);
                        let lower = alias.to_lowercase();
                        if concrete
                            && prefix.iter().all(|&c| self.matches(c, &lower))
                            && !self.aliases.iter().any(|a| a.to_lowercase() == lower)
                        {
                            self.aliases.push(alias.clone());
                        }
                    }
                    self.conds.push(Cond::Host(patterns));
                    block = Some(self.conds.len() - 1);
                }
                "match" => {
                    let cond = if args.len() == 1 && args[0].eq_ignore_ascii_case("all") {
                        Cond::Always
                    } else {
                        self.warnings.push(Warning::Match { at });
                        Cond::Never
                    };
                    self.conds.push(cond);
                    block = Some(self.conds.len() - 1);
                }
                "include" => {
                    if depth >= MAX_DEPTH {
                        self.warnings.push(Warning::IncludeTooDeep { at });
                        continue;
                    }
                    for arg in &args {
                        for path in expand_glob(&paths.expand(arg)) {
                            self.read_file(&path, &conds, depth + 1, paths);
                        }
                    }
                }
                lower => match parse_value(lower, raw, &args) {
                    Ok(Some(value)) => {
                        if let Value::Strict(HostKeyPolicy::AcceptNew) = value
                            && matches!(args[0].to_ascii_lowercase().as_str(), "no" | "off")
                        {
                            self.warnings.push(Warning::Stricter { at });
                        }
                        self.lines.push(Line { conds, value });
                    }
                    Ok(None) => {
                        if self.unsupported.insert(lower.to_owned()) {
                            self.warnings.push(Warning::Unsupported {
                                keyword: keyword.to_owned(),
                                at,
                            });
                        }
                    }
                    Err(()) => self.warnings.push(Warning::BadValue {
                        keyword: keyword.to_owned(),
                        value: raw.to_owned(),
                        at,
                    }),
                },
            }
        }
    }
}

/// The value of a supported keyword; `Ok(None)` for one not imported.
fn parse_value(keyword: &str, raw: &str, args: &[String]) -> Result<Option<Value>, ()> {
    let first = args.first().ok_or(())?;
    let yes_no = || match first.to_ascii_lowercase().as_str() {
        "yes" | "true" => Ok(true),
        "no" | "false" => Ok(false),
        _ => Err(()),
    };
    Ok(Some(match keyword {
        "hostname" => Value::HostName(first.clone()),
        "user" => Value::User(first.clone()),
        "port" => Value::Port(first.parse().map_err(|_| ())?),
        "identityfile" => Value::IdentityFile(first.clone()),
        "certificatefile" => Value::CertificateFile(first.clone()),
        "identitiesonly" => Value::IdentitiesOnly(yes_no()?),
        "identityagent" => Value::IdentityAgent(match first.as_str() {
            "none" => Agent::Off,
            "SSH_AUTH_SOCK" => Agent::System,
            path => Agent::Socket(path.to_owned()),
        }),
        "proxyjump" if first.eq_ignore_ascii_case("none") => Value::Route(RouteSpec::Direct),
        "proxyjump" => Value::Route(RouteSpec::Jump(
            first
                .split(',')
                .map(parse_jump)
                .collect::<Option<Vec<_>>>()
                .ok_or(())?,
        )),
        // The rest of the line, verbatim, as OpenSSH takes it.
        "proxycommand" if raw.eq_ignore_ascii_case("none") => Value::Route(RouteSpec::Direct),
        "proxycommand" => Value::Route(RouteSpec::Command(raw.to_owned())),
        "serveraliveinterval" => Value::KeepAlive(first.parse().map_err(|_| ())?),
        "forwardagent" => Value::ForwardAgent(yes_no()?),
        "setenv" => Value::SetEnv(
            args.iter()
                .map(|a| a.split_once('=').map(|(k, v)| (k.to_owned(), v.to_owned())))
                .collect::<Option<_>>()
                .ok_or(())?,
        ),
        "localforward" | "remoteforward" | "dynamicforward" => {
            let kind = match keyword {
                "localforward" => ForwardKind::Local,
                "remoteforward" => ForwardKind::Remote,
                _ => ForwardKind::Dynamic,
            };
            Value::Forward(parse_forward(kind, args).ok_or(())?)
        }
        "stricthostkeychecking" => Value::Strict(match first.to_ascii_lowercase().as_str() {
            "yes" | "true" => HostKeyPolicy::Strict,
            "ask" => HostKeyPolicy::Ask,
            "accept-new" | "no" | "off" | "false" => HostKeyPolicy::AcceptNew,
            _ => return Err(()),
        }),
        _ => return Ok(None),
    }))
}

/// `[bind:]port`, with `[…]` around an IPv6 bind address.
fn parse_listen(spec: &str) -> Option<(Option<String>, u16)> {
    if spec.contains('/') {
        // A Unix socket: not a TCP forward.
        return None;
    }
    if let Some(bracketed) = spec.strip_prefix('[') {
        let (bind, port) = bracketed.split_once("]:")?;
        return Some((Some(bind.to_owned()), port.parse().ok()?));
    }
    match spec.rsplit_once(':') {
        Some((bind, port)) => Some((Some(bind.to_owned()), port.parse().ok()?)),
        None => Some((None, spec.parse().ok()?)),
    }
}

/// `host:port`, with `[…]` around IPv6 addresses.
fn parse_dest(spec: &str) -> Option<(String, u16)> {
    if spec.contains('/') {
        return None;
    }
    if let Some(bracketed) = spec.strip_prefix('[') {
        let (host, port) = bracketed.split_once("]:")?;
        return Some((host.to_owned(), port.parse().ok()?));
    }
    let (host, port) = spec.rsplit_once(':')?;
    Some((host.to_owned(), port.parse().ok()?))
}

/// The arguments of a forward line. A remote dynamic forward (a
/// `RemoteForward` without a destination) is not supported.
fn parse_forward(kind: ForwardKind, args: &[String]) -> Option<ForwardSpec> {
    // OpenSSH also takes `port:host:hostport` as one argument.
    let parts: Vec<String> = match args {
        [one]
            if kind != ForwardKind::Dynamic
                && one.matches(':').count() >= 2
                && !one.contains('[') =>
        {
            let (listen, dest) = one
                .split_once(':')
                .map(|(l, d)| (l.to_owned(), d.to_owned()))?;
            vec![listen, dest]
        }
        _ => args.to_vec(),
    };
    let (bind, port) = parse_listen(parts.first()?)?;
    if port == 0 {
        return None;
    }
    let dest = match kind {
        ForwardKind::Dynamic => None,
        _ => Some(parse_dest(parts.get(1)?)?),
    };
    Some(ForwardSpec {
        kind,
        bind,
        port,
        dest,
    })
}

/// `[ssh://][user@]host[:port]`, with `[…]` around IPv6 addresses.
fn parse_jump(spec: &str) -> Option<JumpSpec> {
    let spec = spec.strip_prefix("ssh://").unwrap_or(spec);
    let (user, rest) = match spec.rsplit_once('@') {
        Some((user, rest)) => (Some(user.to_owned()), rest),
        None => (None, spec),
    };
    let (host, port) = if let Some(bracketed) = rest.strip_prefix('[') {
        let (host, after) = bracketed.split_once(']')?;
        let port = match after {
            "" => None,
            p => Some(p.strip_prefix(':')?.parse().ok()?),
        };
        (host, port)
    } else {
        match rest.split_once(':') {
            Some((host, port)) => (host, Some(port.parse().ok()?)),
            None => (rest, None),
        }
    };
    (!host.is_empty()).then(|| JumpSpec {
        user: user.filter(|u| !u.is_empty()),
        host: host.to_owned(),
        port,
    })
}

/// `HostName` accepts `%h` (the alias) and `%%`.
fn expand_hostname(value: &str, alias: &str) -> String {
    let mut out = String::new();
    let mut chars = value.chars();
    while let Some(c) = chars.next() {
        match (c, chars.clone().next()) {
            ('%', Some('h')) => {
                out.push_str(alias);
                chars.next();
            }
            ('%', Some('%')) => {
                out.push('%');
                chars.next();
            }
            _ => out.push(c),
        }
    }
    out
}

/// Splits a line into its keyword and the rest (`Keyword value`,
/// `Keyword=value`); `None` for blank lines and comments.
fn split_keyword(line: &str) -> Option<(&str, &str)> {
    let line = line.trim();
    if line.is_empty() || line.starts_with('#') {
        return None;
    }
    let end = line
        .find(|c: char| c.is_whitespace() || c == '=')
        .unwrap_or(line.len());
    let (keyword, rest) = line.split_at(end);
    let rest = rest.trim_start();
    let rest = rest.strip_prefix('=').unwrap_or(rest).trim_start();
    Some((keyword, rest))
}

/// Whitespace-separated arguments with `"…"` or `'…'` quoting; an unquoted
/// `#` starting an argument ends the line.
fn split_args(raw: &str) -> Vec<String> {
    let mut args = Vec::new();
    let mut chars = raw.chars().peekable();
    loop {
        while chars.next_if(|c| c.is_whitespace()).is_some() {}
        match chars.peek() {
            None | Some('#') => break,
            Some(_) => {}
        }
        let mut arg = String::new();
        let mut quote = None;
        while let Some(c) = chars.next() {
            match (quote, c) {
                (None, c) if c.is_whitespace() => break,
                (None, '"' | '\'') => quote = Some(c),
                (Some(q), c) if c == q => quote = None,
                (Some('"'), '\\') if matches!(chars.peek(), Some('"' | '\\')) => {
                    arg.extend(chars.next());
                }
                _ => arg.push(c),
            }
        }
        args.push(arg);
    }
    args
}

/// The files a pattern names, sorted, as `glob(3)` returns them; a plain
/// path that does not exist yields nothing.
fn expand_glob(pattern: &Path) -> Vec<PathBuf> {
    let Some(text) = pattern.to_str() else {
        return Vec::new();
    };
    let options = glob::MatchOptions {
        require_literal_leading_dot: true,
        ..glob::MatchOptions::new()
    };
    let mut files: Vec<PathBuf> = match glob::glob_with(text, options) {
        Ok(paths) => paths.flatten().filter(|p| p.is_file()).collect(),
        Err(_) => Vec::new(),
    };
    files.sort();
    files
}

/// `*` and `?`, over the whole text.
fn glob(pattern: &str, text: &str) -> bool {
    let (p, t): (Vec<char>, Vec<char>) = (pattern.chars().collect(), text.chars().collect());
    let (mut pi, mut ti, mut star, mut mark) = (0, 0, None, 0);
    while ti < t.len() {
        if pi < p.len() && (p[pi] == '?' || p[pi] == t[ti]) {
            pi += 1;
            ti += 1;
        } else if pi < p.len() && p[pi] == '*' {
            star = Some(pi);
            mark = ti;
            pi += 1;
        } else if let Some(s) = star {
            pi = s + 1;
            mark += 1;
            ti = mark;
        } else {
            return false;
        }
    }
    p[pi..].iter().all(|&c| c == '*')
}

/// The import: hosts with fresh ids, to create in one batch, and what did
/// not carry over.
#[derive(Debug)]
pub struct Import {
    pub hosts: Vec<(ItemId, Host)>,
    /// The hosts' forwards as tunnels that open on connect, pointing at the
    /// ids in `hosts`.
    pub forwards: Vec<PortForward>,
    pub warnings: Vec<Warning>,
}

/// Turns every alias into a host. A `ProxyJump` through another imported
/// alias becomes a jump through that host, so it keeps its own settings.
pub fn import(config: &SshConfig) -> Import {
    let aliases: Vec<(String, ItemId, Resolved)> = config
        .aliases()
        .iter()
        .map(|a| (a.clone(), ItemId::new(), config.resolve(a)))
        .collect();
    let mut warnings = config.warnings.clone();
    let mut hosts = Vec::new();
    let mut forwards = Vec::new();
    for (alias, id, r) in &aliases {
        for f in &r.forwards {
            forwards.push(tunnel(alias, *id, f));
        }
        let route = r.route.as_ref().map(|route| match route {
            RouteSpec::Direct => Route::Direct,
            RouteSpec::Command(c) => Route::Command(c.clone()),
            RouteSpec::Jump(specs) => Route::Jump(
                specs
                    .iter()
                    .map(|spec| {
                        let target = aliases
                            .iter()
                            .find(|(a, ..)| a.eq_ignore_ascii_case(&spec.host));
                        if let Some((_, target, tr)) = target
                            && (spec.user.is_none() || spec.user == tr.user)
                            && (spec.port.is_none() || spec.port == Some(tr.port.unwrap_or(22)))
                        {
                            return Jump::Host(*target);
                        }
                        let jr = config.resolve(&spec.host);
                        let lossy = !jr.identity_files.is_empty()
                            || !jr.certificate_files.is_empty()
                            || matches!(jr.route, Some(RouteSpec::Jump(_) | RouteSpec::Command(_)));
                        if lossy {
                            warnings.push(Warning::JumpLossy {
                                alias: alias.clone(),
                                jump: spec.host.clone(),
                            });
                        }
                        Jump::Address {
                            host: jr.hostname.unwrap_or_else(|| spec.host.clone()),
                            user: spec.user.clone().or(jr.user),
                            port: spec.port.or(jr.port),
                        }
                    })
                    .collect(),
            ),
        });
        let settings = Settings {
            user: r.user.clone(),
            port: r.port,
            identity_files: (!r.identity_files.is_empty()).then(|| r.identity_files.clone()),
            certificate_files: (!r.certificate_files.is_empty())
                .then(|| r.certificate_files.clone()),
            identities_only: r.identities_only,
            agent: r.agent.clone(),
            route,
            keepalive_secs: r.keepalive_secs,
            agent_forward: r.agent_forward,
            env: r.env.clone(),
            host_key_policy: r.host_key_policy,
            ..Settings::default()
        };
        hosts.push((
            *id,
            Host {
                label: alias.clone(),
                address: r.hostname.clone().unwrap_or_else(|| alias.clone()),
                settings,
                source: Some(Source::SshConfig {
                    alias: alias.clone(),
                }),
                ..Host::default()
            },
        ));
    }
    Import {
        hosts,
        forwards,
        warnings,
    }
}

/// A forward line as a tunnel: `5433 → db:5432`, `SOCKS 1080`.
fn tunnel(alias: &str, host: ItemId, f: &ForwardSpec) -> PortForward {
    let label = match (&f.kind, &f.dest) {
        (ForwardKind::Dynamic, _) => format!("SOCKS {}", f.port),
        (ForwardKind::Remote, Some((h, p))) => format!("{alias}:{} → {h}:{p}", f.port),
        (_, Some((h, p))) => format!("{} → {h}:{p}", f.port),
        (_, None) => f.port.to_string(),
    };
    PortForward {
        label,
        host,
        kind: f.kind,
        listen_port: f.port,
        listen_address: f.bind.clone(),
        dest_host: f.dest.as_ref().map(|(h, _)| h.clone()),
        dest_port: f.dest.as_ref().map(|(_, p)| *p),
        autostart: true,
        source: Some(Source::SshConfig {
            alias: alias.to_owned(),
        }),
        extra: Extra::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keywords_and_arguments() {
        assert_eq!(
            split_keyword("  HostName=example.com "),
            Some(("HostName", "example.com"))
        );
        assert_eq!(split_keyword("Port = 22"), Some(("Port", "22")));
        assert_eq!(split_keyword("# comment"), None);
        assert_eq!(
            split_args(r#""~/My Keys/id" 'two words' plain # trailing"#),
            ["~/My Keys/id", "two words", "plain"]
        );
        assert_eq!(split_args(r#""a \"quoted\" word""#), [r#"a "quoted" word"#]);
    }

    #[test]
    fn jump_specs() {
        let spec = |user: Option<&str>, host: &str, port| JumpSpec {
            user: user.map(String::from),
            host: host.into(),
            port,
        };
        assert_eq!(parse_jump("bastion"), Some(spec(None, "bastion", None)));
        assert_eq!(
            parse_jump("ops@b:2222"),
            Some(spec(Some("ops"), "b", Some(2222)))
        );
        assert_eq!(
            parse_jump("ssh://ops@[::1]:22"),
            Some(spec(Some("ops"), "::1", Some(22)))
        );
        assert_eq!(parse_jump("b:port"), None);
    }

    #[test]
    fn host_name_tokens() {
        assert_eq!(expand_hostname("%h.internal", "web"), "web.internal");
        assert_eq!(expand_hostname("100%%", "web"), "100%");
    }

    #[test]
    fn patterns() {
        assert!(glob("*.example.com", "web.example.com"));
        assert!(glob("web-?", "web-1"));
        assert!(!glob("web-?", "web-10"));
        assert!(glob("*", ""));
    }
}
