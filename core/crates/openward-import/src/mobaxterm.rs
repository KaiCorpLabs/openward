//! MobaXterm's sessions: a `.mxtsessions` file from "Export all sessions
//! to file", or the `[Bookmarks…]` sections of `MobaXterm.ini`.
//!
//! Each `[Bookmarks_N]` section is a folder (`SubRep=` its path, nested
//! with `\`) and holds one line per session: `name=` and `#`-separated
//! parts, the third one the connection, `%`-separated, whose first field
//! is the kind of session (0 is SSH). Text in those fields is escaped with
//! tokens such as `__PIPE__`, and paths start with `_CurrentDrive_`.
//! MobaXterm's tunnels (MobaSSHTunnel) are kept elsewhere and not read.

use std::collections::BTreeMap;

use openward_proto::{Agent, Proxy, ProxyServer, Settings};

use crate::bundle::{Bundle, Group, Host, JumpRef, KeyRef, Warning, WarningKind};
use crate::text;

/// Whether the text looks like MobaXterm's sessions.
pub fn sniff(text: &str) -> bool {
    text.lines().any(|l| {
        let l = l.trim();
        l == "[Bookmarks]" || (l.starts_with("[Bookmarks_") && l.ends_with(']'))
    }) && text.contains("=#")
}

const KINDS: [&str; 15] = [
    "ssh", "telnet", "rsh", "xdmcp", "rdp", "vnc", "ftp", "sftp", "serial", "file", "shell",
    "browser", "mosh", "aws s3", "wsl",
];

