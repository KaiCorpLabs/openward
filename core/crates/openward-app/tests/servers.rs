//! Connections through `App` against the S2 test servers
//! (`spikes/s2-ssh/servers/up.sh`). Skipped when they are not running,
//! unless `OPENWARD_REQUIRE_SERVERS` is set (`make ci`).

#[cfg(unix)]
use std::future::Future;
#[cfg(unix)]
use std::path::Path;
use std::path::PathBuf;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::{Duration, Instant};

use openward_app::alive::Timing;
use openward_app::events::{
    CertProblem, ChangedKey, Connected, Health, KeySource, MoshFallback, NetCause, Persistence,
    PreviousKey, SecurityKeyProblem, Stage, Trust,
};
use openward_app::vault::proto::{
    Agent, Data, Group, Host, HostKeyPolicy, Identity, ItemId, Jump, Route, Settings, System,
    SystemSource, UseIdentity,
};
use openward_app::{Answer, App, Event, EventSink, Failure, Local, Prompt, Terminal};
#[cfg(unix)]
use openward_ssh::russh::keys::{Algorithm, PrivateKey, agent};
use zeroize::Zeroizing;

const BASTION: u16 = 22100;
/// Its own server, for the test that freezes it.
const FREEZE: u16 = 22101;

fn fixtures() -> Option<PathBuf> {
    let dir = std::env::var_os("S2_FIXTURES")
        .map(PathBuf::from)
        .or_else(|| {
            let home = PathBuf::from(std::env::var_os("HOME")?);
            Some(if cfg!(target_os = "macos") {
                home.join("Library/Caches/openward/s2-fixtures")
            } else {
                home.join(".cache/openward/s2-fixtures")
            })
        })?;
    let up = std::net::TcpStream::connect(("127.0.0.1", BASTION)).is_ok();
    (up && dir.join("id_ed25519").is_file()).then_some(dir)
}

macro_rules! servers {
    () => {
        match fixtures() {
            Some(dir) => dir,
            // `make ci` sets it: there a skipped test would pass untested.
            None if std::env::var_os("OPENWARD_REQUIRE_SERVERS").is_some_and(|v| !v.is_empty()) => {
                panic!("S2 servers not running (spikes/s2-ssh/servers/up.sh)")
            }
            None => {
                eprintln!("S2 servers not running: skipped");
                return;
            }
        }
    };
}

/// Records events and answers prompts with `reply`.
struct Ui {
    app: OnceLock<Weak<App>>,
    tx: Mutex<Sender<Event>>,
    reply: Box<dyn Fn(&Prompt) -> Answer + Send + Sync>,
}

impl EventSink for Ui {
    fn send(&self, event: Event) {
        if let Event::Prompt { id, prompt } = &event
            && let Some(app) = self.app.get().and_then(Weak::upgrade)
        {
            app.answer(*id, (self.reply)(prompt));
        }
        let _ = self.tx.lock().unwrap().send(event);
    }
}

struct Fixture {
    app: Arc<App>,
    fx: PathBuf,
    _dir: tempfile::TempDir,
}

fn text(s: &str) -> Answer {
    Answer::Text(vec![Zeroizing::new(s.to_owned())])
}

impl Fixture {
    fn new(fx: PathBuf) -> Self {
        let dir = tempfile::tempdir().unwrap();
        // A home of its own: the tester's keys, agent and known_hosts stay out.
        let local = Local {
            home: dir.path().into(),
            user: "nobody".into(),
            ssh_dir: dir.path().join(".ssh"),
            system_ssh_dir: dir.path().join("etc-ssh"),
            agent: None,
        };
        let app = Arc::new(App::open_as(&dir.path().join("data"), local).unwrap());
        Self { app, fx, _dir: dir }
    }

    fn host(&self, label: &str, address: &str, port: u16, settings: Settings) -> ItemId {
        let settings = Settings {
            port: Some(port),
            agent: Some(Agent::Off),
            ..settings
        };
        self.app
            .vault()
            .create(Data::Host(Host {
                label: label.into(),
                address: address.into(),
                settings,
                ..Host::default()
            }))
            .unwrap()
    }

    fn key(&self, name: &str) -> Option<Vec<String>> {
        Some(vec![self.fx.join(name).display().to_string()])
    }

    fn read(&self, name: &str) -> String {
        std::fs::read_to_string(self.fx.join(name))
            .unwrap()
            .trim()
            .to_owned()
    }

    fn password(&self, user: &str) -> String {
        self.read("passwords")
            .lines()
            .find_map(|l| l.strip_prefix(&format!("{user}=")).map(str::to_owned))
            .unwrap()
    }

    fn connect(
        &self,
        host: ItemId,
        reply: impl Fn(&Prompt) -> Answer + Send + Sync + 'static,
    ) -> (Arc<Terminal>, Receiver<Event>) {
        let term = self.app.terminal(80, 24, 1000);
        let rx = self.reconnect(&term, host, reply);
        (term, rx)
    }

    /// Connects `term` again, as «Reconnect» does.
    fn reconnect(
        &self,
        term: &Arc<Terminal>,
        host: ItemId,
        reply: impl Fn(&Prompt) -> Answer + Send + Sync + 'static,
    ) -> Receiver<Event> {
        self.connect_with(term, host, reply, false)
    }

    fn connect_with(
        &self,
        term: &Arc<Terminal>,
        host: ItemId,
        reply: impl Fn(&Prompt) -> Answer + Send + Sync + 'static,
        reuse: bool,
    ) -> Receiver<Event> {
        let (tx, rx) = channel();
        let ui = Arc::new(Ui {
            app: OnceLock::new(),
            tx: Mutex::new(tx),
            reply: Box::new(reply),
        });
        let _ = ui.app.set(Arc::downgrade(&self.app));
        if reuse {
            self.app.connect_reusing(term, host, ui).unwrap();
        } else {
            self.app.connect(term, host, ui).unwrap();
        }
        rx
    }
}

/// Waits for the outcome: connected, or closed with a failure.
fn outcome(rx: &Receiver<Event>) -> (Result<Connected, Option<Failure>>, Vec<Prompt>) {
    let mut prompts = Vec::new();
    loop {
        match rx
            .recv_timeout(Duration::from_secs(30))
            .expect("no outcome in 30 s")
        {
            Event::Connected(c) => return (Ok(c), prompts),
            Event::Closed { failure, .. } => return (Err(failure), prompts),
            Event::Prompt { prompt, .. } => prompts.push(prompt),
            Event::Stage { .. }
            | Event::Started { .. }
            | Event::Route { .. }
            | Event::Reconnecting { .. }
            | Event::Health(_)
            | Event::Hops { .. }
            | Event::HostsChanged { .. }
            | Event::MoshFallback { .. }
            | Event::Persistent { .. } => {}
        }
    }
}

fn wait_for(term: &Terminal, needle: &str) {
    let deadline = Instant::now() + Duration::from_secs(10);
    while !term.screen_text().contains(needle) {
        assert!(
            Instant::now() < deadline,
            "{needle:?} not on screen:\n{}",
            term.screen_text()
        );
        std::thread::sleep(Duration::from_millis(20));
    }
}

#[test]
fn a_key_learns_the_host_and_runs_a_shell() {
    let f = Fixture::new(servers!());
    let host = f.host(
        "bastion",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            env: Some([("LC_OPENWARD".to_owned(), "a2".to_owned())].into()),
            ..Settings::default()
        },
    );
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    let (connected, prompts) = outcome(&rx);
    let connected = connected.unwrap();
    assert!(prompts.is_empty());
    assert_eq!(connected.trust, Trust::New);
    assert!(
        connected.post_quantum,
        "OpenSSH 10 negotiates ML-KEM: {}",
        connected.kex
    );
    assert!(
        f.app
            .vault()
            .known_hosts_text()
            .contains("[127.0.0.1]:22100 ssh-")
    );

    term.resize(100, 30);
    term.text("stty size; echo app-$((6*7))\n");
    wait_for(&term, "app-42");
    wait_for(&term, "30 100");
    // The terminal's modes: UTF-8, and ⌫ (DEL) erases.
    term.text("case \"$(stty -a)\" in *' iutf8'*'erase = ^?'*|*'erase = ^?'*' iutf8'*) echo modes-$((2*2));; esac\n");
    wait_for(&term, "modes-4");
    term.text("exit 5\n");
    let closed = loop {
        if let Event::Closed { exit_code, failure } =
            rx.recv_timeout(Duration::from_secs(10)).unwrap()
        {
            break (exit_code, failure);
        }
    };
    assert_eq!(closed, (Some(5), None));

    // Known from now on.
    let (_term, rx) = f.connect(host, |_| Answer::Cancel);
    assert_eq!(outcome(&rx).0.unwrap().trust, Trust::Known);
}

