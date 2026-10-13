//! The interoperability matrix of spike S2 (docs/spikes/S2-ssh.md §5),
//! against the servers started by `spikes/s2-ssh/servers/up.sh`.

use std::future::Future;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context, bail};
use serde_json::json;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::process::{Child, Command};

use openward_ssh::client::{self, Auth, Hop, Options, Session, Target};
use openward_ssh::forward;
use openward_ssh::known_hosts::{KnownHosts, Unknown, Verdict};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    OpenSsh,
    Dropbear,
}

struct Server {
    name: &'static str,
    port: u16,
    /// Container name, to pause it for the keepalive test.
    container: &'static str,
    kind: Kind,
}

const SERVERS: &[Server] = &[
    Server {
        name: "OpenSSH 8.9",
        port: 22089,
        container: "s2-openssh-8.9",
        kind: Kind::OpenSsh,
    },
    Server {
        name: "OpenSSH 9.2",
        port: 22092,
        container: "s2-openssh-9.2",
        kind: Kind::OpenSsh,
    },
    Server {
        name: "OpenSSH 10.0",
        port: 22100,
        container: "bastion",
        kind: Kind::OpenSsh,
    },
    Server {
        name: "Dropbear",
        port: 22200,
        container: "s2-dropbear",
        kind: Kind::Dropbear,
    },
];
const HOST: &str = "127.0.0.1";

pub struct Fixtures {
    dir: PathBuf,
}

impl Fixtures {
    pub fn new(dir: PathBuf) -> anyhow::Result<Self> {
        if !dir.join("id_ed25519").exists() {
            bail!(
                "no fixtures in {}: start the servers with spikes/s2-ssh/servers/up.sh",
                dir.display()
            );
        }
        Ok(Self { dir })
    }

    pub fn path(&self, name: &str) -> PathBuf {
        self.dir.join(name)
    }

    fn read(&self, name: &str) -> anyhow::Result<String> {
        std::fs::read_to_string(self.path(name)).with_context(|| format!("fixture {name}"))
    }

    fn password(&self, user: &str) -> anyhow::Result<String> {
        self.read("passwords")?
            .lines()
            .find_map(|l| l.strip_prefix(&format!("{user}=")).map(str::to_owned))
            .with_context(|| format!("no password for {user}"))
    }

    pub fn key(&self, name: &str) -> Auth {
        Auth::Key {
            path: self.path(name),
            passphrase: None,
        }
    }
}

/// One cell of the matrix.
struct Cell {
    server: &'static str,
    test: &'static str,
    /// None: not applicable to this server.
    ok: Option<bool>,
    detail: String,
    ms: f64,
}

struct Run<'a> {
    fx: &'a Fixtures,
    cells: Vec<Cell>,
    runtime: Option<String>,
    agent_socket: PathBuf,
}

fn options(user: &str, known: KnownHosts, host_certificates: bool) -> Options {
    Options {
        user: user.to_owned(),
        known_hosts: Arc::new(Mutex::new(known)),
        host_certificates,
        keepalive: None,
        agent_forward: None,
        on_untrusted: None,
    }
}

pub fn tofu(user: &str) -> Options {
    options(user, KnownHosts::new(Unknown::Learn), false)
}

