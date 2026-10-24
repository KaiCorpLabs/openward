//! A vault as OpenWard 0.3.0 writes it: one item of each type, with every
//! field it knows set. `make.sh` runs it from the tag.

use std::collections::BTreeMap;
use std::path::Path;

use openward_vault::Vault;
use openward_vault::proto::*;

const KEY: &str =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg+ccEU+buKk8f5ORMPyzCAzWM04Omv+MOaI8CvGd7f";

fn imported(from: &str, id: &str) -> Option<Imported> {
    Some(Imported {
        from: from.into(),
        id: id.into(),
    })
}

fn main() {
    let path = std::env::args().nth(1).expect("usage: fixture <vault.sqlite>");
    let mut v = Vault::open(Path::new(&path)).unwrap();
    let deploy = v
        .create(Data::Identity(Identity {
            label: "deploy".into(),
            settings: Settings {
                user: Some("deploy".into()),
                identity_files: Some(vec!["~/.ssh/id_deploy".into()]),
                certificate_files: Some(vec!["~/.ssh/id_deploy-cert.pub".into()]),
                identities_only: Some(true),
                agent: Some(Agent::Socket("~/agent.sock".into())),
                ..Settings::default()
            },
            imported: imported("termius", "7"),
            ..Identity::default()
        }))
        .unwrap();
    let prod = v
        .create(Data::Group(Group {
            name: "prod".into(),
            settings: Settings {
                user: Some("ops".into()),
                keepalive_secs: Some(30),
                proxy: Some(Proxy::Socks5(ProxyServer {
                    host: "proxy.example.com".into(),
                    port: 1080,
                    user: Some("ana".into()),
                })),
                identity: Some(UseIdentity::Id(deploy)),
                host_key_policy: Some(HostKeyPolicy::Strict),
                ..Settings::default()
            },
            imported: imported("termius", "1"),
            ..Group::default()
        }))
        .unwrap();
    let eu = v
        .create(Data::Group(Group {
            name: "eu".into(),
            parent: Some(prod),
            ..Group::default()
        }))
        .unwrap();
    let bastion = v
        .create(Data::Host(Host {
            label: "bastion".into(),
            address: "bastion.example.com".into(),
            group: Some(prod),
            ..Host::default()
        }))
        .unwrap();
    let web = v
        .create(Data::Host(Host {
            label: "web".into(),
            address: "web.example.com".into(),
            group: Some(eu),
            tags: vec!["web".into(), "eu".into()],
            notes: Some("La web pública".into()),
            source: Some(Source::SshConfig {
                alias: "web".into(),
            }),
            settings: Settings {
                port: Some(2222),
                route: Some(Route::Jump(vec![
                    Jump::Host(bastion),
                    Jump::Address {
                        host: "10.0.0.1".into(),
                        user: Some("jump".into()),
                        port: Some(2200),
                    },
                ])),
                agent_forward: Some(true),
                term: Some("xterm-256color".into()),
                env: Some(BTreeMap::from([("LANG".into(), "C.UTF-8".into())])),
                identity: Some(UseIdentity::None),
                ..Settings::default()
            },
            ..Host::default()
        }))
        .unwrap();
    v.create(Data::Host(Host {
        label: "db".into(),
        address: "db.internal".into(),
        settings: Settings {
            route: Some(Route::Command(
                "cloudflared access ssh --hostname %h".into(),
            )),
            agent: Some(Agent::Off),
            proxy: Some(Proxy::None),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
        imported: imported("putty", "db"),
        ..Host::default()
    }))
    .unwrap();
    v.create(Data::PortForward(PortForward {
        label: "postgres".into(),
        host: web,
        kind: ForwardKind::Local,
        listen_port: 5432,
        listen_address: Some("127.0.0.1".into()),
        dest_host: Some("localhost".into()),
        dest_port: Some(5432),
        autostart: true,
        source: Some(Source::SshConfig {
            alias: "web".into(),
        }),
        imported: None,
        extra: Extra::new(),
    }))
    .unwrap();
    v.create(Data::PortForward(PortForward {
        label: "socks".into(),
        host: bastion,
        kind: ForwardKind::Dynamic,
        listen_port: 1080,
        listen_address: None,
        dest_host: None,
        dest_port: None,
        autostart: false,
        source: None,
        imported: imported("termius", "9"),
        extra: Extra::new(),
    }))
    .unwrap();
    v.create(Data::Snippet(Snippet {
        label: "Reiniciar".into(),
        script: "sudo systemctl restart {{servicio}}".into(),
        defaults: BTreeMap::from([("servicio".into(), "nginx".into())]),
        type_only: true,
        imported: imported("termius", "3"),
        extra: Extra::new(),
    }))
    .unwrap();
    let pane = |target: Target, active: bool| PaneLayout {
        target: Some(target),
        split: None,
        active,
        extra: Extra::new(),
    };
    v.create(Data::Workspace(Workspace {
        name: "Mañana".into(),
        tabs: vec![
            WorkspaceTab {
                title: Some("web y raíz".into()),
                panes: Some(PaneLayout {
                    target: None,
                    split: Some(Box::new(PaneSplit {
                        vertical: true,
                        ratio: 0.4,
                        first: pane(
                            Target {
                                host: Some(web),
                                ..Target::default()
                            },
                            true,
                        ),
                        second: pane(
                            Target {
                                address: Some("10.0.0.9".into()),
                                user: Some("root".into()),
                                port: Some(22),
                                ..Target::default()
                            },
                            false,
                        ),
                        extra: Extra::new(),
                    })),
                    active: false,
                    extra: Extra::new(),
                }),
                sftp: None,
                extra: Extra::new(),
            },
            WorkspaceTab {
                title: None,
                panes: None,
                sftp: Some(Target {
                    host: Some(bastion),
                    ..Target::default()
                }),
                extra: Extra::new(),
            },
        ],
        active: 1,
        extra: Extra::new(),
    }))
    .unwrap();
    v.trust_host_key("web.example.com", 2222, KEY).unwrap();
    v.create(Data::KnownHost(KnownHost {
        hosts: "*.example.com".into(),
        key: KEY.into(),
        marker: Some(Marker::CertAuthority),
        comment: Some("ops CA".into()),
        ..KnownHost::default()
    }))
    .unwrap();
}
