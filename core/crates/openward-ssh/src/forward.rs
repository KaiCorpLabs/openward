//! Local (-L) and dynamic (-D, SOCKS5) forwarding over `direct-tcpip`.
//! Remote forwarding (-R) lives in the client handler, which receives the
//! server's `forwarded-tcpip` channels.

use std::future::Future;
use std::net::{Ipv4Addr, Ipv6Addr};
use std::sync::Arc;
use std::time::Duration;

use anyhow::bail;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::JoinHandle;

use crate::client::Session;

/// How long a listener may fail in a row before it is given up on.
pub const GIVE_UP: Duration = Duration::from_secs(30);

/// The next connection. A failed accept is most often passing: out of
/// descriptors while a browser opens hundreds through a SOCKS tunnel, a
/// client gone before it was taken. It waits a little and tries again;
/// only after failing for [`GIVE_UP`] in a row does it give up.
pub async fn accept<T, A>(mut next: impl FnMut() -> A) -> std::io::Result<T>
where
    A: Future<Output = std::io::Result<T>>,
{
    let mut pause = Duration::from_millis(10);
    let mut failing = None;
    loop {
        match next().await {
            Ok(accepted) => return Ok(accepted),
            Err(e) => {
                if failing
                    .get_or_insert_with(tokio::time::Instant::now)
                    .elapsed()
                    >= GIVE_UP
                {
                    return Err(e);
                }
                tokio::time::sleep(pause).await;
                pause = (pause * 2).min(Duration::from_secs(1));
            }
        }
    }
}

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
        while let Ok((mut socket, peer)) = accept(|| listener.accept()).await {
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
        while let Ok((socket, _)) = accept(|| listener.accept()).await {
            let session = Arc::clone(&session);
            tokio::spawn(async move {
                let _ = socks5(socket, &session).await;
            });
        }
    });
    Ok(Forward { port, task })
}

/// How long a SOCKS5 client has to say where it is going.
const HANDSHAKE: Duration = Duration::from_secs(10);

/// Serves one SOCKS5 client (no authentication, CONNECT only) whose
/// connection leaves from the SSH server.
pub async fn socks5(mut socket: TcpStream, session: &Session) -> anyhow::Result<()> {
    let (host, port) = tokio::time::timeout(HANDSHAKE, socks5_request(&mut socket))
        .await
        .map_err(|_| anyhow::anyhow!("SOCKS5 client said nothing"))??;
    match session
        .handle
        .channel_open_direct_tcpip(host, u32::from(port), "127.0.0.1", 0)
        .await
    {
        Ok(channel) => {
            socket.write_all(&reply(0)).await?;
            let mut stream = channel.into_stream();
            tokio::io::copy_bidirectional(&mut socket, &mut stream).await?;
        }
        // General failure: the server refused or could not connect.
        Err(_) => socket.write_all(&reply(1)).await?,
    }
    Ok(())
}

/// A reply with no bound address (`0.0.0.0:0`).
fn reply(code: u8) -> [u8; 10] {
    [5, code, 0, 1, 0, 0, 0, 0, 0, 0]
}

/// The greeting and the CONNECT request: where the client is going. What
/// SOCKS5 lets it say no to gets its answer before the error.
async fn socks5_request<S>(socket: &mut S) -> anyhow::Result<(String, u16)>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
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
    if req[0] != 5 {
        socket.write_all(&reply(1)).await?;
        bail!("not SOCKS5");
    }
    if req[1] != 1 {
        socket.write_all(&reply(7)).await?;
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
            match String::from_utf8(name) {
                Ok(name) if !name.is_empty() => name,
                _ => {
                    socket.write_all(&reply(4)).await?;
                    bail!("bad host name");
                }
            }
        }
        4 => {
            let mut a = [0u8; 16];
            socket.read_exact(&mut a).await?;
            Ipv6Addr::from(a).to_string()
        }
        _ => {
            socket.write_all(&reply(8)).await?;
            bail!("bad address type");
        }
    };
    let port = socket.read_u16().await?;
    Ok((host, port))
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

#[cfg(test)]
mod tests {
    use super::*;

