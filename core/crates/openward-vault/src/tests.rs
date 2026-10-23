use ciborium::Value;
use openward_proto::{
    Agent, Environment, EnvironmentMark, ForwardKind, Group, Host, HostKeyPolicy, Identity, Jump,
    KnownHost, PortForward, Route, Settings, System, SystemSource, UseIdentity,
};
use rusqlite::params;

use super::*;

fn group(name: &str, parent: Option<ItemId>, settings: Settings) -> Data {
    Data::Group(Group {
        name: name.into(),
        parent,
        settings,
        ..Group::default()
    })
}

fn host(label: &str, group: Option<ItemId>, settings: Settings) -> Data {
    Data::Host(Host {
        label: label.into(),
        address: format!("{label}.example.com"),
        group,
        settings,
        ..Host::default()
    })
}

#[test]
fn items_persist_across_opens() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    // References between items are ids inside the body: they must decode too.
    let (vault_id, id, before) = {
        let mut v = Vault::open(&path).unwrap();
        let g = v.create(group("prod", None, Settings::default())).unwrap();
        let bastion = v
            .create(host("bastion", Some(g), Settings::default()))
            .unwrap();
        let through_bastion = Settings {
            route: Some(Route::Jump(vec![Jump::Host(bastion)])),
            ..Settings::default()
        };
        let id = v.create(host("web", Some(g), through_bastion)).unwrap();
        (v.id(), id, v.get(id).unwrap().clone())
    };
    let v = Vault::open(&path).unwrap();
    assert_eq!(v.id(), vault_id);
    assert_eq!(v.get(id), Some(&before));
    assert_eq!(v.items().count(), 3);
    assert_eq!(v.unreadable(), 0);

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(&path).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o600);
    }
}

#[test]
fn an_update_from_a_stale_revision_is_refused() {
    let mut v = Vault::open_in_memory().unwrap();
    let id = v.create(host("web", None, Settings::default())).unwrap();
    assert_eq!(
        v.update(id, 1, host("web-1", None, Settings::default()))
            .unwrap(),
        2
    );
    let stale = v.update(id, 1, host("web-2", None, Settings::default()));
    assert!(matches!(stale, Err(Error::Conflict { current: 2, .. })));
    assert_eq!(v.host(id).unwrap().label, "web-1");

    let retype = v.update(id, 2, group("web", None, Settings::default()));
    assert!(matches!(retype, Err(Error::WrongType { .. })));
}

#[test]
fn settings_inherit_from_groups_with_their_origin() {
    let mut v = Vault::open_in_memory().unwrap();
    let root = v
        .create(group(
            "prod",
            None,
            Settings {
                user: Some("deploy".into()),
                port: Some(2222),
                ..Settings::default()
            },
        ))
        .unwrap();
    let eu = v
        .create(group(
            "eu",
            Some(root),
            Settings {
                port: Some(2200),
                agent: Some(Agent::Socket("~/.1password/agent.sock".into())),
                ..Settings::default()
            },
        ))
        .unwrap();
    let h = v
        .create(host(
            "web",
            Some(eu),
            Settings {
                user: Some("root".into()),
                ..Settings::default()
            },
        ))
        .unwrap();

    let e = v.effective(h).unwrap();
    assert_eq!(e.settings.user.as_deref(), Some("root"));
    assert_eq!(e.origin("user"), Some(Origin::Host));
    assert_eq!(e.settings.port, Some(2200));
    assert_eq!(e.origin("port"), Some(Origin::Group(eu)));
    assert_eq!(e.origin("agent"), Some(Origin::Group(eu)));
    assert_eq!(e.settings.host_key_policy, Some(HostKeyPolicy::Ask));
    assert_eq!(e.origin("host_key_policy"), Some(Origin::Default));
    assert_eq!(e.origin("identity_files"), None);

    // Unset in the subgroup: the root's value shows through.
    let Data::Group(mut g) = v.get(eu).unwrap().body.data.clone() else {
        unreachable!()
    };
    g.settings.port = None;
    v.update(eu, 1, Data::Group(g)).unwrap();
    let e = v.effective(h).unwrap();
    assert_eq!(e.settings.port, Some(2222));
    assert_eq!(e.origin("port"), Some(Origin::Group(root)));

    // What a new host in the subgroup would get, before its own settings.
    let i = v.inherited(Some(eu), None).unwrap();
    assert_eq!(i.settings.user.as_deref(), Some("deploy"));
    assert_eq!(i.origin("user"), Some(Origin::Group(root)));
    assert_eq!(i.origin("agent"), Some(Origin::Group(eu)));
    let top = v.inherited(None, None).unwrap();
    assert_eq!(top.settings.port, Some(22));
    assert_eq!(top.origin("port"), Some(Origin::Default));
    assert_eq!(top.origin("user"), None);
}