/// Letting go of a connected terminal hangs up: the connection task holds
/// the event sink, so the sink is released when the task ends.
#[test]
fn dropping_the_terminal_hangs_up() {
    let f = Fixture::new(servers!());
    let host = f.host(
        "bastion",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (tx, rx) = channel();
    let ui = Arc::new(Ui {
        app: OnceLock::new(),
        tx: Mutex::new(tx),
        reply: Box::new(|_| Answer::Cancel),
    });
    let term = f.app.terminal(80, 24, 1000);
    f.app.connect(&term, host, ui.clone()).unwrap();
    outcome(&rx).0.unwrap();
    assert!(Arc::strong_count(&ui) > 1);
    drop(term);
    let deadline = Instant::now() + Duration::from_secs(5);
    while Arc::strong_count(&ui) > 1 {
        assert!(
            Instant::now() < deadline,
            "the connection outlived its terminal"
        );
        std::thread::sleep(Duration::from_millis(20));
    }
}

/// The container runtime the servers run on (`up.sh` reads the same).
fn runtime() -> String {
    std::env::var("S2_RUNTIME").unwrap_or_else(|_| "podman".into())
}

/// Drops a bastion connection without a goodbye, like a network that
/// goes away: the shell's parent is this connection's sshd, killed.
fn cut_bastion(term: &Terminal) {
    term.text("echo ppid-$PPID-end\n");
    // The output line, not the echo of the command (which has `-end` too).
    wait_for(term, "\nppid-");
    let deadline = Instant::now() + Duration::from_secs(10);
    let pid = loop {
        let screen = term.screen_text();
        if let Some(pid) = screen
            .lines()
            .find_map(|l| l.strip_prefix("ppid-")?.strip_suffix("-end"))
        {
            break pid.to_owned();
        }
        assert!(Instant::now() < deadline, "the pid line:\n{screen}");
        std::thread::sleep(Duration::from_millis(20));
    };
    let killed = std::process::Command::new(runtime())
        .args(["exec", "bastion", "kill", "-9", &pid])
        .status()
        .unwrap();
    assert!(killed.success());
}

/// A connection that drops is made again, on the same screen.
#[test]
fn a_lost_connection_comes_back() {
    let f = Fixture::new(servers!());
    let host = f.host(
        "bastion",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    outcome(&rx).0.unwrap();
    cut_bastion(&term);

    let deadline = Instant::now() + Duration::from_secs(20);
    let mut reconnecting = None;
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        match rx.recv_timeout(left).expect("no reconnection") {
            Event::Reconnecting {
                attempt, reason, ..
            } => reconnecting = Some((attempt, reason)),
            Event::Connected(_) => break,
            Event::Closed { failure, .. } => panic!("gave up: {failure:?}"),
            _ => {}
        }
    }
    let (attempt, reason) = reconnecting.expect("no Reconnecting event");
    assert_eq!(attempt, 1);
    assert!(
        matches!(
            reason,
            Failure::Network {
                cause: NetCause::Lost,
                ..
            }
        ),
        "{reason:?}"
    );
    term.text("echo back-$((6*7))\n");
    wait_for(&term, "back-42");
}

/// Unpauses a container when dropped, even if the test fails.
struct Paused(&'static str);

impl Paused {
    fn new(name: &'static str) -> Self {
        let ok = std::process::Command::new(runtime())
            .args(["pause", name])
            .status()
            .unwrap();
        assert!(ok.success(), "could not pause {name}");
        Self(name)
    }
}

impl Drop for Paused {
    fn drop(&mut self) {
        let _ = std::process::Command::new(runtime())
            .args(["unpause", self.0])
            .status();
    }
}

/// The system connecting stored for a host, once it has.
fn system_of(f: &Fixture, id: ItemId) -> System {
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        if let Some(s) = f.app.vault().host(id).unwrap().system.clone() {
            return s;
        }
        assert!(Instant::now() < deadline, "no system for {id}");
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn bastion_host(f: &Fixture, persistent: Option<bool>) -> ItemId {
    demo_host(f, "bastion", BASTION, persistent)
}

fn demo_host(f: &Fixture, label: &str, port: u16, persistent: Option<bool>) -> ItemId {
    f.host(
        label,
        "127.0.0.1",
        port,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            persistent_session: persistent,
            ..Settings::default()
        },
    )
}

/// A second terminal asked to reuse goes over the first one's connection:
/// it does not log in again, and both shells answer.
#[test]
fn a_second_shell_goes_over_the_connection_that_is_up() {
    let f = Fixture::new(servers!());
    let host = demo_host(&f, "s2-openssh-9.2", 22092, None);
    let (first, rx) = f.connect(host, |_| Answer::Cancel);
    first_shell(&rx);
    let second = f.app.terminal(80, 24, 1000);
    let rx2 = f.connect_with(&second, host, |_| Answer::Cancel, true);
    let mut logged_in = false;
    loop {
        match rx2
            .recv_timeout(Duration::from_secs(30))
            .expect("no outcome")
        {
            Event::Stage {
                stage: Stage::Authenticating,
                ..
            } => logged_in = true,
            Event::Connected(_) => break,
            Event::Closed { failure, .. } => panic!("{failure:?}"),
            _ => {}
        }
    }
    assert!(!logged_in, "it logged in again");
    second.text("echo second-$((6*7))\n");
    wait_for(&second, "second-42");
    first.text("echo first-$((6*7))\n");
    wait_for(&first, "first-42");
}

/// A server that stops answering without closing (frozen, as when it
/// reboots or its network goes) is said not to respond within seconds, and
/// given up and reconnected to in under half a minute, not two.
#[test]
fn a_server_that_stops_answering_is_noticed_in_seconds() {
    let f = Fixture::new(servers!());
    let host = demo_host(&f, "s2-freeze", FREEZE, None);
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    outcome(&rx).0.unwrap();
    term.text("echo ready-$((6*7))\n");
    wait_for(&term, "ready-42");
    let paused = Paused::new("s2-freeze");
    // The host's keepalive is the default: the bounds follow from it, with
    // room for a machine busy with the other tests.
    let t = Timing::from_keepalive(Some(Duration::from_secs(10))).unwrap();
    let slack = Duration::from_secs(5);
    let start = Instant::now();
    let mut stalled = None;
    let lost = loop {
        let left = (t.every + t.lost_after + slack * 2).saturating_sub(start.elapsed());
        match rx.recv_timeout(left).expect("not given up in time") {
            Event::Health(Health::Stalled { .. }) => stalled = Some(start.elapsed()),
            Event::Reconnecting { reason, .. } => break (start.elapsed(), reason),
            Event::Closed { failure, .. } => panic!("gave up: {failure:?}"),
            _ => {}
        }
    };
    let stalled = stalled.expect("never said it did not respond");
    // A question every 10 s; no answer for 5 s: stalled; for 20 s: lost.
    assert!(
        stalled <= t.every + t.stalled_after + slack,
        "stalled after {stalled:?}"
    );
    assert!(
        lost.0 <= t.every + t.lost_after + slack,
        "lost after {:?}",
        lost.0
    );
    let silent = t.lost_after.as_secs() as u32;
    assert!(
        matches!(
            &lost.1,
            Failure::Network { message, cause: NetCause::Silent(s), .. }
                if *s == silent && *message == format!("no answer for {silent} s")
        ),
        "{:?}",
        lost.1
    );
    drop(paused);
    let deadline = Instant::now() + Duration::from_secs(60);
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        match rx.recv_timeout(left).expect("not back in a minute") {
            Event::Connected(_) => break,
            Event::Closed { failure, .. } => panic!("gave up: {failure:?}"),
            _ => {}
        }
    }
    term.text("echo back-$((6*7))\n");
    wait_for(&term, "back-42");
}

/// A host with Mosh on.
fn mosh_host(f: &Fixture, label: &str, port: u16) -> ItemId {
    f.host(
        label,
        "127.0.0.1",
        port,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            mosh: Some(true),
            ..Settings::default()
        },
    )
}

/// Whether this computer has `mosh-client`.
fn has_mosh_client() -> bool {
    tokio::runtime::Runtime::new()
        .unwrap()
        .block_on(openward_ssh::client::find_program("mosh-client"))
        .is_some()
}

/// The events until the first shell is up, with the Mosh fallbacks that
/// came before it.
fn first_shell(rx: &Receiver<Event>) -> (Connected, Vec<MoshFallback>) {
    let mut fallbacks = Vec::new();
    loop {
        match rx
            .recv_timeout(Duration::from_secs(45))
            .expect("no outcome")
        {
            Event::Connected(c) => return (c, fallbacks),
            Event::MoshFallback { reason } => fallbacks.push(reason),
            Event::Closed { failure, .. } => panic!("{failure:?}"),
            _ => {}
        }
    }
}

/// Mosh asked for where it cannot be (no mosh-server in Dropbear's
/// image, or no mosh-client here): the session goes on over SSH, saying
/// why.
#[test]
fn mosh_where_it_cannot_be_goes_on_over_ssh() {
    let f = Fixture::new(servers!());
    let host = mosh_host(&f, "dropbear", 22200);
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    let (connected, fallbacks) = first_shell(&rx);
    assert!(!connected.mosh);
    let want = if has_mosh_client() {
        MoshFallback::NoServer
    } else {
        MoshFallback::NoClient
    };
    assert_eq!(fallbacks, [want]);
    term.text("echo ssh-$((6*7))\n");
    wait_for(&term, "ssh-42");
}

/// Over Mosh to the bastion, whose UDP is published: the shell is
/// mosh-client's, and exit ends it.
#[test]
fn a_mosh_session_over_udp() {
    let f = Fixture::new(servers!());
    if !has_mosh_client() {
        return eprintln!("skipped: no mosh-client here");
    }
    let host = mosh_host(&f, "bastion", BASTION);
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    let (connected, fallbacks) = first_shell(&rx);
    assert!(fallbacks.is_empty(), "{fallbacks:?}");
    assert!(connected.mosh);
    term.text("echo mosh-$((6*7))\n");
    wait_for(&term, "mosh-42");
    term.text("exit\n");
    loop {
        match rx.recv_timeout(Duration::from_secs(30)).expect("no end") {
            Event::MoshFallback { reason } => panic!("fell back: {reason:?}"),
            Event::Closed { exit_code, failure } => {
                assert_eq!((exit_code, failure), (Some(0), None));
                break;
            }
            _ => {}
        }
    }
}

/// A server whose UDP does not get through (this one's is not published):
/// after the wait, the session goes on over SSH, in tmux.
#[test]
fn mosh_without_udp_goes_on_over_ssh() {
    let f = Fixture::new(servers!());
    if !has_mosh_client() {
        return eprintln!("skipped: no mosh-client here");
    }
    let host = mosh_host(&f, "s2-openssh-9.2", 22092);
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    let (first, fallbacks) = first_shell(&rx);
    assert!(first.mosh && fallbacks.is_empty());
    let (again, fallbacks) = first_shell(&rx);
    assert_eq!(fallbacks, [MoshFallback::NoUdp]);
    assert!(!again.mosh);
    term.text("echo back-$((6*7))\n");
    wait_for(&term, "back-42");
}

/// Without tmux on the server (Dropbear's has none), a persistent session
/// is an ordinary shell, and says so.
#[test]
fn a_persistent_session_without_tmux_is_an_ordinary_shell() {
    let f = Fixture::new(servers!());
    let host = demo_host(&f, "dropbear", 22200, Some(true));
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    let mut state = None;
    loop {
        match rx
            .recv_timeout(Duration::from_secs(30))
            .expect("no outcome")
        {
            Event::Persistent { session, state: s } => {
                assert!(session.starts_with("ow-"), "{session}");
                state = Some(s);
            }
            Event::Connected(_) => break,
            Event::Closed { failure, .. } => panic!("{failure:?}"),
            _ => {}
        }
    }
    assert_eq!(state, Some(Persistence::NoTmux));
    term.text("echo plain-$((6*7))\n");
    wait_for(&term, "plain-42");
}

