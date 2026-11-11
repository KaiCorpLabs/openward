//! Running a [`Plan`]: hop by hop, trusting host keys by policy and
//! authenticating the way OpenSSH does, asking the user when needed.
//!
//! Authentication order per hop:
//! 1. `none`, which also tells which methods the server takes;
//! 2. public keys: the agent's keys that match an identity file, the
//!    agent's other keys (unless `IdentitiesOnly`), then the identity files
//!    not offered through the agent, each with its certificate first if it
//!    has one (`CertificateFile`, or `<key>-cert.pub`);
//! 3. keyboard-interactive, with the questions shown to the user;
//! 4. password.
//!
//! A method the server accepts only in part ("partial success") moves on to
//! the next one, which is how publickey + 2FA works.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use openward_ssh::client::{
    self as ssh, Agent, AgentRefused, Hop as Transport, HostKeyHook, HostKeyQuery, Kbd, KeyError,
    Options, Outcome, Session, Target, UntrustedHost,
};
use openward_ssh::known_hosts::{KnownHosts, Unknown, Verdict};
use openward_ssh::proxy::ProxyAuthRequired;
use openward_ssh::russh::MethodKind;
use openward_ssh::russh::keys::{Certificate, HashAlg, PrivateKey, PublicKey};
use openward_vault::Vault;
use openward_vault::proto::{Data, HostKeyPolicy, ItemId};
use zeroize::Zeroizing;

use crate::events::{
    Answer, ChangedKey, Event, EventSink, Failure, KeySource, PreviousKey, Prompt, Prompts,
    Question, Stage,
};
use crate::live::Registry;
use crate::local::Local;
use crate::plan::{Hop, Plan};
use crate::system;
use crate::tunnels::Tunnels;

/// Everything a connection needs from the app.
#[derive(Clone)]
pub(crate) struct Ctx {
    pub vault: Arc<Mutex<Vault>>,
    pub local: Local,
    /// What talks to security keys: the one plugged in.
    pub security_keys: Arc<dyn openward_fido::Authenticator>,
    pub prompts: Arc<Prompts>,
    pub sink: Arc<dyn EventSink>,
    /// Connections that are up, to share.
    pub live: Arc<Registry>,
    pub tunnels: Arc<Tunnels>,
    pub runtime: tokio::runtime::Handle,
}

impl Ctx {
    /// Tells the system of each saved host of a new connection (the jumps
    /// too) and stores it where it changed, in the background: from the
    /// banner, and from `/etc/os-release` where the host asks for it.
    pub fn learn_systems(&self, plan: &Plan, live: &Arc<crate::live::Live>) {
        let plan = plan.clone();
        let live = Arc::clone(live);
        let vault = Arc::clone(&self.vault);
        let sink = Arc::clone(&self.sink);
        self.runtime.spawn(async move {
            let learned = learn_systems(&vault, &plan, &live).await;
            if learned.changed {
                sink.send(Event::HostsChanged {
                    unknown: learned.unknown,
                });
            }
        });
    }

    /// Opens on a new connection the tunnels of its host that open on
    /// connect.
    pub async fn autostart(&self, plan: &Plan, live: &Arc<crate::live::Live>) {
        let Some(host) = plan.hops.last().and_then(|h| h.host) else {
            return;
        };
        let forwards: Vec<_> = lock(&self.vault)
            .port_forwards()
            .into_iter()
            .filter(|(_, f)| f.host == host && f.autostarts())
            .map(|(id, f)| (id, f.clone()))
            .collect();
        if !forwards.is_empty() {
            self.tunnels.autostart(live, forwards).await;
        }
    }
}

/// What telling the systems of a connection changed.
pub(crate) struct Learned {
    /// Something was stored.
    pub changed: bool,
    /// Saved hosts that were just found not to tell their system, and that
    /// do not read `/etc/os-release`: the app can offer to.
    pub unknown: Vec<ItemId>,
}

/// Tells the system of each saved host of `live` (the jumps too) and stores
/// it where it changed.
pub(crate) async fn learn_systems(
    vault: &Mutex<Vault>,
    plan: &Plan,
    live: &crate::live::Live,
) -> Learned {
    let mut learned = Learned {
        changed: false,
        unknown: Vec::new(),
    };
    let hops = plan
        .hops
        .iter()
        .zip(live.sessions())
        .filter_map(|(hop, s)| Some((hop.host?, hop.read_os_release, s)));
    for (host, read, session) in hops {
        let mut told = system::from_banner(&session.info().server_id);
        if read && told.code != "win" {
            let out = tokio::time::timeout(
                system::OS_RELEASE_WITHIN,
                session.exec_short(system::OS_RELEASE),
            )
            .await;
            if let Some(s) = out
                .ok()
                .and_then(Result::ok)
                .and_then(|out| system::from_os_release(&out.text()))
            {
                told = s;
            }
        }
        let mut vault = lock(vault);
        let Ok(h) = vault.host(host) else { continue };
        if let Some(system) = system::learned(h.system.as_ref(), told) {
            let unknown = system.code == system::UNKNOWN && !read;
            let mut h = h.clone();
            h.system = Some(system);
            let rev = vault.get(host).map_or(0, |item| item.rev);
            if vault.update(host, rev, Data::Host(h)).is_ok() {
                learned.changed = true;
                if unknown {
                    learned.unknown.push(host);
                }
            }
        }
    }
    learned
}

impl Ctx {
    async fn ask(&self, prompt: Prompt) -> Answer {
        self.prompts.ask(&self.sink, prompt).await
    }

    pub fn stage(&self, plan: &Plan, hop: usize, stage: Stage) {
        self.sink.send(Event::Stage {
            hop,
            hops: plan.hops.len(),
            label: plan.hops[hop].label.clone(),
            stage,
        });
    }

    /// The vault's trusted keys, and `~/.ssh/known_hosts`.
    /// OpenWard's trusted keys, and OpenSSH's in `files`.
    fn known_hosts(&self, files: &[PathBuf]) -> KnownTexts {
        let openssh = read_known_files(files);
        KnownTexts::of(&lock(&self.vault), openssh)
    }
}