/// The environment is a setting like the others: set on a group, the
/// hosts below get it; a host can mark itself otherwise, or not at all.
#[test]
fn the_environment_is_inherited_and_can_be_turned_off() {
    let mut v = Vault::open_in_memory().unwrap();
    let prod = Environment::Mark(EnvironmentMark {
        name: "Producción".into(),
        short: "prod".into(),
        color: "red".into(),
    });
    let marked = Settings {
        environment: Some(prod.clone()),
        ..Settings::default()
    };
    let g = v.create(group("prod", None, marked)).unwrap();
    let sub = v.create(group("db", Some(g), Settings::default())).unwrap();
    let db = v
        .create(host("db", Some(sub), Settings::default()))
        .unwrap();
    let unmarked = Settings {
        environment: Some(Environment::None),
        ..Settings::default()
    };
    let lab = v.create(host("lab", Some(g), unmarked)).unwrap();
    let loose = v.create(host("loose", None, Settings::default())).unwrap();

    let e = v.effective(db).unwrap();
    assert_eq!(e.settings.environment, Some(prod));
    assert_eq!(e.origin("environment"), Some(Origin::Group(g)));
    let e = v.effective(lab).unwrap();
    assert_eq!(e.settings.environment, Some(Environment::None));
    assert_eq!(e.origin("environment"), Some(Origin::Host));
    let e = v.effective(loose).unwrap();
    assert_eq!(e.settings.environment, Some(Environment::None));
    assert_eq!(e.origin("environment"), Some(Origin::Default));
    // Reading os-release runs a command: off unless asked for.
    assert_eq!(e.settings.read_os_release, Some(false));
}

/// This device's defaults go over the built-in ones, and groups and hosts
/// over them; they are never stored.
#[test]
fn this_devices_defaults_go_under_groups_and_hosts() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    let mut v = Vault::open(&path).unwrap();
    let off = Settings {
        read_os_release: Some(false),
        ..Settings::default()
    };
    let g = v.create(group("quiet", None, off)).unwrap();
    let quiet = v
        .create(host("quiet", Some(g), Settings::default()))
        .unwrap();
    let loose = v.create(host("loose", None, Settings::default())).unwrap();
    v.set_device_defaults(Settings {
        read_os_release: Some(true),
        ..Settings::default()
    });
    let e = v.effective(loose).unwrap();
    assert_eq!(e.settings.read_os_release, Some(true));
    assert_eq!(e.origin("read_os_release"), Some(Origin::Default));
    let e = v.effective(quiet).unwrap();
    assert_eq!(e.settings.read_os_release, Some(false));
    assert_eq!(e.origin("read_os_release"), Some(Origin::Group(g)));
    let e = v.inherited(None, None).unwrap();
    assert_eq!(e.settings.read_os_release, Some(true));
    drop(v);
    let v = Vault::open(&path).unwrap();
    assert_eq!(
        v.effective(loose).unwrap().settings.read_os_release,
        Some(false)
    );
}