/// With tmux, a persistent session is found as it was after a cut and
/// after reconnecting by hand, and ends with the terminal.
#[test]
fn a_persistent_session_comes_back_as_it_was() {
    let f = Fixture::new(servers!());
    let has_tmux = std::process::Command::new(runtime())
        .args(["exec", "bastion", "sh", "-c", "command -v tmux"])
        .output()
        .unwrap()
        .status
        .success();
    if !has_tmux {
        return eprintln!("skipped: no tmux in bastion");
    }
    let persistence = |rx: &Receiver<Event>| {
        let mut state = None;
        loop {
            match rx
                .recv_timeout(Duration::from_secs(60))
                .expect("no outcome")
            {
                Event::Persistent { state: s, .. } => state = Some(s),
                Event::Connected(_) => return state,
                Event::Closed { failure, .. } => panic!("{failure:?}"),
                _ => {}
            }
        }
    };
    let host = bastion_host(&f, Some(true));
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    assert_eq!(persistence(&rx), Some(Persistence::New));
    term.text("MARK=kept-$((6*7)); echo set-$MARK\n");
    wait_for(&term, "set-kept-42");
    // Cut this connection only (other tests use the bastion too): the
    // sshd above the tmux client goes, tmux stays.
    term.text("echo sshd-$(ps -o ppid= -p $(tmux display -p '#{client_pid}') | tr -d ' ')-end\n");
    let deadline = Instant::now() + Duration::from_secs(10);
    let pid = loop {
        let screen = term.screen_text();
        if let Some(pid) = screen.lines().find_map(|l| {
            let pid = l.strip_prefix("sshd-")?.strip_suffix("-end")?;
            pid.chars().all(|c| c.is_ascii_digit()).then_some(pid)
        }) {
            break pid.to_owned();
        }
        assert!(Instant::now() < deadline, "the sshd pid:\n{screen}");
        std::thread::sleep(Duration::from_millis(20));
    };
    let killed = std::process::Command::new(runtime())
        .args(["exec", "bastion", "kill", "-9", &pid])
        .status()
        .unwrap();
    assert!(killed.success());
    assert_eq!(persistence(&rx), Some(Persistence::Resumed));
    term.text("echo again-$MARK\n");
    wait_for(&term, "again-kept-42");
    // «Reconnect» by hand: the same session, not a new one.
    let rx = f.reconnect(&term, host, |_| Answer::Cancel);
    assert_eq!(persistence(&rx), Some(Persistence::Resumed));
    term.text("echo by-hand-$MARK\n");
    wait_for(&term, "by-hand-kept-42");
    let sessions = || {
        let out = std::process::Command::new(runtime())
            .args(["exec", "-u", "demo", "bastion", "tmux", "ls"])
            .output()
            .unwrap();
        String::from_utf8_lossy(&out.stdout).into_owned()
    };
    assert_eq!(sessions().matches("ow-").count(), 1, "{}", sessions());
    // Closing the terminal ends it on the server.
    term.close();
    let deadline = Instant::now() + Duration::from_secs(10);
    while sessions().contains("ow-") {
        assert!(Instant::now() < deadline, "still there: {}", sessions());
        std::thread::sleep(Duration::from_millis(200));
    }
}

/// A server that takes the connection and never says a word is given up
/// on in the time the host allows, instead of «Connecting» for ever. No S2
/// needed: a listener here plays the silent server.
#[test]
fn a_silent_server_is_given_up_on_in_time() {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    std::thread::spawn(move || {
        let mut held = Vec::new();
        for socket in listener.incoming() {
            held.push(socket);
        }
    });
    let f = Fixture::new(PathBuf::new());
    let host = f.host(
        "mute",
        "127.0.0.1",
        port,
        Settings {
            user: Some("demo".into()),
            connect_timeout_secs: Some(2),
            ..Settings::default()
        },
    );
    let started = Instant::now();
    let (_term, rx) = f.connect(host, |_| Answer::Cancel);
    match outcome(&rx).0 {
        Err(Some(Failure::Network { message, cause, .. })) => {
            assert_eq!(message, "no answer for 2 s");
            assert_eq!(cause, NetCause::Silent(2));
        }
        other => panic!("not given up on: {other:?}"),
    }
    let took = started.elapsed();
    assert!(
        took >= Duration::from_secs(2) && took < Duration::from_secs(6),
        "{took:?}"
    );
}

/// A port nobody listens on: refused, by its kind and not its words. No
/// S2 needed.
#[test]
fn a_closed_port_is_refused() {
    let port = {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        listener.local_addr().unwrap().port()
    };
    let f = Fixture::new(PathBuf::new());
    let host = f.host(
        "closed",
        "127.0.0.1",
        port,
        Settings {
            user: Some("demo".into()),
            ..Settings::default()
        },
    );
    let (_term, rx) = f.connect(host, |_| Answer::Cancel);
    match outcome(&rx).0 {
        Err(Some(Failure::Network { cause, .. })) => assert_eq!(cause, NetCause::Refused),
        other => panic!("not refused: {other:?}"),
    }
}

#[test]
fn an_unknown_host_is_asked_about() {
    let f = Fixture::new(servers!());
    let host = f.host(
        "ninetwo",
        "127.0.0.1",
        22092,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            ..Settings::default()
        },
    );
    let (_t, rx) = f.connect(host, |_| Answer::Cancel);
    let (result, prompts) = outcome(&rx);
    assert!(matches!(result, Err(Some(Failure::HostKeyRejected { .. }))));
    let [
        Prompt::HostKey {
            fingerprint, port, ..
        },
    ] = prompts.as_slice()
    else {
        panic!("{prompts:?}")
    };
    assert!(fingerprint.starts_with("SHA256:"));
    assert_eq!(*port, 22092);
    assert!(f.app.vault().known_hosts().is_empty());

    let (_t, rx) = f.connect(host, |p| match p {
        Prompt::HostKey { .. } => Answer::Accept,
        _ => Answer::Cancel,
    });
    assert_eq!(outcome(&rx).0.unwrap().trust, Trust::New);
    assert_eq!(f.app.vault().known_hosts().len(), 1);
}

#[test]
fn a_changed_host_key_is_refused_until_trusted() {
    let f = Fixture::new(servers!());
    let fake = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILg+ccEU+buKk8f5ORMPyzCAzWM04Omv+MOaI8CvGd7f";
    f.app.trust_host_key("127.0.0.1", 22089, fake).unwrap();
    let host = f.host(
        "eightnine",
        "127.0.0.1",
        22089,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (_t, rx) = f.connect(host, |_| Answer::Accept);
    let (result, prompts) = outcome(&rx);
    assert!(prompts.is_empty(), "a changed key is never asked about");
    let Err(Some(Failure::HostKeyChanged(changed))) = result else {
        panic!("{result:?}")
    };
    let ChangedKey {
        key,
        fingerprint,
        previous,
        ..
    } = *changed;
    assert!(fingerprint.starts_with("SHA256:"));
    // What was trusted before, and where: OpenWard's own list.
    assert_eq!(
        previous,
        [PreviousKey {
            fingerprint: "SHA256:OcXwgqVGP3Hoo1XR2bnfs1DJan7drTyBcfSdQo6EdIE".into(),
            source: KeySource::OpenWard,
        }]
    );

    f.app.trust_host_key("127.0.0.1", 22089, &key).unwrap();
    let (_t, rx) = f.connect(host, |_| Answer::Cancel);
    assert_eq!(outcome(&rx).0.unwrap().trust, Trust::Known);
}

#[test]
fn passphrase_and_password_are_asked_for() {
    let f = Fixture::new(servers!());
    let with_passphrase = f.host(
        "pass",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519_pass"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (_t, rx) = f.connect(with_passphrase, |p| match p {
        Prompt::Passphrase { retry: false, .. } => text("wrong"),
        Prompt::Passphrase { retry: true, .. } => text("s2-passphrase"),
        _ => Answer::Cancel,
    });
    let (result, prompts) = outcome(&rx);
    result.unwrap();
    assert_eq!(prompts.len(), 2, "{prompts:?}");

    let password = f.password("demo");
    let with_password = f.host(
        "password",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![]),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    // With PAM the password comes as keyboard-interactive, which OpenSSH
    // (and OpenWard) try before the password method.
    let (_t, rx) = f.connect(with_password, move |p| match p {
        Prompt::Password { retry, .. } => text(if *retry { &password } else { "nope" }),
        Prompt::KeyboardInteractive {
            retry, questions, ..
        } if questions.len() == 1 => text(if *retry { &password } else { "nope" }),
        _ => Answer::Cancel,
    });
    let (result, prompts) = outcome(&rx);
    result.unwrap();
    let retries: Vec<bool> = prompts
        .iter()
        .map(|p| match p {
            Prompt::Password { retry, .. } | Prompt::KeyboardInteractive { retry, .. } => *retry,
            other => panic!("{other:?}"),
        })
        .collect();
    assert_eq!(retries, [false, true]);

    // Cancelling gives up.
    let (_t, rx) = f.connect(with_password, |_| Answer::Cancel);
    assert_eq!(outcome(&rx).0.unwrap_err(), Some(Failure::Cancelled));
}

/// About one P-256 key in 512 that `ssh-keygen` makes has a 31-byte
/// scalar, which `ssh-key` alone refuses. `openward-ssh`'s fixture (in
/// every server's authorized_keys, by fixtures.sh) logs in on all of them,
/// and behind a passphrase too.
#[test]
fn an_ecdsa_key_with_a_short_scalar_logs_in() {
    let f = Fixture::new(servers!());
    let key = |name: &str| {
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../openward-ssh/tests/fixtures");
        Some(vec![dir.join(name).display().to_string()])
    };
    let host = |label: &str, port, file: &str| {
        f.host(
            label,
            "127.0.0.1",
            port,
            Settings {
                user: Some("demo".into()),
                identity_files: key(file),
                host_key_policy: Some(HostKeyPolicy::AcceptNew),
                ..Settings::default()
            },
        )
    };
    for (label, port) in [
        ("s2-openssh-8.9", 22089),
        ("s2-openssh-9.2", 22092),
        ("bastion", BASTION),
        ("dropbear", 22200),
    ] {
        // No passphrase, no password: only the key gets in.
        let (_t, rx) = f.connect(host(label, port, "ecdsa-p256-short"), |_| Answer::Cancel);
        let (result, prompts) = outcome(&rx);
        result.unwrap_or_else(|e| panic!("{label}: {e:?}"));
        assert!(prompts.is_empty(), "{label}: {prompts:?}");
    }

    let encrypted = host("pass", BASTION, "ecdsa-p256-short-aes256-ctr");
    let (_t, rx) = f.connect(encrypted, |p| match p {
        Prompt::Passphrase { retry: false, .. } => text("openward-test"),
        _ => Answer::Cancel,
    });
    let (result, prompts) = outcome(&rx);
    result.unwrap();
    assert_eq!(prompts.len(), 1, "{prompts:?}");
}