    /// What a client sending `sent` hears back, and where it goes.
    async fn request(sent: &[u8]) -> (Vec<u8>, anyhow::Result<(String, u16)>) {
        let (mut ours, mut theirs) = tokio::io::duplex(1024);
        theirs.write_all(sent).await.unwrap();
        theirs.shutdown().await.unwrap();
        let asked = socks5_request(&mut ours).await;
        drop(ours);
        let mut heard = Vec::new();
        theirs.read_to_end(&mut heard).await.unwrap();
        (heard, asked)
    }

    #[tokio::test]
    async fn socks5_requests_by_address_and_by_name() {
        let (heard, asked) = request(&[5, 1, 0, 5, 1, 0, 1, 10, 0, 0, 7, 0, 22]).await;
        assert_eq!(heard, [5, 0]);
        assert_eq!(asked.unwrap(), ("10.0.0.7".into(), 22));

        let mut v6 = vec![5, 2, 2, 0, 5, 1, 0, 4];
        v6.extend_from_slice(&Ipv6Addr::LOCALHOST.octets());
        v6.extend_from_slice(&443u16.to_be_bytes());
        assert_eq!(request(&v6).await.1.unwrap(), ("::1".into(), 443));

        let mut named = vec![5, 1, 0, 5, 1, 0, 3, 7];
        named.extend_from_slice(b"db.test\x00\x50");
        assert_eq!(request(&named).await.1.unwrap(), ("db.test".into(), 80));
    }

    /// A client that says something else, or stops halfway, gets its
    /// answer and an error, and nothing panics.
    #[tokio::test]
    async fn malformed_socks5_requests_fail() {
        let cases: &[(&[u8], &[u8])] = &[
            // SOCKS4, and a greeting cut short.
            (&[4, 1, 0, 80], &[]),
            (&[5, 3, 0], &[]),
            (&[], &[]),
            // Only user/password: none of ours.
            (&[5, 1, 2], &[5, 0xFF]),
            // BIND, a request in another version, an unknown address type.
            (
                &[5, 1, 0, 5, 2, 0, 1],
                &[5, 0, 5, 7, 0, 1, 0, 0, 0, 0, 0, 0],
            ),
            (
                &[5, 1, 0, 4, 1, 0, 1],
                &[5, 0, 5, 1, 0, 1, 0, 0, 0, 0, 0, 0],
            ),
            (
                &[5, 1, 0, 5, 1, 0, 9],
                &[5, 0, 5, 8, 0, 1, 0, 0, 0, 0, 0, 0],
            ),
            // A name that is not UTF-8, an empty one, one cut short.
            (
                &[5, 1, 0, 5, 1, 0, 3, 2, 0xFF, 0xFE, 0, 80],
                &[5, 0, 5, 4, 0, 1, 0, 0, 0, 0, 0, 0],
            ),
            (
                &[5, 1, 0, 5, 1, 0, 3, 0, 0, 80],
                &[5, 0, 5, 4, 0, 1, 0, 0, 0, 0, 0, 0],
            ),
            (&[5, 1, 0, 5, 1, 0, 3, 200, b'a'], &[5, 0]),
            // No port.
            (&[5, 1, 0, 5, 1, 0, 1, 10, 0, 0, 7, 0], &[5, 0]),
        ];
        for (sent, answer) in cases {
            let (heard, asked) = request(sent).await;
            assert!(asked.is_err(), "{sent:?} → {asked:?}");
            assert_eq!(&heard, answer, "{sent:?}");
        }
    }

    /// Out of descriptors for a while: it waits and goes on. Failing for
    /// good: it gives up, in time.
    #[tokio::test(start_paused = true)]
    async fn accepting_rides_out_passing_errors() {
        let emfile = || std::io::Error::other("Too many open files");
        let mut left = 5;
        let accepted = accept(|| {
            left -= 1;
            let r = if left > 0 { Err(emfile()) } else { Ok(7) };
            async move { r }
        })
        .await;
        assert_eq!(accepted.unwrap(), 7);

        let started = tokio::time::Instant::now();
        let given_up = accept(|| async { Err::<(), _>(emfile()) }).await;
        assert!(given_up.is_err());
        let took = started.elapsed();
        assert!(
            took >= GIVE_UP && took < GIVE_UP + Duration::from_secs(2),
            "{took:?}"
        );
    }
}
