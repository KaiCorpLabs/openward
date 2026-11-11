//! Terminals that are not SSH: Telnet against a server of the test's own,
//! and (on Linux) a serial port played by a pseudo-terminal.

use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::time::{Duration, Instant};

use openward_app::vault::proto::{Data, Host, Protocol, Settings};
use openward_app::{App, Event, EventSink, Failure, Local, PlanError};
#[cfg(target_os = "linux")]
use serialport::SerialPort;

const IAC: u8 = 255;
const DO: u8 = 253;
const WILL: u8 = 251;
const SB: u8 = 250;
const SE: u8 = 240;
const ECHO: u8 = 1;
const SGA: u8 = 3;
const TTYPE: u8 = 24;
const NAWS: u8 = 31;

struct Sink(Mutex<Sender<Event>>);

impl EventSink for Sink {
    fn send(&self, event: Event) {
        let _ = self.0.lock().unwrap().send(event);
    }
}

fn events() -> (Arc<dyn EventSink>, Receiver<Event>) {
    let (tx, rx) = channel();
    (Arc::new(Sink(Mutex::new(tx))), rx)
}

fn app() -> (tempfile::TempDir, App) {
    let dir = tempfile::tempdir().unwrap();
    let app = App::open_as(&dir.path().join("data"), Local::from_env()).unwrap();
    (dir, app)
}

/// The first `Connected` or `Closed`.
fn outcome(rx: &Receiver<Event>) -> Result<openward_app::events::Connected, Option<Failure>> {
    loop {
        match rx
            .recv_timeout(Duration::from_secs(10))
            .expect("no outcome")
        {
            Event::Connected(c) => return Ok(c),
            Event::Closed { failure, .. } => return Err(failure),
            _ => {}
        }
    }
}

fn closed(rx: &Receiver<Event>) -> Option<Failure> {
    loop {
        if let Event::Closed { failure, .. } =
            rx.recv_timeout(Duration::from_secs(10)).expect("no end")
        {
            return failure;
        }
    }
}

fn until(what: &str, mut ok: impl FnMut() -> bool) {
    let start = Instant::now();
    while !ok() {
        assert!(start.elapsed() < Duration::from_secs(10), "{what}");
        std::thread::sleep(Duration::from_millis(20));
    }
}

/// A switch's Telnet: asks for the window and the terminal's type,
/// echoes, and hangs up at `exit`. What it heard comes back on the channel.
fn switch() -> (u16, Receiver<Vec<u8>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let (tx, rx) = channel();
    std::thread::spawn(move || {
        let (mut s, _) = listener.accept().unwrap();
        s.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
        s.write_all(&[
            IAC, DO, NAWS, IAC, DO, TTYPE, IAC, WILL, ECHO, IAC, WILL, SGA,
        ])
        .unwrap();
        s.write_all(&[IAC, SB, TTYPE, 1, IAC, SE]).unwrap();
        s.write_all(b"\r\nUser Access Verification\r\n\r\nsw-1> ")
            .unwrap();
        let mut heard = Vec::new();
        let mut buf = [0u8; 1024];
        loop {
            let n = match s.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => n,
            };
            heard.extend_from_slice(&buf[..n]);
            let _ = tx.send(buf[..n].to_vec());
            // The echo of what was typed (anything that is not a command).
            let typed: Vec<u8> = buf[..n]
                .iter()
                .copied()
                .filter(|b| b.is_ascii_graphic())
                .collect();
            if !typed.is_empty() && !buf[..n].contains(&IAC) {
                s.write_all(&typed).unwrap();
            }
            if heard.windows(6).any(|w| w == b"exit\r\n") {
                break;
            }
        }
    });
    (port, rx)
}

/// Everything the server heard so far.
struct Heard {
    rx: Receiver<Vec<u8>>,
    all: Vec<u8>,
}

impl Heard {
    /// Waits until the server has heard `bytes`.
    fn wait(&mut self, bytes: &[u8]) {
        let start = Instant::now();
        while !self.all.windows(bytes.len()).any(|w| w == bytes) {
            assert!(
                start.elapsed() < Duration::from_secs(10),
                "never heard {bytes:?}: {:?}",
                self.all
            );
            if let Ok(chunk) = self.rx.recv_timeout(Duration::from_millis(100)) {
                self.all.extend(chunk);
            }
        }
    }
}