/// An agent of the test's own at `socket`, holding `keys`; with `refuse`,
/// it will not sign with them, as when its user says no. On a Unix socket:
/// the Windows agent (a named pipe) is tried by hand, in
/// docs/plan/prueba-v0.3.md.
#[cfg(unix)]
fn test_agent(socket: &Path, keys: Vec<PrivateKey>, refuse: bool) {
    #[derive(Clone)]
    struct Refuse(bool);
    impl agent::server::Agent for Refuse {
        fn confirm_request(
            &self,
            msg: agent::server::MessageType,
        ) -> impl Future<Output = bool> + Send {
            let refused = self.0 && matches!(msg, agent::server::MessageType::Sign);
            async move { !refused }
        }
    }
    let socket = socket.to_owned();
    let (ready, ready_rx) = channel();
    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async move {
            let listener = tokio::net::UnixListener::bind(&socket).unwrap();
            let incoming = futures::stream::unfold(listener, |l| async move {
                Some((l.accept().await.map(|(s, _)| s), l))
            });
            tokio::spawn(agent::server::serve(Box::pin(incoming), Refuse(refuse)));
            let mut client = agent::client::AgentClient::connect_uds(&socket)
                .await
                .unwrap();
            for key in &keys {
                client.add_identity(key, &[]).await.unwrap();
            }
            ready.send(()).unwrap();
            std::future::pending::<()>().await;
        });
    });
    ready_rx.recv().unwrap();
}

/// An agent that will not sign (a denied confirmation, a locked password
/// manager) is passed over for the next method, not taken for a network
/// failure.
#[cfg(unix)]
#[test]
fn an_agent_that_will_not_sign_is_passed_over() {
    let f = Fixture::new(servers!());
    let socket = f._dir.path().join("agent.sock");
    let key = PrivateKey::read_openssh_file(f.fx.join("id_ed25519")).unwrap();
    test_agent(&socket, vec![key], true);
    let password = f.password("demo");
    let host = f.host(
        "refused",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![]),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    {
        let mut vault = f.app.vault();
        let Data::Host(mut h) = vault.get(host).unwrap().body.data.clone() else {
            unreachable!()
        };
        h.settings.agent = Some(Agent::Socket(socket.display().to_string()));
        vault.update(host, 1, Data::Host(h)).unwrap();
    }
    let (_t, rx) = f.connect(host, move |p| match p {
        Prompt::Password { .. } | Prompt::KeyboardInteractive { .. } => text(&password),
        _ => Answer::Cancel,
    });
    let (result, prompts) = outcome(&rx);
    result.unwrap();
    assert_eq!(prompts.len(), 1, "{prompts:?}");
}

/// A server that hangs up after too many keys (`MaxAuthTries`) failed the
/// login: no network failure, to be tried again offering them all.
#[cfg(unix)]
#[test]
fn too_many_keys_is_a_failed_login() {
    let f = Fixture::new(servers!());
    let socket = f._dir.path().join("agent.sock");
    let keys = (0..8)
        .map(|_| PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap())
        .collect();
    test_agent(&socket, keys, false);
    let host = f.host(
        "keyring",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![]),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    {
        let mut vault = f.app.vault();
        let Data::Host(mut h) = vault.get(host).unwrap().body.data.clone() else {
            unreachable!()
        };
        h.settings.agent = Some(Agent::Socket(socket.display().to_string()));
        vault.update(host, 1, Data::Host(h)).unwrap();
    }
    let (_t, rx) = f.connect(host, |_| Answer::Cancel);
    let (result, prompts) = outcome(&rx);
    match result {
        Err(Some(Failure::AuthFailed { methods, .. })) => {
            assert!(methods.contains(&"publickey".to_owned()), "{methods:?}");
        }
        other => panic!("not a failed login: {other:?}"),
    }
    assert!(prompts.is_empty(), "{prompts:?}");
}

/// Dropbear has no PAM: the plain password method.
#[test]
fn dropbear_asks_for_the_password_itself() {
    let f = Fixture::new(servers!());
    let password = f.password("demo");
    let host = f.host(
        "dropbear",
        "127.0.0.1",
        22200,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![]),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (_t, rx) = f.connect(host, move |p| match p {
        Prompt::Password { .. } => text(&password),
        _ => Answer::Cancel,
    });
    let (result, prompts) = outcome(&rx);
    result.unwrap();
    assert!(
        matches!(prompts.as_slice(), [Prompt::Password { retry: false, .. }]),
        "{prompts:?}"
    );
}

#[test]
fn two_factor_through_keyboard_interactive() {
    let f = Fixture::new(servers!());
    let (password, secret) = (f.password("otp"), f.read("totp_secret"));
    let host = f.host(
        "otp",
        "127.0.0.1",
        22089,
        Settings {
            user: Some("otp".into()),
            identity_files: Some(vec![]),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (_t, rx) = f.connect(host, move |p| {
        let Prompt::KeyboardInteractive { questions, .. } = p else {
            return Answer::Cancel;
        };
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        Answer::Text(
            questions
                .iter()
                .map(|q| {
                    Zeroizing::new(if q.text.to_lowercase().contains("password") {
                        password.clone()
                    } else {
                        openward_ssh::totp::code(&secret, now).unwrap()
                    })
                })
                .collect(),
        )
    });
    let (result, prompts) = outcome(&rx);
    result.unwrap();
    assert!(
        prompts
            .iter()
            .all(|p| matches!(p, Prompt::KeyboardInteractive { .. }))
    );
}

#[test]
fn a_saved_host_as_jump() {
    let f = Fixture::new(servers!());
    let common = Settings {
        user: Some("demo".into()),
        identity_files: f.key("id_ed25519"),
        host_key_policy: Some(HostKeyPolicy::AcceptNew),
        ..Settings::default()
    };
    let bastion = f.host("bastion", "127.0.0.1", BASTION, common.clone());
    let target = f.host(
        "target1",
        "target1",
        22,
        Settings {
            route: Some(Route::Jump(vec![Jump::Host(bastion)])),
            ..common
        },
    );
    let (term, rx) = f.connect(target, |_| Answer::Cancel);
    let (result, _) = outcome(&rx);
    assert_eq!(result.unwrap().hops, 2);
    // The bastion's round trip comes with the first check, at once.
    let hops = loop {
        if let Event::Hops { rtt_ms } = rx.recv_timeout(Duration::from_secs(10)).expect("no hops") {
            break rtt_ms;
        }
    };
    assert!(matches!(hops[..], [Some(_)]), "{hops:?}");
    term.text("hostname\n");
    wait_for(&term, "target1");
    assert_eq!(f.app.vault().known_hosts().len(), 2);
    // Each saved hop tells its system by its banner, the jump too.
    assert_eq!(system_of(&f, target).name, "Debian 12");
    assert_eq!(system_of(&f, bastion).name, "Debian 13");
}

/// Connecting tells the system: by the banner, which runs nothing, and
/// from /etc/os-release where the host asks for it (Dropbear's banner says
/// nothing).
#[test]
fn connecting_tells_the_system() {
    let f = Fixture::new(servers!());
    let ubuntu = demo_host(&f, "ubuntu", 22089, None);
    let (_term, rx) = f.connect(ubuntu, |_| Answer::Cancel);
    let (result, _) = outcome(&rx);
    result.unwrap();
    let s = system_of(&f, ubuntu);
    assert_eq!((s.code.as_str(), s.name.as_str()), ("ubu", "Ubuntu 22.04"));
    assert_eq!(s.source, SystemSource::Banner);
    assert!(
        s.evidence.starts_with("SSH-2.0-OpenSSH_8.9p1 Ubuntu"),
        "{s:?}"
    );

    let plain = demo_host(&f, "dropbear", 22200, None);
    let (_term, rx) = f.connect(plain, |_| Answer::Cancel);
    // Connected, and the app can offer to read os-release for it (the two
    // come in either order).
    let (mut connected, mut unknown) = (false, None);
    let deadline = Instant::now() + Duration::from_secs(30);
    while !connected || unknown.is_none() {
        let left = deadline.saturating_duration_since(Instant::now());
        match rx.recv_timeout(left).expect("not connected and told") {
            Event::Connected(_) => connected = true,
            Event::HostsChanged { unknown: u } => unknown = Some(u),
            Event::Closed { failure, .. } => panic!("closed: {failure:?}"),
            _ => {}
        }
    }
    assert_eq!(system_of(&f, plain).code, "?");
    assert_eq!(unknown, Some(vec![plain]));
    // Asked to, it is read from now on, and now over the connection that
    // is up.
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    assert!(runtime.block_on(f.app.read_os_release(plain)).unwrap());
    let h = f.app.vault().host(plain).unwrap().clone();
    assert_eq!(h.settings.read_os_release, Some(true));
    let s = h.system.unwrap();
    assert_eq!(
        (s.code.as_str(), s.source),
        ("alp", SystemSource::OsRelease)
    );
    // Without a connection it waits for the next one.
    let idle = demo_host(&f, "idle", 22299, None);
    assert!(!runtime.block_on(f.app.read_os_release(idle)).unwrap());
    assert_eq!(
        f.app.vault().host(idle).unwrap().settings.read_os_release,
        Some(true)
    );

    let asks = f.host(
        "dropbear-os",
        "127.0.0.1",
        22200,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            read_os_release: Some(true),
            ..Settings::default()
        },
    );
    let (_term, rx) = f.connect(asks, |_| Answer::Cancel);
    outcome(&rx).0.unwrap();
    let s = system_of(&f, asks);
    assert_eq!(s.code, "alp");
    assert!(s.name.starts_with("Alpine Linux 3."), "{s:?}");
    assert_eq!(s.source, SystemSource::OsRelease);
}

#[cfg(unix)]
#[test]
fn a_local_shell() {
    let dir = tempfile::tempdir().unwrap();
    let app = App::open_as(&dir.path().join("data"), Local::from_env()).unwrap();
    let (tx, rx) = channel();
    let ui = Arc::new(Ui {
        app: OnceLock::new(),
        tx: Mutex::new(tx),
        reply: Box::new(|_| Answer::Cancel),
    });
    let term = app.terminal(80, 24, 1000);
    app.open_local(&term, Some("/bin/sh".into()), ui).unwrap();
    assert!(matches!(rx.recv().unwrap(), Event::Started { program } if program == "/bin/sh"));
    term.text("echo local-$((40+2)); exit 3\n");
    wait_for(&term, "local-42");
    let Event::Closed { exit_code, failure } = rx.recv_timeout(Duration::from_secs(10)).unwrap()
    else {
        panic!("expected the shell to end")
    };
    assert_eq!((exit_code, failure), (Some(3), None));
    assert!(term.poll().is_some());
}

impl Fixture {
    fn sftp(
        &self,
        host: ItemId,
        reply: impl Fn(&Prompt) -> Answer + Send + Sync + 'static,
    ) -> (Arc<openward_app::Sftp>, Receiver<Event>) {
        let (tx, rx) = channel();
        let ui = Arc::new(Ui {
            app: OnceLock::new(),
            tx: Mutex::new(tx),
            reply: Box::new(reply),
        });
        let _ = ui.app.set(Arc::downgrade(&self.app));
        let sftp = self.app.sftp();
        self.app.connect_sftp(&sftp, host, ui).unwrap();
        (sftp, rx)
    }
}

/// Runs a browser's calls, which may come from any executor.
fn block_on<F: std::future::Future>(f: F) -> F::Output {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(f)
}

/// A browser for a host with a terminal open goes over the terminal's
/// connection: no password again, and it stays up when the terminal goes.
#[test]
fn sftp_goes_over_the_terminal_connection() {
    let f = Fixture::new(servers!());
    let password = f.password("demo");
    let host = f.host(
        "password",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![]),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (term, rx) = f.connect(host, move |p| match p {
        Prompt::Password { .. } | Prompt::KeyboardInteractive { .. } => text(&password),
        _ => Answer::Cancel,
    });
    let terminal = outcome(&rx).0.unwrap();

    let (sftp, events) = f.sftp(host, |p| panic!("asked again: {p:?}"));
    let mut stages = Vec::new();
    let connected = loop {
        match events.recv_timeout(Duration::from_secs(30)).unwrap() {
            Event::Connected(c) => break c,
            Event::Stage { stage, .. } => stages.push(stage),
            Event::Closed { failure, .. } => panic!("{failure:?}"),
            _ => {}
        }
    };
    assert_eq!(stages, [openward_app::events::Stage::OpeningSftp]);
    assert_eq!(connected.fingerprint, terminal.fingerprint);
    let home = block_on(sftp.home()).unwrap();
    assert_eq!(home, "/home/demo");

    // The terminal ends; the browser keeps the connection.
    term.text("exit\n");
    loop {
        if let Event::Closed { .. } = rx.recv_timeout(Duration::from_secs(10)).unwrap() {
            break;
        }
    }
    drop(term);
    let names: Vec<String> = block_on(sftp.list(home))
        .unwrap()
        .into_iter()
        .map(|e| e.name)
        .collect();
    assert!(names.contains(&".profile".to_owned()), "{names:?}");
}

/// A new key's public half put on the server over SFTP (as ssh-copy-id
/// does), once; then that key logs in. The server's file is put back.
#[test]
fn a_public_key_put_on_the_server_then_used() {
    use openward_ssh::russh::keys::ssh_key::{Algorithm, LineEnding, PrivateKey};
    let f = Fixture::new(servers!());
    let password = f.password("demo");
    let host = f.host(
        "with-password",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![]),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (sftp, events) = f.sftp(host, move |p| match p {
        Prompt::Password { .. } | Prompt::KeyboardInteractive { .. } => text(&password),
        _ => Answer::Cancel,
    });
    outcome(&events).0.unwrap();
    let remote = sftp.link().get().unwrap();
    let file = "/home/demo/.ssh/authorized_keys";
    let original = block_on(remote.read_small(file, 1 << 20)).unwrap();

    let keys = tempfile::tempdir().unwrap();
    let key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
    let path = keys.path().join("id_new");
    std::fs::write(&path, key.to_openssh(LineEnding::LF).unwrap().as_bytes()).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
    }
    let line = key.public_key().to_openssh().unwrap();
    let extra = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
    let injected = format!("{line}\n{}", extra.public_key().to_openssh().unwrap());
    let refused = block_on(sftp.install_public_key(injected));
    let after_refusal = block_on(remote.read_small(file, 1 << 20)).unwrap();
    let added = block_on(sftp.install_public_key(line.clone()));
    let again = block_on(sftp.install_public_key(line));

    let with_key = f.host(
        "with-new-key",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![path.display().to_string()]),
            identities_only: Some(true),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (_term, rx) = f.connect(with_key, |p| panic!("asked: {p:?}"));
    let logged_in = outcome(&rx).0;

    // Put the server's file back before checking anything; whole, since
    // other tests log in with it meanwhile.
    if let Some(bytes) = &original {
        let next = format!("{file}.restore");
        block_on(remote.write_all(&next, bytes, 0o600)).unwrap();
        block_on(remote.rename(&next, file, true)).unwrap();
    }
    assert!(added.unwrap(), "the key went in");
    assert!(refused.is_err(), "a second key must be rejected");
    assert_eq!(
        after_refusal, original,
        "invalid input must not change authorized_keys"
    );
    assert!(!again.unwrap(), "a key already there is not added again");
    logged_in.unwrap();
}

