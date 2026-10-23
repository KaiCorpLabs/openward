//! PuTTY's and KiTTY's saved sessions.
//!
//! On Windows they live in the registry (`HKCU\Software\SimonTatham\PuTTY
//! \Sessions`, or `9bis.com\KiTTY` for KiTTY), and people bring them as a
//! `.reg` file from `reg export` or regedit: UTF-16 text, one section per
//! session. PuTTY on Linux or macOS keeps one file per session in
//! `~/.putty/sessions` (or `~/.config/putty/sessions`), `Key=Value` lines;
//! portable KiTTY keeps `Sessions/` files with `Key\value\` lines.
//!
//! Only SSH sessions come in. PuTTY has no groups; KiTTY's folders do. A
//! jump through "SSH proxy" names another saved session or an address.
//! Port forwards open whenever the session connects, as in PuTTY.

use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::io;
use std::path::Path;

use openward_proto::{Agent, ForwardKind, Proxy, ProxyServer, Settings};

use crate::bundle::{Bundle, Group, Host, JumpRef, KeyRef, Program, Tunnel, Warning, WarningKind};
use crate::text;

#[derive(Clone, Debug, PartialEq)]
enum Val {
    Text(String),
    Number(u32),
}

impl Val {
    fn text(&self) -> String {
        match self {
            Val::Text(s) => s.clone(),
            Val::Number(n) => n.to_string(),
        }
    }

    fn number(&self) -> Option<u32> {
        match self {
            Val::Number(n) => Some(*n),
            Val::Text(s) => s.trim().parse().ok(),
        }
    }
}

type Session = BTreeMap<String, Val>;

/// Whether a `.reg` file holds PuTTY's or KiTTY's sessions.
pub fn sniff_reg(text: &str) -> Option<Program> {
    let head = text.trim_start_matches('\u{feff}').trim_start();
    if !(head.starts_with("Windows Registry Editor") || head.starts_with("REGEDIT4")) {
        return None;
    }
    let lower = text.to_ascii_lowercase();
    if lower.contains("\\9bis.com\\kitty\\sessions\\") {
        Some(Program::Kitty)
    } else if lower.contains("\\simontatham\\putty\\sessions\\") {
        Some(Program::Putty)
    } else {
        None
    }
}

/// Sessions from a `.reg` export.
pub fn from_reg(bytes: &[u8]) -> Result<(Program, Bundle), String> {
    let text = text::decode(bytes);
    let program = sniff_reg(&text).ok_or("not a PuTTY or KiTTY registry export")?;
    let mut sessions: Vec<(String, Session)> = Vec::new();
    let mut current: Option<usize> = None;
    let mut lines = text.lines().peekable();
    while let Some(line) = lines.next() {
        let mut line = line.trim_end_matches('\r').to_owned();
        // A long value goes on over lines ending in `\`.
        while line.ends_with('\\') && !line.starts_with('[') {
            line.pop();
            match lines.next() {
                Some(next) => line.push_str(next.trim()),
                None => break,
            }
        }
        let line = line.trim();
        if let Some(section) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            current = None;
            if section.starts_with('-') {
                continue;
            }
            let lower = section.to_ascii_lowercase();
            if let Some(at) = lower.find("\\sessions\\") {
                let escaped = &section[at + "\\sessions\\".len()..];
                if !escaped.contains('\\') {
                    sessions.push((unescape(escaped), Session::new()));
                    current = Some(sessions.len() - 1);
                }
            }
            continue;
        }
        let (Some(i), Some(rest)) = (current, line.strip_prefix('"')) else {
            continue;
        };
        let Some((name, value)) = rest.split_once("\"=") else {
            continue;
        };
        let value = if let Some(hex) = value.strip_prefix("dword:") {
            match u32::from_str_radix(hex.trim(), 16) {
                Ok(n) => Val::Number(n),
                Err(_) => continue,
            }
        } else if let Some(s) = value.strip_prefix('"').and_then(|v| v.strip_suffix('"')) {
            Val::Text(
                s.replace("\\\\", "\u{0}")
                    .replace("\\\"", "\"")
                    .replace('\u{0}', "\\"),
            )
        } else {
            continue;
        };
        sessions[i].1.insert(name.to_owned(), value);
    }
    Ok((program, bundle(sessions, &HashMap::new())))
}

/// Sessions from a folder: PuTTY's `sessions` (Unix), or KiTTY's portable
/// `Sessions`, whose subfolders become groups.
pub fn from_dir(dir: &Path, _program: Program) -> io::Result<Bundle> {
    let mut sessions = Vec::new();
    let mut folders: HashMap<String, Vec<String>> = HashMap::new();
    walk(dir, &mut Vec::new(), &mut sessions, &mut folders)?;
    Ok(bundle(sessions, &folders))
}

