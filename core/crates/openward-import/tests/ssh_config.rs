use std::fs;

use openward_import::ssh_config::{Paths, SshConfig, Warning, import};
use openward_proto::{Agent, Data, Group, HostKeyPolicy, ItemId, Jump, Route, Source};
use openward_vault::Vault;

/// A home directory with `~/.ssh/config` and the given extra files.
fn home(config: &str, extra: &[(&str, &str)]) -> (tempfile::TempDir, Paths) {
    let dir = tempfile::tempdir().unwrap();
    let paths = Paths::new(dir.path());
    fs::create_dir_all(&paths.ssh_dir).unwrap();
    fs::write(paths.user_config(), config).unwrap();
    for (name, text) in extra {
        let path = paths.ssh_dir.join(name);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, text).unwrap();
    }
    (dir, paths)
}

fn load(paths: &Paths) -> SshConfig {
    SshConfig::load(&paths.user_config(), paths)
}

#[test]
fn the_first_value_obtained_wins() {
    let (_dir, paths) = home(
        "
# Specific first, defaults last, as OpenSSH recommends.
Host web
    HostName web.example.com
    User deploy
    IdentityFile ~/.ssh/web_ed25519

Host db db-replica
    HostName=%h.internal
    Port 2222

Host *
    User ops
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 15
",
        &[],
    );
    let config = load(&paths);
    assert_eq!(config.aliases(), ["web", "db", "db-replica"]);
    assert!(config.warnings.is_empty(), "{:?}", config.warnings);

    let web = config.resolve("web");
    assert_eq!(web.hostname.as_deref(), Some("web.example.com"));
    assert_eq!(web.user.as_deref(), Some("deploy"));
    assert_eq!(web.port, Some(22));
    assert_eq!(
        web.identity_files,
        ["~/.ssh/web_ed25519", "~/.ssh/id_ed25519"]
    );
    assert_eq!(web.keepalive_secs, Some(15));

    let replica = config.resolve("DB-Replica");
    assert_eq!(replica.hostname.as_deref(), Some("DB-Replica.internal"));
    assert_eq!(replica.user.as_deref(), Some("ops"));
    assert_eq!(replica.port, Some(2222));
}

#[test]
fn wildcards_and_negation() {
    let (_dir, paths) = home(
        "
Host *.prod !legacy.prod
    User admin
Host legacy.prod app.prod
    Port 2200
",
        &[],
    );
    let config = load(&paths);
    assert_eq!(config.aliases(), ["legacy.prod", "app.prod"]);
    assert_eq!(config.resolve("app.prod").user.as_deref(), Some("admin"));
    assert_eq!(config.resolve("legacy.prod").user, None);
}