/// What the server runs and the place among the favorites go with the
/// host.
#[test]
fn a_hosts_system_and_favorite_persist() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    let id = {
        let mut v = Vault::open(&path).unwrap();
        v.create(Data::Host(Host {
            label: "db".into(),
            address: "10.0.4.21".into(),
            system: Some(System {
                code: "deb".into(),
                name: "Debian 12".into(),
                source: SystemSource::Banner,
                evidence: "SSH-2.0-OpenSSH_9.2p1 Debian-2+deb12u3".into(),
            }),
            favorite: Some(2),
            ..Host::default()
        }))
        .unwrap()
    };
    let v = Vault::open(&path).unwrap();
    let h = v.host(id).unwrap();
    assert_eq!(h.system.as_ref().unwrap().name, "Debian 12");
    assert_eq!(h.system.as_ref().unwrap().source, SystemSource::Banner);
    assert_eq!(h.favorite, Some(2));
    assert!(h.extra.is_empty());
}

#[test]
fn references_are_checked() {
    let mut v = Vault::open_in_memory().unwrap();
    let missing = ItemId::new();
    assert!(matches!(
        v.create(host("web", Some(missing), Settings::default())),
        Err(Error::NotFound(_))
    ));
    let h = v.create(host("web", None, Settings::default())).unwrap();
    assert!(matches!(
        v.create(host("db", Some(h), Settings::default())),
        Err(Error::WrongType { .. })
    ));

    let a = v.create(group("a", None, Settings::default())).unwrap();
    let b = v.create(group("b", Some(a), Settings::default())).unwrap();
    assert!(matches!(
        v.update(a, 1, group("a", Some(b), Settings::default())),
        Err(Error::Cycle)
    ));
    assert!(matches!(
        v.update(a, 1, group("a", Some(a), Settings::default())),
        Err(Error::Cycle)
    ));

    let jump_self = Settings {
        route: Some(Route::Jump(vec![Jump::Host(h)])),
        ..Settings::default()
    };
    assert!(matches!(
        v.update(h, 1, host("web", None, jump_self)),
        Err(Error::Invalid(_))
    ));
}

#[test]
fn a_batch_can_refer_to_itself_and_is_all_or_nothing() {
    let mut v = Vault::open_in_memory().unwrap();
    let (g, bastion, web) = (ItemId::new(), ItemId::new(), ItemId::new());
    let through_bastion = Settings {
        route: Some(Route::Jump(vec![Jump::Host(bastion)])),
        ..Settings::default()
    };
    v.create_all(vec![
        (web, host("web", Some(g), through_bastion.clone())),
        (bastion, host("bastion", Some(g), Settings::default())),
        (g, group("imported", None, Settings::default())),
    ])
    .unwrap();
    assert_eq!(v.hosts().len(), 2);

    let bad = v.create_all(vec![
        (ItemId::new(), host("db", None, Settings::default())),
        (
            ItemId::new(),
            host("cache", Some(ItemId::new()), Settings::default()),
        ),
    ]);
    assert!(bad.is_err());
    assert_eq!(v.hosts().len(), 2);
}

#[test]
fn deleting_a_group_moves_its_contents_up() {
    let mut v = Vault::open_in_memory().unwrap();
    let root = v.create(group("root", None, Settings::default())).unwrap();
    let mid = v
        .create(group("mid", Some(root), Settings::default()))
        .unwrap();
    let leaf = v
        .create(group("leaf", Some(mid), Settings::default()))
        .unwrap();
    let h = v
        .create(host("web", Some(mid), Settings::default()))
        .unwrap();
    v.delete(mid).unwrap();
    assert!(v.get(mid).is_none());
    assert_eq!(v.group(leaf).unwrap().parent, Some(root));
    assert_eq!(v.host(h).unwrap().group, Some(root));
    assert_eq!(v.get(h).unwrap().rev, 2);
}

#[test]
fn a_jump_host_in_use_cannot_be_deleted() {
    let mut v = Vault::open_in_memory().unwrap();
    let bastion = v
        .create(host("bastion", None, Settings::default()))
        .unwrap();
    let web = v
        .create(host(
            "web",
            None,
            Settings {
                route: Some(Route::Jump(vec![Jump::Host(bastion)])),
                ..Settings::default()
            },
        ))
        .unwrap();
    assert!(matches!(v.delete(bastion), Err(Error::InUse(_, users)) if users == [web]));
    v.delete(web).unwrap();
    v.delete(bastion).unwrap();
    assert!(v.hosts().is_empty());
}