impl Run<'_> {
    async fn cell<F, Fut>(&mut self, server: &'static str, test: &'static str, f: F)
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = anyhow::Result<String>>,
    {
        let started = Instant::now();
        let result = tokio::time::timeout(Duration::from_secs(30), f()).await;
        let (ok, detail) = match result {
            Ok(Ok(detail)) => (Some(true), detail),
            Ok(Err(e)) => (Some(false), format!("{e:#}")),
            Err(_) => (Some(false), "timeout (30 s)".to_owned()),
        };
        let ms = started.elapsed().as_secs_f64() * 1e3;
        eprintln!(
            "{:<13} {:<26} {:<4} {}",
            server,
            test,
            if ok == Some(true) { "ok" } else { "FAIL" },
            detail
        );
        self.cells.push(Cell {
            server,
            test,
            ok,
            detail,
            ms,
        });
    }

    fn skip(&mut self, server: &'static str, test: &'static str, why: &str) {
        eprintln!("{server:<13} {test:<26} n/a  {why}");
        self.cells.push(Cell {
            server,
            test,
            ok: None,
            detail: why.to_owned(),
            ms: 0.0,
        });
    }

    async fn server(&mut self, s: &'static Server) -> anyhow::Result<()> {
        let fx = self.fx;
        let target = Target::new(HOST, s.port);
        let openssh = s.kind == Kind::OpenSsh;
        let password = fx.password("demo")?;

        self.cell(s.name, "kex", || async {
            let session =
                client::connect(&target, Hop::Tcp, &fx.key("id_ed25519"), &tofu("demo")).await?;
            let info = session.info();
            Ok(format!(
                "{}{} · {} · {} · host key {}",
                info.kex,
                if info.post_quantum() {
                    " (poscuántico)"
                } else {
                    ""
                },
                info.cipher,
                info.mac,
                info.host_key
            ))
        })
        .await;

        self.cell(s.name, "tofu", || async {
            let opts = tofu("demo");
            let first = client::connect(&target, Hop::Tcp, &fx.key("id_ed25519"), &opts).await?;
            let second = client::connect(&target, Hop::Tcp, &fx.key("id_ed25519"), &opts).await?;
            match (first.info().verdict, second.info().verdict) {
                (Some(Verdict::Learned), Some(Verdict::Known)) => Ok("learned, then known".into()),
                other => bail!("unexpected verdicts {other:?}"),
            }
        })
        .await;

        self.cell(s.name, "clave de host cambiada", || async {
            // The host CA's public key stands in for "some other ed25519 key".
            let wrong = fx.read("host_ca.pub")?;
            let known = KnownHosts::parse(&format!("[{HOST}]:{} {wrong}", s.port), Unknown::Reject);
            match client::connect(
                &target,
                Hop::Tcp,
                &fx.key("id_ed25519"),
                &options("demo", known, false),
            )
            .await
            {
                Ok(_) => bail!("connected despite a changed host key"),
                Err(e) if format!("{e:#}").contains("Changed") => Ok("refused (Changed)".into()),
                Err(e) => bail!("refused for another reason: {e:#}"),
            }
        })
        .await;

        if openssh {
            self.cell(s.name, "certificado de host", || async {
                let known = KnownHosts::parse(&fx.read("known_hosts_ca")?, Unknown::Reject);
                let session = client::connect(
                    &target,
                    Hop::Tcp,
                    &fx.key("id_ed25519"),
                    &options("demo", known, true),
                )
                .await?;
                match session.info().verdict {
                    Some(Verdict::Certified { key_id, .. }) => Ok(format!("certified ({key_id})")),
                    other => bail!("not certified: {other:?}"),
                }
            })
            .await;
        } else {
            self.skip(
                s.name,
                "certificado de host",
                "Dropbear no tiene certificados",
            );
        }

        let auths: Vec<(&'static str, Auth, bool)> = vec![
            ("contraseña", Auth::Password(password.clone()), true),
            ("Ed25519", fx.key("id_ed25519"), true),
            ("ECDSA P-256", fx.key("id_ecdsa"), true),
            ("RSA (rsa-sha2)", fx.key("id_rsa"), true),
            (
                "Ed25519 con frase",
                Auth::Key {
                    path: fx.path("id_ed25519_pass"),
                    passphrase: Some("s2-passphrase".into()),
                },
                true,
            ),
            (
                "certificado de usuario",
                Auth::Cert {
                    key: fx.path("id_cert"),
                    cert: fx.path("id_cert-cert.pub"),
                },
                openssh,
            ),
            (
                "agente",
                Auth::Agent {
                    socket: self.agent_socket.clone(),
                },
                true,
            ),
        ];
        for (name, auth, applies) in auths {
            if !applies {
                self.skip(s.name, name, "Dropbear no tiene certificados");
                continue;
            }
            self.cell(s.name, name, || async {
                let session = client::connect(&target, Hop::Tcp, &auth, &tofu("demo")).await?;
                let out = session.exec("whoami").await?;
                if out.text() != "demo" {
                    bail!("whoami: {}", out.text());
                }
                Ok(format!(
                    "{:.0} ms hasta autenticado",
                    session.info().connect_ms
                ))
            })
            .await;
        }

        if openssh {
            self.cell(s.name, "2FA (contraseña + TOTP)", || async {
                let auth = Auth::KeyboardInteractive {
                    password: fx.password("otp")?,
                    totp_secret: Some(fx.read("totp_secret")?),
                };
                let session = client::connect(&target, Hop::Tcp, &auth, &tofu("otp")).await?;
                Ok(format!("whoami → {}", session.exec("whoami").await?.text()))
            })
            .await;
        } else {
            self.skip(s.name, "2FA (contraseña + TOTP)", "sin PAM en Dropbear");
        }

        // The remaining tests share one session.
        let session = match client::connect(
            &target,
            Hop::Tcp,
            &fx.key("id_ed25519"),
            &Options {
                agent_forward: Some(self.agent_socket.clone()),
                ..tofu("demo")
            },
        )
        .await
        {
            Ok(s) => Arc::new(s),
            Err(e) => bail!("{}: no session for the remaining tests: {e:#}", s.name),
        };

        self.cell(s.name, "agent forwarding", || async {
            let out = session
                .exec_with("test -S \"$SSH_AUTH_SOCK\" && echo agent-ok", true, &[])
                .await?;
            if out.text() == "agent-ok" {
                Ok("SSH_AUTH_SOCK en el servidor".into())
            } else {
                bail!("no forwarded agent: {:?}", out.text())
            }
        })
        .await;

        self.cell(s.name, "PTY y redimensionado", || pty_test(&session))
            .await;

        self.cell(s.name, "exec y código de salida", || async {
            let out = session.exec("echo hola; exit 3").await?;
            match (out.text().as_str(), out.status) {
                ("hola", Some(3)) => Ok("salida y código 3".into()),
                other => bail!("got {other:?}"),
            }
        })
        .await;

        if openssh {
            self.cell(s.name, "variables de entorno", || async {
                let out = session
                    .exec_with("echo \"$OW_TEST\"", false, &[("OW_TEST", "s2")])
                    .await?;
                if out.text() == "s2" {
                    Ok("AcceptEnv OW_*".into())
                } else {
                    bail!("got {:?}", out.text())
                }
            })
            .await;
        } else {
            self.skip(
                s.name,
                "variables de entorno",
                "Dropbear ignora las peticiones env",
            );
        }

        self.cell(s.name, "túnel local (-L)", || async {
            let fwd = forward::local(Arc::clone(&session), "127.0.0.1", 8080).await?;
            let page =
                http_get(tokio::net::TcpStream::connect(("127.0.0.1", fwd.port)).await?).await?;
            if page.contains("s2-forward-ok") {
                Ok("página del servidor".into())
            } else {
                bail!("{page}")
            }
        })
        .await;

        self.cell(s.name, "túnel remoto (-R)", || async {
            let local = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
            let local_port = local.local_addr()?.port();
            tokio::spawn(async move {
                if let Ok((mut c, _)) = local.accept().await {
                    let _ = c.write_all(b"s2-remote-ok\n").await;
                }
            });
            let port = session.remote_forward(("127.0.0.1", local_port)).await?;
            let out = session
                .exec(&format!("timeout 5 nc 127.0.0.1 {port} </dev/null"))
                .await?;
            if out.text().contains("s2-remote-ok") {
                Ok(format!("puerto remoto {port}"))
            } else {
                bail!("got {:?}", out.text())
            }
        })
        .await;

        self.cell(s.name, "túnel dinámico (-D)", || async {
            let fwd = forward::dynamic(Arc::clone(&session)).await?;
            let stream = forward::socks5_connect(fwd.port, "127.0.0.1", 8080).await?;
            let page = http_get(stream).await?;
            if page.contains("s2-forward-ok") {
                Ok("SOCKS5 → página del servidor".into())
            } else {
                bail!("{page}")
            }
        })
        .await;

        self.cell(s.name, "ProxyCommand", || async {
            let hop = Hop::ProxyCommand(format!("nc {HOST} {}", s.port));
            let session =
                client::connect(&target, hop, &fx.key("id_ed25519"), &tofu("demo")).await?;
            Ok(format!("whoami → {}", session.exec("whoami").await?.text()))
        })
        .await;

        match self.runtime.clone() {
            Some(runtime) => {
                self.cell(s.name, "keepalive y corte", || {
                    keepalive_test(&target, fx, &runtime, s.container)
                })
                .await
            }
            None => self.skip(s.name, "keepalive y corte", "sin podman/docker"),
        }
        Ok(())
    }

    async fn jumps(&mut self) {
        let fx = self.fx;
        let bastion = Target::new(HOST, 22100);
        self.cell("Saltos", "salto simple", || async {
            let jump =
                client::connect(&bastion, Hop::Tcp, &fx.key("id_ed25519"), &tofu("demo")).await?;
            let t1 = client::connect(
                &Target::new("target1", 22),
                Hop::Via(&jump),
                &fx.key("id_ed25519"),
                &tofu("demo"),
            )
            .await?;
            Ok(format!("hostname → {}", t1.exec("hostname").await?.text()))
        })
        .await;
        self.cell("Saltos", "salto doble", || async {
            let jump =
                client::connect(&bastion, Hop::Tcp, &fx.key("id_ed25519"), &tofu("demo")).await?;
            let t1 = client::connect(
                &Target::new("target1", 22),
                Hop::Via(&jump),
                &fx.key("id_ed25519"),
                &tofu("demo"),
            )
            .await?;
            let t2 = client::connect(
                &Target::new("target2", 22),
                Hop::Via(&t1),
                &fx.key("id_ed25519"),
                &tofu("demo"),
            )
            .await?;
            let info = t2.info();
            Ok(format!(
                "hostname → {} ({})",
                t2.exec("hostname").await?.text(),
                info.kex
            ))
        })
        .await;
        self.cell("Saltos", "ProxyCommand + salto", || async {
            let jump = client::connect(
                &bastion,
                Hop::ProxyCommand(format!("nc {HOST} 22100")),
                &fx.key("id_ed25519"),
                &tofu("demo"),
            )
            .await?;
            let t1 = client::connect(
                &Target::new("target1", 22),
                Hop::Via(&jump),
                &fx.key("id_ed25519"),
                &tofu("demo"),
            )
            .await?;
            Ok(format!("hostname → {}", t1.exec("hostname").await?.text()))
        })
        .await;
    }
}

