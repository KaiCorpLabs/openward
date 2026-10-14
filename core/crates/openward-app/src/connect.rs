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

use std::path::Path;
use std::sync::{Arc, Mutex};

use openward_ssh::client::{
    self as ssh, Agent, Hop as Transport, HostKeyHook, HostKeyQuery, Kbd, KeyError, Options,
    Outcome, Session, Target, UntrustedHost,
};
use openward_ssh::known_hosts::{KnownHosts, Unknown, Verdict};
use openward_ssh::russh::MethodKind;
use openward_ssh::russh::keys::{Certificate, HashAlg, PrivateKey, PublicKey};
use openward_vault::Vault;
use openward_vault::proto::HostKeyPolicy;
use zeroize::Zeroizing;

use crate::events::{
    Answer, ChangedKey, Event, EventSink, Failure, KeySource, PreviousKey, Prompt, Prompts,
    Question, Stage,
};
use crate::local::Local;
use crate::plan::{Hop, Plan};

/// Everything a connection needs from the app.
#[derive(Clone)]
pub(crate) struct Ctx {
    pub vault: Arc<Mutex<Vault>>,
    pub local: Local,
    pub prompts: Arc<Prompts>,
    pub sink: Arc<dyn EventSink>,
}

impl Ctx {
    async fn ask(&self, prompt: Prompt) -> Answer {
        self.prompts.ask(&self.sink, prompt).await
    }

    fn stage(&self, plan: &Plan, hop: usize, stage: Stage) {
        self.sink.send(Event::Stage {
            hop,
            hops: plan.hops.len(),
            label: plan.hops[hop].label.clone(),
            stage,
        });
    }

    /// The vault's trusted keys, and `~/.ssh/known_hosts`.
    fn known_hosts(&self) -> KnownTexts {
        KnownTexts {
            openward: lock(&self.vault).known_hosts_text(),
            openssh: std::fs::read_to_string(self.local.known_hosts_file()).unwrap_or_default(),
        }
    }
}

struct KnownTexts {
    openward: String,
    openssh: String,
}

impl KnownTexts {
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
    let texts = ctx.known_hosts();
    let known = texts.all();
    let mut sessions: Vec<Session> = Vec::with_capacity(plan.hops.len());
    for (i, hop) in plan.hops.iter().enumerate() {
        ctx.stage(plan, i, Stage::Connecting);
        let refused = Arc::new(Mutex::new(None));
        let last = i + 1 == plan.hops.len();
        let opts = Options {
            user: hop.user.clone(),
            known_hosts: Arc::new(Mutex::new(KnownHosts::parse(&known, Unknown::Reject))),
            host_certificates: known.contains("@cert-authority"),
            keepalive: hop.keepalive,
            agent_forward: if last && plan.agent_forward {
                hop.agent.clone()
            } else {
                None
            },
            on_untrusted: Some(host_key_hook(hop, ctx, Arc::clone(&refused))),
        };
        let target = Target::new(&hop.address, hop.port);
        let transport = match (sessions.last(), &hop.proxy_command) {
            (Some(previous), _) => Transport::Via(previous),
            (None, Some(command)) => Transport::ProxyCommand(command.clone()),
            (None, None) => Transport::Tcp,
        };
        let mut session = match ssh::open(&target, transport, &opts).await {
            Ok(session) => session,
            Err(e) => return Err(open_failure(hop, &e, &refused, &texts)),
        };
        ctx.stage(plan, i, Stage::Authenticating);
        authenticate(&mut session, hop, ctx).await?;
        sessions.push(session);
    }
    Ok(sessions)
}

/// Decides on keys `known_hosts` does not vouch for, by the hop's policy.
/// Refused queries are kept to explain the failure.
fn host_key_hook(hop: &Hop, ctx: &Ctx, refused: Arc<Mutex<Option<HostKeyQuery>>>) -> HostKeyHook {
    let (ctx, policy, label) = (ctx.clone(), hop.host_key_policy, hop.label.clone());
    Arc::new(move |q: HostKeyQuery| {
        let (ctx, refused, label) = (ctx.clone(), Arc::clone(&refused), label.clone());
        Box::pin(async move {
            let accept = match (&q.verdict, policy) {
                (Verdict::Unknown, HostKeyPolicy::AcceptNew) => true,
                (Verdict::Unknown, HostKeyPolicy::Ask) => {
                    let prompt = Prompt::HostKey {
                        label,
                        host: q.host.clone(),
                        port: q.port,
                        algorithm: q.key.algorithm().to_string(),
                        fingerprint: q.key.fingerprint(HashAlg::Sha256).to_string(),
                    };
                    matches!(ctx.ask(prompt).await, Answer::Accept)
                }
                // Strict, a changed key, a bad certificate.
                _ => false,
            };
            if accept {
                if let Ok(key) = q.key.to_openssh() {
                    // Not saved is not fatal: it is trusted for this session.
                    let _ = lock(&ctx.vault).trust_host_key(&q.host, q.port, &key);
                }
            } else {
                *lock(&refused) = Some(q);
            }
            accept
        })
    })
}