#[test]
fn search_and_tags() {
    let mut v = Vault::open_in_memory().unwrap();
    let prod = v
        .create(group("Production", None, Settings::default()))
        .unwrap();
    for (label, tags, group) in [
        ("web-1", vec!["nginx", "eu"], Some(prod)),
        ("web-2", vec!["nginx", "us"], Some(prod)),
        ("db", vec!["postgres", "eu"], None),
    ] {
        let mut h = Host {
            label: label.into(),
            address: format!("{label}.example.com"),
            group,
            ..Host::default()
        };
        h.tags = tags.into_iter().map(String::from).collect();
        v.create(Data::Host(h)).unwrap();
    }
    let labels = |ids: Vec<ItemId>| -> Vec<String> {
        ids.into_iter()
            .map(|id| v.host(id).unwrap().label.clone())
            .collect()
    };
    assert_eq!(labels(v.search("WEB")), ["web-1", "web-2"]);
    assert_eq!(labels(v.search("eu")), ["db", "web-1"]);
    assert_eq!(labels(v.search("production eu")), ["web-1"]);
    assert_eq!(labels(v.search("")), ["db", "web-1", "web-2"]);
    assert_eq!(v.tags()["eu"], 2);
    assert_eq!(v.tags()["postgres"], 1);
}

/// A known host is one `known_hosts` line: a comment with a line break
/// could otherwise add a line that makes a key a CA for every host.
#[test]
fn a_known_host_cannot_add_lines() {
    let mut v = Vault::open_in_memory().unwrap();
    let ok = KnownHost {
        hosts: "web.example.com".into(),
        key: "ssh-ed25519 AAAAOK".into(),
        comment: Some("from the old laptop".into()),
        ..KnownHost::default()
    };
    v.create(Data::KnownHost(ok.clone())).unwrap();
    for bad in [
        KnownHost {
            comment: Some("x\n@cert-authority * ssh-ed25519 AAAAEVIL".into()),
            ..ok.clone()
        },
        KnownHost {
            hosts: "web.example.com\n@cert-authority *".into(),
            ..ok.clone()
        },
        KnownHost {
            key: "ssh-ed25519 AAAAOK extra".into(),
            ..ok.clone()
        },
        KnownHost {
            hosts: "a b".into(),
            ..ok.clone()
        },
    ] {
        assert!(v.create(Data::KnownHost(bad.clone())).is_err(), "{bad:?}");
    }
    assert!(
        v.trust_host_key("evil\n@cert-authority", 22, "ssh-ed25519 AAAAX")
            .is_err()
    );
    assert_eq!(v.known_hosts_text().lines().count(), 1);
}

#[test]
fn trusting_a_host_key_replaces_the_old_one() {
    let mut v = Vault::open_in_memory().unwrap();
    let ca = KnownHost {
        hosts: "*.example.com".into(),
        key: "ssh-ed25519 AAAACA".into(),
        marker: Some(openward_proto::Marker::CertAuthority),
        ..KnownHost::default()
    };
    v.create(Data::KnownHost(ca)).unwrap();
    v.trust_host_key("git.example.com", 2222, "ssh-ed25519 AAAAOLD")
        .unwrap();
    v.trust_host_key("git.example.com", 2222, "ecdsa-sha2-nistp256 AAAAEC")
        .unwrap();
    v.trust_host_key("git.example.com", 2222, "ssh-ed25519 AAAANEW user@laptop")
        .unwrap();
    let mut lines: Vec<String> = v.known_hosts_text().lines().map(String::from).collect();
    lines.sort();
    assert_eq!(
        lines,
        [
            "@cert-authority *.example.com ssh-ed25519 AAAACA",
            "[git.example.com]:2222 ecdsa-sha2-nistp256 AAAAEC",
            "[git.example.com]:2222 ssh-ed25519 AAAANEW",
        ]
    );
    assert!(v.trust_host_key("git.example.com", 22, "garbage").is_err());
}

