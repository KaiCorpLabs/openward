//! SecureCRT's sessions: the XML of Tools › Export Settings, or the
//! `Config/Sessions` folder, one `.ini` file per session.
//!
//! Both hold the same values: `Hostname`, `Username`, `[SSH2] Port`,
//! `Identity Filename V2`, the port forward tables and so on; in the XML
//! as `<string>`, `<dword>` (decimal) and `<array>`, in the `.ini` files as
//! `S:"…"=`, `D:"…"=` (eight hex digits) and `Z:"…"=` (a count, then one
//! indented line each). Folders become groups. A firewall `Session:…`
//! names another session to jump through; a global firewall is SecureCRT's
//! own and not read. Forwards open on connect, as in SecureCRT.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::Path;

use openward_proto::{ForwardKind, Settings};
use quick_xml::events::Event;
use quick_xml::{Reader, XmlVersion};

use crate::bundle::{Bundle, Group, Host, JumpRef, KeyRef, Tunnel, Warning, WarningKind};
use crate::text;

#[derive(Clone, Debug, PartialEq)]
enum Val {
    Text(String),
    Number(u64),
    List(Vec<String>),
}

type Session = BTreeMap<String, Val>;

/// Whether the text is SecureCRT's XML export.
pub fn sniff_xml(text: &str) -> bool {
    text.contains("<VanDyke")
}

/// Sessions from the XML export.
pub fn from_xml(bytes: &[u8]) -> Result<Bundle, String> {
    let xml = text::decode(bytes);
    let mut reader = Reader::from_str(&xml);
    reader.config_mut().trim_text(true);
    // The path of `<key>` names, and the sessions found.
    let mut path: Vec<String> = Vec::new();
    let mut values: Vec<Session> = Vec::new();
    let mut sessions: Vec<(Vec<String>, Session)> = Vec::new();
    // The value being read: its element, name and text (or list items).
    let mut value: Option<(String, String, String)> = None;
    let mut list: Option<(String, Vec<String>)> = None;
    let mut in_sessions = false;
    loop {
        match reader.read_event().map_err(|e| e.to_string())? {
            Event::Start(e) | Event::Empty(e) if e.name().as_ref() == "key" => {
                path.push(attr(&e, "name"));
                values.push(Session::new());
                in_sessions = path.first().is_some_and(|p| p == "Sessions")
                    || path.get(1).is_some_and(|p| p == "Sessions");
            }
            Event::End(e) if e.name().as_ref() == "key" => {
                let s = values.pop().unwrap_or_default();
                let p = path.clone();
                path.pop();
                let is_session = matches!(s.get("Is Session"), Some(Val::Number(1)))
                    || s.contains_key("Hostname");
                if in_sessions && is_session {
                    // The path inside `Sessions`.
                    let start = p.iter().position(|x| x == "Sessions").map_or(0, |i| i + 1);
                    sessions.push((p[start..].to_vec(), s));
                }
            }
            Event::Start(e) if matches!(e.name().as_ref(), "string" | "dword") => {
                let tag = e.name().as_ref().to_owned();
                let name = attr(&e, "name");
                if list.is_some() {
                    value = Some((tag, String::new(), String::new()));
                } else {
                    value = Some((tag, name, String::new()));
                }
            }
            Event::Empty(e) if matches!(e.name().as_ref(), "string" | "dword") => {
                if let Some(s) = values.last_mut()
                    && list.is_none()
                {
                    s.insert(attr(&e, "name"), Val::Text(String::new()));
                }
            }
            Event::Start(e) if e.name().as_ref() == "array" => {
                list = Some((attr(&e, "name"), Vec::new()));
            }
            Event::Text(t) => {
                if let Some((_, _, text)) = value.as_mut() {
                    text.push_str(&t.xml10_content());
                }
            }
            // `&amp;` and the like come as events of their own.
            Event::GeneralRef(r) => {
                if let Some((_, _, text)) = value.as_mut() {
                    match r.resolve_char_ref().map_err(|e| e.to_string())? {
                        Some(c) => text.push(c),
                        None => text.push_str(match r.as_ref() {
                            "amp" => "&",
                            "lt" => "<",
                            "gt" => ">",
                            "quot" => "\"",
                            "apos" => "'",
                            _ => "",
                        }),
                    }
                }
            }
            Event::End(e) if matches!(e.name().as_ref(), "string" | "dword") => {
                let Some((tag, name, text)) = value.take() else {
                    continue;
                };
                if let Some((_, items)) = list.as_mut() {
                    items.push(text);
                } else if let Some(s) = values.last_mut() {
                    let v = if tag == "dword" {
                        text.trim()
                            .parse()
                            .map(Val::Number)
                            .unwrap_or(Val::Text(text))
                    } else {
                        Val::Text(text)
                    };
                    s.insert(name, v);
                }
            }
            Event::End(e) if e.name().as_ref() == "array" => {
                if let (Some((name, items)), Some(s)) = (list.take(), values.last_mut()) {
                    s.insert(name, Val::List(items));
                }
            }
            Event::Eof => break,
            _ => {}
        }
    }
    Ok(bundle(sessions))
}