fn read_known_files(files: &[PathBuf]) -> String {
    files
        .iter()
        .filter_map(|f| std::fs::read_to_string(f).ok())
        .collect::<Vec<_>>()
        .join("\n")
}

#[derive(Debug)]
enum KeyRefusal {
    Query(Box<HostKeyQuery>),
    Changed(Box<HostKeyQuery>, Vec<PreviousKey>),
    Save(String),
}

/// Revalidate under the vault's operation lock, after any user prompt.
/// Learning is not rotation: a stale Unknown snapshot may never replace
/// a key saved by another connection while this one was asking.
fn learn_key(vault: &mut Vault, openssh: &str, mut query: HostKeyQuery) -> Result<(), KeyRefusal> {
    use openward_ssh::russh::keys::PublicKeyOrCertificate;
    let texts = KnownTexts::of(vault, openssh.to_owned());
    let mut known = texts.known();
    let offered = PublicKeyOrCertificate::PublicKey {
        key: query.key.clone(),
        hash_alg: None,
    };
    let now = known.check(&query.host, query.port, &offered);
    if now == Verdict::Known {
        return Ok(());
    }
    if !matches!(now, Verdict::Unknown | Verdict::OtherType) || now != query.verdict {
        let previous =
            (now == Verdict::Changed).then(|| texts.previous(&query.host, query.port, &query.key));
        query.verdict = now;
        return Err(match previous {
            Some(previous) => KeyRefusal::Changed(Box::new(query), previous),
            None => KeyRefusal::Query(Box::new(query)),
        });
    }
    let key = query
        .key
        .to_openssh()
        .map_err(|e| KeyRefusal::Save(e.to_string()))?;
    vault
        .trust_host_key(&query.host, query.port, &key)
        .map_err(|e| KeyRefusal::Save(e.to_string()))?;
    Ok(())
}

#[derive(Default)]
struct KnownTexts {
    openward: String,
    openssh: String,
    local_pins: String,
}

impl KnownTexts {
    fn of(vault: &Vault, openssh: String) -> Self {
        let local_pins = vault
            .known_hosts()
            .into_iter()
            .filter(|(_, k)| {
                k.imported.is_none() && k.marker.is_none() && k.usable_for_connections()
            })
            .map(|(_, k)| k.to_line())
            .collect::<Vec<_>>()
            .join("\n");
        Self {
            openward: vault.known_hosts_text(),
            openssh,
            local_pins,
        }
    }

    fn known(&self) -> KnownHosts {
        KnownHosts::parse(&self.all(), Unknown::Reject).with_local_pins(&self.local_pins)
    }
    fn all(&self) -> String {
        format!("{}\n{}", self.openward, self.openssh)
    }

    /// What was trusted for `host:port` with the algorithm of `key`, and
    /// where it is written.
    fn previous(&self, host: &str, port: u16, key: &PublicKey) -> Vec<PreviousKey> {
        let mut out = Vec::new();
        for (text, source) in [
            (&self.openward, KeySource::OpenWard),
            (&self.openssh, KeySource::OpenSsh),
        ] {
            let known = KnownHosts::parse(text, Unknown::Reject);
            for k in known.listed(host, port) {
                if k.algorithm() == key.algorithm() {
                    out.push(PreviousKey {
                        fingerprint: k.fingerprint(HashAlg::Sha256).to_string(),
                        source,
                        key: k.to_openssh().expect("a parsed public key encodes"),
                    });
                }
            }
        }
        out
    }
}

pub(crate) fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// Authenticated sessions, jumps first; they must live as long as the last.
pub(crate) async fn run(plan: &Plan, ctx: &Ctx) -> Result<Vec<Session>, Failure> {
    ssh_hops(plan, ctx, plan.hops.len()).await
}

/// A Telnet plan's connection: its jumps by SSH, then the target's plain
/// stream, out of the last jump or the way the plan says. The sessions
/// must live as long as the stream.
pub(crate) async fn telnet(
    plan: &Plan,
    ctx: &Ctx,
) -> Result<(Vec<Session>, openward_ssh::client::Stream), Failure> {
    let last = plan.hops.len() - 1;
    let sessions = ssh_hops(plan, ctx, last).await?;
    ctx.stage(plan, last, Stage::Connecting);
    let hop = &plan.hops[last];
    let target = Target::new(&hop.address, hop.port);
    let mut proxy = hop.proxy.clone();
    let mut asked = 0;
    loop {
        let transport = match (sessions.last(), &hop.proxy_command, &proxy) {
            (Some(previous), _, _) => Transport::Via(previous),
            (None, Some(command), _) => Transport::ProxyCommand(command.clone()),
            (None, None, Some(p)) => Transport::Proxy(p.clone()),
            (None, None, None) => Transport::Tcp,
        };
        match openward_ssh::client::open_stream(&target, transport, hop.connect_timeout).await {
            Ok(stream) => return Ok((sessions, stream)),
            Err(e) if e.downcast_ref::<ProxyAuthRequired>().is_some() && asked < 3 => {
                let p = proxy.as_mut().expect("only a proxy asks");
                proxy_login(p, ctx, asked > 0).await?;
                asked += 1;
            }
            Err(e) => return Err(Failure::network(hop.label.clone(), &e)),
        }
    }
}