/// A newer version wrote an extra field and an item type this one does not
/// know: both survive this version's reads and writes.
#[test]
fn what_a_newer_version_wrote_is_kept() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    let mut v = Vault::open(&path).unwrap();
    let id = v.create(host("web", None, Settings::default())).unwrap();

    let mut body: Value = ciborium::from_reader(&v.get(id).unwrap().body.to_cbor()[..]).unwrap();
    body.as_map_mut()
        .unwrap()
        .push((Value::Text("color".into()), Value::Text("teal".into())));
    let snippet = Value::Map(vec![
        (Value::Text("created".into()), Value::Integer(1.into())),
        (Value::Text("modified".into()), Value::Integer(1.into())),
        (
            Value::Text("type".into()),
            Value::Text("ai_provider".into()),
        ),
    ]);
    let snippet_id = ItemId::new();
    for (item, body, rev) in [(id, body, 1), (snippet_id, snippet, 1)] {
        let mut bytes = Vec::new();
        ciborium::into_writer(&body, &mut bytes).unwrap();
        let envelope = Value::Map(vec![
            (Value::Text("v".into()), Value::Integer(0.into())),
            (Value::Text("body".into()), Value::Bytes(bytes)),
        ]);
        let mut sealed = Vec::new();
        ciborium::into_writer(&envelope, &mut sealed).unwrap();
        v.store
            .conn()
            .execute(
                "INSERT OR REPLACE INTO items VALUES (?1, ?2, ?3, ?4)",
                params![&v.id().as_bytes()[..], &item.as_bytes()[..], rev, sealed],
            )
            .unwrap();
    }
    drop(v);

    let mut v = Vault::open(&path).unwrap();
    assert_eq!(v.unreadable(), 1);
    assert_eq!(v.items().count(), 1);
    let Data::Host(mut h) = v.get(id).unwrap().body.data.clone() else {
        unreachable!()
    };
    h.label = "web-1".into();
    v.update(id, 1, Data::Host(h)).unwrap();
    drop(v);

    let v = Vault::open(&path).unwrap();
    let h = v.host(id).unwrap();
    assert_eq!(h.label, "web-1");
    assert_eq!(h.extra["color"], Value::Text("teal".into()));
    assert_eq!(v.unreadable(), 1);
}

#[test]
fn a_vault_from_a_newer_version_is_refused() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    drop(Vault::open(&path).unwrap());
    rusqlite::Connection::open(&path)
        .unwrap()
        .pragma_update(None, "user_version", 99)
        .unwrap();
    assert!(matches!(Vault::open(&path), Err(Error::NewerFormat(99))));
}

fn tunnel(label: &str, host: ItemId, kind: ForwardKind, dest: Option<(&str, u16)>) -> Data {
    Data::PortForward(PortForward {
        label: label.into(),
        host,
        kind,
        listen_port: 5433,
        listen_address: None,
        dest_host: dest.map(|(h, _)| h.to_owned()),
        dest_port: dest.map(|(_, p)| p),
        autostart: false,
        source: None,
        imported: None,
        extra: Default::default(),
    })
}

#[test]
fn tunnels_belong_to_a_host_and_go_with_it() {
    let mut v = Vault::open_in_memory().unwrap();
    let db = v.create(host("db", None, Settings::default())).unwrap();
    let pg = v
        .create(tunnel(
            "pg",
            db,
            ForwardKind::Local,
            Some(("10.0.4.21", 5432)),
        ))
        .unwrap();
    let socks = v
        .create(tunnel("Proxy", db, ForwardKind::Dynamic, None))
        .unwrap();
    let names: Vec<_> = v
        .port_forwards()
        .iter()
        .map(|(_, f)| f.label.clone())
        .collect();
    assert_eq!(names, ["pg", "Proxy"]);

    // Local and remote ones need somewhere to go; every one needs a host.
    assert!(matches!(
        v.create(tunnel("x", db, ForwardKind::Remote, None)),
        Err(Error::Invalid(_))
    ));
    let group = v.create(group("g", None, Settings::default())).unwrap();
    assert!(matches!(
        v.create(tunnel("x", group, ForwardKind::Dynamic, None)),
        Err(Error::WrongType { .. })
    ));

    let other = v.create(host("web", None, Settings::default())).unwrap();
    let kept = v
        .create(tunnel("web", other, ForwardKind::Dynamic, None))
        .unwrap();
    v.delete(db).unwrap();
    assert!(v.get(pg).is_none() && v.get(socks).is_none());
    assert!(v.get(kept).is_some());
}

