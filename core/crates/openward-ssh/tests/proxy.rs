//! The proxy client against small proxies started here, in front of an
//! echo server.

use data_encoding::BASE64;
use openward_ssh::proxy::{self, Proxy, ProxyAuthRequired, ProxyKind};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

/// A server that sends back what it gets; its port.
async fn echo() -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        while let Ok((mut s, _)) = listener.accept().await {
            tokio::spawn(async move {
                let (mut r, mut w) = s.split();
                let _ = tokio::io::copy(&mut r, &mut w).await;
            });
        }
    });
    port
}

/// An HTTP proxy that understands CONNECT; with `login`, it wants it.
async fn http_proxy(login: Option<&'static str>) -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        while let Ok((mut s, _)) = listener.accept().await {
            tokio::spawn(async move {
                let mut head = Vec::new();
                while !head.ends_with(b"\r\n\r\n") {
                    head.push(s.read_u8().await.unwrap());
                }
                let head = String::from_utf8(head).unwrap();
                let target = head.split_whitespace().nth(1).unwrap().to_owned();
                if let Some(login) = login {
                    let want = format!(
                        "Proxy-Authorization: Basic {}",
                        BASE64.encode(login.as_bytes())
                    );
                    if !head.contains(&want) {
                        let _ = s
                            .write_all(b"HTTP/1.1 407 Proxy Authentication Required\r\n\r\n")
                            .await;
                        return;
                    }
                }
                let Ok(mut up) = TcpStream::connect(target).await else {
                    let _ = s.write_all(b"HTTP/1.1 502 Bad Gateway\r\n\r\n").await;
                    return;
                };
                s.write_all(b"HTTP/1.1 200 Connection established\r\n\r\n")
                    .await
                    .unwrap();
                let _ = tokio::io::copy_bidirectional(&mut s, &mut up).await;
            });
        }
    });
    port
}

/// A SOCKS5 proxy (CONNECT by name or IPv4); with `login`, user/password only.
async fn socks_proxy(login: Option<(&'static str, &'static str)>) -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        while let Ok((mut s, _)) = listener.accept().await {
            tokio::spawn(async move {
                let mut head = [0u8; 2];
                s.read_exact(&mut head).await.unwrap();
                let mut methods = vec![0u8; usize::from(head[1])];
                s.read_exact(&mut methods).await.unwrap();
                match login {
                    None => s.write_all(&[5, 0]).await.unwrap(),
                    Some(_) if !methods.contains(&2) => {
                        s.write_all(&[5, 0xFF]).await.unwrap();
                        return;
                    }
                    Some((user, pass)) => {
                        s.write_all(&[5, 2]).await.unwrap();
                        let mut v = [0u8; 2];
                        s.read_exact(&mut v).await.unwrap();
                        let mut u = vec![0u8; usize::from(v[1])];
                        s.read_exact(&mut u).await.unwrap();
                        let plen = s.read_u8().await.unwrap();
                        let mut p = vec![0u8; usize::from(plen)];
                        s.read_exact(&mut p).await.unwrap();
                        let ok = u == user.as_bytes() && p == pass.as_bytes();
                        s.write_all(&[1, if ok { 0 } else { 1 }]).await.unwrap();
                        if !ok {
                            return;
                        }
                    }
                }
                let mut req = [0u8; 4];
                s.read_exact(&mut req).await.unwrap();
                let host = match req[3] {
                    1 => {
                        let mut a = [0u8; 4];
                        s.read_exact(&mut a).await.unwrap();
                        std::net::Ipv4Addr::from(a).to_string()
                    }
                    3 => {
                        let n = s.read_u8().await.unwrap();
                        let mut name = vec![0u8; usize::from(n)];
                        s.read_exact(&mut name).await.unwrap();
                        String::from_utf8(name).unwrap()
                    }
                    _ => return,
                };
                let port = s.read_u16().await.unwrap();
                let host = if host == "echo.test" {
                    "127.0.0.1".to_owned()
                } else {
                    host
                };
                match TcpStream::connect((host.as_str(), port)).await {
                    Ok(mut up) => {
                        s.write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0]).await.unwrap();
                        let _ = tokio::io::copy_bidirectional(&mut s, &mut up).await;
                    }
                    Err(_) => s.write_all(&[5, 5, 0, 1, 0, 0, 0, 0, 0, 0]).await.unwrap(),
                }
            });
        }
    });
    port
}

fn proxy(kind: ProxyKind, port: u16, user: Option<&str>, password: Option<&str>) -> Proxy {
    Proxy {
        kind,
        host: "127.0.0.1".into(),
        port,
        user: user.map(str::to_owned),
        password: password.map(str::to_owned),
    }
}

async fn round_trip(mut s: TcpStream) {
    s.write_all(b"hola").await.unwrap();
    let mut got = [0u8; 4];
    s.read_exact(&mut got).await.unwrap();
    assert_eq!(&got, b"hola");
}

fn auth_required(e: &anyhow::Error) -> bool {
    e.downcast_ref::<ProxyAuthRequired>().is_some()
}

#[tokio::test]
async fn http_connect_with_and_without_a_password() {
    let target = echo().await;
    let open = http_proxy(None).await;
    let p = proxy(ProxyKind::Http, open, None, None);
    round_trip(proxy::connect(&p, "127.0.0.1", target).await.unwrap()).await;

    let guarded = http_proxy(Some("ana:secreto")).await;
    let none = proxy(ProxyKind::Http, guarded, Some("ana"), None);
    assert!(auth_required(
        &proxy::connect(&none, "127.0.0.1", target)
            .await
            .unwrap_err()
    ));
    let wrong = proxy(ProxyKind::Http, guarded, Some("ana"), Some("no"));
    assert!(auth_required(
        &proxy::connect(&wrong, "127.0.0.1", target)
            .await
            .unwrap_err()
    ));
    let right = proxy(ProxyKind::Http, guarded, Some("ana"), Some("secreto"));
    round_trip(proxy::connect(&right, "127.0.0.1", target).await.unwrap()).await;

    // A target the proxy cannot reach says so.
    let err = proxy::connect(&p, "127.0.0.1", 1).await.unwrap_err();
    assert!(err.to_string().contains("502"), "{err:#}");
}

#[tokio::test]
async fn socks5_by_name_and_with_a_password() {
    let target = echo().await;
    let open = socks_proxy(None).await;
    let p = proxy(ProxyKind::Socks5, open, None, None);
    // The name goes to the proxy, which resolves it.
    round_trip(proxy::connect(&p, "echo.test", target).await.unwrap()).await;
    round_trip(proxy::connect(&p, "127.0.0.1", target).await.unwrap()).await;

    let guarded = socks_proxy(Some(("ana", "secreto"))).await;
    let none = proxy(ProxyKind::Socks5, guarded, None, None);
    assert!(auth_required(
        &proxy::connect(&none, "echo.test", target)
            .await
            .unwrap_err()
    ));
    let wrong = proxy(ProxyKind::Socks5, guarded, Some("ana"), Some("no"));
    assert!(auth_required(
        &proxy::connect(&wrong, "echo.test", target)
            .await
            .unwrap_err()
    ));
    let right = proxy(ProxyKind::Socks5, guarded, Some("ana"), Some("secreto"));
    round_trip(proxy::connect(&right, "echo.test", target).await.unwrap()).await;

    let err = proxy::connect(&p, "127.0.0.1", 1).await.unwrap_err();
    assert!(err.to_string().contains("connection refused"), "{err:#}");
}