#[test]
fn includes_follow_globs_and_the_block_they_are_in() {
    let (_dir, paths) = home(
        "
Include config.d/*
Host work-*
    Include ~/.ssh/work.conf
Host personal
    User me
",
        &[
            ("config.d/10-git", "Host git\n  HostName git.example.com\n"),
            (
                "config.d/20-ci",
                "Host ci\n  HostName ci.example.com\n  User ci\n",
            ),
            ("config.d/.hidden", "Host hidden\n"),
            // Applies only to hosts that match `work-*`.
            ("work.conf", "User worker\nHost work-db\n  Port 5433\n"),
        ],
    );
    let config = load(&paths);
    assert_eq!(config.aliases(), ["git", "ci", "work-db", "personal"]);
    assert_eq!(config.resolve("ci").user.as_deref(), Some("ci"));
    assert_eq!(config.resolve("work-db").user.as_deref(), Some("worker"));
    assert_eq!(config.resolve("work-db").port, Some(5433));
    // `User worker` sits in the `work-*` block, not before `Host personal`.
    assert_eq!(config.resolve("personal").user.as_deref(), Some("me"));
    assert_eq!(config.resolve("git").user, None);
}

#[test]
fn an_include_loop_stops_at_the_depth_limit() {
    let (_dir, paths) = home("Include config\nHost a\n", &[]);
    let config = load(&paths);
    assert!(
        config
            .warnings
            .iter()
            .any(|w| matches!(w, Warning::IncludeTooDeep { .. }))
    );
    assert_eq!(config.aliases(), ["a"]);
}

#[test]
fn routes_agents_and_policies() {
    let (_dir, paths) = home(
        r#"
Host bastion
    HostName bastion.example.com
    User jump
    IdentityFile ~/.ssh/bastion

Host inner
    HostName 10.0.0.5
    ProxyJump bastion
    ProxyCommand nc %h %p

Host deep
    HostName 10.0.0.6
    ProxyJump bastion,ops@edge.example.com:2222,inner

Host legacy
    ProxyCommand ssh -W %h:%p "jump host" # verbatim, comment included
    ProxyJump bastion

Host direct
    ProxyJump none

Host vault
    HostName vault.example.com
    IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    IdentitiesOnly yes
    ForwardAgent yes
    SetEnv LANG=C.UTF-8 TZ=UTC
    SetEnv IGNORED=1
    StrictHostKeyChecking no

Host *
    IdentityAgent none
    StrictHostKeyChecking yes
"#,
        &[],
    );
    let config = load(&paths);
    assert_eq!(
        config
            .warnings
            .iter()
            .filter(|w| matches!(w, Warning::Stricter { .. }))
            .count(),
        1
    );
    let imported = import(&config);
    let host = |alias: &str| {
        imported
            .hosts
            .iter()
            .find(|(_, h)| h.label == alias)
            .unwrap_or_else(|| panic!("{alias} not imported"))
    };
    let (bastion_id, _) = host("bastion");
    let (inner_id, inner) = host("inner");
    assert_eq!(inner.address, "10.0.0.5");
    assert_eq!(
        inner.source,
        Some(Source::SshConfig {
            alias: "inner".into(),
            extra: Default::default(),
        })
    );
    // ProxyJump came first, so the ProxyCommand below it is ignored.
    assert_eq!(
        inner.settings.route,
        Some(Route::Jump(vec![Jump::Host(*bastion_id)]))
    );

    let (_, deep) = host("deep");
    assert_eq!(
        deep.settings.route,
        Some(Route::Jump(vec![
            Jump::Host(*bastion_id),
            Jump::Address {
                host: "edge.example.com".into(),
                user: Some("ops".into()),
                port: Some(2222),
                extra: Default::default(),
            },
            Jump::Host(*inner_id),
        ]))
    );

    let (_, legacy) = host("legacy");
    assert_eq!(
        legacy.settings.route,
        Some(Route::Command(
            r#"ssh -W %h:%p "jump host" # verbatim, comment included"#.into()
        ))
    );
    assert_eq!(host("direct").1.settings.route, Some(Route::Direct));

    let (_, vault) = host("vault");
    assert_eq!(
        vault.settings.agent,
        Some(Agent::Socket(
            "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock".into()
        ))
    );
    assert_eq!(vault.settings.identities_only, Some(true));
    assert_eq!(vault.settings.agent_forward, Some(true));
    let env = vault.settings.env.as_ref().unwrap();
    assert_eq!(env.len(), 2);
    assert_eq!(env["LANG"], "C.UTF-8");
    assert_eq!(
        vault.settings.host_key_policy,
        Some(HostKeyPolicy::AcceptNew)
    );

    assert_eq!(host("bastion").1.settings.agent, Some(Agent::Off));
    assert_eq!(
        host("bastion").1.settings.host_key_policy,
        Some(HostKeyPolicy::Strict)
    );
}

#[test]
fn a_jump_that_loses_settings_is_reported() {
    let (_dir, paths) = home(
        "
Host web
    ProxyJump gateway.example.com
Host *.example.com
    User gw
    IdentityFile ~/.ssh/gateway
",
        &[],
    );
    let imported = import(&load(&paths));
    let (_, web) = &imported.hosts[0];
    assert_eq!(
        web.settings.route,
        Some(Route::Jump(vec![Jump::Address {
            host: "gateway.example.com".into(),
            user: Some("gw".into()),
            port: None,
            extra: Default::default(),
        }]))
    );
    assert!(imported.warnings.iter().any(
        |w| matches!(w, Warning::JumpLossy { alias, jump } if alias == "web" && jump == "gateway.example.com")
    ));
}

#[test]
fn unsupported_lines_are_reported_once_and_match_blocks_skipped() {
    let (_dir, paths) = home(
        "
Host a
    Compression yes
    Port nope
Host b
    Compression no
    UseKeychain yes
Match host b exec \"true\"
    User matched
Match all
    User everyone
",
        &[],
    );
    let config = load(&paths);
    let unsupported: Vec<&str> = config
        .warnings
        .iter()
        .filter_map(|w| match w {
            Warning::Unsupported { keyword, .. } => Some(keyword.as_str()),
            _ => None,
        })
        .collect();
    assert_eq!(unsupported, ["Compression", "UseKeychain"]);
    assert!(
        config
            .warnings
            .iter()
            .any(|w| matches!(w, Warning::Match { at } if at.line == 8))
    );
    assert!(
        config
            .warnings
            .iter()
            .any(|w| matches!(w, Warning::BadValue { keyword, .. } if keyword == "Port"))
    );
    assert_eq!(config.resolve("b").user.as_deref(), Some("everyone"));
}

/// `UserKnownHostsFile` and `GlobalKnownHostsFile`: every file of the
/// first line that applies; `none` is none.
#[test]
fn known_hosts_files_are_imported() {
    let (_dir, paths) = home(
        "
Host lab
    UserKnownHostsFile ~/.ssh/known_hosts_lab /work/known_hosts
Host scratch
    UserKnownHostsFile none
    GlobalKnownHostsFile /dev/null
Host *
    UserKnownHostsFile ~/.ssh/known_hosts
",
        &[],
    );
    let config = load(&paths);
    let lab = config.resolve("lab");
    assert_eq!(
        lab.known_hosts_files,
        Some(vec![
            "~/.ssh/known_hosts_lab".to_owned(),
            "/work/known_hosts".to_owned()
        ])
    );
    assert_eq!(lab.global_known_hosts_files, None);
    let scratch = config.resolve("scratch");
    assert_eq!(scratch.known_hosts_files, Some(vec![]));
    assert_eq!(
        scratch.global_known_hosts_files,
        Some(vec!["/dev/null".to_owned()])
    );
    let imported = import(&config);
    let lab = imported
        .hosts
        .iter()
        .find(|(_, h)| h.label == "lab")
        .unwrap();
    assert_eq!(
        lab.1.settings.known_hosts_files.as_deref(),
        Some(
            &[
                "~/.ssh/known_hosts_lab".to_owned(),
                "/work/known_hosts".to_owned()
            ][..]
        )
    );
    assert!(imported.warnings.is_empty(), "{:?}", imported.warnings);
}

/// `HostKeyAlgorithms +ssh-rsa` lets an old server in; nothing else of the
/// list is imported.
#[test]
fn old_host_keys_are_allowed_where_the_config_does() {
    let (_dir, paths) = home(
        "
Host old
    HostKeyAlgorithms +ssh-rsa,ssh-dss
Host listed
    HostKeyAlgorithms ssh-ed25519,ssh-rsa
Host modern
    HostKeyAlgorithms ssh-ed25519
    ConnectTimeout 5
Host removed
    HostKeyAlgorithms -ssh-rsa
",
        &[],
    );
    let config = load(&paths);
    assert_eq!(config.resolve("old").legacy_host_keys, Some(true));
    assert_eq!(config.resolve("listed").legacy_host_keys, Some(true));
    assert_eq!(config.resolve("modern").legacy_host_keys, None);
    assert_eq!(config.resolve("modern").connect_timeout_secs, Some(5));
    assert_eq!(config.resolve("removed").legacy_host_keys, None);
    let imported = import(&config);
    let old = imported
        .hosts
        .iter()
        .find(|(_, h)| h.label == "old")
        .unwrap();
    assert_eq!(old.1.settings.legacy_host_keys, Some(true));
}

#[test]
fn a_missing_config_imports_nothing() {
    let dir = tempfile::tempdir().unwrap();
    let paths = Paths::new(dir.path());
    let config = SshConfig::load(&paths.user_config(), &paths);
    assert!(config.aliases().is_empty());
    assert!(config.warnings.is_empty());
    assert!(import(&config).hosts.is_empty());
}

/// What the importer returns goes into the vault as one batch, in a group,
/// with jumps pointing at the imported hosts.
#[test]
fn an_import_goes_into_the_vault() {
    let (_dir, paths) = home(
        "
Host bastion
    HostName bastion.example.com
Host app
    ProxyJump bastion
",
        &[],
    );
    let imported = import(&load(&paths));
    let mut vault = Vault::open_in_memory().unwrap();
    let group = ItemId::new();
    let mut items = vec![(
        group,
        Data::Group(Group {
            name: "~/.ssh/config".into(),
            ..Group::default()
        }),
    )];
    items.extend(imported.hosts.into_iter().map(|(id, mut h)| {
        h.group = Some(group);
        (id, Data::Host(h))
    }));
    vault.create_all(items).unwrap();

    let (app, _) = vault
        .hosts()
        .into_iter()
        .find(|(_, h)| h.label == "app")
        .unwrap();
    let (bastion, _) = vault
        .hosts()
        .into_iter()
        .find(|(_, h)| h.label == "bastion")
        .unwrap();
    assert_eq!(vault.jump_users(bastion), [app]);
    assert_eq!(
        vault.effective(app).unwrap().settings.route,
        Some(Route::Jump(vec![Jump::Host(bastion)]))
    );
}

#[test]
fn forwards_become_tunnels_that_open_on_connect() {
    use openward_proto::ForwardKind;
    let (_dir, paths) = home(
        "
Host db
    HostName db.internal
    LocalForward 5433 10.0.4.21:5432
    LocalForward 127.0.0.1:8080 [::1]:80
    DynamicForward *:1080

Host web
    RemoteForward 8080 localhost:5173
    RemoteForward 9000:localhost:9001
    # Not supported: a SOCKS proxy on the server, and a Unix socket.
    RemoteForward 1081
    LocalForward /tmp/s.sock /var/run/docker.sock

Host *
    LocalForward 5050 localhost:80
",
        &[],
    );
    let config = load(&paths);
    let db = config.resolve("db");
    let spec = |kind, bind: Option<&str>, port, dest: Option<(&str, u16)>| {
        openward_import::ssh_config::ForwardSpec {
            kind,
            bind: bind.map(str::to_owned),
            port,
            dest: dest.map(|(h, p)| (h.to_owned(), p)),
        }
    };
    assert_eq!(
        db.forwards,
        [
            spec(ForwardKind::Local, None, 5433, Some(("10.0.4.21", 5432))),
            spec(
                ForwardKind::Local,
                Some("127.0.0.1"),
                8080,
                Some(("::1", 80))
            ),
            spec(ForwardKind::Dynamic, Some("*"), 1080, None),
            // From `Host *` too: forwards add up.
            spec(ForwardKind::Local, None, 5050, Some(("localhost", 80))),
        ]
    );
    let web = config.resolve("web");
    assert_eq!(
        web.forwards[..2],
        [
            spec(ForwardKind::Remote, None, 8080, Some(("localhost", 5173))),
            spec(ForwardKind::Remote, None, 9000, Some(("localhost", 9001))),
        ]
    );
    let bad: Vec<_> = config
        .warnings
        .iter()
        .filter_map(|w| match w {
            Warning::BadValue { keyword, .. } => Some(keyword.as_str()),
            _ => None,
        })
        .collect();
    assert_eq!(bad, ["RemoteForward", "LocalForward"]);

    let imported = import(&config);
    let db_id = imported
        .hosts
        .iter()
        .find(|(_, h)| h.label == "db")
        .unwrap()
        .0;
    let tunnels: Vec<_> = imported
        .forwards
        .iter()
        .filter(|f| f.host == db_id)
        .map(|f| (f.label.as_str(), f.autostart))
        .collect();
    assert_eq!(
        tunnels,
        [
            ("5433 → 10.0.4.21:5432", true),
            ("8080 → ::1:80", true),
            ("SOCKS 1080", true),
            ("5050 → localhost:80", true),
        ]
    );
    assert_eq!(
        imported.forwards[0].source,
        Some(Source::SshConfig {
            alias: "db".into(),
            extra: Default::default(),
        })
    );
}