fn identity(label: &str, user: &str, key: &str) -> Data {
    Data::Identity(Identity {
        label: label.into(),
        settings: Settings {
            user: Some(user.into()),
            identity_files: Some(vec![key.into()]),
            agent: Some(Agent::Off),
            ..Settings::default()
        },
        ..Identity::default()
    })
}

fn uses(identity: ItemId) -> Settings {
    Settings {
        identity: Some(UseIdentity::Id(identity)),
        ..Settings::default()
    }
}

#[test]
fn an_identity_comes_between_the_groups_and_the_host() {
    let mut v = Vault::open_in_memory().unwrap();
    let deploy = v
        .create(identity("deploy", "deploy", "~/.ssh/deploy"))
        .unwrap();
    let prod = v
        .create(group(
            "prod",
            None,
            Settings {
                user: Some("ops".into()),
                port: Some(2222),
                ..uses(deploy)
            },
        ))
        .unwrap();
    let web = v
        .create(host("web", Some(prod), Settings::default()))
        .unwrap();
    let db = v
        .create(host(
            "db",
            Some(prod),
            Settings {
                user: Some("root".into()),
                ..Settings::default()
            },
        ))
        .unwrap();

    // The identity beats the group's user; what it does not set (the
    // port) still comes from the group.
    let e = v.effective(web).unwrap();
    assert_eq!(e.identity, Some(deploy));
    assert_eq!(e.settings.user.as_deref(), Some("deploy"));
    assert_eq!(e.origin("user"), Some(Origin::Identity(deploy)));
    assert_eq!(e.origin("identity_files"), Some(Origin::Identity(deploy)));
    assert_eq!(e.origin("agent"), Some(Origin::Identity(deploy)));
    assert_eq!(e.origin("identity"), Some(Origin::Group(prod)));
    assert_eq!(e.origin("port"), Some(Origin::Group(prod)));
    // The host's own user beats the identity.
    let e = v.effective(db).unwrap();
    assert_eq!(e.settings.user.as_deref(), Some("root"));
    assert_eq!(e.origin("user"), Some(Origin::Host));
    assert_eq!(
        e.settings.identity_files,
        Some(vec!["~/.ssh/deploy".into()])
    );

    // "None" in a subgroup turns the group's identity off.
    let lab = v
        .create(group(
            "lab",
            Some(prod),
            Settings {
                identity: Some(UseIdentity::None),
                ..Settings::default()
            },
        ))
        .unwrap();
    let box1 = v
        .create(host("box", Some(lab), Settings::default()))
        .unwrap();
    let e = v.effective(box1).unwrap();
    assert_eq!(e.identity, None);
    assert_eq!(e.settings.user.as_deref(), Some("ops"));
    assert_eq!(e.origin("identity"), Some(Origin::Group(lab)));

    // What an editor shows for a host in lab that chooses deploy itself.
    let i = v
        .inherited(Some(lab), Some(UseIdentity::Id(deploy)))
        .unwrap();
    assert_eq!(i.settings.user.as_deref(), Some("deploy"));
    assert_eq!(i.origin("user"), Some(Origin::Identity(deploy)));
    let i = v.inherited(Some(lab), None).unwrap();
    assert_eq!(i.origin("user"), Some(Origin::Group(prod)));
}

#[test]
fn an_identity_sets_only_its_fields_and_is_referenced_by_kind() {
    let mut v = Vault::open_in_memory().unwrap();
    let wide = Data::Identity(Identity {
        label: "wide".into(),
        settings: Settings {
            port: Some(2222),
            ..Settings::default()
        },
        ..Identity::default()
    });
    assert!(matches!(v.create(wide), Err(Error::Invalid(_))));
    let unnamed = identity(" ", "deploy", "~/.ssh/k");
    assert!(matches!(v.create(unnamed), Err(Error::Invalid(_))));

    let g = v.create(group("prod", None, Settings::default())).unwrap();
    assert!(matches!(
        v.create(host("web", None, uses(g))),
        Err(Error::WrongType {
            expected: "identity",
            ..
        })
    ));
    assert!(matches!(
        v.create(host("web", None, uses(ItemId::new()))),
        Err(Error::NotFound(_))
    ));
}