fn attr(e: &quick_xml::events::BytesStart, name: &str) -> String {
    e.attributes()
        .flatten()
        .find(|a| a.key.as_ref() == name)
        .and_then(|a| {
            a.normalized_value(XmlVersion::Implicit1_0)
                .ok()
                .map(|v| v.into_owned())
        })
        .unwrap_or_default()
}

/// Sessions from a `Sessions` folder of `.ini` files.
pub fn from_dir(dir: &Path) -> io::Result<Bundle> {
    let mut sessions = Vec::new();
    walk(dir, &mut Vec::new(), &mut sessions)?;
    Ok(bundle(sessions))
}

fn walk(
    dir: &Path,
    path: &mut Vec<String>,
    out: &mut Vec<(Vec<String>, Session)>,
) -> io::Result<()> {
    let mut entries: Vec<_> = fs::read_dir(dir)?.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let p = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if p.is_dir() {
            path.push(name);
            walk(&p, path, out)?;
            path.pop();
        } else if let Some(stem) = name.strip_suffix(".ini") {
            if stem == "__FolderData__" {
                continue;
            }
            let s = parse_ini(&text::decode(&fs::read(&p)?));
            let mut full = path.clone();
            full.push(stem.to_owned());
            out.push((full, s));
        }
    }
    Ok(())
}

fn parse_ini(text: &str) -> Session {
    let mut s = Session::new();
    let mut lines = text.lines().peekable();
    while let Some(line) = lines.next() {
        let line = line.trim_end_matches('\r');
        let Some((kind, rest)) = line.split_once(":\"") else {
            continue;
        };
        let Some((name, value)) = rest.split_once("\"=") else {
            continue;
        };
        let v = match kind {
            "S" => Val::Text(value.to_owned()),
            "D" => match u64::from_str_radix(value.trim(), 16) {
                Ok(n) => Val::Number(n),
                Err(_) => continue,
            },
            "Z" => {
                let count = usize::from_str_radix(value.trim(), 16).unwrap_or(0);
                let mut items = Vec::new();
                while items.len() < count
                    && let Some(next) = lines.next_if(|l| l.starts_with(' '))
                {
                    items.push(next.trim_end_matches('\r')[1..].to_owned());
                }
                Val::List(items)
            }
            "B" => {
                // Binary: a length, then hex lines. Not used here.
                while lines.next_if(|l| l.starts_with(' ')).is_some() {}
                continue;
            }
            _ => continue,
        };
        s.insert(name.to_owned(), v);
    }
    s
}