/// Without a terminal, a browser connects on its own; transfers go through
/// the app and outlive the browser.
#[test]
fn sftp_on_its_own_and_transfers_that_outlive_it() {
    use openward_app::files::{Direction, JobState, OnConflict, Request};
    let f = Fixture::new(servers!());
    let host = f.host(
        "bastion",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (sftp, events) = f.sftp(host, |_| Answer::Cancel);
    outcome(&events).0.unwrap();
    let dir = format!("/home/demo/ow-app-sftp-{}", std::process::id());
    block_on(sftp.remove(vec![dir.clone()])).unwrap();
    block_on(sftp.mkdir(dir.clone())).unwrap();

    let local = tempfile::tempdir().unwrap();
    let file = local.path().join("data.bin");
    std::fs::write(&file, vec![7u8; 5 << 20]).unwrap();
    let id = f.app.transfer(
        &sftp,
        Request {
            direction: Direction::Upload,
            source: file.display().to_string(),
            dest_dir: dir.clone(),
            on_conflict: OnConflict::Replace,
        },
    );
    // Closed at once: the transfer still has its connection.
    let link = sftp.link();
    drop(sftp);
    let job = block_on(f.app.transfers().wait(id)).unwrap();
    assert_eq!(job.state, JobState::Done, "{:?}", job.error);
    assert_eq!(job.host, "bastion");

    let remote = link.get().unwrap();
    let got = block_on(remote.stat(&format!("{dir}/data.bin")))
        .unwrap()
        .unwrap();
    assert_eq!(got.size, 5 << 20);

    // A browser opened again takes up the same link.
    let (again, events) = f.sftp(host, |_| Answer::Cancel);
    outcome(&events).0.unwrap();
    assert!(Arc::ptr_eq(&again.link(), &link));
    let conflicts = block_on(again.conflicts(
        Direction::Upload,
        vec![file.display().to_string()],
        dir.clone(),
    ))
    .unwrap();
    assert_eq!(conflicts.len(), 1);
    assert_eq!(conflicts[0].theirs.size, 5 << 20);
    block_on(again.remove(vec![dir])).unwrap();
}

// ----------------------------------------------------------------- tunnels

use openward_app::vault::proto::{ForwardKind, PortForward, Proxy, ProxyServer};
use openward_app::{TunnelError, TunnelState};
use std::io::{Read, Write};

impl Fixture {
    fn tunnel(
        &self,
        host: ItemId,
        kind: ForwardKind,
        port: u16,
        dest: Option<(&str, u16)>,
        autostart: bool,
    ) -> ItemId {
        self.app
            .vault()
            .create(Data::PortForward(PortForward {
                label: format!("{kind:?} {port}"),
                host,
                kind,
                listen_port: port,
                listen_address: None,
                dest_host: dest.map(|(h, _)| h.to_owned()),
                dest_port: dest.map(|(_, p)| p),
                autostart,
                source: None,
                imported: None,
                extra: Default::default(),
            }))
            .unwrap()
    }

    fn state(&self, id: ItemId) -> TunnelState {
        self.app
            .tunnels()
            .into_iter()
            .find(|t| t.id == id)
            .unwrap()
            .state
    }

    fn wait_state(&self, id: ItemId, done: impl Fn(&TunnelState) -> bool) -> TunnelState {
        let deadline = Instant::now() + Duration::from_secs(20);
        loop {
            let s = self.state(id);
            if done(&s) {
                return s;
            }
            assert!(Instant::now() < deadline, "tunnel stuck in {s:?}");
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    /// Opens a tunnel, answering questions with `reply`.
    fn open_tunnel(
        &self,
        id: ItemId,
        reply: impl Fn(&Prompt) -> Answer + Send + Sync + 'static,
    ) -> Receiver<Event> {
        let (tx, rx) = channel();
        let ui = Arc::new(Ui {
            app: OnceLock::new(),
            tx: Mutex::new(tx),
            reply: Box::new(reply),
        });
        let _ = ui.app.set(Arc::downgrade(&self.app));
        self.app.open_tunnel(id, ui).unwrap();
        rx
    }

    fn bastion(&self) -> ItemId {
        self.host(
            "bastion",
            "127.0.0.1",
            BASTION,
            Settings {
                user: Some("demo".into()),
                identity_files: self.key("id_ed25519"),
                host_key_policy: Some(HostKeyPolicy::AcceptNew),
                ..Settings::default()
            },
        )
    }
}

fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

/// The first bytes a server sends on `port`: an SSH banner, say.
fn banner(stream: &mut std::net::TcpStream) -> String {
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    let mut buf = [0u8; 64];
    let n = stream.read(&mut buf).unwrap();
    String::from_utf8_lossy(&buf[..n]).into_owned()
}

/// Local (-L) and dynamic (-D) tunnels reach the bastion's own SSH server.
#[test]
fn local_and_dynamic_tunnels() {
    let f = Fixture::new(servers!());
    let host = f.bastion();
    let port = free_port();
    let local = f.tunnel(
        host,
        ForwardKind::Local,
        port,
        Some(("127.0.0.1", 22)),
        false,
    );
    let rx = f.open_tunnel(local, |_| Answer::Cancel);
    outcome(&rx).0.unwrap();
    assert_eq!(
        f.state(local),
        TunnelState::Open {
            port,
            connections: 0
        }
    );
    let mut s = std::net::TcpStream::connect(("127.0.0.1", port)).unwrap();
    assert!(
        banner(&mut s).starts_with("SSH-2.0-OpenSSH"),
        "through the tunnel"
    );
    f.wait_state(local, |s| {
        matches!(s, TunnelState::Open { connections: 1, .. })
    });
    drop(s);

    // A SOCKS5 proxy whose connections leave from the bastion.
    let socks_port = free_port();
    let dynamic = f.tunnel(host, ForwardKind::Dynamic, socks_port, None, false);
    let rx = f.open_tunnel(dynamic, |_| Answer::Cancel);
    outcome(&rx).0.unwrap();
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let stream = rt
        .block_on(openward_ssh::forward::socks5_connect(
            socks_port,
            "127.0.0.1",
            22,
        ))
        .unwrap();
    let mut s = stream.into_std().unwrap();
    s.set_nonblocking(false).unwrap();
    assert!(banner(&mut s).starts_with("SSH-2.0-OpenSSH"));

    // Taken: the second one cannot listen.
    let clash = f.tunnel(
        host,
        ForwardKind::Local,
        port,
        Some(("127.0.0.1", 22)),
        false,
    );
    let rx = f.open_tunnel(clash, |_| Answer::Cancel);
    assert!(outcome(&rx).0.is_err());
    assert_eq!(
        f.state(clash),
        TunnelState::Failed {
            error: TunnelError::PortInUse {
                port,
                remote: false
            },
            on_connect: false
        }
    );
    assert!(f.app.free_port_near(port).is_some_and(|p| p > port));

    // Closed, the port is free again.
    f.app.close_tunnel(local);
    assert_eq!(f.state(local), TunnelState::Closed);
    let deadline = Instant::now() + Duration::from_secs(5);
    while std::net::TcpListener::bind(("127.0.0.1", port)).is_err() {
        assert!(Instant::now() < deadline, "still listening");
        std::thread::sleep(Duration::from_millis(20));
    }
}

/// A tunnel to `localhost` listens on both loopbacks; closing it cuts the
/// connections going through it, not just new ones.
#[test]
fn closing_a_tunnel_cuts_its_connections() {
    let f = Fixture::new(servers!());
    let host = f.bastion();
    let port = free_port();
    let local = f.tunnel(
        host,
        ForwardKind::Local,
        port,
        Some(("127.0.0.1", 22)),
        false,
    );
    outcome(&f.open_tunnel(local, |_| Answer::Cancel))
        .0
        .unwrap();
    let mut s = std::net::TcpStream::connect(("::1", port)).unwrap();
    assert!(banner(&mut s).starts_with("SSH-2.0-OpenSSH"), "over IPv6");
    f.wait_state(local, |s| {
        matches!(s, TunnelState::Open { connections: 1, .. })
    });

    f.app.close_tunnel(local);
    let mut rest = [0u8; 64];
    match s.read(&mut rest) {
        Ok(0) => {}
        Err(e) if e.kind() == std::io::ErrorKind::ConnectionReset => {}
        other => panic!("still connected: {other:?}"),
    }
}

/// Closed while it was connecting (a question pending): it stays closed,
/// whatever the connection does next.
#[test]
fn a_tunnel_closed_while_opening_stays_closed() {
    let f = Fixture::new(servers!());
    let password = f.password("demo");
    let host = f.host(
        "with password",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![]),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let port = free_port();
    let local = f.tunnel(
        host,
        ForwardKind::Local,
        port,
        Some(("127.0.0.1", 22)),
        false,
    );
    let app = Arc::downgrade(&f.app);
    let rx = f.open_tunnel(local, move |p| match p {
        Prompt::Password { .. } | Prompt::KeyboardInteractive { .. } => {
            app.upgrade().unwrap().close_tunnel(local);
            text(&password)
        }
        _ => Answer::Cancel,
    });
    assert_eq!(outcome(&rx).0.unwrap_err(), None, "closed, not failed");
    assert_eq!(f.state(local), TunnelState::Closed);
    assert!(std::net::TcpListener::bind(("127.0.0.1", port)).is_ok());
}

/// A browser through a SOCKS tunnel opens hundreds of connections at once:
/// the tunnel answers them all and is still there after. (To a closed port
/// of the server: hundreds at its sshd would make it drop the other
/// tests' connections, `MaxStartups`.)
#[test]
fn a_socks_tunnel_takes_a_browser_s_load() {
    let f = Fixture::new(servers!());
    let host = f.bastion();
    let port = free_port();
    let socks = f.tunnel(host, ForwardKind::Dynamic, port, None, false);
    outcome(&f.open_tunnel(socks, |_| Answer::Cancel))
        .0
        .unwrap();
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap();
    let answered = rt.block_on(async {
        let mut all = tokio::task::JoinSet::new();
        for _ in 0..300 {
            all.spawn(openward_ssh::forward::socks5_connect(port, "127.0.0.1", 9));
        }
        let mut answered = 0;
        while let Some(done) = all.join_next().await {
            let refused = done.unwrap().err().map(|e| e.to_string());
            if refused.is_some_and(|e| e.starts_with("SOCKS5 CONNECT failed")) {
                answered += 1;
            }
        }
        answered
    });
    assert_eq!(answered, 300);
    f.wait_state(socks, |s| {
        matches!(s, TunnelState::Open { connections: 0, .. })
    });
    // Still taking connections.
    let stream = rt
        .block_on(openward_ssh::forward::socks5_connect(port, "127.0.0.1", 22))
        .unwrap();
    let mut s = stream.into_std().unwrap();
    s.set_nonblocking(false).unwrap();
    assert!(banner(&mut s).starts_with("SSH-2.0-OpenSSH"));
}

/// Remote (-R): the server's port leads to an echo server here.
#[test]
fn remote_tunnel() {
    let f = Fixture::new(servers!());
    let host = f.bastion();
    let echo = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let echo_port = echo.local_addr().unwrap().port();
    std::thread::spawn(move || {
        for s in echo.incoming() {
            let Ok(mut s) = s else { return };
            let mut buf = [0u8; 64];
            if let Ok(n) = s.read(&mut buf) {
                let _ = s.write_all(&buf[..n]);
            }
        }
    });
    let server_port = 20000 + (std::process::id() % 10000) as u16;
    let id = f.tunnel(
        host,
        ForwardKind::Remote,
        server_port,
        Some(("127.0.0.1", echo_port)),
        false,
    );
    let rx = f.open_tunnel(id, |_| Answer::Cancel);
    outcome(&rx).0.unwrap();
    // From the server, through it.
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    outcome(&rx).0.unwrap();
    term.text(&format!(
        "echo hola | nc -q1 127.0.0.1 {server_port} | sed 's/^/got-/'\n"
    ));
    wait_for(&term, "got-hola");
    f.app.close_tunnel(id);
}

/// A tunnel that opens on connect comes up with a terminal, over its
/// connection; one whose port is taken says so and the terminal carries on.
#[test]
fn tunnels_open_with_the_terminal() {
    let f = Fixture::new(servers!());
    let password = f.password("demo");
    let host = f.host(
        "password",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![]),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let port = free_port();
    let auto = f.tunnel(
        host,
        ForwardKind::Local,
        port,
        Some(("127.0.0.1", 22)),
        true,
    );
    let taken = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let taken_port = taken.local_addr().unwrap().port();
    let busy = f.tunnel(
        host,
        ForwardKind::Local,
        taken_port,
        Some(("127.0.0.1", 22)),
        true,
    );
    let manual = f.tunnel(host, ForwardKind::Dynamic, free_port(), None, false);

    let (term, rx) = f.connect(host, move |p| match p {
        Prompt::Password { .. } | Prompt::KeyboardInteractive { .. } => text(&password),
        _ => Answer::Cancel,
    });
    outcome(&rx).0.unwrap();
    f.wait_state(auto, |s| matches!(s, TunnelState::Open { .. }));
    assert_eq!(
        f.wait_state(busy, |s| matches!(s, TunnelState::Failed { .. })),
        TunnelState::Failed {
            error: TunnelError::PortInUse {
                port: taken_port,
                remote: false
            },
            on_connect: true
        }
    );
    assert_eq!(f.state(manual), TunnelState::Closed);

    // Opened by hand while the terminal is up: no password again.
    let opened = f.open_tunnel(manual, |p| panic!("asked again: {p:?}"));
    outcome(&opened).0.unwrap();

    // The terminal goes (its shell, then the terminal itself); the tunnels
    // keep the connection.
    term.text("exit\n");
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if let Event::Closed { .. } = rx.recv_timeout(left).expect("the shell did not end") {
            break;
        }
    }
    drop(term);
    assert!(matches!(f.state(auto), TunnelState::Open { .. }));
    let mut s = std::net::TcpStream::connect(("127.0.0.1", port)).unwrap();
    assert!(banner(&mut s).starts_with("SSH-2.0-OpenSSH"));
    drop(taken);
}

/// IM-1: old foreign-program records cannot start tunnels through either
/// connection entry point. Ordinary autostart and explicit opening remain.
#[test]
fn imported_tunnels_wait_for_review_in_terminal_and_sftp_connections() {
    use openward_app::vault::proto::Imported;

    for browser in [false, true] {
        let f = Fixture::new(servers!());
        let host = f.bastion();
        let mut imported = Vec::new();
        for kind in [
            ForwardKind::Local,
            ForwardKind::Remote,
            ForwardKind::Dynamic,
        ] {
            let id = f.tunnel(host, kind, free_port(), Some(("127.0.0.1", 22)), true);
            let mut vault = f.app.vault();
            let mut spec = vault.port_forward(id).unwrap().clone();
            spec.imported = Some(Imported {
                from: "termius".into(),
                id: format!("legacy-{kind:?}"),
                extra: Default::default(),
            });
            let rev = vault.get(id).unwrap().rev;
            vault.update(id, rev, Data::PortForward(spec)).unwrap();
            imported.push(id);
        }
        let control = f.tunnel(
            host,
            ForwardKind::Local,
            free_port(),
            Some(("127.0.0.1", 22)),
            true,
        );
        let (_terminal, _browser) = if browser {
            let (sftp, events) = f.sftp(host, |p| panic!("unexpected prompt: {p:?}"));
            outcome(&events).0.unwrap();
            (None, Some(sftp))
        } else {
            let (terminal, events) = f.connect(host, |p| panic!("unexpected prompt: {p:?}"));
            outcome(&events).0.unwrap();
            (Some(terminal), None)
        };
        // Connected is emitted after all autostart attempts finish.
        assert!(matches!(f.state(control), TunnelState::Open { .. }));
        for id in &imported {
            assert_eq!(f.state(*id), TunnelState::Closed, "browser={browser}");
        }
        let opened = f.open_tunnel(imported[0], |p| panic!("asked again: {p:?}"));
        outcome(&opened).0.unwrap();
        assert!(matches!(f.state(imported[0]), TunnelState::Open { .. }));
    }
}

/// A tiny HTTP CONNECT proxy that wants ana:secreto; its port.
fn login_proxy() -> u16 {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    std::thread::spawn(move || {
        for s in listener.incoming() {
            let Ok(mut s) = s else { return };
            std::thread::spawn(move || {
                let mut head = Vec::new();
                let mut byte = [0u8; 1];
                while !head.ends_with(b"\r\n\r\n") {
                    if s.read(&mut byte).unwrap_or(0) == 0 {
                        return;
                    }
                    head.push(byte[0]);
                }
                let head = String::from_utf8_lossy(&head).into_owned();
                // "ana:secreto" in base64.
                if !head.contains("Proxy-Authorization: Basic YW5hOnNlY3JldG8=") {
                    let _ = s.write_all(b"HTTP/1.1 407 Proxy Authentication Required\r\n\r\n");
                    return;
                }
                let target = head.split_whitespace().nth(1).unwrap().to_owned();
                let up = std::net::TcpStream::connect(target).unwrap();
                s.write_all(b"HTTP/1.1 200 OK\r\n\r\n").unwrap();
                let (mut a, mut b) = (s.try_clone().unwrap(), up.try_clone().unwrap());
                let (mut c, mut d) = (s, up);
                std::thread::spawn(move || std::io::copy(&mut a, &mut b));
                let _ = std::io::copy(&mut d, &mut c);
            });
        }
    });
    port
}

/// Through an HTTP proxy that asks for a login: the password is asked
/// for, the user comes from the settings.
#[test]
fn through_a_proxy_that_asks_for_a_password() {
    let f = Fixture::new(servers!());
    let proxy_port = login_proxy();
    let host = f.host(
        "behind",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            proxy: Some(Proxy::Http(ProxyServer {
                host: "127.0.0.1".into(),
                port: proxy_port,
                user: Some("ana".into()),
                extra: Default::default(),
            })),
            ..Settings::default()
        },
    );
    let (_term, rx) = f.connect(host, |p| match p {
        Prompt::ProxyLogin { retry: false, .. } => text("mal"),
        Prompt::ProxyLogin { retry: true, .. } => text("secreto"),
        _ => Answer::Cancel,
    });
    let (result, prompts) = outcome(&rx);
    result.unwrap();
    assert_eq!(
        prompts,
        [
            Prompt::ProxyLogin {
                proxy: format!("127.0.0.1:{proxy_port}"),
                user: "ana".into(),
                retry: false
            },
            Prompt::ProxyLogin {
                proxy: format!("127.0.0.1:{proxy_port}"),
                user: "ana".into(),
                retry: true
            },
        ]
    );
    // Cancelling gives up.
    let (_term, rx) = f.connect(host, |_| Answer::Cancel);
    assert_eq!(outcome(&rx).0.unwrap_err(), Some(Failure::Cancelled));
}

/// A security key's sk-ssh-ed25519 key on the server: it logs in, asking
/// for the touch; with another key plugged in, the failure says it was not
/// this one. (A key in software, which signs as a real one does.)
#[test]
fn a_security_key_logs_in_and_says_when_it_is_not_this_one() {
    use openward_fido::soft::SoftKeys;
    let f = Fixture::new(servers!());
    let password = f.password("demo");
    let soft = Arc::new(SoftKeys::new());
    f.app.set_security_keys(soft.clone());
    let with_password = f.host(
        "with-password",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![]),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let answer = password.clone();
    let (sftp, events) = f.sftp(with_password, move |p| match p {
        Prompt::Password { .. } | Prompt::KeyboardInteractive { .. } => text(&answer),
        _ => Answer::Cancel,
    });
    outcome(&events).0.unwrap();
    let remote = sftp.link().get().unwrap();
    let file = "/home/demo/.ssh/authorized_keys";
    let original = block_on(remote.read_small(file, 1 << 20)).unwrap();

    let key =
        openward_fido::new_key(&*soft, openward_fido::Kind::Ed25519, "s2-sk", None, false).unwrap();
    let keys = tempfile::tempdir().unwrap();
    let path = keys.path().join("id_ed25519_sk");
    std::fs::write(
        &path,
        key.to_openssh(openward_ssh::russh::keys::ssh_key::LineEnding::LF)
            .unwrap()
            .as_bytes(),
    )
    .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
    }
    let added = block_on(sftp.install_public_key(key.public_key().to_openssh().unwrap()));

    let with_key = f.host(
        "with-security-key",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![path.display().to_string()]),
            identities_only: Some(true),
            agent: Some(openward_app::vault::proto::Agent::Off),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (_term, rx) = f.connect(with_key, |p| panic!("asked: {p:?}"));
    let mut touched = false;
    let logged_in = loop {
        match rx
            .recv_timeout(Duration::from_secs(30))
            .expect("no outcome")
        {
            Event::Stage {
                stage: Stage::TouchKey,
                ..
            } => touched = true,
            Event::Connected(c) => break Ok(c),
            Event::Closed { failure, .. } => break Err(failure),
            _ => {}
        }
    };

    // Another key plugged in: not this one.
    f.app.set_security_keys(Arc::new(SoftKeys::new()));
    let (_term, rx) = f.connect(with_key, |p| match p {
        Prompt::Password { .. } | Prompt::KeyboardInteractive { .. } => text("not-this-one"),
        _ => Answer::Cancel,
    });
    let other = outcome(&rx).0;

    if let Some(bytes) = &original {
        let next = format!("{file}.restore");
        block_on(remote.write_all(&next, bytes, 0o600)).unwrap();
        block_on(remote.rename(&next, file, true)).unwrap();
    }
    assert!(added.unwrap(), "the key went in");
    logged_in.unwrap();
    assert!(touched, "the touch was asked for");
    assert!(
        matches!(
            other,
            Err(Some(Failure::AuthFailed {
                security_key: Some(SecurityKeyProblem::NotThisKey),
                ..
            }))
        ),
        "{other:?}"
    );
}