fn open_failure(
    hop: &Hop,
    error: &anyhow::Error,
    refused: &Mutex<Option<HostKeyQuery>>,
    texts: &KnownTexts,
) -> Failure {
    let label = hop.label.clone();
    let Some(UntrustedHost(verdict)) = error.downcast_ref::<UntrustedHost>() else {
        return Failure::Network {
            label,
            message: format!("{error:#}"),
        };
    };
    match (verdict, lock(refused).take()) {
        (Verdict::Changed, Some(q)) => Failure::HostKeyChanged(Box::new(ChangedKey {
            label,
            previous: texts.previous(&q.host, q.port, &q.key),
            host: q.host,
            port: q.port,
            algorithm: q.key.algorithm().to_string(),
            fingerprint: q.key.fingerprint(HashAlg::Sha256).to_string(),
            key: q.key.to_openssh().unwrap_or_default(),
        })),
        (Verdict::BadCertificate(reason), _) => Failure::BadCertificate {
            label,
            reason: reason.clone(),
        },
        _ => Failure::HostKeyRejected { label },
    }
}

fn network(hop: &Hop) -> impl Fn(anyhow::Error) -> Failure + '_ {
    move |e| Failure::Network {
        label: hop.label.clone(),
        message: format!("{e:#}"),
    }
}

/// The method failed outright: try the next one.
fn rejected(outcome: &Outcome) -> bool {
    matches!(outcome, Outcome::Continue { partial: false, .. })
}

async fn authenticate(s: &mut Session, hop: &Hop, ctx: &Ctx) -> Result<(), Failure> {
    let user = hop.user.as_str();
    let mut methods = match s.auth_none(user).await.map_err(network(hop))? {
        Outcome::Success => return Ok(()),
        Outcome::Continue { methods, .. } => methods,
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
            return Err(Failure::AuthFailed {
                label: hop.label.clone(),
                user: user.to_owned(),
                methods: methods.iter().map(|m| <&str>::from(m).to_owned()).collect(),
            });
        };
        tried.push(method);
        // What stands if a method has nothing to try.
        let unchanged = Outcome::Continue {
            methods: methods.clone(),
            partial: false,
        };
        let outcome = match method {
            MethodKind::PublicKey => public_keys(s, hop, ctx, unchanged).await?,
            MethodKind::KeyboardInteractive => keyboard_interactive(s, hop, ctx, unchanged).await?,
            _ => password(s, hop, ctx, unchanged).await?,
        };
        match outcome {
            Outcome::Success => return Ok(()),
            Outcome::Continue { methods: m, .. } => methods = m,
        }
    }
}

async fn public_keys(
    s: &mut Session,
    hop: &Hop,
    ctx: &Ctx,
    mut last: Outcome,
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
            let outcome = s
                .auth_agent(user, &mut agent, key.clone())
                .await
                .map_err(network(hop))?;
            offered.push(key);
            if !rejected(&outcome) {
                return Ok(outcome);
            }
            last = outcome;
        }
    }

    for (path, public) in files {
        if public
            .as_ref()
            .is_some_and(|p| offered.iter().any(|o| o.key_data() == p.key_data()))
        {
            continue;
        }
        let Some(key) = load_key(path, ctx).await? else {
            continue;
        };
        let key = Arc::new(key);
        if let Some(cert) = certificate_for(&key, path, &hop.certificate_files) {
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
fn certificate_for(
    key: &PrivateKey,
    path: &Path,
    explicit: &[std::path::PathBuf],
) -> Option<Certificate> {
    let mut implicit = path.as_os_str().to_owned();
    implicit.push("-cert.pub");
    explicit
        .iter()
        .map(|p| p.as_path())
        .chain([Path::new(&implicit)])
        .filter(|p| p.is_file())
        .filter_map(|p| openward_ssh::russh::keys::load_openssh_certificate(p).ok())
        .find(|c| c.public_key() == key.public_key().key_data())
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
