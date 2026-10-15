//! SFTP with `russh-sftp` 3.0.1 over `openward-ssh` (plan v0.2, B4: the
//! first risk). Per server: the usual operations, then a file (1 GiB by
//! default) up and down, each cut partway and resumed from the offset,
//! checked byte by byte. With `--rtt`, through a relay that delays every
//! byte, as a far server would.

use std::time::{Duration, Instant};

use anyhow::{Context, bail};
use russh_sftp::client::{Config, SftpSession};
use russh_sftp::protocol::{FileAttributes, OpenFlags};
use serde_json::json;
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;

use openward_ssh::client::{self, Hop, Session, Target};

use crate::matrix::{Fixtures, tofu};

const HOST: &str = "127.0.0.1";
const SERVERS: &[(&str, u16)] = &[
    ("OpenSSH 8.9", 22089),
    ("OpenSSH 9.2", 22092),
    ("OpenSSH 10.0", 22100),
    ("Dropbear", 22200),
];

const CHUNK: usize = 1 << 20;

/// How much to move, and where each transfer is cut to resume from there.
#[derive(Clone, Copy)]
pub struct Plan {
    pub size: u64,
    pub cut: u64,
}

impl Plan {
    pub fn mib(mib: u64) -> Self {
        Self {
            size: mib << 20,
            cut: (mib * 3 / 10).max(1) << 20,
        }
    }
}

/// The test file's bytes: word `i` is splitmix64(i), so any range can be
/// generated (and checked) on its own.
fn fill(buf: &mut [u8], offset: u64) {
    debug_assert!(offset.is_multiple_of(8) && buf.len().is_multiple_of(8));
    for (i, word) in buf.as_chunks_mut::<8>().0.iter_mut().enumerate() {
        let mut z = (offset / 8 + i as u64).wrapping_add(0x9E37_79B9_7F4A_7C15);
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        word.copy_from_slice(&(z ^ (z >> 31)).to_le_bytes());
    }
}

fn mib_s(bytes: u64, secs: f64) -> f64 {
    bytes as f64 / (1 << 20) as f64 / secs
}

struct Variant {
    name: &'static str,
    config: Config,
}

fn variants() -> Vec<Variant> {
    vec![
        Variant {
            name: "por defecto (16 × 32 KiB)",
            config: Config::default(),
        },
        Variant {
            name: "64 en vuelo × 255 KiB",
            config: Config {
                max_concurrent_reads: 64,
                max_concurrent_writes: 64,
                max_write_packet_len: 255 * 1024,
                ..Config::default()
            },
        },
    ]
}

/// The SSH session too: the SFTP channel lives as long as it does.
/// A TCP relay to `port` that holds what crosses it for half of `rtt` in
/// each direction (bandwidth is not limited). Returns its port.
async fn delayed(port: u16, rtt: Duration) -> anyhow::Result<u16> {
    let listener = TcpListener::bind((HOST, 0)).await?;
    let local = listener.local_addr()?.port();
    tokio::spawn(async move {
        while let Ok((inbound, _)) = listener.accept().await {
            let Ok(outbound) = TcpStream::connect((HOST, port)).await else {
                continue;
            };
            let (ri, wi) = inbound.into_split();
            let (ro, wo) = outbound.into_split();
            tokio::spawn(pipe(ri, wo, rtt / 2));
            tokio::spawn(pipe(ro, wi, rtt / 2));
        }
    });
    Ok(local)
}

async fn pipe(mut r: OwnedReadHalf, mut w: OwnedWriteHalf, delay: Duration) {
    let (tx, mut rx) = mpsc::unbounded_channel::<(Instant, Vec<u8>)>();
    tokio::spawn(async move {
        let mut buf = vec![0u8; 64 * 1024];
        while let Ok(n @ 1..) = r.read(&mut buf).await {
            if tx
                .send((Instant::now() + delay, buf[..n].to_vec()))
                .is_err()
            {
                break;
            }
        }
    });
    while let Some((at, data)) = rx.recv().await {
        tokio::time::sleep_until(at.into()).await;
        if w.write_all(&data).await.is_err() {
            break;
        }
    }
    let _ = w.shutdown().await;
}

async fn open(fx: &Fixtures, port: u16, config: Config) -> anyhow::Result<(Session, SftpSession)> {
    let session = client::connect(
        &Target::new(HOST, port),
        Hop::Tcp,
        &fx.key("id_ed25519"),
        &tofu("demo"),
    )
    .await?;
    let channel = session.handle.channel_open_session().await?;
    channel.request_subsystem(true, "sftp").await?;
    let sftp = tokio::time::timeout(
        std::time::Duration::from_secs(10),
        SftpSession::new_with_config(channel.into_stream(), config),
    )
    .await
    .context("the server did not answer the SFTP handshake (no sftp-server?)")??;
    Ok((session, sftp))
}