/// A key only accepted through its certificate, with one that ran out
/// yesterday: it is not offered, and the failure says it was the reason.
#[test]
fn an_expired_certificate_is_why_the_login_fails() {
    let f = Fixture::new(servers!());
    let dir = tempfile::tempdir().unwrap();
    let key = dir.path().join("id_cert");
    std::fs::copy(f.fx.join("id_cert"), &key).unwrap();
    std::fs::copy(f.fx.join("id_cert.pub"), dir.path().join("id_cert.pub")).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&key, std::fs::Permissions::from_mode(0o600)).unwrap();
    }
    let signed = std::process::Command::new("ssh-keygen")
        .args(["-q", "-s"])
        .arg(f.fx.join("user_ca"))
        .args(["-I", "s2-old", "-n", "demo", "-V", "-2d:-1d"])
        .arg(dir.path().join("id_cert.pub"))
        .status()
        .unwrap();
    assert!(signed.success());
    let cert = dir.path().join("id_cert-cert.pub");
    let host = f.host(
        "bastion",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: Some(vec![key.display().to_string()]),
            identities_only: Some(true),
            agent: Some(openward_app::vault::proto::Agent::Off),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    // Wrong passwords, so that it ends as a failed login.
    let (_term, rx) = f.connect(host, |p| match p {
        Prompt::Password { .. } | Prompt::KeyboardInteractive { .. } => text("not-this-one"),
        _ => Answer::Cancel,
    });
    match outcome(&rx).0 {
        Err(Some(Failure::AuthFailed {
            expired_certificate: Some(path),
            ..
        })) => assert_eq!(std::path::Path::new(&path), cert),
        other => panic!("not a failed login because of the certificate: {other:?}"),
    }
}