pub fn parse(bytes: &[u8]) -> Bundle {
    let text = text::decode(bytes);
    let mut out = Bundle::default();
    struct Line {
        folder: String,
        name: String,
        value: String,
    }
    let mut lines = Vec::new();
    let mut folder: Option<String> = None;
    let mut in_bookmarks = false;
    for raw in text.lines() {
        let l = raw.trim_end_matches('\r');
        if let Some(section) = l.trim().strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
            in_bookmarks = section == "Bookmarks" || section.starts_with("Bookmarks_");
            folder = Some(String::new());
            continue;
        }
        if !in_bookmarks {
            continue;
        }
        let Some((key, value)) = l.split_once('=') else {
            continue;
        };
        match key {
            "SubRep" => folder = Some(value.trim().to_owned()),
            "ImgNum" => {}
            _ if value.starts_with('#') => lines.push(Line {
                folder: folder.clone().unwrap_or_default(),
                name: key.to_owned(),
                value: value.to_owned(),
            }),
            _ => {}
        }
    }

    // Folders, and their parents even when they hold no session.
    let mut groups: BTreeMap<String, ()> = BTreeMap::new();
    for l in &lines {
        let parts: Vec<&str> = l.folder.split('\\').filter(|p| !p.is_empty()).collect();
        for depth in 1..=parts.len() {
            let path = parts[..depth].join("\\");
            if groups.insert(path.clone(), ()).is_none() {
                out.groups.push(Group {
                    id: path,
                    name: parts[depth - 1].to_owned(),
                    parent: (depth > 1).then(|| parts[..depth - 1].join("\\")),
                    ..Group::default()
                });
            }
        }
    }

    // Addresses of the SSH sessions, to point jumps at them.
    let mut by_address: BTreeMap<(String, u16, Option<String>), String> = BTreeMap::new();
    let mut parsed = Vec::new();
    for l in lines {
        let parts: Vec<String> = l.value.split('#').map(str::to_owned).collect();
        let conn: Vec<String> = parts
            .get(2)
            .map(|c| c.split('%').map(unescape).collect())
            .unwrap_or_default();
        let field = |i: usize| conn.get(i).map(String::as_str).unwrap_or("").trim();
        let id = if l.folder.is_empty() {
            l.name.clone()
        } else {
            format!("{}\\{}", l.folder, l.name)
        };
        let kind: usize = field(0).parse().unwrap_or(usize::MAX);
        let port: u16 = field(2).parse().unwrap_or(22);
        let user = user(field(3));
        if kind == 0 {
            by_address.insert((field(1).to_owned(), port, user.clone()), id.clone());
        }
        parsed.push((l, id, kind, conn.clone(), port, user, parts));
    }

    for (l, id, kind, conn, port, user, parts) in parsed {
        let field = |i: usize| conn.get(i).map(String::as_str).unwrap_or("").trim();
        let on = |i: usize| field(i) == "-1";
        let name = l.name.clone();
        let mut settings = Settings {
            user: user.clone(),
            port: (port != 22).then_some(port),
            ..Settings::default()
        };
        if field(3).starts_with('[') {
            out.warnings.push(Warning::about(
                &name,
                WarningKind::Unsupported("a stored MobaXterm credential".into()),
            ));
        }
        if on(5) {
            out.warnings.push(Warning::about(
                &name,
                WarningKind::Unsupported("X11 forwarding".into()),
            ));
        }
        if !field(7).is_empty() {
            out.warnings
                .push(Warning::about(&name, WarningKind::StartupCommand));
        }
        // Jump hosts: parallel lists of hosts, ports and users.
        let list = |i: usize| -> Vec<String> {
            field(i)
                .split("__PIPE__")
                .map(|s| s.trim().to_owned())
                .collect()
        };
        let (hosts, ports, users) = (list(8), list(9), list(10));
        let mut jumps = Vec::new();
        for (i, h) in hosts.iter().enumerate().filter(|(_, h)| !h.is_empty()) {
            let p: u16 = ports.get(i).and_then(|p| p.parse().ok()).unwrap_or(22);
            let u = users.get(i).map(String::as_str).and_then(user_of);
            jumps.push(match by_address.get(&(h.clone(), p, u.clone())) {
                Some(target) if *target != id => JumpRef::Host(target.clone()),
                _ => JumpRef::Address {
                    host: h.clone(),
                    user: u,
                    port: (p != 22).then_some(p),
                },
            });
        }
        let keys: Vec<KeyRef> = Some(field(14))
            .filter(|k| !k.is_empty())
            .map(|k| KeyRef::Path(path(k)))
            .into_iter()
            .collect();
        let proxy_port = field(21).parse().unwrap_or(1080);
        let server = || ProxyServer {
            host: field(20).to_owned(),
            port: proxy_port,
            user: user_of(field(22)),
        };
        match field(19) {
            "" | "0" => {}
            "2" if !field(20).is_empty() => settings.proxy = Some(Proxy::Socks5(server())),
            "3" if !field(20).is_empty() => settings.proxy = Some(Proxy::Http(server())),
            "5" if !field(26).is_empty() => out.warnings.push(Warning::about(
                &name,
                WarningKind::ProxyCommand(field(26).to_owned()),
            )),
            "1" => out.warnings.push(Warning::about(
                &name,
                WarningKind::Unsupported("SOCKS4 proxy".into()),
            )),
            other => out.warnings.push(Warning::about(
                &name,
                WarningKind::Unsupported(format!("proxy type {other}")),
            )),
        }
        if field(33) == "0" {
            settings.agent = Some(Agent::Off);
        }
        if on(34) {
            settings.agent_forward = Some(true);
        }
        let notes = parts
            .get(5)
            .map(|c| unescape(c).trim().to_owned())
            .filter(|c| !c.is_empty());
        out.hosts.push(Host {
            id,
            label: name,
            address: field(1).to_owned(),
            group: (!l.folder.is_empty()).then(|| {
                l.folder
                    .split('\\')
                    .filter(|p| !p.is_empty())
                    .collect::<Vec<_>>()
                    .join("\\")
            }),
            settings,
            identity: None,
            keys,
            jumps,
            tags: Vec::new(),
            notes,
            unsupported: (kind != 0).then(|| {
                KINDS
                    .get(kind)
                    .map(|k| (*k).to_owned())
                    .unwrap_or_else(|| format!("session type {}", field(0)))
            }),
        });
    }
    out
}

fn user(field: &str) -> Option<String> {
    user_of(field.trim_start_matches('[').trim_end_matches(']'))
}