fn bundle(sessions: Vec<(Vec<String>, Session)>) -> Bundle {
    let mut out = Bundle::default();
    let mut groups: BTreeMap<String, ()> = BTreeMap::new();
    let ids: Vec<String> = sessions.iter().map(|(p, _)| p.join("/")).collect();
    for (path, s) in sessions {
        let name = path.last().cloned().unwrap_or_default();
        if path.len() == 1 && name == "Default" {
            continue;
        }
        let folder = &path[..path.len().saturating_sub(1)];
        for depth in 1..=folder.len() {
            let id = folder[..depth].join("/");
            if groups.insert(id.clone(), ()).is_none() {
                out.groups.push(Group {
                    id,
                    name: folder[depth - 1].clone(),
                    parent: (depth > 1).then(|| folder[..depth - 1].join("/")),
                    ..Group::default()
                });
            }
        }
        let text = |k: &str| match s.get(k) {
            Some(Val::Text(t)) if !t.trim().is_empty() => Some(t.trim().to_owned()),
            _ => None,
        };
        let num = |k: &str| match s.get(k) {
            Some(Val::Number(n)) => Some(*n),
            Some(Val::Text(t)) => t.trim().parse().ok(),
            _ => None,
        };
        let list = |k: &str| match s.get(k) {
            Some(Val::List(l)) => l.clone(),
            _ => Vec::new(),
        };
        let protocol = text("Protocol Name").unwrap_or_else(|| "SSH2".into());
        let mut settings = Settings {
            user: text("Username"),
            ..Settings::default()
        };
        match num("[SSH2] Port") {
            Some(22) | None => {}
            Some(p) => match u16::try_from(p) {
                Ok(p) if p > 0 => settings.port = Some(p),
                _ => out.warnings.push(Warning::about(
                    &name,
                    WarningKind::BadValue {
                        field: "[SSH2] Port".into(),
                        value: p.to_string(),
                    },
                )),
            },
        }
        let mut keys = Vec::new();
        if num("Use Global Public Key") == Some(1) {
            out.warnings.push(Warning::about(
                &name,
                WarningKind::Unsupported("SecureCRT's global key".into()),
            ));
        } else if let Some(file) =
            text("Identity Filename V2").or_else(|| text("Identity Filename"))
        {
            // `path::rawkey`, and the public key's path for the private one.
            let file = file.split("::").next().unwrap_or_default();
            let file = file.strip_suffix(".pub").unwrap_or(file);
            if !file.is_empty() {
                keys.push(KeyRef::Path(file.to_owned()));
            }
        }
        if num("Forward X11") == Some(1) {
            out.warnings.push(Warning::about(
                &name,
                WarningKind::Unsupported("X11 forwarding".into()),
            ));
        }
        if num("Enable Agent Forwarding") == Some(1) {
            settings.agent_forward = Some(true);
        }
        if text("Password V2").or_else(|| text("Password")).is_some() {
            out.passwords += 1;
        }
        let mut jumps = Vec::new();
        match text("Firewall Name").as_deref() {
            None | Some("None") => {}
            Some(fw) => match fw.strip_prefix("Session:") {
                Some(target) => {
                    let target = target.trim_matches('/').replace('\\', "/");
                    if ids.contains(&target) {
                        jumps.push(JumpRef::Host(target));
                    } else {
                        out.warnings.push(Warning::about(
                            &name,
                            WarningKind::Unsupported(format!("a jump through {target}")),
                        ));
                    }
                }
                None => out.warnings.push(Warning::about(
                    &name,
                    WarningKind::Unsupported(format!("SecureCRT's firewall {fw}")),
                )),
            },
        }
        let id = path.join("/");
        for (table, kind) in [
            ("Port Forward Table V2", ForwardKind::Local),
            ("Reverse Forward Table V2", ForwardKind::Remote),
        ] {
            for entry in list(table) {
                if let Some(t) = forward(&entry, kind, &id) {
                    out.tunnels.push(t);
                }
            }
        }
        let description = list("Description").join("\n");
        out.hosts.push(Host {
            id,
            label: name,
            address: text("Hostname").unwrap_or_default(),
            group: (!folder.is_empty()).then(|| folder.join("/")),
            settings,
            keys,
            jumps,
            notes: (!description.trim().is_empty()).then(|| description.trim().to_owned()),
            unsupported: (!protocol.eq_ignore_ascii_case("SSH2")).then(|| protocol.to_lowercase()),
            ..Host::default()
        });
    }
    out
}

