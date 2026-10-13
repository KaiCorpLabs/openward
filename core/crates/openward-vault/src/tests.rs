use ciborium::Value;
use openward_proto::{Agent, Group, Host, HostKeyPolicy, Jump, KnownHost, Route, Settings};
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
        let bastion = v.create(host("bastion", Some(g), Settings::default())).unwrap();
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
        (Value::Text("type".into()), Value::Text("snippet".into())),
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
