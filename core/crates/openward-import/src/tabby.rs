//! Tabby's `config.yaml`, read where Tabby keeps it: no export needed.
//!
//! Profiles of type `ssh` become hosts, `groups` (nested through
//! `parentGroupId`) groups. A jump is another profile's id. Keys go by
//! `file://` URL, or live in Tabby's vault, which is not read. Tabby's
//! default user is `root`, so a profile without one keeps `root`. Its
//! forwarded ports open on connect, as in Tabby.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use openward_proto::{ForwardKind, Proxy, ProxyServer, Route, Settings};
use yaml_rust2::{Yaml, YamlLoader};

use crate::bundle::{Bundle, Group, Host, JumpRef, KeyRef, Tunnel, Warning, WarningKind};
use crate::text;

/// Where Tabby keeps its configuration on this system.
pub fn config_path(home: &Path) -> PathBuf {
    if cfg!(target_os = "macos") {
        home.join("Library/Application Support/tabby/config.yaml")
    } else if cfg!(windows) {
        std::env::var_os("APPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join("AppData/Roaming"))
            .join("tabby/config.yaml")
    } else {
        home.join(".config/tabby/config.yaml")
    }
}

/// Whether the text looks like Tabby's configuration.
pub fn sniff(text: &str) -> bool {
    text.lines().any(|l| l.starts_with("profiles:"))
        && (text.contains("type: ssh") || text.contains("version:"))
}

pub fn parse(bytes: &[u8]) -> Result<Bundle, String> {
    let docs = YamlLoader::load_from_str(&text::decode(bytes)).map_err(|e| e.to_string())?;
    let doc = docs.first().ok_or("an empty file")?;
    if doc["encrypted"].as_bool() == Some(true) {
        return Err(
            "Tabby's configuration is encrypted: turn off its vault's encryption first".into(),
        );
    }
    let mut out = Bundle::default();
    let s = |y: &Yaml| {
        y.as_str()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_owned)
    };
    let n = |y: &Yaml| y.as_i64().or_else(|| y.as_str()?.trim().parse().ok());

    let mut by_name: HashMap<String, String> = HashMap::new();
    for g in doc["groups"].as_vec().into_iter().flatten() {
        let (Some(id), Some(name)) = (s(&g["id"]), s(&g["name"])) else {
            continue;
        };
        by_name.insert(name.clone(), id.clone());
        out.groups.push(Group {
            id,
            name,
            parent: s(&g["parentGroupId"]),
            ..Group::default()
        });
    }

    for p in doc["profiles"].as_vec().into_iter().flatten() {
        if p["isBuiltin"].as_bool() == Some(true) || p["isTemplate"].as_bool() == Some(true) {
            continue;
        }
        let kind = s(&p["type"]).unwrap_or_default();
        let (Some(id), Some(name)) = (s(&p["id"]), s(&p["name"])) else {
            continue;
        };
        let o = &p["options"];
        if kind != "ssh" {
            if kind == "telnet" || kind == "serial" {
                out.hosts.push(Host {
                    id,
                    label: name,
                    address: s(&o["host"]).unwrap_or_default(),
                    unsupported: Some(kind),
                    ..Host::default()
                });
            }
            continue;
        }
        // Since config version 5 a profile names its group by id; before,
        // by name.
        let group = s(&p["group"]).map(|g| {
            if out.groups.iter().any(|x| x.id == g) {
                g
            } else if let Some(id) = by_name.get(&g) {
                id.clone()
            } else {
                out.groups.push(Group {
                    id: g.clone(),
                    name: g.clone(),
                    ..Group::default()
                });
                by_name.insert(g.clone(), g.clone());
                g
            }
        });
        let mut settings = Settings {
            user: Some(s(&o["user"]).unwrap_or_else(|| "root".into())),
            ..Settings::default()
        };
        if let Some(port) = n(&o["port"]) {
            match u16::try_from(port) {
                Ok(22) => {}
                Ok(p) if p > 0 => settings.port = Some(p),
                _ => out.warnings.push(Warning::about(
                    &name,
                    WarningKind::BadValue {
                        field: "port".into(),
                        value: port.to_string(),
                    },
                )),
            }
        }
        let mut keys = Vec::new();
        for k in o["privateKeys"]
            .as_vec()
            .into_iter()
            .flatten()
            .filter_map(s)
        {
            if let Some(path) = k.strip_prefix("file://") {
                keys.push(KeyRef::Path(text::percent_decode(path)));
            } else {
                out.warnings.push(Warning::about(
                    &name,
                    WarningKind::Unsupported("a key in Tabby's vault".into()),
                ));
            }
        }
        if o["agentForward"].as_bool() == Some(true) {
            settings.agent_forward = Some(true);
        }
        if o["x11"].as_bool() == Some(true) {
            out.warnings.push(Warning::about(
                &name,
                WarningKind::Unsupported("X11 forwarding".into()),
            ));
        }
        if let Some(cmd) = s(&o["proxyCommand"]) {
            settings.route = Some(Route::Command(cmd));
        }
        let server = |host: &str, port: &str, default: u16| {
            s(&o[host]).map(|host| ProxyServer {
                host,
                port: n(&o[port])
                    .and_then(|p| u16::try_from(p).ok())
                    .unwrap_or(default),
                user: None,
            })
        };
        if let Some(socks) = server("socksProxyHost", "socksProxyPort", 1080) {
            settings.proxy = Some(Proxy::Socks5(socks));
        } else if let Some(http) = server("httpProxyHost", "httpProxyPort", 8080) {
            settings.proxy = Some(Proxy::Http(http));
        }
        if o["scripts"].as_vec().is_some_and(|v| !v.is_empty()) {
            out.warnings
                .push(Warning::about(&name, WarningKind::StartupCommand));
        }
        if s(&o["password"]).is_some() {
            out.passwords += 1;
        }
        for f in o["forwardedPorts"].as_vec().into_iter().flatten() {
            let kind = match s(&f["type"]).unwrap_or_default().as_str() {
                "Remote" => ForwardKind::Remote,
                "Dynamic" => ForwardKind::Dynamic,
                _ => ForwardKind::Local,
            };
            let Some(port) = n(&f["port"]).and_then(|p| u16::try_from(p).ok()) else {
                continue;
            };
            let dynamic = kind == ForwardKind::Dynamic;
            out.tunnels.push(Tunnel {
                host: id.clone(),
                label: s(&f["description"]).unwrap_or_default(),
                kind,
                listen_address: s(&f["host"]).filter(|h| h != "127.0.0.1" && h != "localhost"),
                listen_port: port,
                dest_host: (!dynamic).then(|| s(&f["targetAddress"])).flatten(),
                dest_port: (!dynamic)
                    .then(|| n(&f["targetPort"]).and_then(|p| u16::try_from(p).ok()))
                    .flatten(),
                autostart: true,
            });
        }
        out.hosts.push(Host {
            id,
            label: name,
            address: s(&o["host"]).unwrap_or_default(),
            group,
            settings,
            jumps: s(&o["jumpHost"]).map(JumpRef::Host).into_iter().collect(),
            keys,
            ..Host::default()
        });
    }
    // A jump to a profile that is not there (or not SSH) cannot be kept.
    let ids: Vec<String> = out.hosts.iter().map(|h| h.id.clone()).collect();
    for h in &mut out.hosts {
        let before = h.jumps.len();
        h.jumps
            .retain(|j| matches!(j, JumpRef::Host(id) if ids.contains(id)));
        if h.jumps.len() < before {
            out.warnings.push(Warning::about(
                &h.label,
                WarningKind::Unsupported("a jump through a profile that is not SSH".into()),
            ));
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const CONFIG: &str = r#"version: 8
groups:
  - id: g1
    name: Production
  - id: g2
    name: Databases
    parentGroupId: g1
profiles:
  - id: ssh:custom:bastion:aaaa
    type: ssh
    name: bastion
    group: g1
    options:
      host: bastion.example.com
      user: ana
  - id: ssh:custom:db-01:bbbb
    type: ssh
    name: db-01
    group: g2
    options:
      host: db01.example.com
      port: 2222
      privateKeys:
        - file:///home/ana/.ssh/id%20ed25519
        - vault://abc
      jumpHost: ssh:custom:bastion:aaaa
      agentForward: true
      socksProxyHost: socks.example.com
      forwardedPorts:
        - type: Local
          host: 127.0.0.1
          port: 5432
          targetAddress: localhost
          targetPort: 5432
          description: pg
        - type: Dynamic
          host: 0.0.0.0
          port: 1080
          targetAddress: ''
          targetPort: 0
  - id: local:zsh
    type: local
    name: zsh
  - id: old
    type: ssh
    name: legacy
    group: Old
    options:
      host: old.example.com
      user: root
"#;

    #[test]
    fn profiles_groups_jumps_and_forwards() {
        assert!(sniff(CONFIG));
        let b = parse(CONFIG.as_bytes()).unwrap();
        assert_eq!(b.hosts.len(), 3);
        let db = &b.hosts[1];
        assert_eq!(db.group.as_deref(), Some("g2"));
        assert_eq!(db.settings.user.as_deref(), Some("root"));
        assert_eq!(db.settings.port, Some(2222));
        assert_eq!(db.keys, [KeyRef::Path("/home/ana/.ssh/id ed25519".into())]);
        assert_eq!(db.jumps, [JumpRef::Host("ssh:custom:bastion:aaaa".into())]);
        assert!(matches!(&db.settings.proxy, Some(Proxy::Socks5(p)) if p.port == 1080));
        assert_eq!(b.tunnels.len(), 2);
        assert_eq!(b.tunnels[1].listen_address.as_deref(), Some("0.0.0.0"));
        assert!(b.tunnels.iter().all(|t| t.autostart));
        // A group named, as before config version 5.
        assert_eq!(b.hosts[2].group.as_deref(), Some("Old"));
        assert!(b.groups.iter().any(|g| g.id == "Old"));
        assert_eq!(b.groups[1].parent.as_deref(), Some("g1"));
    }

    #[test]
    fn an_encrypted_config_is_refused() {
        let err = parse(b"encrypted: true\nvault:\n  contents: abc\n").unwrap_err();
        assert!(err.contains("encrypted"), "{err}");
    }
}