#[test]
fn a_telnet_session_from_login_to_exit() {
    let (_dir, app) = app();
    let (port, heard) = switch();
    let mut heard = Heard {
        rx: heard,
        all: Vec::new(),
    };
    let term = app.terminal(80, 24, 100);
    let (sink, rx) = events();
    app.connect_address(
        &term,
        "127.0.0.1".into(),
        None,
        Some(port),
        Protocol::Telnet,
        sink,
    )
    .unwrap();
    let connected = outcome(&rx).unwrap();
    assert_eq!(connected.protocol, Protocol::Telnet);
    assert_eq!(connected.port, port);
    assert!(connected.cipher.is_empty());

    // It told the window's size and the terminal's type when asked.
    let mut naws = vec![IAC, SB, NAWS, 0, 80, 0, 24, IAC, SE];
    heard.wait(&naws);
    let mut ttype = vec![IAC, SB, TTYPE, 0];
    ttype.extend(b"xterm-256color");
    ttype.extend([IAC, SE]);
    heard.wait(&ttype);
    until("the prompt", || term.screen_text().contains("sw-1>"));

    term.resize(100, 30);
    naws = vec![IAC, SB, NAWS, 0, 100, 0, 30, IAC, SE];
    heard.wait(&naws);

    // Enter goes as Telnet's end of line, and the server's echo shows.
    term.text("show ver\r");
    heard.wait(b"show ver\r\n");
    until("the echo", || term.screen_text().contains("showver"));

    // The server hangs up: the session ends, not lost.
    term.text("exit\r");
    assert_eq!(closed(&rx), None);
}

/// A saved Telnet host connects the same way; what only SSH does (files)
/// is refused for it.
#[test]
fn a_saved_telnet_host_and_what_it_cannot_do() {
    let (_dir, app) = app();
    let (port, _heard) = switch();
    let host = app
        .vault()
        .create(Data::Host(Host {
            label: "sw-1".into(),
            address: "127.0.0.1".into(),
            settings: Settings {
                protocol: Some(Protocol::Telnet),
                port: Some(port),
                ..Settings::default()
            },
            ..Host::default()
        }))
        .unwrap();
    let term = app.terminal(80, 24, 100);
    let (sink, rx) = events();
    app.connect(&term, host, sink).unwrap();
    assert_eq!(outcome(&rx).unwrap().protocol, Protocol::Telnet);
    until("the prompt", || term.screen_text().contains("sw-1>"));

    let sftp = app.sftp();
    let (sink, _rx) = events();
    assert!(matches!(
        app.connect_sftp(&sftp, host, sink),
        Err(PlanError::NotSsh(l)) if l == "sw-1"
    ));
    term.close();
}

/// Nothing listens: a network failure, as with SSH.
#[test]
fn a_telnet_host_that_is_not_there() {
    let (_dir, app) = app();
    let port = TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port();
    let term = app.terminal(80, 24, 100);
    let (sink, rx) = events();
    app.connect_address(
        &term,
        "127.0.0.1".into(),
        None,
        Some(port),
        Protocol::Telnet,
        sink,
    )
    .unwrap();
    assert!(matches!(outcome(&rx), Err(Some(Failure::Network { .. }))));
}

#[test]
fn a_serial_port_that_is_not_there() {
    let (_dir, app) = app();
    let term = app.terminal(80, 24, 100);
    let (sink, rx) = events();
    let path = if cfg!(windows) {
        "COM250"
    } else {
        "/dev/openward-no-such-port"
    };
    app.open_serial(&term, path.into(), Default::default(), sink);
    assert!(matches!(
        outcome(&rx),
        Err(Some(Failure::Serial {
            problem: openward_app::events::SerialProblem::Missing,
            ..
        }))
    ));
}

/// A pseudo-terminal plays the cable (Linux: macOS cannot set one's
/// speed). What the console says shows, what is typed goes down the line
/// as it is, and pulling the cable closes the session saying so.
#[cfg(target_os = "linux")]
#[test]
fn a_console_over_a_serial_port() {
    let (mut cable, end) = serialport::TTYPort::pair().unwrap();
    let path = end.name().unwrap();
    let (_dir, app) = app();
    let term = app.terminal(80, 24, 100);
    let (sink, rx) = events();
    app.open_serial(&term, path.clone(), Default::default(), sink);
    let connected = outcome(&rx).unwrap();
    assert_eq!(connected.protocol, Protocol::Serial);
    assert_eq!(connected.host, path);

    cable.write_all(b"\r\nRouter>").unwrap();
    until("the console", || term.screen_text().contains("Router>"));
    term.text("en\r");
    let mut got = [0u8; 3];
    cable.set_timeout(Duration::from_secs(5)).unwrap();
    cable.read_exact(&mut got).unwrap();
    assert_eq!(&got, b"en\r", "no Telnet line ends on a serial port");

    drop(cable);
    drop(end);
    assert!(matches!(
        closed(&rx),
        Some(Failure::Serial {
            problem: openward_app::events::SerialProblem::Gone,
            ..
        })
    ));
}

/// Closing the tab lets the port go at once: it opens again.
#[cfg(target_os = "linux")]
#[test]
fn closing_lets_the_port_go() {
    let (_cable, end) = serialport::TTYPort::pair().unwrap();
    let path = end.name().unwrap();
    let (_dir, app) = app();
    let term = app.terminal(80, 24, 100);
    let (sink, rx) = events();
    app.open_serial(&term, path.clone(), Default::default(), sink);
    outcome(&rx).unwrap();
    term.close();
    assert_eq!(closed(&rx), None);
    let again = app.terminal(80, 24, 100);
    let (sink, rx) = events();
    app.open_serial(&again, path, Default::default(), sink);
    outcome(&rx).unwrap();
}