async fn http_get(mut stream: tokio::net::TcpStream) -> anyhow::Result<String> {
    stream
        .write_all(b"GET / HTTP/1.0\r\nHost: localhost\r\n\r\n")
        .await?;
    let mut body = Vec::new();
    stream.read_to_end(&mut body).await?;
    Ok(String::from_utf8_lossy(&body).into_owned())
}

/// Reads from a shell until `needle` shows up.
async fn read_until(
    channel: &mut openward_ssh::russh::Channel<openward_ssh::russh::client::Msg>,
    seen: &mut String,
    needle: &str,
) -> anyhow::Result<()> {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !seen.contains(needle) {
        let left = deadline.saturating_duration_since(Instant::now());
        match tokio::time::timeout(left, channel.wait()).await {
            Ok(Some(openward_ssh::russh::ChannelMsg::Data { data })) => {
                seen.push_str(&String::from_utf8_lossy(&data))
            }
            Ok(Some(_)) => {}
            Ok(None) => bail!("channel closed waiting for {needle:?}"),
            Err(_) => bail!("timeout waiting for {needle:?}; got {seen:?}"),
        }
    }
    Ok(())
}

async fn pty_test(session: &Session) -> anyhow::Result<String> {
    let mut ch = session.shell("xterm-256color", 80, 24).await?;
    let mut seen = String::new();
    client::send(&ch, b"stty size; echo T=$TERM\n").await?;
    read_until(&mut ch, &mut seen, "24 80").await?;
    read_until(&mut ch, &mut seen, "T=xterm-256color").await?;
    ch.window_change(100, 30, 0, 0).await?;
    seen.clear();
    client::send(&ch, b"stty size\n").await?;
    read_until(&mut ch, &mut seen, "30 100").await?;
    client::send(&ch, b"exit 7\n").await?;
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        match tokio::time::timeout(left, ch.wait()).await {
            Ok(Some(openward_ssh::russh::ChannelMsg::ExitStatus { exit_status: 7 })) => {
                return Ok("TERM, 80×24 → 100×30, exit 7".into());
            }
            Ok(Some(_)) => {}
            Ok(None) | Err(_) => bail!("no exit status 7"),
        }
    }
}