#[test]
fn deleting_an_identity_sends_its_users_back_to_inheriting() {
    let mut v = Vault::open_in_memory().unwrap();
    let deploy = v.create(identity("deploy", "deploy", "~/.ssh/d")).unwrap();
    let ops = v.create(identity("ops", "ops", "~/.ssh/o")).unwrap();
    let prod = v.create(group("prod", None, uses(ops))).unwrap();
    let web = v.create(host("web", Some(prod), uses(deploy))).unwrap();
    let db = v
        .create(host("db", Some(prod), Settings::default()))
        .unwrap();
    assert_eq!(v.identity_choosers(deploy), vec![web]);
    assert_eq!(v.identity_hosts(ops), vec![db]);
    assert_eq!(
        v.identities()
            .iter()
            .map(|(_, i)| i.label.as_str())
            .collect::<Vec<_>>(),
        ["deploy", "ops"]
    );

    v.delete(deploy).unwrap();
    assert!(v.get(deploy).is_none());
    assert_eq!(v.host(web).unwrap().settings.identity, None);
    assert_eq!(v.get(web).unwrap().rev, 2);
    // Back to the group's.
    assert_eq!(v.effective(web).unwrap().identity, Some(ops));
}

#[test]
fn using_an_identity_on_groups_and_hosts_at_once() {
    let mut v = Vault::open_in_memory().unwrap();
    let deploy = v.create(identity("deploy", "deploy", "~/.ssh/d")).unwrap();
    let ci = v.create(identity("ci", "ci", "~/.ssh/ci")).unwrap();
    let prod = v.create(group("prod", None, Settings::default())).unwrap();
    let staging = v.create(group("staging", None, uses(ci))).unwrap();
    let web = v
        .create(host("web", Some(prod), Settings::default()))
        .unwrap();
    let db = v.create(host("db", Some(prod), uses(ci))).unwrap();
    let replica = v
        .create(host("replica", Some(staging), Settings::default()))
        .unwrap();
    let bastion = v.create(host("bastion", None, uses(deploy))).unwrap();

    // Prod and the replica choose it; the bastion no longer does.
    let choosers: HashSet<ItemId> = [prod, replica].into();
    let preview = v.identity_use_preview(deploy, &choosers);
    let of = |h: ItemId| preview.iter().find(|u| u.host == h).unwrap().clone();
    assert_eq!(
        of(web),
        IdentityUse {
            host: web,
            before: None,
            after: Some(deploy),
            by: Some(Origin::Group(prod)),
        }
    );
    // db keeps its own.
    assert_eq!((of(db).before, of(db).after), (Some(ci), Some(ci)));
    assert_eq!(
        (of(replica).before, of(replica).after, of(replica).by),
        (Some(ci), Some(deploy), Some(Origin::Host))
    );
    assert_eq!(
        (of(bastion).before, of(bastion).after),
        (Some(deploy), None)
    );
    // Nothing is written by a preview.
    assert_eq!(v.effective(web).unwrap().identity, None);

    assert_eq!(v.use_identity(deploy, &choosers).unwrap(), 3);
    assert_eq!(v.identity_hosts(deploy), vec![replica, web]);
    assert_eq!(v.effective(bastion).unwrap().identity, None);
    // Again: nothing to change.
    assert_eq!(v.use_identity(deploy, &choosers).unwrap(), 0);
    assert!(matches!(
        v.use_identity(prod, &choosers),
        Err(Error::WrongType { .. })
    ));
}

/// One process at a time: a second one would write over the first's
/// changes from its own copy of the items. Closing lets go.
#[test]
fn a_vault_opens_in_one_place_at_a_time() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    let v = Vault::open(&path).unwrap();
    assert!(matches!(Vault::open(&path), Err(Error::OpenElsewhere)));
    drop(v);
    Vault::open(&path).unwrap();
}
