//! Vaults as the published versions wrote them (`tests/fixtures`, made by
//! `make.sh` from their tags): this version opens them, reads every item
//! and writes over them without losing anything. Renaming or retyping a
//! field fails here, before a `brew upgrade` finds it.

use std::path::{Path, PathBuf};

use openward_vault::Vault;
use openward_vault::proto::{
    Agent, Data, Environment, ForwardKind, HostKeyPolicy, Jump, Marker, Proxy, Route, Source,
    SystemSource, UseIdentity,
};

/// A copy of a fixture to open: opening may write.
fn copy(version: &str) -> (tempfile::TempDir, PathBuf) {
    let from = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(format!("vault-{version}.sqlite"));
    let dir = tempfile::tempdir().unwrap();
    let to = dir.path().join("vault.db");
    std::fs::copy(&from, &to).unwrap();
    (dir, to)
}

fn named<'a, T>(
    items: &[(openward_vault::proto::ItemId, &'a T)],
    name: impl Fn(&T) -> &str,
    want: &str,
) -> (openward_vault::proto::ItemId, &'a T) {
    *items
        .iter()
        .find(|(_, t)| name(t) == want)
        .unwrap_or_else(|| panic!("no {want}"))
}

/// What 0.3.0 already had, and so every fixture.
fn check_common(v: &Vault) {
    assert_eq!(v.unreadable(), 0, "every row read");
    assert_eq!(v.items().count(), 12);

    let identities = v.identities();
    let (deploy, identity) = named(&identities, |i| &i.label, "deploy");
    assert_eq!(
        identity.settings.agent,
        Some(Agent::Socket("~/agent.sock".into()))
    );
    assert_eq!(identity.settings.identities_only, Some(true));
    assert_eq!(identity.imported.as_ref().unwrap().from, "termius");

    let groups = v.groups();
    let (prod, group) = named(&groups, |g| &g.name, "prod");
    let Some(Proxy::Socks5(proxy)) = &group.settings.proxy else {
        panic!("no proxy")
    };
    assert_eq!(
        (proxy.host.as_str(), proxy.port),
        ("proxy.example.com", 1080)
    );
    assert_eq!(group.settings.identity, Some(UseIdentity::Id(deploy)));
    assert_eq!(group.settings.host_key_policy, Some(HostKeyPolicy::Strict));
    let (_, eu) = named(&groups, |g| &g.name, "eu");
    assert_eq!(eu.parent, Some(prod));

    let hosts = v.hosts();
    let (bastion, _) = named(&hosts, |h| &h.label, "bastion");
    let (web, host) = named(&hosts, |h| &h.label, "web");
    assert_eq!(host.tags, ["web", "eu"]);
    assert_eq!(host.notes.as_deref(), Some("La web pública"));
    assert!(matches!(&host.source, Some(Source::SshConfig { alias, .. }) if alias == "web"));
    let Some(Route::Jump(jumps)) = &host.settings.route else {
        panic!("no jumps")
    };
    assert_eq!(jumps[0], Jump::Host(bastion));
    assert!(
        matches!(&jumps[1], Jump::Address { host, port: Some(2200), .. } if host == "10.0.0.1")
    );
    assert_eq!(host.settings.env.as_ref().unwrap()["LANG"], "C.UTF-8");
    let (_, db) = named(&hosts, |h| &h.label, "db");
    assert!(matches!(&db.settings.route, Some(Route::Command(c)) if c.contains("%h")));
    assert_eq!(db.settings.proxy, Some(Proxy::None));

    // Inheritance reads them as before: the group's user and proxy.
    let effective = v.effective(web).unwrap().settings;
    assert_eq!(effective.user.as_deref(), Some("ops"));
    assert_eq!(effective.port, Some(2222));
    assert!(matches!(effective.proxy, Some(Proxy::Socks5(_))));

    let tunnels = v.port_forwards();
    let (_, pg) = named(&tunnels, |t| &t.label, "postgres");
    assert_eq!(
        (pg.host, pg.kind, pg.listen_port, pg.autostart),
        (web, ForwardKind::Local, 5432, true)
    );
    let (_, socks) = named(&tunnels, |t| &t.label, "socks");
    assert_eq!(socks.kind, ForwardKind::Dynamic);

    let snippets = v.snippets();
    let (_, snippet) = named(&snippets, |s| &s.label, "Reiniciar");
    assert_eq!(snippet.defaults["servicio"], "nginx");
    assert!(snippet.type_only);

    let workspaces = v.workspaces();
    let (_, w) = named(&workspaces, |w| &w.name, "Mañana");
    assert_eq!((w.tabs.len(), w.active), (2, 1));
    let split = w.tabs[0].panes.as_ref().unwrap().split.as_ref().unwrap();
    assert!(split.vertical);
    assert_eq!(split.first.target.as_ref().unwrap().host, Some(web));
    assert_eq!(
        split.second.target.as_ref().unwrap().user.as_deref(),
        Some("root")
    );
    assert_eq!(w.tabs[1].sftp.as_ref().unwrap().host, Some(bastion));

    let known = v.known_hosts();
    assert_eq!(known.len(), 2);
    assert!(
        known
            .iter()
            .any(|(_, k)| k.marker == Some(Marker::CertAuthority))
    );
    assert!(
        v.known_hosts_text()
            .contains("[web.example.com]:2222 ssh-ed25519")
    );
}

/// Written over by this version and opened again: still all there.
fn rewrite(path: &Path) {
    {
        let mut v = Vault::open(path).unwrap();
        let ids: Vec<_> = v
            .items()
            .map(|i| (i.id, i.rev, i.body.data.clone()))
            .collect();
        for (id, rev, data) in ids {
            v.update(id, rev, data).unwrap();
        }
    }
    check_common(&Vault::open(path).unwrap());
}

#[test]
fn a_vault_of_0_3_0() {
    let (_dir, path) = copy("0.3.0");
    check_common(&Vault::open(&path).unwrap());
    rewrite(&path);
}

#[test]
fn a_vault_of_0_3_1() {
    let (_dir, path) = copy("0.3.1");
    let v = Vault::open(&path).unwrap();
    check_common(&v);
    let groups = v.groups();
    let (_, prod) = named(&groups, |g| &g.name, "prod");
    let Some(Environment::Mark(mark)) = &prod.settings.environment else {
        panic!("no mark")
    };
    assert_eq!(
        (mark.name.as_str(), mark.color.as_str()),
        ("Producción", "red")
    );
    assert_eq!(prod.settings.read_os_release, Some(true));
    let hosts = v.hosts();
    let (_, web) = named(&hosts, |h| &h.label, "web");
    let system = web.system.as_ref().unwrap();
    assert_eq!(
        (system.code.as_str(), system.source),
        ("deb", SystemSource::OsRelease)
    );
    assert_eq!(web.favorite, Some(0));
    assert_eq!(web.settings.persistent_session, Some(true));
    assert_eq!(web.settings.environment, Some(Environment::None));
    drop(v);
    rewrite(&path);
    let v = Vault::open(&path).unwrap();
    assert!(v.hosts().iter().any(|(_, h)| h.favorite == Some(0)));
    assert!(v.items().all(|i| !matches!(i.body.data, Data::Unsupported)));
}