/// `Name|[ListenHost,]ListenPort|TargetDiffers|TargetHost|TargetPort|…`;
/// a dynamic one has `socks,` for its target host.
fn forward(entry: &str, kind: ForwardKind, host: &str) -> Option<Tunnel> {
    let f: Vec<&str> = entry.split('|').collect();
    let (listen_address, port) = match f.get(1)?.split_once(',') {
        Some((a, p)) => (Some(a.trim().to_owned()).filter(|a| !a.is_empty()), p),
        None => (None, *f.get(1)?),
    };
    let listen_port = port.trim().parse().ok()?;
    let target = f.get(3).copied().unwrap_or("").trim();
    let dynamic = target.starts_with("socks");
    Some(Tunnel {
        host: host.to_owned(),
        label: f.first()?.trim().to_owned(),
        kind: if dynamic { ForwardKind::Dynamic } else { kind },
        listen_address: listen_address.filter(|a| a != "127.0.0.1" && a != "localhost"),
        listen_port,
        dest_host: (!dynamic).then(|| {
            if target.is_empty() {
                "localhost".to_owned()
            } else {
                target.to_owned()
            }
        }),
        dest_port: (!dynamic)
            .then(|| f.get(4).and_then(|p| p.trim().parse().ok()))
            .flatten(),
        autostart: true,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const XML: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<VanDyke version="3.0">
  <key name="Sessions">
    <key name="Default">
      <string name="Hostname"></string>
    </key>
    <key name="Production">
      <key name="bastion">
        <dword name="Is Session">1</dword>
        <string name="Protocol Name">SSH2</string>
        <string name="Hostname">bastion.example.com</string>
        <string name="Username">ana</string>
        <dword name="[SSH2] Port">22</dword>
        <string name="Firewall Name">None</string>
      </key>
      <key name="web-01">
        <dword name="Is Session">1</dword>
        <string name="Protocol Name">SSH2</string>
        <string name="Hostname">web01.example.com</string>
        <string name="Username">deploy</string>
        <dword name="[SSH2] Port">2222</dword>
        <string name="Firewall Name">Session:Production/bastion</string>
        <string name="Identity Filename V2">/home/ana/.ssh/deploy.pub::rawkey</string>
        <dword name="Enable Agent Forwarding">1</dword>
        <array name="Port Forward Table V2">
          <string>web|127.0.0.1,8080|1|localhost|80||</string>
          <string>socks|1080|0|socks,|1080||</string>
        </array>
        <array name="Description">
          <string>Web tier</string>
        </array>
      </key>
    </key>
    <key name="switch">
      <dword name="Is Session">1</dword>
      <string name="Protocol Name">Telnet</string>
      <string name="Hostname">10.0.9.2</string>
    </key>
  </key>
</VanDyke>
"#;

    #[test]
    fn an_xml_export() {
        assert!(sniff_xml(XML));
        let b = from_xml(XML.as_bytes()).unwrap();
        assert_eq!(b.groups.len(), 1);
        let labels: Vec<&str> = b.hosts.iter().map(|h| h.label.as_str()).collect();
        assert_eq!(labels, ["bastion", "web-01", "switch"]);
        let web = &b.hosts[1];
        assert_eq!(web.group.as_deref(), Some("Production"));
        assert_eq!(web.settings.port, Some(2222));
        assert_eq!(web.jumps, [JumpRef::Host("Production/bastion".into())]);
        assert_eq!(web.keys, [KeyRef::Path("/home/ana/.ssh/deploy".into())]);
        assert_eq!(web.settings.agent_forward, Some(true));
        assert_eq!(web.notes.as_deref(), Some("Web tier"));
        assert_eq!(b.hosts[2].unsupported.as_deref(), Some("telnet"));
        let t: Vec<(ForwardKind, u16, Option<&str>)> = b
            .tunnels
            .iter()
            .map(|t| (t.kind, t.listen_port, t.dest_host.as_deref()))
            .collect();
        assert_eq!(
            t,
            [
                (ForwardKind::Local, 8080, Some("localhost")),
                (ForwardKind::Dynamic, 1080, None)
            ]
        );
    }

    #[test]
    fn ini_session_files() {
        let dir = tempfile::tempdir().unwrap();
        fs::create_dir(dir.path().join("Production")).unwrap();
        fs::write(
            dir.path().join("Production/web-01.ini"),
            "\u{feff}D:\"Is Session\"=00000001\r\nS:\"Protocol Name\"=SSH2\r\nS:\"Hostname\"=web01.example.com\r\nS:\"Username\"=deploy\r\nD:\"[SSH2] Port\"=00000016\r\nZ:\"Port Forward Table V2\"=00000001\r\n web|127.0.0.1,8080|1|localhost|80||\r\nZ:\"Description\"=00000001\r\n Web tier\r\n",
        )
        .unwrap();
        fs::write(
            dir.path().join("Production/__FolderData__.ini"),
            "S:\"x\"=y\r\n",
        )
        .unwrap();
        let b = from_dir(dir.path()).unwrap();
        assert_eq!(b.hosts.len(), 1);
        let web = &b.hosts[0];
        assert_eq!(web.settings.port, None);
        assert_eq!(web.notes.as_deref(), Some("Web tier"));
        assert_eq!(b.tunnels[0].listen_port, 8080);
    }
}