/// The first `count` hops of `plan`, by SSH.
async fn ssh_hops(plan: &Plan, ctx: &Ctx, count: usize) -> Result<Vec<Session>, Failure> {
    let mut sessions: Vec<Session> = Vec::with_capacity(count);
    for (i, hop) in plan.hops.iter().take(count).enumerate() {
        ctx.stage(plan, i, Stage::Connecting);
        let texts = ctx.known_hosts(&hop.known_hosts);
        let known = texts.all();
        let refused = Arc::new(Mutex::new(None));
        let last = i + 1 == count;
        let opts = Options {
            user: hop.user.clone(),
            known_hosts: Arc::new(Mutex::new(texts.known())),
            host_certificates: known.contains("@cert-authority"),
            legacy_host_keys: hop.legacy_host_keys,
            connect_timeout: hop.connect_timeout,
            keepalive: hop.keepalive,
            agent_forward: if last && plan.agent_forward {
                hop.agent.clone()
            } else {
                None
            },
            on_untrusted: Some(host_key_hook(hop, ctx, Arc::clone(&refused))),
        };
        let target = Target::new(&hop.address, hop.port);
        let mut proxy = hop.proxy.clone();
        let mut asked = 0;
        let mut session = loop {
            let transport = match (sessions.last(), &hop.proxy_command, &proxy) {
                (Some(previous), _, _) => Transport::Via(previous),
                (None, Some(command), _) => Transport::ProxyCommand(command.clone()),
                (None, None, Some(p)) => Transport::Proxy(p.clone()),
                (None, None, None) => Transport::Tcp,
            };
            match ssh::open(&target, transport, &opts).await {
                Ok(session) => break session,
                Err(e) if e.downcast_ref::<ProxyAuthRequired>().is_some() && asked < 3 => {
                    let p = proxy.as_mut().expect("only a proxy asks");
                    proxy_login(p, ctx, asked > 0).await?;
                    asked += 1;
                }
                Err(e) => return Err(open_failure(hop, &e, &refused, &texts)),
            }
        };
        ctx.stage(plan, i, Stage::Authenticating);
        authenticate(&mut session, hop, ctx, (i, plan.hops.len())).await?;
        sessions.push(session);
    }
    Ok(sessions)
}

/// Decides on keys `known_hosts` does not vouch for, by the hop's policy.
/// Refused queries are kept to explain the failure.
fn host_key_hook(hop: &Hop, ctx: &Ctx, refused: Arc<Mutex<Option<KeyRefusal>>>) -> HostKeyHook {
    let (ctx, policy, label) = (ctx.clone(), hop.host_key_policy, hop.label.clone());
    let files = hop.known_hosts.clone();
    Arc::new(move |q: HostKeyQuery| {
        let (ctx, refused, label) = (ctx.clone(), Arc::clone(&refused), label.clone());
        let files = files.clone();
        Box::pin(async move {
            let ask = |known_types: Vec<String>| Prompt::HostKey {
                label: label.clone(),
                host: q.host.clone(),
                port: q.port,
                algorithm: q.key.algorithm().to_string(),
                fingerprint: q.key.fingerprint(HashAlg::Sha256).to_string(),
                known_types,
            };
            let accept = match (&q.verdict, policy) {
                (Verdict::Unknown, HostKeyPolicy::AcceptNew) => true,
                (Verdict::Unknown, HostKeyPolicy::Ask) => {
                    matches!(ctx.ask(ask(Vec::new())).await, Answer::Accept)
                }
                // Known by other keys: asked even where new hosts are not.
                (Verdict::OtherType, HostKeyPolicy::Ask | HostKeyPolicy::AcceptNew) => {
                    matches!(ctx.ask(ask(q.known_types.clone())).await, Answer::Accept)
                }
                // Strict, a changed key, a bad certificate, a revoked key.
                _ => false,
            };
            if accept {
                let openssh = read_known_files(&files);
                if let Err(why) = learn_key(&mut lock(&ctx.vault), &openssh, q) {
                    *lock(&refused) = Some(why);
                    return false;
                }
            } else {
                *lock(&refused) = Some(KeyRefusal::Query(Box::new(q)));
            }
            accept
        })
    })
}

/// Asks for the proxy's password (and its user, if none is set) into `p`.
async fn proxy_login(
    p: &mut openward_ssh::proxy::Proxy,
    ctx: &Ctx,
    retry: bool,
) -> Result<(), Failure> {
    let prompt = Prompt::ProxyLogin {
        proxy: p.address(),
        user: p.user.clone().unwrap_or_default(),
        retry,
    };
    let Answer::Text(texts) = ctx.ask(prompt).await else {
        return Err(Failure::Cancelled);
    };
    let mut texts = texts.into_iter();
    if p.user.as_deref().is_none_or(str::is_empty) {
        p.user = texts.next().map(|u| u.as_str().to_owned());
    }
    p.password = texts.next();
    Ok(())
}

fn open_failure(
    hop: &Hop,
    error: &anyhow::Error,
    refused: &Mutex<Option<KeyRefusal>>,
    texts: &KnownTexts,
) -> Failure {
    let label = hop.label.clone();
    let Some(UntrustedHost(verdict)) = error.downcast_ref::<UntrustedHost>() else {
        return Failure::network(label, error);
    };
    let (query, previous) = match lock(refused).take() {
        Some(KeyRefusal::Save(why)) => {
            return Failure::Other(format!("{label}: could not save the host key: {why}"));
        }
        Some(KeyRefusal::Changed(query, previous)) => (Some(*query), Some(previous)),
        Some(KeyRefusal::Query(query)) => (Some(*query), None),
        None => (None, None),
    };
    // The revalidation may have superseded the connection's old snapshot.
    let verdict = query
        .as_ref()
        .map_or_else(|| verdict.clone(), |q| q.verdict.clone());
    match (&verdict, query) {
        (Verdict::Changed, Some(q)) => Failure::HostKeyChanged(Box::new(ChangedKey {
            label,
            previous: previous.unwrap_or_else(|| texts.previous(&q.host, q.port, &q.key)),
            host: q.host,
            port: q.port,
            algorithm: q.key.algorithm().to_string(),
            fingerprint: q.key.fingerprint(HashAlg::Sha256).to_string(),
            key: q.key.to_openssh().unwrap_or_default(),
        })),
        (Verdict::BadCertificate(problem), _) => Failure::BadCertificate {
            label,
            problem: *problem,
        },
        (Verdict::Revoked, q) => Failure::HostKeyRevoked {
            label,
            fingerprint: q
                .map(|q| q.key.fingerprint(HashAlg::Sha256).to_string())
                .unwrap_or_default(),
        },
        _ => Failure::HostKeyRejected { label },
    }
}

