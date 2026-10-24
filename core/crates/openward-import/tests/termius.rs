//! Termius's importer against a database Chromium wrote: made-up data in
//! Termius's tables and encryption, under a test key.
//!
//! To write the fixture again (after changing `tables`):
//!
//!   cargo test -p openward-import --test termius -- --ignored write_page
//!   crates/openward-import/tests/fixtures/termius/make.sh

use std::path::PathBuf;

use openward_import::bundle::{KeyRef, WarningKind};
use openward_import::termius::{self, crypto};
use openward_proto::{ForwardKind, HostKeyPolicy, Proxy};
use serde_json::{Value, json};

const KEY: [u8; 32] = [0x42; 32];

fn fixtures() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/termius")
}

/// Termius's tables as JSON, with `enc(…)` for the fields Termius
/// encrypts. A reference is `{id, local_id}`, `id` null until synced.
fn tables() -> Value {
    let mut nonce = 0u8;
    let mut enc = |text: &str| {
        nonce += 1;
        Value::String(crypto::encrypt(&KEY, &[nonce; 24], text))
    };
    let r = |id: Option<i64>, local: i64| json!({ "id": id, "local_id": local });
    json!({
        "groups": [
            { "id": 101, "local_id": 1, "label": enc("Producción"), "parent_group": null,
              "ssh_config": r(Some(201), 1), "updated_at": "2026-10-01T10:00:00" },
            { "id": 102, "local_id": 2, "label": enc("Web"), "parent_group": r(Some(101), 1),
              "ssh_config": null, "updated_at": "2026-10-01T10:00:00" },
        ],
        "keys": [
            { "id": 301, "local_id": 1, "label": enc("deploy"),
              "private_key": enc("-----BEGIN OPENSSH PRIVATE KEY-----\nfixture-deploy\n-----END OPENSSH PRIVATE KEY-----\n"),
              "passphrase": enc(""), "public_key": enc("") },
            { "id": 302, "local_id": 2, "label": enc("ci"),
              "private_key": enc("-----BEGIN OPENSSH PRIVATE KEY-----\nfixture-ci\n-----END OPENSSH PRIVATE KEY-----\n"),
              "passphrase": enc("frase"), "public_key": enc("") },
        ],
        "ssh_identities": [
            { "id": 401, "local_id": 1, "label": enc("deploy"), "username": enc("deploy"),
              "password": enc(""), "is_visible": true, "ssh_key": r(Some(301), 1) },
            { "id": 402, "local_id": 2, "label": enc(""), "username": enc("ops"),
              "password": enc("secreto"), "is_visible": false, "ssh_key": null },
            { "id": 403, "local_id": 3, "label": enc("ci"), "username": enc("ci"),
              "password": enc(""), "is_visible": true, "ssh_key": r(Some(302), 2) },
        ],
        "ssh_configs": [
            { "id": 201, "local_id": 1, "port": 2222, "identity": r(Some(401), 1) },
            { "id": 202, "local_id": 2, "identity": r(Some(402), 2), "agent_forwarding": true,
              "env_variables": enc(r#"{"LANG": "es_ES.UTF-8"}"#), "strict_host_key_check": true,
              "proxycommand": r(Some(501), 1) },
            { "id": 203, "local_id": 3, "identity": null },
            { "id": 204, "local_id": 4, "use_mosh": true, "startup_snippet": r(Some(601), 1),
              "content": enc(r#"{"port": 2200, "use_mosh": true}"#) },
            { "id": null, "local_id": 5, "port": 70000 },
        ],
        "ssh_config_identities": [
            { "id": 701, "local_id": 1, "ssh_config": r(Some(203), 3), "identity": r(Some(403), 3) },
        ],
        "proxies": [
            { "id": 501, "local_id": 1, "type": "socks5", "hostname": enc("proxy.example.com"),
              "port": 1080, "identity": null },
        ],
        "hosts": [
            { "id": 801, "local_id": 1, "label": enc("bastion"), "address": enc("bastion.example.com"),
              "group": null, "ssh_config": r(Some(202), 2), "updated_at": "2026-10-01T10:00:00" },
            // Its address only in `content`.
            { "id": 802, "local_id": 2, "label": enc("web-1"),
              "content": enc(r#"{"address": "web-1.example.com", "label": "web-1"}"#),
              "group": r(Some(102), 2), "ssh_config": r(Some(203), 3) },
            { "id": 803, "local_id": 3, "label": enc("lab-mosh"), "address": enc("lab.example.com"),
              "ssh_config": r(Some(204), 4) },
            { "id": 804, "local_id": 4, "label": enc("old-switch"), "address": enc("10.0.9.2"),
              "ssh_config": null, "telnet_config": r(Some(901), 1) },
            // Not synced: no id, and a packed address.
            { "id": null, "local_id": 5, "label": enc("packed"), "address": enc("3221226008"),
              "ssh_config": r(None, 5) },
            { "id": 806, "local_id": 6, "label": "shared", "address": "team.example.com",
              "encrypted_with": "team-key" },
            { "id": 807, "local_id": 7, "label": enc("gone"), "address": enc("gone.example.com"),
              "status": "deleted" },
        ],
        "pf_rules": [
            { "id": 1001, "local_id": 1, "host": r(Some(802), 2), "label": enc("Postgres"),
              "pf_type": "Local Rule", "bound_address": "127.0.0.1", "local_port": 5433,
              "hostname": enc("10.0.4.21"), "remote_port": 5432 },
            { "id": 1002, "local_id": 2, "host": r(Some(801), 1), "label": enc("SOCKS"),
              "pf_type": "Dynamic Rule", "bound_address": "0.0.0.0", "local_port": 1080 },
        ],
        "snippets": [
            { "id": 601, "local_id": 1, "label": enc("Reiniciar nginx"),
              "script": enc("sudo systemctl restart nginx") },
        ],
        "tags": [ { "id": 1101, "local_id": 1, "label": enc("prod") } ],
        "tag_hosts": [ { "id": 1201, "local_id": 1, "tag": r(Some(1101), 1), "host": r(Some(802), 2) } ],
        "known_hosts": [
            { "id": 1301, "local_id": 1, "hostnames": enc("bastion.example.com"),
              "key": enc("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"),
              "marker": null, "comment": null },
        ],
        "host_chains": [],
    })
}

/// Writes the page that `make.sh` loads in Chrome to create the database.
#[test]
#[ignore]
fn write_page() {
    let page = format!(
        r#"<!doctype html><meta charset="utf-8"><title>wait</title>
<script>
// Written by tests/termius.rs (write_page): made-up data, test key.
const TABLES = {};
function openDb(name) {{
  return new Promise((ok, bad) => {{
    const r = indexedDB.open(name, 1);
    r.onupgradeneeded = () => r.result.createObjectStore(name, {{ keyPath: "local_id" }});
    r.onsuccess = () => ok(r.result);
    r.onerror = () => bad(r.error);
  }});
}}
(async () => {{
  for (const [name, rows] of Object.entries(TABLES)) {{
    const db = await openDb(name);
    await new Promise((ok, bad) => {{
      const t = db.transaction(name, "readwrite");
      for (const row of rows) t.objectStore(name).put(row);
      t.oncomplete = ok;
      t.onerror = () => bad(t.error);
    }});
    db.close();
  }}
  document.title = "done";
}})();
</script>
"#,
        serde_json::to_string_pretty(&tables()).unwrap()
    );
    std::fs::write(fixtures().join("make.html"), page).unwrap();
}

#[test]
fn the_fixture_as_a_bundle() {
    let b = termius::read(&fixtures().join("Termius"), Some(vec![[0; 32], KEY])).unwrap();
    let host = |label: &str| {
        b.hosts
            .iter()
            .find(|h| h.label == label)
            .unwrap_or_else(|| panic!("no host {label}"))
    };

    // Groups, nested, with the parent's port and identity.
    assert_eq!(b.groups.len(), 2);
    let prod = b.groups.iter().find(|g| g.name == "Producción").unwrap();
    let web = b.groups.iter().find(|g| g.name == "Web").unwrap();
    assert_eq!(web.parent.as_deref(), Some(prod.id.as_str()));
    assert_eq!(prod.settings.port, Some(2222));
    assert_eq!(prod.identity.as_deref(), Some("id:401|local:1"));

    // Named identities come as identities, with their stored key.
    let labels: Vec<&str> = b.identities.iter().map(|i| i.label.as_str()).collect();
    assert_eq!(labels, ["deploy", "ci"]);
    assert_eq!(
        b.identities[0].keys,
        [KeyRef::Stored("id:301|local:1".into())]
    );
    assert_eq!(b.keys.len(), 2);
    assert_eq!(
        b.keys[1].passphrase.as_ref().map(|p| p.as_str()),
        Some("frase")
    );

    // A host's own identity is its user; it forwards the agent, sends LANG,
    // goes through a SOCKS proxy and checks host keys strictly.
    let bastion = host("bastion");
    assert_eq!(bastion.address, "bastion.example.com");
    assert_eq!(bastion.settings.user.as_deref(), Some("ops"));
    assert!(bastion.identity.is_none());
    assert_eq!(bastion.settings.agent_forward, Some(true));
    assert_eq!(
        bastion.settings.env.as_ref().unwrap()["LANG"],
        "es_ES.UTF-8"
    );
    assert_eq!(
        bastion.settings.host_key_policy,
        Some(HostKeyPolicy::Strict)
    );
    assert!(
        matches!(&bastion.settings.proxy, Some(Proxy::Socks5(p)) if p.host == "proxy.example.com" && p.port == 1080)
    );
    assert!(bastion.jumps.is_empty());

    // web-1: its address from `content`, in Web, a named identity through
    // the join table, tagged.
    let web1 = host("web-1");
    assert_eq!(web1.address, "web-1.example.com");
    assert_eq!(web1.group.as_deref(), Some(web.id.as_str()));
    assert_eq!(web1.identity.as_deref(), Some("id:403|local:3"));
    assert_eq!(web1.tags, ["prod"]);

    // Mosh comes in as SSH, with its port from `content`; telnet does not.
    assert_eq!(host("lab-mosh").settings.port, Some(2200));
    assert_eq!(host("old-switch").unsupported.as_deref(), Some("telnet"));
    assert_eq!(host("packed").address, "192.0.2.24");
    assert_eq!(host("packed").id, "local:5");
    assert!(
        b.hosts
            .iter()
            .all(|h| h.label != "gone" && h.label != "shared")
    );

    let kinds: Vec<(Option<&str>, &WarningKind)> = b
        .warnings
        .iter()
        .map(|w| (w.subject.as_deref(), &w.kind))
        .collect();
    assert!(
        kinds.contains(&(None, &WarningKind::Shared { count: 1 })),
        "{kinds:?}"
    );
    assert!(kinds.contains(&(Some("lab-mosh"), &WarningKind::Mosh)));
    assert!(kinds.contains(&(Some("lab-mosh"), &WarningKind::StartupCommand)));
    assert!(kinds.contains(&(
        Some("packed"),
        &WarningKind::BadValue {
            field: "port".into(),
            value: "70000".into()
        }
    )));

    // Tunnels, a snippet and a known host.
    assert_eq!(b.tunnels.len(), 2);
    let pg = b.tunnels.iter().find(|t| t.label == "Postgres").unwrap();
    assert_eq!(pg.host, web1.id);
    assert_eq!(
        (pg.kind, pg.listen_port, pg.listen_address.as_deref()),
        (ForwardKind::Local, 5433, None)
    );
    assert_eq!(
        (pg.dest_host.as_deref(), pg.dest_port),
        (Some("10.0.4.21"), Some(5432))
    );
    let socks = b.tunnels.iter().find(|t| t.label == "SOCKS").unwrap();
    assert_eq!(
        (
            socks.kind,
            socks.listen_address.as_deref(),
            socks.dest_host.as_deref()
        ),
        (ForwardKind::Dynamic, Some("0.0.0.0"), None)
    );
    assert_eq!(b.snippets[0].script, "sudo systemctl restart nginx");
    assert_eq!(b.known_hosts[0].hosts, "bastion.example.com");

    // A password and a passphrase, counted, never brought.
    assert_eq!((b.passwords, b.passphrases), (1, 1));
}

#[test]
fn a_wrong_key_is_an_error_and_not_an_empty_import() {
    let err = termius::read(&fixtures().join("Termius"), Some(vec![[1; 32]])).unwrap_err();
    assert!(matches!(err, termius::Error::WrongKey), "{err}");
}