/// The user, key and certificate come from the identity of the host's
/// group: the key is only accepted through its certificate.
#[test]
fn an_identity_of_the_group_logs_in_with_its_certificate() {
    let f = Fixture::new(servers!());
    let identity = f
        .app
        .vault()
        .create(Data::Identity(Identity {
            label: "demo con certificado".into(),
            settings: Settings {
                user: Some("demo".into()),
                identity_files: f.key("id_cert"),
                certificate_files: f.key("id_cert-cert.pub"),
                identities_only: Some(true),
                ..Settings::default()
            },
            ..Identity::default()
        }))
        .unwrap();
    let group = f
        .app
        .vault()
        .create(Data::Group(Group {
            name: "s2".into(),
            settings: Settings {
                user: Some("nobody-else".into()),
                identity: Some(UseIdentity::Id(identity)),
                host_key_policy: Some(HostKeyPolicy::AcceptNew),
                ..Settings::default()
            },
            ..Group::default()
        }))
        .unwrap();
    let host = f.host("bastion", "127.0.0.1", BASTION, Settings::default());
    {
        let mut vault = f.app.vault();
        let Data::Host(mut h) = vault.get(host).unwrap().body.data.clone() else {
            unreachable!()
        };
        h.group = Some(group);
        vault.update(host, 1, Data::Host(h)).unwrap();
    }
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    let (connected, prompts) = outcome(&rx);
    connected.unwrap();
    assert!(prompts.is_empty(), "{prompts:?}");
    term.text("echo who-$(whoami)-end\n");
    wait_for(&term, "who-demo-end");
}

/// A host key marked `@revoked` in `~/.ssh/known_hosts` is refused, even
/// after OpenWard trusted it.
#[test]
fn a_revoked_host_key_is_refused() {
    let f = Fixture::new(servers!());
    let host = f.host(
        "bastion",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    outcome(&rx).0.unwrap();
    term.close();
    let trusted = f.app.vault().known_hosts_text();
    let key = trusted
        .split_whitespace()
        .skip(1)
        .take(2)
        .collect::<Vec<_>>()
        .join(" ");
    let ssh = f.app.local().ssh_dir.clone();
    std::fs::create_dir_all(&ssh).unwrap();
    std::fs::write(ssh.join("known_hosts"), format!("@revoked * {key}\n")).unwrap();

    let (_term, rx) = f.connect(host, |_| Answer::Cancel);
    match outcome(&rx).0 {
        Err(Some(Failure::HostKeyRevoked { fingerprint, .. })) => {
            assert!(fingerprint.starts_with("SHA256:"), "{fingerprint}");
        }
        other => panic!("not refused as revoked: {other:?}"),
    }
}

/// A host certificate of a CA that is not trusted falls back to the plain
/// key, as in OpenSSH: here known.
#[test]
fn a_certificate_of_another_ca_falls_back_to_the_known_key() {
    let f = Fixture::new(servers!());
    let scan = std::process::Command::new("ssh-keyscan")
        .args(["-t", "ed25519", "-p", &BASTION.to_string(), "127.0.0.1"])
        .output()
        .unwrap();
    let plain = String::from_utf8(scan.stdout).unwrap();
    assert!(plain.contains("ssh-ed25519"), "{plain}");
    // The users' CA: it signs no host.
    let other_ca = f.read("user_ca.pub");
    let ssh = f.app.local().ssh_dir.clone();
    std::fs::create_dir_all(&ssh).unwrap();
    std::fs::write(
        ssh.join("known_hosts"),
        format!("@cert-authority * {other_ca}\n{plain}"),
    )
    .unwrap();
    let host = f.host(
        "bastion",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            ..Settings::default()
        },
    );
    let (_term, rx) = f.connect(host, |_| Answer::Cancel);
    let (connected, prompts) = outcome(&rx);
    assert!(prompts.is_empty(), "asked: {prompts:?}");
    assert_eq!(connected.unwrap().trust, Trust::Known);

    // Not known by the plain key either: the certificate's fault is told.
    std::fs::write(
        ssh.join("known_hosts"),
        format!("@cert-authority * {other_ca}\n"),
    )
    .unwrap();
    let (_term, rx) = f.connect(host, |_| Answer::Cancel);
    match outcome(&rx).0 {
        Err(Some(Failure::BadCertificate {
            problem: CertProblem::Untrusted,
            ..
        })) => {}
        other => panic!("not a bad certificate: {other:?}"),
    }
}