fn walk(
    dir: &Path,
    path: &mut Vec<String>,
    sessions: &mut Vec<(String, Session)>,
    folders: &mut HashMap<String, Vec<String>>,
) -> io::Result<()> {
    let mut entries: Vec<_> = fs::read_dir(dir)?.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let p = entry.path();
        if p.is_dir() {
            path.push(unescape(&name));
            walk(&p, path, sessions, folders)?;
            path.pop();
            continue;
        }
        let Ok(bytes) = fs::read(&p) else { continue };
        let name = unescape(name.strip_suffix(".ktx").unwrap_or(&name));
        let mut session = Session::new();
        for line in text::decode(&bytes).lines() {
            let line = line.trim_end_matches('\r');
            // KiTTY: `Key\value\`, the value %-escaped.
            if let Some(rest) = line.strip_suffix('\\')
                && let Some((k, v)) = rest.split_once('\\')
            {
                session.insert(k.to_owned(), Val::Text(unescape(v)));
            } else if let Some((k, v)) = line.split_once('=') {
                session.insert(k.to_owned(), Val::Text(v.to_owned()));
            }
        }
        if !path.is_empty() {
            folders.insert(name.clone(), path.clone());
        }
        sessions.push((name, session));
    }
    Ok(())
}

/// `%XX` escapes, as PuTTY writes session names (and KiTTY values).
fn unescape(s: &str) -> String {
    text::percent_decode(s)
}

fn bundle(sessions: Vec<(String, Session)>, folders: &HashMap<String, Vec<String>>) -> Bundle {
    let mut out = Bundle::default();
    let names: Vec<String> = sessions.iter().map(|(n, _)| n.clone()).collect();
    // Groups from KiTTY's folders, nested by path.
    let mut group_ids: BTreeMap<Vec<String>, String> = BTreeMap::new();
    for path in folders.values() {
        for depth in 1..=path.len() {
            let p = path[..depth].to_vec();
            if group_ids.contains_key(&p) {
                continue;
            }
            let id = p.join("/");
            out.groups.push(Group {
                id: id.clone(),
                name: p[depth - 1].clone(),
                parent: (depth > 1).then(|| path[..depth - 1].join("/")),
                ..Group::default()
            });
            group_ids.insert(p, id);
        }
    }
    for (name, s) in sessions {
        if name == "Default Settings" {
            continue;
        }
        let get = |k: &str| s.get(k);
        let text = |k: &str| get(k).map(Val::text).filter(|t| !t.is_empty());
        let num = |k: &str| get(k).and_then(Val::number);
        let flag = |k: &str| num(k).map(|n| n != 0);

        let protocol = text("Protocol").unwrap_or_else(|| "ssh".into());
        let mut host = text("HostName").unwrap_or_default();
        let mut user = text("UserName");
        if let Some((u, h)) = host.rsplit_once('@')
            && user.is_none()
        {
            user = Some(u.to_owned());
            host = h.to_owned();
        }
        let mut settings = Settings {
            user: user.filter(|_| flag("UserNameFromEnvironment") != Some(true)),
            ..Settings::default()
        };
        match num("PortNumber") {
            Some(22) | None => {}
            Some(p) => match u16::try_from(p) {
                Ok(p) if p > 0 => settings.port = Some(p),
                _ => out.warnings.push(Warning::about(
                    &name,
                    WarningKind::BadValue {
                        field: "PortNumber".into(),
                        value: p.to_string(),
                    },
                )),
            },
        }
        let keys: Vec<KeyRef> = text("PublicKeyFile")
            .map(KeyRef::Path)
            .into_iter()
            .collect();
        if let Some(cert) = text("DetachedCertificate") {
            settings.certificate_files = Some(vec![cert]);
        }
        if flag("AgentFwd") == Some(true) {
            settings.agent_forward = Some(true);
        }
        if flag("TryAgent") == Some(false) {
            settings.agent = Some(Agent::Off);
        }
        if flag("X11Forward") == Some(true) {
            out.warnings.push(Warning::about(
                &name,
                WarningKind::Unsupported("X11 forwarding".into()),
            ));
        }
        if text("RemoteCommand").is_some() {
            out.warnings
                .push(Warning::about(&name, WarningKind::StartupCommand));
        }
        if text("ProxyPassword").is_some() || text("Password").is_some() {
            out.passwords += 1;
        }

        // Proxies, and jumps through "SSH proxy".
        let mut jumps = Vec::new();
        let proxy_host = text("ProxyHost");
        let proxy_port = num("ProxyPort").and_then(|p| u16::try_from(p).ok());
        let proxy_user = text("ProxyUsername");
        let server = || {
            proxy_host.clone().map(|host| ProxyServer {
                host,
                port: proxy_port.unwrap_or(1080),
                user: proxy_user.clone(),
            })
        };
        let method = match (num("ProxyMethod"), num("ProxyType")) {
            (Some(m), _) => m,
            // Before 0.77: 1 HTTP, 2 SOCKS (4 or 5), 3 telnet, 4 command.
            (None, Some(1)) => 3,
            (None, Some(2)) if num("ProxySOCKSVersion") == Some(4) => 1,
            (None, Some(2)) => 2,
            (None, Some(3)) => 4,
            (None, Some(4)) => 5,
            _ => 0,
        };
        match method {
            0 => {}
            2 => settings.proxy = server().map(Proxy::Socks5),
            3 => settings.proxy = server().map(Proxy::Http),
            5 => {
                if let Some(cmd) = text("ProxyTelnetCommand") {
                    out.warnings.push(Warning::about(
                        &name,
                        WarningKind::ProxyCommand(
                            cmd.replace("%host", "%h").replace("%port", "%p"),
                        ),
                    ));
                }
            }
            6..=8 => {
                if let Some(target) = proxy_host.clone() {
                    jumps.push(if names.contains(&target) {
                        JumpRef::Host(target)
                    } else {
                        JumpRef::Address {
                            host: target,
                            user: proxy_user.clone(),
                            port: proxy_port.filter(|p| *p != 22),
                        }
                    });
                }
            }
            1 => out.warnings.push(Warning::about(
                &name,
                WarningKind::Unsupported("SOCKS4 proxy".into()),
            )),
            _ => out.warnings.push(Warning::about(
                &name,
                WarningKind::Unsupported("telnet proxy".into()),
            )),
        }

        if let Some(spec) = text("PortForwardings") {
            let all_local = flag("LocalPortAcceptAll") == Some(true);
            let all_remote = flag("RemotePortAcceptAll") == Some(true);
            for t in port_forwardings(&spec) {
                let mut t = Tunnel {
                    host: name.clone(),
                    ..t
                };
                if t.listen_address.is_none()
                    && ((t.kind == ForwardKind::Remote && all_remote)
                        || (t.kind != ForwardKind::Remote && all_local))
                {
                    t.listen_address = Some("0.0.0.0".into());
                }
                out.tunnels.push(t);
            }
        }

        let group = folders
            .get(&name)
            .and_then(|p| group_ids.get(p))
            .cloned()
            .or_else(|| {
                // KiTTY also names a session's folder in a value.
                text("Folder").filter(|f| f != "Default").inspect(|f| {
                    if let std::collections::btree_map::Entry::Vacant(e) =
                        group_ids.entry(vec![f.clone()])
                    {
                        e.insert(f.clone());
                        out.groups.push(Group {
                            id: f.clone(),
                            name: f.clone(),
                            ..Group::default()
                        });
                    }
                })
            });
        out.hosts.push(Host {
            id: name.clone(),
            label: name,
            address: host,
            group,
            settings,
            identity: None,
            keys,
            jumps,
            tags: Vec::new(),
            notes: None,
            unsupported: (protocol != "ssh").then_some(protocol),
        });
    }
    out
}