fn network(hop: &Hop) -> impl Fn(anyhow::Error) -> Failure + '_ {
    move |e| Failure::network(hop.label.clone(), &e)
}

/// The method failed outright: try the next one.
fn rejected(outcome: &Outcome) -> bool {
    matches!(outcome, Outcome::Continue { partial: false, .. })
}

/// Logs in to `hop`, the `at.0`-th of `at.1` (for the stages it tells).
async fn authenticate(
    s: &mut Session,
    hop: &Hop,
    ctx: &Ctx,
    at: (usize, usize),
) -> Result<(), Failure> {
    let user = hop.user.as_str();
    let mut methods = match s.auth_none(user).await.map_err(network(hop))? {
        Outcome::Success => return Ok(()),
        Outcome::Continue { methods, .. } => methods,
    };
    // Why it failed, likely: a key's certificate that had run out, a
    // security key that did not sign.
    let mut why = Why::default();
    let failed = |methods: &[MethodKind], why: &Why| Failure::AuthFailed {
        label: hop.label.clone(),
        user: user.to_owned(),
        methods: methods.iter().map(|m| <&str>::from(m).to_owned()).collect(),
        expired_certificate: why.expired.clone(),
        security_key: why.security_key,
    };
    let mut tried = Vec::new();
    loop {
        let next = [
            MethodKind::PublicKey,
            MethodKind::KeyboardInteractive,
            MethodKind::Password,
        ]
        .into_iter()
        .find(|m| methods.contains(m) && !tried.contains(m));
        let Some(method) = next else {
            return Err(failed(&methods, &why));
        };
        tried.push(method);
        // What stands if a method has nothing to try.
        let unchanged = Outcome::Continue {
            methods: methods.clone(),
            partial: false,
        };
        let outcome = match method {
            MethodKind::PublicKey => public_keys(s, hop, ctx, unchanged, &mut why, at).await,
            MethodKind::KeyboardInteractive => keyboard_interactive(s, hop, ctx, unchanged).await,
            _ => password(s, hop, ctx, unchanged).await,
        };
        match outcome {
            Ok(Outcome::Success) => return Ok(()),
            // Hung up on after a rejection (`MaxAuthTries`): not the
            // network, and trying again would offer every key again.
            Ok(Outcome::Continue { .. }) | Err(Failure::Network { .. }) if s.gave_up() => {
                return Err(failed(&methods, &why));
            }
            Ok(Outcome::Continue { methods: m, .. }) => methods = m,
            Err(failure) => return Err(failure),
        }
    }
}

/// What a failed login may have failed for.
#[derive(Default)]
struct Why {
    expired: Option<String>,
    security_key: Option<crate::events::SecurityKeyProblem>,
}

async fn public_keys(
    s: &mut Session,
    hop: &Hop,
    ctx: &Ctx,
    mut last: Outcome,
    why: &mut Why,
    at: (usize, usize),
) -> Result<Outcome, Failure> {
    let user = hop.user.as_str();
    let files: Vec<(&Path, Option<PublicKey>)> = hop
        .identity_files
        .iter()
        .filter(|p| p.is_file())
        .map(|p| (p.as_path(), public_half(p)))
        .collect();
    let mut offered: Vec<PublicKey> = Vec::new();

    if let Some(socket) = &hop.agent
        && let Ok(mut agent) = Agent::connect(socket).await
    {
        let keys = agent.keys().await.unwrap_or_default();
        let listed = |k: &PublicKey| {
            files
                .iter()
                .any(|(_, p)| p.as_ref().is_some_and(|p| p.key_data() == k.key_data()))
        };
        let (mut order, others): (Vec<_>, Vec<_>) = keys.into_iter().partition(|k| listed(k));
        if !hop.identities_only {
            order.extend(others);
        }
        for key in order {
            if s.is_closed() {
                return Ok(last);
            }
            let outcome = match s.auth_agent(user, &mut agent, key.clone()).await {
                Ok(outcome) => outcome,
                Err(e) => match e.downcast_ref::<AgentRefused>() {
                    // Not this one (a denied confirmation, a locked
                    // agent): the next may do.
                    Some(AgentRefused::Refused(_)) => continue,
                    // Its answer may still come: the files are next.
                    Some(AgentRefused::Silent(_)) => break,
                    None => return Err(network(hop)(e)),
                },
            };
            offered.push(key);
            if !rejected(&outcome) {
                return Ok(outcome);
            }
            last = outcome;
        }
    }

    for (path, public) in files {
        if s.is_closed() {
            break;
        }
        if public
            .as_ref()
            .is_some_and(|p| offered.iter().any(|o| o.key_data() == p.key_data()))
        {
            continue;
        }
        let Some(key) = load_key(path, ctx).await? else {
            continue;
        };
        if openward_fido::is_security_key(&key) {
            match security_key(s, hop, ctx, path, key, at).await? {
                Ok(outcome) if !rejected(&outcome) => return Ok(outcome),
                Ok(outcome) => last = outcome,
                Err(problem) => why.security_key = Some(problem),
            }
            continue;
        }
        let key = Arc::new(key);
        let found = certificate_for(&key, path, &hop.certificate_files);
        let found = found.filter(|(cert, cert_path)| {
            let valid = in_force(cert);
            if !valid {
                why.expired = Some(cert_path.display().to_string());
            }
            valid
        });
        if let Some((cert, _)) = found {
            let outcome = s
                .auth_cert(user, Arc::clone(&key), cert)
                .await
                .map_err(network(hop))?;
            if !rejected(&outcome) {
                return Ok(outcome);
            }
        }
        let outcome = s.auth_key(user, key).await.map_err(network(hop))?;
        if !rejected(&outcome) {
            return Ok(outcome);
        }
        last = outcome;
    }
    Ok(last)
}

