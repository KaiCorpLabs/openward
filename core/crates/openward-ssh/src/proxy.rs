//! Reaching the first hop through an HTTP (`CONNECT`) or SOCKS5 proxy, as
//! offices and some networks require. What comes back is a TCP stream to
//! the target that SSH runs over; the proxy sees where it goes, not what
//! goes through it.

use std::net::IpAddr;

use anyhow::{Context, bail};
use data_encoding::BASE64;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProxyKind {
    Http,
    Socks5,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Proxy {
    pub kind: ProxyKind,
    pub host: String,
    pub port: u16,
    pub user: Option<String>,
    /// Only for this attempt: never stored.
    pub password: Option<String>,
}

impl Proxy {
    /// `host:port`, as the UI names it.
    pub fn address(&self) -> String {
        if self.host.contains(':') {
            format!("[{}]:{}", self.host, self.port)
        } else {
            format!("{}:{}", self.host, self.port)
        }
    }
}

/// The proxy wants a user and password, or refused the ones given.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProxyAuthRequired;

impl std::fmt::Display for ProxyAuthRequired {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "the proxy asks for a user and password")
    }
}

impl std::error::Error for ProxyAuthRequired {}

/// A stream to `host:port` through `proxy`.
pub async fn connect(proxy: &Proxy, host: &str, port: u16) -> anyhow::Result<TcpStream> {
    let mut stream = TcpStream::connect((proxy.host.as_str(), proxy.port))
        .await
        .with_context(|| format!("proxy {}", proxy.address()))?;
    stream.set_nodelay(true)?;
    match proxy.kind {
        ProxyKind::Http => http_connect(&mut stream, proxy, host, port).await?,
        ProxyKind::Socks5 => socks5_connect(&mut stream, proxy, host, port).await?,
    }
    Ok(stream)
}

fn credentials(proxy: &Proxy) -> Option<(&str, &str)> {
    match (&proxy.user, &proxy.password) {
        (Some(u), Some(p)) => Some((u.as_str(), p.as_str())),
        _ => None,
    }
}

async fn http_connect(
    stream: &mut TcpStream,
    proxy: &Proxy,
    host: &str,
    port: u16,
) -> anyhow::Result<()> {
    let authority = if host.contains(':') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    };
    let mut request = format!("CONNECT {authority} HTTP/1.1\r\nHost: {authority}\r\n");
    if let Some((user, password)) = credentials(proxy) {
        let token = BASE64.encode(format!("{user}:{password}").as_bytes());
        request.push_str(&format!("Proxy-Authorization: Basic {token}\r\n"));
    }
    request.push_str("\r\n");
    stream.write_all(request.as_bytes()).await?;

    // The answer's head, byte by byte: what follows it is SSH's.
    let mut head = Vec::with_capacity(256);
    while !head.ends_with(b"\r\n\r\n") {
        if head.len() > 16 * 1024 {
            bail!("proxy {}: answer too long", proxy.address());
        }
        let byte = stream
            .read_u8()
            .await
            .with_context(|| format!("proxy {}: closed before answering", proxy.address()))?;
        head.push(byte);
    }
    let head = String::from_utf8_lossy(&head);
    let status_line = head.lines().next().unwrap_or_default();
    let code: u16 = status_line
        .split_whitespace()
        .nth(1)
        .and_then(|c| c.parse().ok())
        .with_context(|| format!("proxy {}: not HTTP ({status_line})", proxy.address()))?;
    match code {
        200..=299 => Ok(()),
        407 => Err(ProxyAuthRequired.into()),
        _ => bail!("proxy {}: {status_line}", proxy.address()),
    }
}

async fn socks5_connect(
    stream: &mut TcpStream,
    proxy: &Proxy,
    host: &str,
    port: u16,
) -> anyhow::Result<()> {
    let creds = credentials(proxy);
    // No authentication, and user/password when there is one to offer.
    let greeting: &[u8] = if creds.is_some() {
        &[5, 2, 0, 2]
    } else {
        &[5, 1, 0]
    };
    stream.write_all(greeting).await?;
    let mut choice = [0u8; 2];
    stream.read_exact(&mut choice).await?;
    if choice[0] != 5 {
        bail!("proxy {}: not SOCKS5", proxy.address());
    }
    match choice[1] {
        0 => {}
        2 => {
            let (user, password) = creds.ok_or(ProxyAuthRequired)?;
            if user.len() > 255 || password.len() > 255 {
                bail!("proxy user or password too long");
            }
            let mut auth = vec![1, user.len() as u8];
            auth.extend_from_slice(user.as_bytes());
            auth.push(password.len() as u8);
            auth.extend_from_slice(password.as_bytes());
            stream.write_all(&auth).await?;
            let mut status = [0u8; 2];
            stream.read_exact(&mut status).await?;
            if status[1] != 0 {
                return Err(ProxyAuthRequired.into());
            }
        }
        // None of ours: it wants a way to authenticate we did not offer.
        _ => return Err(ProxyAuthRequired.into()),
    }

    // CONNECT, by name when it is one: the proxy resolves it.
    let mut request = vec![5, 1, 0];
    match host.parse::<IpAddr>() {
        Ok(IpAddr::V4(ip)) => {
            request.push(1);
            request.extend_from_slice(&ip.octets());
        }
        Ok(IpAddr::V6(ip)) => {
            request.push(4);
            request.extend_from_slice(&ip.octets());
        }
        Err(_) => {
            if host.len() > 255 {
                bail!("host name too long for SOCKS5");
            }
            request.push(3);
            request.push(host.len() as u8);
            request.extend_from_slice(host.as_bytes());
        }
    }
    request.extend_from_slice(&port.to_be_bytes());
    stream.write_all(&request).await?;

    let mut reply = [0u8; 4];
    stream.read_exact(&mut reply).await?;
    if reply[1] != 0 {
        let why = match reply[1] {
            2 => "not allowed by its rules",
            3 => "network unreachable",
            4 => "host unreachable",
            5 => "connection refused",
            6 => "TTL expired",
            _ => "general failure",
        };
        bail!("proxy {}: {why}", proxy.address());
    }
    // The bound address, which nobody needs.
    let skip = match reply[3] {
        1 => 4,
        4 => 16,
        3 => usize::from(stream.read_u8().await?),
        _ => bail!("proxy {}: bad reply", proxy.address()),
    };
    let mut rest = vec![0u8; skip + 2];
    stream.read_exact(&mut rest).await?;
    Ok(())
}