/// Freezes the server (no RST, no FIN: like a dead network) and measures
/// how long keepalives take to notice; then reconnects.
async fn keepalive_test(
    target: &Target,
    fx: &Fixtures,
    runtime: &str,
    container: &str,
) -> anyhow::Result<String> {
    let opts = Options {
        keepalive: Some(Duration::from_secs(1)),
        ..tofu("demo")
    };
    let session = client::connect(target, Hop::Tcp, &fx.key("id_ed25519"), &opts).await?;
    let pause = Command::new(runtime)
        .args(["pause", container])
        .stdout(Stdio::null())
        .status()
        .await?;
    if !pause.success() {
        bail!("{runtime} pause {container} failed");
    }
    let frozen = Instant::now();
    let mut detected = None;
    while frozen.elapsed() < Duration::from_secs(15) {
        if session.is_closed() {
            detected = Some(frozen.elapsed());
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    let _ = Command::new(runtime)
        .args(["unpause", container])
        .stdout(Stdio::null())
        .status()
        .await;
    let Some(after) = detected else {
        bail!("dead connection not detected in 15 s");
    };
    let again = client::connect(target, Hop::Tcp, &fx.key("id_ed25519"), &tofu("demo")).await?;
    again.exec("true").await?;
    Ok(format!(
        "corte detectado en {:.1} s (keepalive 1 s × 3); reconecta",
        after.as_secs_f64()
    ))
}

/// A throwaway ssh-agent holding the test key, for agent auth and forwarding.
async fn start_agent(fx: &Fixtures, dir: &Path) -> anyhow::Result<(Child, PathBuf)> {
    let socket = dir.join("agent.sock");
    let _ = std::fs::remove_file(&socket);
    let child = Command::new("ssh-agent")
        .arg("-D")
        .arg("-a")
        .arg(&socket)
        .stdout(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .context("ssh-agent")?;
    for _ in 0..50 {
        if socket.exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    let added = Command::new("ssh-add")
        .arg("-q")
        .arg(fx.path("id_ed25519"))
        .env("SSH_AUTH_SOCK", &socket)
        .status()
        .await?;
    if !added.success() {
        bail!("ssh-add failed");
    }
    Ok((child, socket))
}

pub async fn run(fx: &Fixtures, json: bool, only: Option<&str>) -> anyhow::Result<()> {
    let tmp = std::env::temp_dir().join(format!("sshprobe-{}", std::process::id()));
    std::fs::create_dir_all(&tmp)?;
    let (_agent, agent_socket) = start_agent(fx, &tmp).await?;
    // Same runtime as servers/up.sh: $S2_RUNTIME, else podman, else docker.
    let runtime = std::env::var("S2_RUNTIME").ok().or_else(|| {
        ["podman", "docker"]
            .iter()
            .find(|r| {
                std::process::Command::new(r)
                    .arg("--version")
                    .output()
                    .is_ok()
            })
            .map(|r| (*r).to_owned())
    });
    let mut run = Run {
        fx,
        cells: Vec::new(),
        runtime,
        agent_socket,
    };
    for s in SERVERS {
        if only.is_some_and(|o| !s.name.contains(o)) {
            continue;
        }
        if let Err(e) = run.server(s).await {
            eprintln!("{e:#}");
        }
    }
    if only.is_none_or(|o| "Saltos".contains(o)) {
        run.jumps().await;
    }
    let _ = std::fs::remove_dir_all(&tmp);

    let passed = run.cells.iter().filter(|c| c.ok == Some(true)).count();
    let failed = run.cells.iter().filter(|c| c.ok == Some(false)).count();
    let skipped = run.cells.iter().filter(|c| c.ok.is_none()).count();
    if json {
        let cells: Vec<_> = run
            .cells
            .iter()
            .map(|c| json!({"server": c.server, "test": c.test, "ok": c.ok, "detail": c.detail, "ms": c.ms}))
            .collect();
        println!(
            "{}",
            json!({"kind": "ssh-matrix", "russh": "0.64.1", "passed": passed, "failed": failed,
                   "skipped": skipped, "cells": cells})
        );
    } else {
        println!("{passed} ok, {failed} fallos, {skipped} no aplican");
    }
    if failed > 0 {
        bail!("{failed} tests failed");
    }
    Ok(())
}