/// `<key>.pub`, to match identity files with agent keys without
/// decrypting them.
fn public_half(private: &Path) -> Option<PublicKey> {
    let mut path = private.as_os_str().to_owned();
    path.push(".pub");
    PublicKey::read_openssh_file(Path::new(&path)).ok()
}

/// Loads a key, asking for its passphrase up to three times. `None` skips
/// it: unreadable, or the user would rather not (as ssh does on an empty
/// passphrase).
/// A key of a security key: touched (with its PIN when it was made with
/// `verify-required`), it signs. Why it did not, if it did not.
async fn security_key(
    s: &mut Session,
    hop: &Hop,
    ctx: &Ctx,
    path: &Path,
    key: PrivateKey,
    at: (usize, usize),
) -> Result<Result<Outcome, crate::events::SecurityKeyProblem>, Failure> {
    use crate::events::SecurityKeyProblem;
    let key = Arc::new(key);
    let mut pin: Option<zeroize::Zeroizing<String>> = None;
    for attempt in 0..3 {
        if openward_fido::needs_pin(&key) && pin.is_none() {
            let prompt = Prompt::SecurityKeyPin {
                key: path.display().to_string(),
                retry: attempt > 0,
            };
            let Answer::Text(mut texts) = ctx.ask(prompt).await else {
                return Err(Failure::Cancelled);
            };
            pin = texts.drain(..).next().filter(|p| !p.is_empty());
            if pin.is_none() {
                return Err(Failure::Cancelled);
            }
        }
        // The hop's place, with the key's file for a label.
        ctx.sink.send(Event::Stage {
            hop: at.0,
            hops: at.1,
            label: path.display().to_string(),
            stage: Stage::TouchKey,
        });
        let (auth, signing_key, given) = (
            Arc::clone(&ctx.security_keys),
            Arc::clone(&key),
            pin.clone(),
        );
        let problem = Arc::new(Mutex::new(None));
        let said = Arc::clone(&problem);
        let sign: openward_ssh::client::SignFn = Arc::new(move |data: &[u8]| {
            openward_fido::sign(
                &*auth,
                &signing_key,
                data,
                given.as_deref().map(String::as_str),
            )
            .map_err(|e| {
                *lock(&said) = Some(e.clone());
                anyhow::Error::new(e)
            })
        });
        let signed = s
            .auth_signed(&hop.user, key.public_key().clone(), sign)
            .await;
        let failed = lock(&problem).take();
        match (signed, failed) {
            (Ok(outcome), _) => return Ok(Ok(outcome)),
            (Err(_), Some(openward_fido::FidoError::WrongPin)) => pin = None,
            (Err(_), Some(e)) => return Ok(Err(SecurityKeyProblem::of(&e))),
            (Err(e), None) => return Err(network(hop)(e)),
        }
    }
    Ok(Err(SecurityKeyProblem::WrongPin))
}

async fn load_key(path: &Path, ctx: &Ctx) -> Result<Option<PrivateKey>, Failure> {
    match ssh::load_key(path, None) {
        Ok(key) => return Ok(Some(key)),
        Err(KeyError::Encrypted) => {}
        Err(_) => return Ok(None),
    }
    for attempt in 0..3 {
        let prompt = Prompt::Passphrase {
            key: path.display().to_string(),
            retry: attempt > 0,
        };
        let Answer::Text(texts) = ctx.ask(prompt).await else {
            return Ok(None);
        };
        let Some(passphrase) = texts.first().filter(|p| !p.is_empty()) else {
            return Ok(None);
        };
        match ssh::load_key(path, Some(passphrase)) {
            Ok(key) => return Ok(Some(key)),
            Err(KeyError::WrongPassphrase) => continue,
            Err(_) => return Ok(None),
        }
    }
    Ok(None)
}

/// The certificate for `key`: one of `explicit`, or `<key>-cert.pub`.
/// The certificate that goes with `key`, and where it is: one of those
/// named, or `<key>-cert.pub`.
fn certificate_for(
    key: &PrivateKey,
    path: &Path,
    explicit: &[PathBuf],
) -> Option<(Certificate, PathBuf)> {
    let mut implicit = path.as_os_str().to_owned();
    implicit.push("-cert.pub");
    explicit
        .iter()
        .map(|p| p.as_path())
        .chain([Path::new(&implicit)])
        .filter(|p| p.is_file())
        .filter_map(|p| {
            openward_ssh::russh::keys::load_openssh_certificate(p)
                .ok()
                .map(|c| (c, p.to_owned()))
        })
        .find(|(c, _)| c.public_key() == key.public_key().key_data())
}

/// Valid now: after its start and before its end.
fn in_force(cert: &Certificate) -> bool {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    cert.valid_after() <= now && now < cert.valid_before()
}

async fn keyboard_interactive(
    s: &mut Session,
    hop: &Hop,
    ctx: &Ctx,
    mut last: Outcome,
) -> Result<Outcome, Failure> {
    let user = hop.user.as_str();
    for attempt in 0..3 {
        let mut step = s.kbd_start(user).await.map_err(network(hop))?;
        let mut rounds = 0;
        let outcome = loop {
            match step {
                Kbd::Done(outcome) => break outcome,
                Kbd::Questions {
                    name,
                    instructions,
                    prompts,
                } => {
                    rounds += 1;
                    if rounds > 10 {
                        return Err(Failure::Other("keyboard-interactive never ends".into()));
                    }
                    // Servers may send a round with nothing to ask.
                    let answers: Vec<Zeroizing<String>> = if prompts.is_empty() {
                        Vec::new()
                    } else {
                        let prompt = Prompt::KeyboardInteractive {
                            user: user.to_owned(),
                            host: hop.address.clone(),
                            name,
                            instructions,
                            questions: prompts
                                .into_iter()
                                .map(|(text, echo)| Question { text, echo })
                                .collect(),
                            retry: attempt > 0,
                        };
                        match ctx.ask(prompt).await {
                            Answer::Text(texts) => texts,
                            _ => return Err(Failure::Cancelled),
                        }
                    };
                    let answers = answers.iter().map(|a| a.as_str().to_owned()).collect();
                    step = s.kbd_respond(answers).await.map_err(network(hop))?;
                }
            }
        };
        if !rejected(&outcome) {
            return Ok(outcome);
        }
        let again = matches!(&outcome, Outcome::Continue { methods, .. }
            if methods.contains(&MethodKind::KeyboardInteractive));
        last = outcome;
        if !again {
            break;
        }
    }
    Ok(last)
}