/// The system's `known_hosts` (`/etc/ssh/ssh_known_hosts`) is trusted as
/// OpenSSH trusts it, `@cert-authority` lines too.
#[test]
fn the_system_known_hosts_is_trusted() {
    let f = Fixture::new(servers!());
    let system = f.app.local().system_ssh_dir.clone();
    std::fs::create_dir_all(&system).unwrap();
    std::fs::copy(f.fx.join("known_hosts_ca"), system.join("ssh_known_hosts")).unwrap();
    let host = f.host(
        "bastion",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::Strict),
            ..Settings::default()
        },
    );
    let (_term, rx) = f.connect(host, |_| Answer::Cancel);
    let (connected, prompts) = outcome(&rx);
    assert!(prompts.is_empty(), "asked: {prompts:?}");
    assert!(
        matches!(connected.unwrap().trust, Trust::Certified { .. }),
        "not by the system's CA"
    );
}

/// A host known in `~/.ssh/known_hosts` only by its ECDSA key is checked
/// against that key, not taken for a new host because it also has an
/// Ed25519 one.
#[test]
fn a_host_known_by_another_key_type_is_checked_against_it() {
    let f = Fixture::new(servers!());
    let scan = std::process::Command::new("ssh-keyscan")
        .args(["-t", "ecdsa", "-p", &BASTION.to_string(), "127.0.0.1"])
        .output()
        .unwrap();
    let ecdsa = String::from_utf8(scan.stdout).unwrap();
    assert!(ecdsa.contains("ecdsa-sha2-nistp256"), "{ecdsa}");
    let ssh = f.app.local().ssh_dir.clone();
    std::fs::create_dir_all(&ssh).unwrap();
    std::fs::write(ssh.join("known_hosts"), &ecdsa).unwrap();
    let host = f.host(
        "bastion",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            ..Settings::default()
        },
    );
    let (_term, rx) = f.connect(host, |_| Answer::Cancel);
    let (connected, prompts) = outcome(&rx);
    assert!(prompts.is_empty(), "asked: {prompts:?}");
    assert_eq!(connected.unwrap().trust, Trust::Known);
}

/// A host known only by keys of a type its server does not offer is asked
/// about, saying which types are known, even where new hosts are accepted.
#[test]
fn keys_of_another_type_are_asked_about_even_with_accept_new() {
    let f = Fixture::new(servers!());
    // A security key's host key: no server here offers that type.
    let sk = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gAAAABHNzaDo=";
    let ssh = f.app.local().ssh_dir.clone();
    std::fs::create_dir_all(&ssh).unwrap();
    std::fs::write(
        ssh.join("known_hosts"),
        format!("[127.0.0.1]:{BASTION} {sk}\n"),
    )
    .unwrap();
    let host = f.host(
        "bastion",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            ..Settings::default()
        },
    );
    let (_term, rx) = f.connect(host, |_| Answer::Cancel);
    let (closed, prompts) = outcome(&rx);
    match prompts.as_slice() {
        [Prompt::HostKey { known_types, .. }] => {
            assert_eq!(known_types, &["sk-ssh-ed25519@openssh.com"]);
        }
        other => panic!("not asked about the other type: {other:?}"),
    }
    assert!(
        matches!(closed, Err(Some(Failure::HostKeyRejected { .. }))),
        "{closed:?}"
    );
    assert!(f.app.vault().known_hosts().is_empty(), "not trusted");
}

/// Waits for the session to end, as the shell's exit ends it.
fn closed(rx: &Receiver<Event>) -> (Option<u32>, Option<Failure>) {
    loop {
        if let Event::Closed { exit_code, failure } = rx
            .recv_timeout(Duration::from_secs(10))
            .expect("no end in 10 s")
        {
            return (exit_code, failure);
        }
    }
}

fn recorded_output(logs: &openward_app::Logs, id: &str) -> String {
    logs.read(id)
        .unwrap()
        .events
        .into_iter()
        .filter_map(|(_, e)| match e {
            openward_app::logs::cast::Event::Output(s) => Some(s),
            _ => None,
        })
        .collect()
}

/// What came out is in the session log, and a password typed with the
/// echo off (as `sudo` and `read -s` ask for them) never is.
#[test]
fn a_session_log_keeps_what_was_seen_never_a_hidden_password() {
    let f = Fixture::new(servers!());
    let host = f.host(
        "bastion",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            session_log: Some(true),
            ..Settings::default()
        },
    );
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    outcome(&rx).0.unwrap();
    let state = term.log_state().expect("a log from the start");
    assert!(state.recording && !state.paused);

    term.log_command("echo visible-$((6*7))");
    term.text("echo visible-$((6*7))\n");
    wait_for(&term, "visible-42");
    term.text("stty -echo; echo ready-$((1+1)); read -r s; stty echo; echo got-${#s}\n");
    wait_for(&term, "ready-2");
    term.text("hunter2-secret\n");
    wait_for(&term, "got-14");
    term.text("exit\n");
    assert_eq!(closed(&rx), (Some(0), None));
    assert!(term.log_state().is_none());

    let logs = f.app.logs();
    let [entry] = logs.list().try_into().unwrap();
    assert_eq!(entry.id, state.id);
    assert_eq!(entry.end, openward_app::logs::End::Closed);
    assert_eq!(entry.label, "bastion");
    assert_eq!(entry.address, format!("demo@127.0.0.1:{BASTION}"));
    assert_eq!(entry.commands, 1);
    assert!(entry.recorded && entry.bytes > 0);
    let out = recorded_output(logs, &entry.id);
    assert!(
        out.contains("visible-42") && out.contains("got-14"),
        "{out}"
    );
    assert!(!out.contains("hunter2"), "the hidden password was recorded");
    let text: Vec<String> = logs
        .text(&entry.id)
        .unwrap()
        .into_iter()
        .map(|(_, l)| l)
        .collect();
    assert!(text.iter().any(|l| l == "visible-42"), "{text:?}");
    assert!(!text.iter().any(|l| l.contains("hunter2")));
}

/// Hosts record when they or their defaults say so: by default only the
/// entry is kept; «everywhere» on this device turns it on, and a host
/// that says no keeps saying no.
#[test]
fn a_host_records_when_its_settings_say_so() {
    let f = Fixture::new(servers!());
    let plain = bastion_host(&f, None);
    let never = f.host(
        "never",
        "127.0.0.1",
        BASTION,
        Settings {
            user: Some("demo".into()),
            identity_files: f.key("id_ed25519"),
            host_key_policy: Some(HostKeyPolicy::AcceptNew),
            session_log: Some(false),
            ..Settings::default()
        },
    );
    let session = |host| {
        let (term, rx) = f.connect(host, |_| Answer::Cancel);
        outcome(&rx).0.unwrap();
        let id = term.log_state().unwrap().id;
        term.text("echo hola-$((2+3)); exit\n");
        assert_eq!(closed(&rx).1, None);
        f.app.logs().entry(&id).unwrap()
    };
    assert!(!session(plain).recorded);
    f.app.set_read_os_release_everywhere(true);
    f.app.set_session_log_everywhere(true);
    let entry = session(plain);
    assert!(entry.recorded);
    assert!(recorded_output(f.app.logs(), &entry.id).contains("hola-5"));
    assert!(!session(never).recorded);
    // The other device default stays.
    assert_eq!(f.app.vault().device_defaults().read_os_release, Some(true));
    assert_eq!(f.app.logs().list().len(), 3);
}

/// A host records because its group says so; a cut leaves its one log
/// whole on both sides, marked where it was lost and where it came back.
#[test]
fn a_cut_keeps_the_log_whole_on_both_sides() {
    let f = Fixture::new(servers!());
    let group = f
        .app
        .vault()
        .create(Data::Group(Group {
            name: "prod".into(),
            settings: Settings {
                session_log: Some(true),
                ..Settings::default()
            },
            ..Group::default()
        }))
        .unwrap();
    let host = bastion_host(&f, None);
    {
        let mut vault = f.app.vault();
        let mut h = vault.host(host).unwrap().clone();
        h.group = Some(group);
        let rev = vault.get(host).map_or(0, |i| i.rev);
        vault.update(host, rev, Data::Host(h)).unwrap();
    }
    let (term, rx) = f.connect(host, |_| Answer::Cancel);
    outcome(&rx).0.unwrap();
    let state = term.log_state().expect("a log, from the group");
    assert!(state.recording);
    term.text("echo before-$((6*7))\n");
    wait_for(&term, "\nbefore-42");
    cut_bastion(&term);
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        match rx.recv_timeout(left).expect("no reconnection") {
            Event::Connected(_) => break,
            Event::Closed { failure, .. } => panic!("gave up: {failure:?}"),
            _ => {}
        }
    }
    assert_eq!(term.log_state().unwrap().id, state.id, "the same log");
    term.text("echo after-$((2*2))\n");
    wait_for(&term, "\nafter-4");
    term.text("exit\n");
    assert_eq!(closed(&rx).1, None);

    let logs = f.app.logs();
    let [entry] = logs.list().try_into().unwrap();
    assert_eq!(entry.id, state.id);
    assert!(entry.recorded);
    assert_eq!(entry.end, openward_app::logs::End::Closed);
    let out = recorded_output(logs, &entry.id);
    assert!(
        out.contains("before-42") && out.contains("after-4"),
        "{out}"
    );
    let marks: Vec<String> = logs
        .read(&entry.id)
        .unwrap()
        .events
        .into_iter()
        .filter_map(|(_, e)| match e {
            openward_app::logs::cast::Event::Marker(m) if !m.starts_with('$') => Some(m),
            _ => None,
        })
        .collect();
    assert_eq!(marks, ["lost", "back"]);
}

/// A local terminal is recorded only when this device asks for it. With
/// `sh`: PowerShell on Windows is tried by hand, in docs/plan/prueba-v0.3.md.
#[cfg(unix)]
#[test]
fn a_local_shell_is_recorded_when_asked() {
    let dir = tempfile::tempdir().unwrap();
    let app = App::open_as(&dir.path().join("data"), Local::from_env()).unwrap();
    let run = |echo: &str| {
        let (tx, rx) = channel();
        let ui = Arc::new(Ui {
            app: OnceLock::new(),
            tx: Mutex::new(tx),
            reply: Box::new(|_| Answer::Cancel),
        });
        let term = app.terminal(80, 24, 1000);
        app.open_local(&term, Some("/bin/sh".into()), ui).unwrap();
        let id = term.log_state().unwrap().id;
        term.text(&format!("echo {echo}-$((40+2)); exit 3\n"));
        assert_eq!(closed(&rx), (Some(3), None));
        app.logs().entry(&id).unwrap()
    };
    let entry = run("off");
    assert_eq!(entry.place, openward_app::logs::Place::Local);
    assert!(!entry.recorded);
    app.logs().set_config(openward_app::logs::Config {
        record_local: true,
        ..app.logs().config()
    });
    let entry = run("on");
    assert!(entry.recorded);
    assert_eq!(entry.end, openward_app::logs::End::Closed);
    assert!(recorded_output(app.logs(), &entry.id).contains("on-42"));
}
