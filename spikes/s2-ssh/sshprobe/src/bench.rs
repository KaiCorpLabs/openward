//! Measurements for spike S2: connection setup, channel throughput and
//! keystroke echo through a remote PTY. The servers run in containers, so the
//! network path is the container runtime's (a VM on macOS): OpenSSH's own
//! client is timed over the same path as the reference.

use std::time::{Duration, Instant};

use anyhow::bail;
use serde_json::json;

use crate::matrix::{Fixtures, tofu};
use sshprobe::client::{self, Hop, Target};

fn summary(mut v: Vec<f64>) -> serde_json::Value {
    v.sort_by(f64::total_cmp);
    let at = |q: f64| v[((v.len() - 1) as f64 * q).round() as usize];
    json!({"p50": at(0.5), "p95": at(0.95), "max": v[v.len() - 1], "n": v.len()})
}

/// OpenSSH's client over the same path, for reference.
fn openssh_args(fx: &Fixtures, port: u16) -> Vec<String> {
    [
        "-F",
        "/dev/null",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "UserKnownHostsFile=/dev/null",
        "-o",
        "LogLevel=ERROR",
        "-o",
        "IdentitiesOnly=yes",
    ]
    .iter()
    .map(|s| (*s).to_owned())
    .chain([
        "-p".into(),
        port.to_string(),
        "-i".into(),
        fx.path("id_ed25519").display().to_string(),
        "demo@127.0.0.1".into(),
    ])
    .collect()
}

pub async fn run(fx: &Fixtures, port: u16, json_out: bool) -> anyhow::Result<()> {
    let target = Target::new("127.0.0.1", port);
    let key = fx.key("id_ed25519");

    // 1. Connection setup: TCP, kex, host key, Ed25519 auth.
    let mut ours = Vec::new();
    for _ in 0..30 {
        let s = client::connect(&target, Hop::Tcp, &key, &tofu("demo")).await?;
        ours.push(s.info().connect_ms);
        s.disconnect().await;
    }
    let mut theirs = Vec::new();
    for _ in 0..30 {
        let t = Instant::now();
        let st = tokio::process::Command::new("ssh")
            .args(openssh_args(fx, port))
            .arg("true")
            .status()
            .await?;
        if !st.success() {
            bail!("ssh true failed");
        }
        theirs.push(t.elapsed().as_secs_f64() * 1e3);
    }

    // 2. Throughput of one channel: 512 MiB of zeros from the server.
    const BYTES: u64 = 512 << 20;
    let session = client::connect(&target, Hop::Tcp, &key, &tofu("demo")).await?;
    let t = Instant::now();
    let out = session.exec(&format!("head -c {BYTES} /dev/zero")).await?;
    let secs = t.elapsed().as_secs_f64();
    if out.stdout.len() as u64 != BYTES {
        bail!("got {} bytes", out.stdout.len());
    }
    let ours_mibs = BYTES as f64 / 1_048_576.0 / secs;
    let t = Instant::now();
    let st = tokio::process::Command::new("ssh")
        .args(openssh_args(fx, port))
        .arg(format!("head -c {BYTES} /dev/zero"))
        .stdout(std::process::Stdio::null())
        .status()
        .await?;
    if !st.success() {
        bail!("ssh head failed");
    }
    let theirs_mibs = BYTES as f64 / 1_048_576.0 / t.elapsed().as_secs_f64();

    // 3. Keystroke echo: one byte into a remote PTY (cooked mode echoes it).
    let mut ch = session.shell("xterm-256color", 80, 24).await?;
    client::send(&ch, b"stty -icanon; cat\n").await?;
    tokio::time::sleep(Duration::from_millis(300)).await;
    while tokio::time::timeout(Duration::from_millis(50), ch.wait())
        .await
        .is_ok()
    {}
    let mut echo = Vec::new();
    for i in 0..300u32 {
        let byte = b'a' + (i % 26) as u8;
        let t = Instant::now();
        client::send(&ch, &[byte]).await?;
        loop {
            match tokio::time::timeout(Duration::from_secs(2), ch.wait()).await {
                Ok(Some(russh::ChannelMsg::Data { data })) if data.contains(&byte) => break,
                Ok(Some(_)) => {}
                _ => bail!("no echo for byte {i}"),
            }
        }
        echo.push(t.elapsed().as_secs_f64() * 1e3);
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    session.disconnect().await;

    let result = json!({
        "kind": "ssh-bench",
        "port": port,
        "server": out_banner(port),
        "connect_ms": {"russh": summary(ours), "openssh": summary(theirs)},
        "throughput_mib_s": {"russh": ours_mibs, "openssh": theirs_mibs},
        "echo_ms": summary(echo),
    });
    if json_out {
        println!("{result}");
    } else {
        println!("{}", serde_json::to_string_pretty(&result)?);
    }
    Ok(())
}

fn out_banner(port: u16) -> &'static str {
    match port {
        22089 => "OpenSSH 8.9",
        22092 => "OpenSSH 9.2",
        22100 => "OpenSSH 10.0",
        22200 => "Dropbear",
        _ => "?",
    }
}