async fn password(
    s: &mut Session,
    hop: &Hop,
    ctx: &Ctx,
    mut last: Outcome,
) -> Result<Outcome, Failure> {
    let user = hop.user.as_str();
    for attempt in 0..3 {
        let prompt = Prompt::Password {
            user: user.to_owned(),
            host: hop.address.clone(),
            retry: attempt > 0,
        };
        let Answer::Text(texts) = ctx.ask(prompt).await else {
            return Err(Failure::Cancelled);
        };
        let password = texts.first().map_or("", |p| p.as_str());
        let outcome = s
            .auth_password(user, password)
            .await
            .map_err(network(hop))?;
        if !rejected(&outcome) {
            return Ok(outcome);
        }
        last = outcome;
    }
    Ok(last)
}

#[cfg(test)]
mod trust_tests {
    use super::*;
    use crate::App;
    use openward_ssh::russh::keys::{PublicKeyOrCertificate, ssh_key::private::Ed25519Keypair};
    use openward_vault::proto::KnownHost;

    fn key(seed: u8) -> PublicKey {
        PrivateKey::from(Ed25519Keypair::from_seed(&[seed; 32]))
            .public_key()
            .clone()
    }
    fn offered(key: PublicKey) -> PublicKeyOrCertificate {
        PublicKeyOrCertificate::PublicKey {
            key,
            hash_alg: None,
        }
    }

    struct Sink;
    impl EventSink for Sink {
        fn send(&self, _: Event) {}
    }

    #[test]
    fn failed_key_persistence_refuses_the_connection() {
        let temp = tempfile::tempdir().unwrap();
        let app = App::open_as(temp.path(), Local::from_env()).unwrap();
        let conn = rusqlite::Connection::open(temp.path().join("vault.db")).unwrap();
        conn.execute_batch("CREATE TRIGGER reject_key BEFORE INSERT ON items BEGIN SELECT RAISE(FAIL, 'injected storage failure'); END;").unwrap();
        let sink: Arc<dyn EventSink> = Arc::new(Sink);
        let ctx = app.ctx(&sink);
        let mut hop = Plan::for_address(
            "host.example",
            None,
            None,
            openward_vault::proto::Protocol::Ssh,
            app.local(),
        )
        .hops
        .remove(0);
        hop.host_key_policy = HostKeyPolicy::AcceptNew;
        hop.known_hosts.clear();
        let refused = Arc::new(Mutex::new(None));
        let query = HostKeyQuery {
            host: hop.address.clone(),
            port: hop.port,
            key: key(20),
            verdict: Verdict::Unknown,
            known_types: vec![],
        };
        assert!(
            !app.runtime
                .block_on(host_key_hook(&hop, &ctx, Arc::clone(&refused))(query))
        );
        assert!(app.vault().known_hosts_text().is_empty());
        let error = anyhow::Error::new(UntrustedHost(Verdict::Unknown));
        let failure = open_failure(
            &hop,
            &error,
            &refused,
            &KnownTexts {
                openward: String::new(),
                openssh: String::new(),
                ..KnownTexts::default()
            },
        );
        assert!(
            matches!(failure, Failure::Other(message) if message.contains("save the host key") && message.contains("injected storage failure"))
        );
    }

    #[test]
    fn learning_revalidates_stale_queries_instead_of_rotating_them() {
        let mut vault = Vault::open_in_memory().unwrap();
        let query = |seed| HostKeyQuery {
            host: "host.example".into(),
            port: 2222,
            key: key(seed),
            verdict: Verdict::Unknown,
            known_types: vec![],
        };
        learn_key(&mut vault, "", query(21)).unwrap();
        let saved = vault.known_hosts_text();
        learn_key(&mut vault, "", query(21)).unwrap(); // another connection, same key
        assert_eq!(vault.known_hosts_text(), saved);
        let Err(KeyRefusal::Changed(changed, previous)) = learn_key(&mut vault, "", query(22))
        else {
            panic!("a stale query must be refused as a change");
        };
        assert_eq!(changed.verdict, Verdict::Changed);
        assert_eq!(previous.len(), 1);
        assert_eq!(previous[0].key, key(21).to_openssh().unwrap());
        assert_eq!(vault.known_hosts_text(), saved);
        let revoke = format!(
            "@revoked [host.example]:2222 {}",
            key(21).to_openssh().unwrap()
        );
        assert!(
            matches!(learn_key(&mut vault, &revoke, query(21)), Err(KeyRefusal::Query(q)) if q.verdict == Verdict::Revoked)
        );
    }

