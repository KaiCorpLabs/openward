//! From a saved host to the hops a connection goes through, with every
//! setting resolved and expanded.
//!
//! A host whose route jumps through other hosts gets their chains first: a
//! jump through a saved host brings that host's own route and settings
//! along. A `ProxyCommand` only applies to the first hop; further in, a host
//! is reached through the hop before it.

use std::path::PathBuf;
use std::time::Duration;

use openward_vault::proto::{Agent, HostKeyPolicy, ItemId, Jump, Route, Settings};
use openward_vault::{Vault, defaults};

use crate::local::{Local, Tokens};

/// More than this is a mistake, not a network.
const MAX_HOPS: usize = 16;

/// Keys OpenSSH tries when no `IdentityFile` is set, in its order (the
/// ones that exist).
const DEFAULT_KEYS: &[&str] = &["id_ed25519", "id_ecdsa", "id_rsa"];

#[derive(Clone, Debug, PartialEq)]
pub struct Hop {
    /// What the UI calls this hop: the host's label, or the address.
    pub label: String,
    pub host: Option<ItemId>,
    pub address: String,
    pub port: u16,
    pub user: String,
    /// Private keys to try, in order; missing files are skipped.
    pub identity_files: Vec<PathBuf>,
    pub certificate_files: Vec<PathBuf>,
    pub identities_only: bool,
    pub agent: Option<PathBuf>,
    /// Only on the first hop.
    pub proxy_command: Option<String>,
    pub keepalive: Option<Duration>,
    pub host_key_policy: HostKeyPolicy,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Plan {
    /// Jump hosts first, the target last.
    pub hops: Vec<Hop>,
    pub term: String,
    pub env: Vec<(String, String)>,
    /// Forward the target's agent requests to the last hop's agent.
    pub agent_forward: bool,
}

#[derive(Debug, thiserror::Error)]
pub enum PlanError {
    #[error(transparent)]
    Vault(#[from] openward_vault::Error),
    #[error("the jumps of {0} go round in a loop")]
    JumpLoop(String),
    #[error("too many jumps")]
    TooManyHops,
}

impl Plan {
    pub fn for_host(vault: &Vault, host: ItemId, local: &Local) -> Result<Self, PlanError> {
        let mut hops = Vec::new();
        chain(vault, host, local, &mut Vec::new(), &mut hops)?;
        let settings = vault.effective(host)?.settings;
        let target = hops.last().expect("the chain ends with the host");
        Ok(Self {
            term: settings.term.unwrap_or_else(|| "xterm-256color".into()),
            env: settings.env.unwrap_or_default().into_iter().collect(),
            agent_forward: settings.agent_forward.unwrap_or(false) && target.agent.is_some(),
            hops,
        })
    }
}

fn chain(
    vault: &Vault,
    id: ItemId,
    local: &Local,
    visiting: &mut Vec<ItemId>,
    hops: &mut Vec<Hop>,
) -> Result<(), PlanError> {
    let host = vault.host(id)?;
    if visiting.contains(&id) {
        return Err(PlanError::JumpLoop(host.label.clone()));
    }
    visiting.push(id);
    let settings = vault.effective(id)?.settings;
    if let Some(Route::Jump(jumps)) = &settings.route {
        for jump in jumps {
            match jump {
                Jump::Host(jid) => chain(vault, *jid, local, visiting, hops)?,
                Jump::Address { host, user, port } => {
                    let bare = Settings {
                        user: user.clone(),
                        port: *port,
                        ..defaults()
                    };
                    hops.push(hop(host, None, host, &bare, local, hops.is_empty()));
                }
            }
            if hops.len() > MAX_HOPS {
                return Err(PlanError::TooManyHops);
            }
        }
    }
    hops.push(hop(
        &host.label,
        Some(id),
        &host.address,
        &settings,
        local,
        hops.is_empty(),
    ));
    visiting.pop();
    Ok(())
}

/// One hop from complete settings (defaults included).
fn hop(
    label: &str,
    host: Option<ItemId>,
    address: &str,
    s: &Settings,
    local: &Local,
    first: bool,
) -> Hop {
    let user = s.user.clone().unwrap_or_else(|| local.user.clone());
    let port = s.port.unwrap_or(22);
    let t = Tokens {
        host: address,
        port,
        user: &user,
        alias: label,
    };
    let identity_files = match &s.identity_files {
        Some(files) => files.iter().map(|f| local.path(f, &t)).collect(),
        None => DEFAULT_KEYS.iter().map(|k| local.ssh_dir.join(k)).collect(),
    };
    let agent = match s.agent.as_ref().unwrap_or(&Agent::System) {
        Agent::Off => None,
        Agent::System => local.agent.clone(),
        Agent::Socket(path) => Some(local.path(path, &t)),
    };
    let proxy_command = match &s.route {
        Some(Route::Command(c)) if first => Some(local.command(c, &t)),
        _ => None,
    };
    Hop {
        label: label.to_owned(),
        host,
        address: address.to_owned(),
        port,
        identity_files,
        certificate_files: s
            .certificate_files
            .iter()
            .flatten()
            .map(|f| local.path(f, &t))
            .collect(),
        identities_only: s.identities_only.unwrap_or(false),
        agent,
        proxy_command,
        keepalive: s
            .keepalive_secs
            .filter(|&k| k > 0)
            .map(|k| Duration::from_secs(u64::from(k))),
        host_key_policy: s.host_key_policy.unwrap_or(HostKeyPolicy::Ask),
        user,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use openward_vault::proto::{Data, Group, Host};

    fn local() -> Local {
        Local {
            home: PathBuf::from("/home/ana"),
            user: "ana".into(),
            ssh_dir: PathBuf::from("/home/ana/.ssh"),
            agent: Some(PathBuf::from("/tmp/agent.sock")),
        }
    }

    fn host(v: &mut Vault, label: &str, group: Option<ItemId>, settings: Settings) -> ItemId {
        v.create(Data::Host(Host {
            label: label.into(),
            address: format!("{label}.example.com"),
            group,
            settings,
            ..Host::default()
        }))
        .unwrap()
    }

    #[test]
    fn a_direct_host_gets_defaults_and_inherited_settings() {
        let mut v = Vault::open_in_memory().unwrap();
        let g = v
            .create(Data::Group(Group {
                name: "prod".into(),
                settings: Settings {
                    user: Some("deploy".into()),
                    identity_files: Some(vec!["~/.ssh/prod_%n".into()]),
                    env: Some([("LANG".to_owned(), "C.UTF-8".to_owned())].into()),
                    agent_forward: Some(true),
                    ..Settings::default()
                },
                ..Group::default()
            }))
            .unwrap();
        let web = host(&mut v, "web", Some(g), Settings::default());
        let plan = Plan::for_host(&v, web, &local()).unwrap();
        assert_eq!(plan.hops.len(), 1);
        let hop = &plan.hops[0];
        assert_eq!((hop.address.as_str(), hop.port), ("web.example.com", 22));
        assert_eq!(hop.user, "deploy");
        assert_eq!(
            hop.identity_files,
            [PathBuf::from("/home/ana/.ssh/prod_web")]
        );
        assert_eq!(hop.agent, Some(PathBuf::from("/tmp/agent.sock")));
        assert_eq!(hop.keepalive, Some(Duration::from_secs(30)));
        assert_eq!(hop.host_key_policy, HostKeyPolicy::Ask);
        assert_eq!(plan.env, [("LANG".to_owned(), "C.UTF-8".to_owned())]);
        assert!(plan.agent_forward);
        assert_eq!(plan.term, "xterm-256color");

        let bare = host(&mut v, "bare", None, Settings::default());
        let hop = &Plan::for_host(&v, bare, &local()).unwrap().hops[0];
        assert_eq!(hop.user, "ana");
        assert_eq!(
            hop.identity_files[0],
            PathBuf::from("/home/ana/.ssh/id_ed25519")
        );
    }

    #[test]
    fn jumps_bring_their_own_chains() {
        let mut v = Vault::open_in_memory().unwrap();
        let edge = host(
            &mut v,
            "edge",
            None,
            Settings {
                route: Some(Route::Command(
                    "cloudflared access ssh --hostname %h".into(),
                )),
                ..Settings::default()
            },
        );
        let bastion = host(
            &mut v,
            "bastion",
            None,
            Settings {
                user: Some("jump".into()),
                route: Some(Route::Jump(vec![Jump::Host(edge)])),
                ..Settings::default()
            },
        );
        let db = host(
            &mut v,
            "db",
            None,
            Settings {
                route: Some(Route::Jump(vec![
                    Jump::Host(bastion),
                    Jump::Address {
                        host: "10.0.0.9".into(),
                        user: Some("ops".into()),
                        port: Some(2200),
                    },
                ])),
                agent: Some(Agent::Off),
                agent_forward: Some(true),
                ..Settings::default()
            },
        );
        let plan = Plan::for_host(&v, db, &local()).unwrap();
        let labels: Vec<&str> = plan.hops.iter().map(|h| h.label.as_str()).collect();
        assert_eq!(labels, ["edge", "bastion", "10.0.0.9", "db"]);
        assert_eq!(
            plan.hops[0].proxy_command.as_deref(),
            Some("cloudflared access ssh --hostname edge.example.com")
        );
        assert_eq!(plan.hops[1].user, "jump");
        assert_eq!(plan.hops[1].proxy_command, None);
        assert_eq!(
            (plan.hops[2].user.as_str(), plan.hops[2].port),
            ("ops", 2200)
        );
        assert_eq!(plan.hops[3].agent, None);
        // No agent to forward.
        assert!(!plan.agent_forward);
    }

    #[test]
    fn a_proxy_command_further_in_is_ignored() {
        let mut v = Vault::open_in_memory().unwrap();
        let cmd = host(
            &mut v,
            "cmd",
            None,
            Settings {
                route: Some(Route::Command("nc %h %p".into())),
                ..Settings::default()
            },
        );
        let target = host(
            &mut v,
            "target",
            None,
            Settings {
                route: Some(Route::Jump(vec![
                    Jump::Address {
                        host: "first".into(),
                        user: None,
                        port: None,
                    },
                    Jump::Host(cmd),
                ])),
                ..Settings::default()
            },
        );
        let plan = Plan::for_host(&v, target, &local()).unwrap();
        assert!(plan.hops.iter().all(|h| h.proxy_command.is_none()));
    }

    #[test]
    fn a_jump_loop_is_an_error() {
        let mut v = Vault::open_in_memory().unwrap();
        let a = host(&mut v, "a", None, Settings::default());
        let b = host(
            &mut v,
            "b",
            None,
            Settings {
                route: Some(Route::Jump(vec![Jump::Host(a)])),
                ..Settings::default()
            },
        );
        let Data::Host(mut ha) = v.get(a).unwrap().body.data.clone() else {
            unreachable!()
        };
        ha.settings.route = Some(Route::Jump(vec![Jump::Host(b)]));
        v.update(a, 1, Data::Host(ha)).unwrap();
        assert!(matches!(
            Plan::for_host(&v, b, &local()),
            Err(PlanError::JumpLoop(_))
        ));
    }
}