/// `L8080=localhost:80,4L127.0.0.1:5432=db:5432,R2222=localhost:22,D1080=`:
/// an optional `4`/`6`, the kind, the listening `[address:]port`, and for
/// local and remote ones where to. `\` escapes `=`, `,` and itself.
fn port_forwardings(spec: &str) -> Vec<Tunnel> {
    let mut items = Vec::new();
    let mut current = String::new();
    let mut chars = spec.chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' => {
                if let Some(n) = chars.next() {
                    current.push(n);
                }
            }
            ',' => items.push(std::mem::take(&mut current)),
            _ => current.push(c),
        }
    }
    items.push(current);
    items
        .into_iter()
        .filter_map(|item| {
            let (key, value) = item.split_once('=').unwrap_or((&item, ""));
            let key = key.trim_start_matches(['4', '6']);
            let mut k = key.chars();
            let kind = match k.next()? {
                'L' => ForwardKind::Local,
                'R' => ForwardKind::Remote,
                'D' => ForwardKind::Dynamic,
                _ => return None,
            };
            let source = k.as_str();
            let (listen_address, port) = match source.rsplit_once(':') {
                Some((a, p)) => (Some(a.trim_matches(['[', ']']).to_owned()), p),
                None => (None, source),
            };
            let listen_port = port.parse().ok()?;
            let (dest_host, dest_port) = if kind == ForwardKind::Dynamic {
                (None, None)
            } else {
                let (h, p) = value.rsplit_once(':')?;
                (
                    Some(h.trim_matches(['[', ']']).to_owned()),
                    Some(p.parse().ok()?),
                )
            };
            Some(Tunnel {
                host: String::new(),
                label: String::new(),
                kind,
                listen_address,
                listen_port,
                dest_host,
                dest_port,
                autostart: true,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const REG: &str = r#"Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Default%20Settings]
"Present"=dword:00000001
"HostName"=""

[HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\bastion]
"Present"=dword:00000001
"HostName"="bastion.example.com"
"Protocol"="ssh"
"PortNumber"=dword:00000016
"UserName"="ana"

[HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\prod%20web]
"HostName"="web01.example.com"
"Protocol"="ssh"
"PortNumber"=dword:00000801
"UserName"="deploy"
"PublicKeyFile"="C:\\Users\\ana\\.ssh\\deploy.ppk"
"AgentFwd"=dword:00000001
"ProxyMethod"=dword:00000006
"ProxyHost"="bastion"
"ProxyPort"=dword:00000016
"ProxyPassword"="no"
"PortForwardings"="L8080=localhost:80,4L127.0.0.1:5432=db.internal.example.com:5432,R2222=localhost:22,D1080="

[HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\switch]
"HostName"="10.0.9.2"
"Protocol"="telnet"
"#;

    fn utf16(text: &str) -> Vec<u8> {
        let mut out = vec![0xff, 0xfe];
        out.extend(
            text.replace('\n', "\r\n")
                .encode_utf16()
                .flat_map(|u| u.to_le_bytes()),
        );
        out
    }

    #[test]
    fn a_utf16_registry_export() {
        let (program, b) = from_reg(&utf16(REG)).unwrap();
        assert_eq!(program, Program::Putty);
        let labels: Vec<&str> = b.hosts.iter().map(|h| h.label.as_str()).collect();
        assert_eq!(labels, ["bastion", "prod web", "switch"]);
        let web = &b.hosts[1];
        assert_eq!(web.address, "web01.example.com");
        assert_eq!(web.settings.port, Some(2049));
        assert_eq!(web.settings.user.as_deref(), Some("deploy"));
        assert_eq!(web.settings.agent_forward, Some(true));
        assert_eq!(
            web.keys,
            [KeyRef::Path(r"C:\Users\ana\.ssh\deploy.ppk".into())]
        );
        assert_eq!(web.jumps, [JumpRef::Host("bastion".into())]);
        assert_eq!(b.hosts[0].settings.port, None);
        assert_eq!(b.hosts[2].unsupported.as_deref(), Some("telnet"));
        assert_eq!(b.passwords, 1);

        type Row<'a> = (
            ForwardKind,
            Option<&'a str>,
            u16,
            Option<&'a str>,
            Option<u16>,
        );
        let t: Vec<Row> = b
            .tunnels
            .iter()
            .map(|t| {
                (
                    t.kind,
                    t.listen_address.as_deref(),
                    t.listen_port,
                    t.dest_host.as_deref(),
                    t.dest_port,
                )
            })
            .collect();
        assert_eq!(
            t,
            [
                (ForwardKind::Local, None, 8080, Some("localhost"), Some(80)),
                (
                    ForwardKind::Local,
                    Some("127.0.0.1"),
                    5432,
                    Some("db.internal.example.com"),
                    Some(5432)
                ),
                (ForwardKind::Remote, None, 2222, Some("localhost"), Some(22)),
                (ForwardKind::Dynamic, None, 1080, None, None),
            ]
        );
        assert!(
            b.tunnels
                .iter()
                .all(|t| t.host == "prod web" && t.autostart)
        );
    }

    #[test]
    fn unix_session_files_and_kitty_folders() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("my%20box"),
            "HostName=box.example.com\nPortNumber=2222\nUserName=me\nPortForwardings=D1080\n",
        )
        .unwrap();
        fs::create_dir(dir.path().join("Prod")).unwrap();
        fs::write(
            dir.path().join("Prod/web"),
            "HostName\\web.example.com\\\nUserName\\deploy\\\nProtocol\\ssh\\\n",
        )
        .unwrap();
        let b = from_dir(dir.path(), Program::Kitty).unwrap();
        assert_eq!(b.groups.len(), 1);
        assert_eq!(b.groups[0].name, "Prod");
        let web = b.hosts.iter().find(|h| h.label == "web").unwrap();
        assert_eq!(web.group.as_deref(), Some("Prod"));
        assert_eq!(web.settings.user.as_deref(), Some("deploy"));
        let mine = b.hosts.iter().find(|h| h.label == "my box").unwrap();
        assert_eq!(mine.settings.port, Some(2222));
        assert_eq!(b.tunnels[0].kind, ForwardKind::Dynamic);
    }
}