    #[test]
    fn persistence_failure_stops_real_ssh_before_authentication() {
        use openward_ssh::russh::{self, server};
        use std::sync::atomic::{AtomicUsize, Ordering};
        struct Server(Arc<AtomicUsize>);
        impl server::Handler for Server {
            type Error = russh::Error;
            async fn auth_none(&mut self, _: &str) -> Result<server::Auth, Self::Error> {
                self.0.fetch_add(1, Ordering::SeqCst);
                Ok(server::Auth::Accept)
            }
        }
        let temp = tempfile::tempdir().unwrap();
        let app = App::open_as(temp.path(), Local::from_env()).unwrap();
        let conn = rusqlite::Connection::open(temp.path().join("vault.db")).unwrap();
        conn.execute_batch("CREATE TRIGGER reject_key BEFORE INSERT ON items BEGIN SELECT RAISE(FAIL, 'injected storage failure'); END;").unwrap();
        let sink: Arc<dyn EventSink> = Arc::new(Sink);
        let ctx = app.ctx(&sink);
        for fail in [true, false] {
            if !fail {
                conn.execute_batch("DROP TRIGGER reject_key").unwrap();
            }
            let attempts = Arc::new(AtomicUsize::new(0));
            app.runtime.block_on(async {
                let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
                let mut plan = Plan::for_address("127.0.0.1", None, Some(listener.local_addr().unwrap().port()), openward_vault::proto::Protocol::Ssh, app.local());
                plan.hops[0].host_key_policy = HostKeyPolicy::AcceptNew;
                plan.hops[0].known_hosts.clear();
                let mut config = server::Config::default();
                config.keys.push(PrivateKey::from(Ed25519Keypair::from_seed(&[55; 32])));
                let server_attempts = Arc::clone(&attempts);
                let task = tokio::spawn(async move {
                    let (socket, _) = listener.accept().await.unwrap();
                    if let Ok(session) = server::run_stream(Arc::new(config), socket, Server(server_attempts)).await { let _ = session.await; }
                });
                let result = tokio::time::timeout(std::time::Duration::from_secs(10), ssh_hops(&plan, &ctx, 1)).await.unwrap();
                if fail {
                    assert!(matches!(result, Err(Failure::Other(message)) if message.contains("injected storage failure")));
                    assert_eq!(attempts.load(Ordering::SeqCst), 0);
                    assert!(app.vault().known_hosts_text().is_empty());
                } else {
                    let sessions = result.unwrap();
                    assert_eq!(attempts.load(Ordering::SeqCst), 1);
                    assert!(!app.vault().known_hosts_text().is_empty());
                    sessions[0].disconnect().await;
                }
                task.abort();
                let _ = task.await;
            });
        }
    }

    #[test]
    fn hashed_and_case_variant_keys_are_revoked_without_changing_other_ports() {
        use hmac::{Hmac, KeyInit, Mac};
        use sha1::Sha1;
        let temp = tempfile::tempdir().unwrap();
        let app = App::open_as(temp.path(), Local::from_env()).unwrap();
        for port in [22, 2222] {
            let (old, new) = (key(41), key(42));
            let spec = if port == 22 {
                "node.example.org".into()
            } else {
                format!("[node.example.org]:{port}")
            };
            let mut mac = Hmac::<Sha1>::new_from_slice(b"0123456789abcdefghij").unwrap();
            mac.update(spec.as_bytes());
            let b64 = data_encoding::BASE64;
            let hashed = format!(
                "|1|{}|{}",
                b64.encode(b"0123456789abcdefghij"),
                b64.encode(&mac.finalize().into_bytes())
            );
            for hosts in [hashed, spec.to_uppercase()] {
                app.vault()
                    .create(Data::KnownHost(KnownHost {
                        hosts,
                        key: old.to_openssh().unwrap(),
                        ..KnownHost::default()
                    }))
                    .unwrap();
            }
            app.trust_host_key("Node.Example.org", port, &new.to_openssh().unwrap())
                .unwrap();
            let mut known = KnownHosts::parse(&app.vault().known_hosts_text(), Unknown::Reject);
            assert_eq!(
                known.check("node.example.org", port, &offered(old.clone())),
                Verdict::Revoked
            );
            assert_eq!(
                known.check("NODE.EXAMPLE.ORG", port, &offered(new.clone())),
                Verdict::Known
            );
            assert_eq!(
                app.vault()
                    .known_hosts()
                    .iter()
                    .filter(
                        |(_, k)| k.marker == Some(openward_vault::proto::Marker::Revoked)
                            && k.hosts.eq_ignore_ascii_case(&spec)
                    )
                    .count(),
                1
            );
            // A repeated approval does not duplicate revocations or revoke itself.
            app.rotate_host_key(
                "node.example.org",
                port,
                &new.to_openssh().unwrap(),
                &[old.to_openssh().unwrap(), new.to_openssh().unwrap()],
            )
            .unwrap();
            assert_eq!(
                app.vault()
                    .known_hosts()
                    .iter()
                    .filter(
                        |(_, k)| k.marker == Some(openward_vault::proto::Marker::Revoked)
                            && k.hosts.eq_ignore_ascii_case(&spec)
                    )
                    .count(),
                1
            );
        }
    }

    #[test]
    fn historical_rotation_residues_require_review_without_changing_file_only_policy() {
        let (old, new) = (key(61), key(62));
        let external = format!("host.example,other.example {}", old.to_openssh().unwrap());
        let mut vault = Vault::open_in_memory().unwrap();
        // This is the persisted state written by the old rotation method:
        // an exact local pin alongside an old key in another source.
        vault
            .trust_host_key("host.example", 22, &new.to_openssh().unwrap())
            .unwrap();
        let mut known = KnownTexts::of(&vault, external.clone()).known();
        assert_eq!(
            known.check("host.example", 22, &offered(old.clone())),
            Verdict::Changed
        );
        assert_eq!(
            known.check("host.example", 22, &offered(new.clone())),
            Verdict::Known
        );
        assert_eq!(
            known.check("other.example", 22, &offered(old.clone())),
            Verdict::Known
        );
        // Conflicting old case variants have no reliable ordering: ask
        // again for either key instead of silently choosing one.
        vault
            .create(Data::KnownHost(KnownHost {
                hosts: "HOST.EXAMPLE".into(),
                key: old.to_openssh().unwrap(),
                ..KnownHost::default()
            }))
            .unwrap();
        let mut ambiguous = KnownTexts::of(&vault, external.clone()).known();
        assert_eq!(
            ambiguous.check("host.example", 22, &offered(old.clone())),
            Verdict::Changed
        );
        assert_eq!(
            ambiguous.check("host.example", 22, &offered(new.clone())),
            Verdict::Changed
        );
        let mut file_only = KnownTexts {
            openssh: format!("{external}\nhost.example {}", new.to_openssh().unwrap()),
            ..KnownTexts::default()
        }
        .known();
        assert_eq!(
            file_only.check("host.example", 22, &offered(old)),
            Verdict::Known
        );
        assert_eq!(
            file_only.check("host.example", 22, &offered(new)),
            Verdict::Known
        );
    }

