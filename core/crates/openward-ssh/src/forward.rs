//! Local (-L) and dynamic (-D, SOCKS5) forwarding over `direct-tcpip`.
//! Remote forwarding (-R) lives in the client handler, which receives the
//! server's `forwarded-tcpip` channels.

use std::net::{Ipv4Addr, Ipv6Addr};
use std::sync::Arc;

use anyhow::bail;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::JoinHandle;

use crate::client::Session;

/// A listening forward; dropping it stops accepting.
pub struct Forward {
    pub port: u16,
    task: JoinHandle<()>,
}

impl Drop for Forward {
    fn drop(&mut self) {
        self.task.abort();
    }
}

/// `-L 127.0.0.1:<port>:<host>:<host_port>` with a port picked by the OS.
pub async fn local(session: Arc<Session>, host: &str, port: u16) -> anyhow::Result<Forward> {
    let listener = TcpListener::bind("127.0.0.1:0").await?;
    let local_port = listener.local_addr()?.port();
    let host = host.to_owned();
    let task = tokio::spawn(async move {
        while let Ok((mut socket, peer)) = listener.accept().await {
            let session = Arc::clone(&session);
            let host = host.clone();
            tokio::spawn(async move {
                let Ok(channel) = session
                    .handle
                    .channel_open_direct_tcpip(
                        host,
                        u32::from(port),
                        peer.ip().to_string(),
                        u32::from(peer.port()),
                    )
                    .await
                else {
                    return;
                };
                let mut stream = channel.into_stream();
                let _ = tokio::io::copy_bidirectional(&mut socket, &mut stream).await;
            });
        }
    });
    Ok(Forward {
        port: local_port,
        task,
    })
}

/// `-D 127.0.0.1:<port>`: a SOCKS5 server (no authentication, CONNECT only)
/// whose connections leave from the SSH server.
pub async fn dynamic(session: Arc<Session>) -> anyhow::Result<Forward> {
    let listener = TcpListener::bind("127.0.0.1:0").await?;
    let port = listener.local_addr()?.port();
    let task = tokio::spawn(async move {
        while let Ok((socket, _)) = listener.accept().await {
            let session = Arc::clone(&session);
            tokio::spawn(async move {
                let _ = socks5(socket, &session).await;
            });
        }
    });
    Ok(Forward { port, task })
}

/// Serves one SOCKS5 client (no authentication, CONNECT only) whose
/// connection leaves from the SSH server.
pub async fn socks5(mut socket: TcpStream, session: &Session) -> anyhow::Result<()> {
    // Greeting: VER NMETHODS METHODS…; we only offer "no authentication".
    let mut head = [0u8; 2];
    socket.read_exact(&mut head).await?;
    if head[0] != 5 {
        bail!("not SOCKS5");
    }
    let mut methods = vec![0u8; usize::from(head[1])];
    socket.read_exact(&mut methods).await?;
    if !methods.contains(&0) {
        socket.write_all(&[5, 0xFF]).await?;
        bail!("client wants authentication");
    }
    socket.write_all(&[5, 0]).await?;

    // Request: VER CMD RSV ATYP DST.ADDR DST.PORT
    let mut req = [0u8; 4];
    socket.read_exact(&mut req).await?;
    if req[1] != 1 {
        socket.write_all(&[5, 7, 0, 1, 0, 0, 0, 0, 0, 0]).await?;
        bail!("only CONNECT is supported");
    }
    let host = match req[3] {
        1 => {
            let mut a = [0u8; 4];
            socket.read_exact(&mut a).await?;
            Ipv4Addr::from(a).to_string()
        }
        3 => {
            let len = socket.read_u8().await?;
            let mut name = vec![0u8; usize::from(len)];
            socket.read_exact(&mut name).await?;
            String::from_utf8(name)?
        }
        4 => {
            let mut a = [0u8; 16];
            socket.read_exact(&mut a).await?;
            Ipv6Addr::from(a).to_string()
        }
        _ => bail!("bad address type"),
    };
    let port = socket.read_u16().await?;

    match session
        .handle
        .channel_open_direct_tcpip(host, u32::from(port), "127.0.0.1", 0)
        .await
    {
        Ok(channel) => {
            socket.write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0]).await?;
            let mut stream = channel.into_stream();
            tokio::io::copy_bidirectional(&mut socket, &mut stream).await?;
        }
        Err(_) => {
            // General failure: the server refused or could not connect.
            socket.write_all(&[5, 1, 0, 1, 0, 0, 0, 0, 0, 0]).await?;
        }
    }
    Ok(())
}

/// A SOCKS5 CONNECT from the client side, for the tests.
pub async fn socks5_connect(proxy_port: u16, host: &str, port: u16) -> anyhow::Result<TcpStream> {
    let mut s = TcpStream::connect(("127.0.0.1", proxy_port)).await?;
    s.write_all(&[5, 1, 0]).await?;
    let mut reply = [0u8; 2];
    s.read_exact(&mut reply).await?;
    if reply != [5, 0] {
        bail!("SOCKS5 greeting refused");
    }
    let mut req = vec![5, 1, 0, 3, u8::try_from(host.len())?];
    req.extend_from_slice(host.as_bytes());
    req.extend_from_slice(&port.to_be_bytes());
    s.write_all(&req).await?;
    let mut answer = [0u8; 10];
    s.read_exact(&mut answer).await?;
    if answer[1] != 0 {
        bail!("SOCKS5 CONNECT failed ({})", answer[1]);
    }
    Ok(s)
}
