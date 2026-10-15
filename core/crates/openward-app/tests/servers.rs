//! Connections through `App` against the S2 test servers
//! (`spikes/s2-ssh/servers/up.sh`). Skipped when they are not running.

use std::path::PathBuf;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::{Duration, Instant};

use openward_app::events::{ChangedKey, Connected, KeySource, PreviousKey, Trust};
use openward_app::vault::proto::{Agent, Data, Host, HostKeyPolicy, ItemId, Jump, Route, Settings};
use openward_app::{Answer, App, Event, EventSink, Failure, Local, Prompt, Terminal};
use zeroize::Zeroizing;

const BASTION: u16 = 22100;

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
        let (tx, rx) = channel();
        let ui = Arc::new(Ui {
            app: OnceLock::new(),
            tx: Mutex::new(tx),
            reply: Box::new(reply),
        });
        let _ = ui.app.set(Arc::downgrade(&self.app));
        let term = self.app.terminal(80, 24, 1000);
        self.app.connect(&term, host, ui).unwrap();
        (term, rx)
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
            | Event::Reconnecting { .. } => {}
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
    // The shell's parent is this connection's sshd: killing it drops the
    // connection without a goodbye, like a network that goes away.
    term.text("echo ppid-$PPID-end\n");
    wait_for(&term, "-end\n");
    let screen = term.screen_text();
    let pid = screen
        .lines()
        .find_map(|l| l.strip_prefix("ppid-")?.strip_suffix("-end"))
        .expect("the pid line")
        .to_owned();
    let killed = std::process::Command::new(runtime())
        .args(["exec", "bastion", "kill", "-9", &pid])
        .status()
        .unwrap();
    assert!(killed.success());

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
    assert!(matches!(reason, Failure::Network { .. }), "{reason:?}");
    term.text("echo back-$((6*7))\n");
    wait_for(&term, "back-42");
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
    term.text("hostname\n");
    wait_for(&term, "target1");
    assert_eq!(f.app.vault().known_hosts().len(), 2);
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