    #[test]
    fn rotation_retires_the_certified_old_subject_but_keeps_ca_validation() {
        use openward_ssh::russh::keys::ssh_key::certificate::{Builder, CertType};
        use std::time::{SystemTime, UNIX_EPOCH};
        let temp = tempfile::tempdir().unwrap();
        let app = App::open_as(temp.path(), Local::from_env()).unwrap();
        let (old, new, ca) = (
            key(71),
            key(72),
            PrivateKey::from(Ed25519Keypair::from_seed(&[73; 32])),
        );
        app.vault()
            .create(Data::KnownHost(KnownHost {
                hosts: "host.example".into(),
                key: ca.public_key().to_openssh().unwrap(),
                marker: Some(openward_vault::proto::Marker::CertAuthority),
                ..KnownHost::default()
            }))
            .unwrap();
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let certificate = |key: &PublicKey| {
            let mut builder =
                Builder::new([7; 16], key.key_data().clone(), now - 60, now + 3600).unwrap();
            builder.cert_type(CertType::Host).unwrap();
            builder.valid_principal("host.example").unwrap();
            PublicKeyOrCertificate::Certificate(builder.sign(&ca).unwrap())
        };
        app.rotate_host_key(
            "host.example",
            22,
            &new.to_openssh().unwrap(),
            &[old.to_openssh().unwrap()],
        )
        .unwrap();
        let mut known = KnownTexts::of(
            &app.vault(),
            format!("host.example {}", old.to_openssh().unwrap()),
        )
        .known();
        assert_eq!(
            known.check("host.example", 22, &certificate(&old)),
            Verdict::Revoked
        );
        assert!(matches!(
            known.check("host.example", 22, &certificate(&new)),
            Verdict::Certified { .. }
        ));
        // An unlisted subject signed by the configured CA remains valid;
        // a local pin does not replace the administrator's CA policy.
        assert!(matches!(
            known.check("host.example", 22, &certificate(&key(74))),
            Verdict::Certified { .. }
        ));
    }

    #[test]
    fn rotation_carries_custom_file_keys_and_is_atomic_on_failure() {
        let temp = tempfile::tempdir().unwrap();
        let app = App::open_as(temp.path(), Local::from_env()).unwrap();
        let (old, new) = (key(31), key(32));
        let line = format!(
            "[host.example]:2222,other.example {}",
            old.to_openssh().unwrap()
        );
        let file = temp.path().join("custom_known_hosts");
        std::fs::write(&file, &line).unwrap();
        let texts = KnownTexts::of(&app.vault(), read_known_files(std::slice::from_ref(&file)));
        let previous = texts.previous("host.example", 2222, &new);
        assert_eq!(previous[0].source, KeySource::OpenSsh);
        app.rotate_host_key(
            "host.example",
            2222,
            &new.to_openssh().unwrap(),
            &previous.iter().map(|p| p.key.clone()).collect::<Vec<_>>(),
        )
        .unwrap();
        let persisted = app.vault().known_hosts_text();
        let mut known = KnownHosts::parse(&format!("{persisted}\n{line}"), Unknown::Reject);
        assert_eq!(
            known.check("host.example", 2222, &offered(old.clone())),
            Verdict::Revoked
        );
        assert_eq!(
            known.check("host.example", 2222, &offered(new.clone())),
            Verdict::Known
        );
        assert_eq!(
            known.check("other.example", 22, &offered(old)),
            Verdict::Known
        );
        // Neither the file nor trust for a different port is rewritten.
        assert_eq!(
            known.check("host.example", 22, &offered(new.clone())),
            Verdict::Unknown
        );
        assert_eq!(std::fs::read_to_string(file).unwrap(), line);
        let conn = rusqlite::Connection::open(temp.path().join("vault.db")).unwrap();
        conn.execute_batch("CREATE TABLE failures (n INTEGER); INSERT INTO failures VALUES (0); CREATE TRIGGER reject_second BEFORE INSERT ON items BEGIN UPDATE failures SET n=n+1; SELECT CASE WHEN (SELECT n FROM failures)=2 THEN RAISE(FAIL, 'second write failed') END; END;").unwrap();
        assert!(
            app.rotate_host_key("HOST.EXAMPLE", 2222, &key(33).to_openssh().unwrap(), &[])
                .is_err()
        );
        assert_eq!(app.vault().known_hosts_text(), persisted);
        drop(conn);
        drop(app);
        assert_eq!(
            Vault::open(&temp.path().join("vault.db"))
                .unwrap()
                .known_hosts_text(),
            persisted
        );
    }

    #[test]
    fn rotation_revokes_residual_pattern_keys_for_only_the_selected_host() {
        let temp = tempfile::tempdir().unwrap();
        let app = App::open_as(temp.path(), Local::from_env()).unwrap();
        let (old, new) = (key(11), key(12));
        app.vault()
            .create(Data::KnownHost(KnownHost {
                hosts: "*.example.org,!excluded.example.org".into(),
                key: old.to_openssh().unwrap(),
                ..KnownHost::default()
            }))
            .unwrap();
        app.trust_host_key("Node.Example.org", 22, &new.to_openssh().unwrap())
            .unwrap();
        let mut known = KnownHosts::parse(&app.vault().known_hosts_text(), Unknown::Reject);
        assert_eq!(
            known.check("node.example.org", 22, &offered(old.clone())),
            Verdict::Revoked
        );
        assert_eq!(
            known.check("node.example.org", 22, &offered(new)),
            Verdict::Known
        );
        assert_eq!(
            known.check("other.example.org", 22, &offered(old.clone())),
            Verdict::Known
        );
        assert_eq!(
            known.check("excluded.example.org", 22, &offered(old)),
            Verdict::Unknown
        );
    }
}