/// `<default>` is MobaXterm's default login, the computer's user.
fn user_of(field: &str) -> Option<String> {
    let f = field.trim();
    (!f.is_empty() && f != "<default>").then(|| f.to_owned())
}

fn unescape(s: &str) -> String {
    s.replace("__PTVIRG__", ";")
        .replace("__DIEZE__", "#")
        .replace("__PERCENT__", "%")
        .replace("__DBLQUO__", "\"")
        .replace("__EQUAL__", "=")
        .replace("__DBLDOT__", ":")
}

/// `_CurrentDrive_:\…` is `C:\…`; `_ProfileDir_\…` the user's folder.
fn path(p: &str) -> String {
    if let Some(rest) = p.strip_prefix("_CurrentDrive_") {
        format!("C:{}", rest.strip_prefix(':').unwrap_or(rest))
    } else if let Some(rest) = p.strip_prefix("_ProfileDir_") {
        format!("~{rest}")
    } else {
        p.to_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FILE: &str = "[Bookmarks]\r\nSubRep=\r\nImgNum=42\r\n\
bastion=#109#0%bastion.example.com%22%ana%%-1%-1%%%%%0%0%0%%%-1%0%0%0%%1080%%0%0%1#MobaFont%10#0# #-1\r\n\
[Bookmarks_1]\r\nSubRep=Production\r\nImgNum=41\r\n\
web-01=#109#0%web01.example.com%22%deploy%%0%-1%%bastion.example.com%22%ana%0%0%0%_CurrentDrive_:\\Users\\ana\\.ssh\\id_ed25519%%-1%0%0%2%socks.example.com%1081%%0%0%1#MobaFont%10#0#Web tier __DIEZE__1#-1\r\n\
[Bookmarks_2]\r\nSubRep=Production\\Databases\r\nImgNum=41\r\n\
db-01=#109#0%db01.example.com%2222%<default>%%-1%-1%ls __PTVIRG__ pwd%gw1.example.com__PIPE__gw2.example.com%22__PIPE__2200%u1__PIPE__u2%0%-1%0%%%-1%0%0%0%%1080%%0%0%1#MobaFont%10#0# #-1\r\n\
desktop=#91#4%win.example.com%3389%admin%%0%0%%%%#MobaFont#0# #-1\r\n";

    #[test]
    fn folders_jumps_keys_and_a_proxy() {
        assert!(sniff(FILE));
        let b = parse(FILE.as_bytes());
        let groups: Vec<(&str, Option<&str>)> = b
            .groups
            .iter()
            .map(|g| (g.name.as_str(), g.parent.as_deref()))
            .collect();
        assert_eq!(
            groups,
            [("Production", None), ("Databases", Some("Production"))]
        );

        let web = &b.hosts[1];
        assert_eq!(web.label, "web-01");
        assert_eq!(web.group.as_deref(), Some("Production"));
        assert_eq!(web.jumps, [JumpRef::Host("bastion".into())]);
        assert_eq!(
            web.keys,
            [KeyRef::Path(r"C:\Users\ana\.ssh\id_ed25519".into())]
        );
        assert!(
            matches!(&web.settings.proxy, Some(Proxy::Socks5(p)) if p.host == "socks.example.com" && p.port == 1081)
        );
        assert_eq!(web.notes.as_deref(), Some("Web tier #1"));

        let db = &b.hosts[2];
        assert_eq!(db.group.as_deref(), Some("Production\\Databases"));
        assert_eq!(db.settings.port, Some(2222));
        assert_eq!(db.settings.user, None);
        assert_eq!(
            db.jumps,
            [
                JumpRef::Address {
                    host: "gw1.example.com".into(),
                    user: Some("u1".into()),
                    port: None
                },
                JumpRef::Address {
                    host: "gw2.example.com".into(),
                    user: Some("u2".into()),
                    port: Some(2200)
                },
            ]
        );
        assert!(
            b.warnings
                .contains(&Warning::about("db-01", WarningKind::StartupCommand))
        );
        assert_eq!(b.hosts[3].unsupported.as_deref(), Some("rdp"));
    }
}