/// mkdir, write, stat, list, rename, chmod, symlink, remove.
async fn operations(sftp: &SftpSession, dir: &str) -> anyhow::Result<String> {
    sftp.create_dir(dir).await.context("mkdir")?;
    let a = format!("{dir}/a.txt");
    // `SftpSession::write` opens without CREATE: only for files that exist.
    let mut f = sftp.create(&a).await.context("create")?;
    f.write_all(b"hola\n").await?;
    f.shutdown().await.context("write")?;
    if sftp.metadata(&a).await?.size != Some(5) {
        bail!("stat: wrong size");
    }
    let b = format!("{dir}/b.txt");
    sftp.rename(&a, &b).await.context("rename")?;
    sftp.set_metadata(
        &b,
        FileAttributes {
            permissions: Some(0o754),
            ..FileAttributes::empty()
        },
    )
    .await
    .context("chmod")?;
    let mode = sftp.metadata(&b).await?.permissions.unwrap_or(0) & 0o777;
    if mode != 0o754 {
        bail!("chmod: {mode:o}");
    }
    let link = format!("{dir}/l");
    // OpenSSH's sftp-server reads SYMLINK's two paths the other way round
    // (its PROTOCOL file, §4.1); so does its client, and so most servers.
    sftp.symlink("b.txt", &link).await.context("symlink")?;
    let target = sftp.read_link(&link).await.context("readlink")?;
    let names: Vec<String> = sftp
        .read_dir(dir)
        .await
        .context("readdir")?
        .map(|e| e.file_name())
        .collect();
    if !names.contains(&"b.txt".to_owned()) || !names.contains(&"l".to_owned()) {
        bail!("readdir: {names:?}");
    }
    let home = sftp.canonicalize(".").await?;
    sftp.remove_file(&link).await?;
    sftp.remove_file(&b).await?;
    Ok(format!("enlace → {target}, home {home}"))
}

/// Uploads the plan's bytes, cut and resumed at the remote size.
async fn upload(sftp: &SftpSession, path: &str, plan: Plan) -> anyhow::Result<f64> {
    let mut buf = vec![0u8; CHUNK];
    let start = Instant::now();
    {
        let mut f = sftp
            .open_with_flags(
                path,
                OpenFlags::CREATE | OpenFlags::TRUNCATE | OpenFlags::WRITE,
            )
            .await?;
        let mut at = 0;
        while at < plan.cut {
            fill(&mut buf, at);
            f.write_all(&buf).await?;
            at += CHUNK as u64;
        }
        f.shutdown().await?;
    }
    let have = sftp.metadata(path).await?.size.unwrap_or(0);
    if have != plan.cut {
        bail!("after the cut: {have} bytes");
    }
    let mut f = sftp.open_with_flags(path, OpenFlags::WRITE).await?;
    f.seek(std::io::SeekFrom::Start(have)).await?;
    let mut at = have;
    while at < plan.size {
        fill(&mut buf, at);
        f.write_all(&buf).await?;
        at += CHUNK as u64;
    }
    f.shutdown().await?;
    let secs = start.elapsed().as_secs_f64();
    let size = sftp.metadata(path).await?.size.unwrap_or(0);
    if size != plan.size {
        bail!("uploaded {size} bytes");
    }
    Ok(mib_s(plan.size, secs))
}

/// Downloads it in two parts (the second from the cut) and checks every
/// byte.
async fn download(sftp: &SftpSession, path: &str, plan: Plan) -> anyhow::Result<f64> {
    let mut got = vec![0u8; CHUNK];
    let mut want = vec![0u8; CHUNK];
    let start = Instant::now();
    for (from, to) in [(0, plan.cut), (plan.cut, plan.size)] {
        let mut f = sftp.open(path).await?;
        f.seek(std::io::SeekFrom::Start(from)).await?;
        let mut at = from;
        while at < to {
            f.read_exact(&mut got).await?;
            fill(&mut want, at);
            if got != want {
                bail!("different bytes in the MiB at {at}");
            }
            at += CHUNK as u64;
        }
    }
    Ok(mib_s(plan.size, start.elapsed().as_secs_f64()))
}

pub async fn run(
    fx: &Fixtures,
    json: bool,
    plan: Plan,
    rtt: Option<Duration>,
    only: Option<&str>,
) -> anyhow::Result<()> {
    for &(server, port) in SERVERS {
        if only.is_some_and(|o| !server.contains(o)) {
            continue;
        }
        let port = match rtt {
            Some(rtt) => delayed(port, rtt).await?,
            None => port,
        };
        for (i, v) in variants().into_iter().enumerate() {
            let dir = format!("ow-sftp-{}-{i}", std::process::id());
            let started = Instant::now();
            let result: anyhow::Result<(String, f64, f64)> = async {
                let (_ssh, sftp) = open(fx, port, v.config.clone()).await?;
                let ops = operations(&sftp, &dir).await?;
                let big = format!("{dir}/big.bin");
                let up = upload(&sftp, &big, plan).await?;
                let down = download(&sftp, &big, plan).await?;
                sftp.remove_file(&big).await?;
                sftp.remove_dir(&dir).await?;
                Ok((ops, up, down))
            }
            .await;
            let secs = started.elapsed().as_secs_f64();
            match &result {
                Ok((ops, up, down)) if json => println!(
                    "{}",
                    json!({"server": server, "variant": v.name, "ok": true, "ops": ops,
                           "up_mib_s": up, "down_mib_s": down, "secs": secs})
                ),
                Ok((ops, up, down)) => println!(
                    "{server:<13} {:<26} ok  subida {up:>6.1} MiB/s  bajada {down:>6.1} MiB/s  ({secs:.0} s; {ops})",
                    v.name
                ),
                Err(e) if json => println!(
                    "{}",
                    json!({"server": server, "variant": v.name, "ok": false, "error": format!("{e:#}")})
                ),
                Err(e) => println!("{server:<13} {:<26} FALLA {e:#}", v.name),
            }
        }
    }
    Ok(())
}
