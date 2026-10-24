//! `openward-sftp` against the S2 test servers
//! (`spikes/s2-ssh/servers/up.sh`). Skipped when they are not running,
//! unless `OPENWARD_REQUIRE_SERVERS` is set (`make ci`).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};
use std::time::{Duration, Instant};

use openward_sftp::transfer::{FILES_AT_ONCE, PART, RESUME_OVERLAP, part_path};
use openward_sftp::{
    Direction, Entry, JobState, Kind, Link, OnConflict, Remote, Request, Transfers, join,
};
use openward_ssh::client::{self, Auth, Hop, Options, Session, Target};
use openward_ssh::known_hosts::{KnownHosts, Unknown};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, ReadBuf};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::task::AbortHandle;

const HOST: &str = "127.0.0.1";
const OPENSSH: u16 = 22100;
/// Every server of the matrix: OpenSSH 8.9, 9.2 and 10.0, and Dropbear.
const ALL: [u16; 4] = [22089, 22092, 22100, 22200];

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
    let up = std::net::TcpStream::connect((HOST, OPENSSH)).is_ok();
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

struct Server {
    ssh: Session,
    remote: Arc<Remote>,
    /// A folder of this test's own in the user's home, removed at the end.
    dir: String,
}

async fn connect(fx: &Path, port: u16) -> Session {
    let opts = Options {
        user: "demo".into(),
        known_hosts: Arc::new(Mutex::new(KnownHosts::new(Unknown::Learn))),
        host_certificates: false,
        legacy_host_keys: false,
        connect_timeout: None,
        keepalive: None,
        agent_forward: None,
        on_untrusted: None,
    };
    let auth = Auth::Key {
        path: fx.join("id_ed25519"),
        passphrase: None,
    };
    client::connect(&Target::new(HOST, port), Hop::Tcp, &auth, &opts)
        .await
        .unwrap()
}

async fn server(fx: &Path, port: u16, name: &str) -> Server {
    let ssh = connect(fx, port).await;
    let remote = Remote::open(ssh.sftp().await.unwrap()).await.unwrap();
    let dir = join(
        remote.home(),
        &format!("ow-sftp-{name}-{}-{port}", std::process::id()),
    );
    remote.remove(&dir).await.unwrap();
    remote.mkdir(&dir).await.unwrap();
    Server { ssh, remote, dir }
}

impl Server {
    async fn sh(&self, script: &str) {
        let out = self
            .ssh
            .exec(&format!("cd {} && {script}", self.dir))
            .await
            .unwrap();
        assert_eq!(out.status, Some(0), "{script}");
    }

    async fn cat(&self, rel: &str) -> Vec<u8> {
        self.ssh
            .exec(&format!("cat '{}'", join(&self.dir, rel)))
            .await
            .unwrap()
            .stdout
    }

    async fn entry(&self, rel: &str) -> Option<Entry> {
        self.remote.lstat(&join(&self.dir, rel)).await.unwrap()
    }

    /// The `.part` files in a folder of the test's.
    async fn parts(&self, rel: &str) -> Vec<String> {
        let mut names: Vec<String> = (self.remote.list(&join(&self.dir, rel)).await)
            .unwrap()
            .into_iter()
            .map(|e| e.name)
            .filter(|n| n.ends_with(PART))
            .collect();
        names.sort();
        names
    }

    /// The `.part` files anywhere below a folder of the test's.
    async fn parts_below(&self, rel: &str) -> Vec<String> {
        let out = self
            .ssh
            .exec(&format!(
                "cd '{}' && find . -name '*{PART}' | sort",
                join(&self.dir, rel)
            ))
            .await
            .unwrap();
        out.text().lines().map(str::to_owned).collect()
    }

    /// How many whole files (not parts) there are below a folder of the
    /// test's.
    async fn files_below(&self, rel: &str) -> usize {
        let out = self
            .ssh
            .exec(&format!(
                "cd '{}' && find . -type f ! -name '*{PART}' | wc -l",
                join(&self.dir, rel)
            ))
            .await
            .unwrap();
        out.text().trim().parse().unwrap()
    }

    async fn done(self) {
        self.remote.remove(&self.dir).await.unwrap();
        assert!(self.remote.lstat(&self.dir).await.unwrap().is_none());
    }
}

/// A TCP proxy to a server that holds what goes through it `delay` each
/// way, as a far server's network would; [`cut`](Far::cut) drops every
/// connection through it, as a lost one does.
struct Far {
    port: u16,
    /// The tasks that carry each connection: aborted, it is gone.
    pipes: Arc<Mutex<Vec<AbortHandle>>>,
}

impl Far {
    async fn new(to: u16, delay: Duration) -> Self {
        let listener = tokio::net::TcpListener::bind((HOST, 0)).await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let pipes = Arc::new(Mutex::new(Vec::new()));
        let held = Arc::clone(&pipes);
        tokio::spawn(async move {
            while let Ok((near, _)) = listener.accept().await {
                let Ok(far) = tokio::net::TcpStream::connect((HOST, to)).await else {
                    continue;
                };
                let _ = (near.set_nodelay(true), far.set_nodelay(true));
                let (near_read, near_write) = near.into_split();
                let (far_read, far_write) = far.into_split();
                let mut pipes = held.lock().unwrap();
                pipes.extend(late(near_read, far_write, delay));
                pipes.extend(late(far_read, near_write, delay));
            }
        });
        Self { port, pipes }
    }

    fn cut(&self) {
        for pipe in self.pipes.lock().unwrap().drain(..) {
            pipe.abort();
        }
    }

    /// A connection to the server through here, with its SFTP requests
    /// counted in `sent`.
    async fn remote(&self, fx: &Path, sent: &Sent) -> (Session, Arc<Remote>) {
        let ssh = connect(fx, self.port).await;
        let stream = Counted {
            inner: ssh.sftp().await.unwrap(),
            sent: sent.clone(),
            head: Vec::new(),
            left: 0,
        };
        let remote = Remote::open(stream).await.unwrap();
        (ssh, remote)
    }
}

/// Copies `from` to `to`, each read `delay` after it came.
fn late(mut from: OwnedReadHalf, mut to: OwnedWriteHalf, delay: Duration) -> [AbortHandle; 2] {
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<(tokio::time::Instant, Vec<u8>)>();
    let write = tokio::spawn(async move {
        while let Some((at, data)) = rx.recv().await {
            tokio::time::sleep_until(at + delay).await;
            if to.write_all(&data).await.is_err() {
                break;
            }
        }
    });
    let read = tokio::spawn(async move {
        let mut buf = vec![0u8; 64 << 10];
        while let Ok(n @ 1..) = from.read(&mut buf).await {
            if tx
                .send((tokio::time::Instant::now(), buf[..n].to_vec()))
                .is_err()
            {
                break;
            }
        }
    });
    [write.abort_handle(), read.abort_handle()]
}

/// The SFTP requests sent on a stream, by type.
#[derive(Clone, Default)]
struct Sent(Arc<Mutex<BTreeMap<u8, u64>>>);

impl Sent {
    /// What was sent since the last time.
    fn take(&self) -> BTreeMap<u8, u64> {
        std::mem::take(&mut self.0.lock().unwrap())
    }
}

/// An SFTP stream that counts the packets written to it: four bytes of
/// length, then the type.
struct Counted<S> {
    inner: S,
    sent: Sent,
    /// The start of the packet being written, until its type is known.
    head: Vec<u8>,
    /// What is left of the packet being written, after its type.
    left: usize,
}

impl<S> Counted<S> {
    fn count(&mut self, mut bytes: &[u8]) {
        while !bytes.is_empty() {
            if self.left > 0 {
                let n = self.left.min(bytes.len());
                self.left -= n;
                bytes = &bytes[n..];
                continue;
            }
            let n = (5 - self.head.len()).min(bytes.len());
            self.head.extend_from_slice(&bytes[..n]);
            bytes = &bytes[n..];
            if self.head.len() == 5 {
                let len = u32::from_be_bytes(self.head[..4].try_into().unwrap()) as usize;
                *self.sent.0.lock().unwrap().entry(self.head[4]).or_default() += 1;
                self.left = len - 1;
                self.head.clear();
            }
        }
    }
}

impl<S: AsyncRead + Unpin> AsyncRead for Counted<S> {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_read(cx, buf)
    }
}

impl<S: AsyncWrite + Unpin> AsyncWrite for Counted<S> {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        let this = self.get_mut();
        let written = Pin::new(&mut this.inner).poll_write(cx, buf);
        if let Poll::Ready(Ok(n)) = written {
            this.count(&buf[..n]);
        }
        written
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_flush(cx)
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_shutdown(cx)
    }
}

/// The requests in `sent`, by name, and how many there were per file.
fn requests(sent: &BTreeMap<u8, u64>, files: usize) -> String {
    let name = |t: u8| match t {
        3 => "open",
        4 => "close",
        5 => "read",
        6 => "write",
        7 => "lstat",
        9 => "setstat",
        11 => "opendir",
        12 => "readdir",
        13 => "remove",
        14 => "mkdir",
        16 => "realpath",
        17 => "stat",
        18 => "rename",
        19 => "readlink",
        200 => "extended",
        _ => "other",
    };
    let total: u64 = sent.values().sum();
    let each: Vec<String> = sent
        .iter()
        .map(|(t, n)| format!("{} {n}", name(*t)))
        .collect();
    format!(
        "{total} requests, {:.2} per file ({})",
        total as f64 / files as f64,
        each.join(", ")
    )
}

/// `n` small files below `root`, in `dirs` folders with a folder each
/// inside: what they are called (`/`-separated) and hold.
fn small_files(root: &Path, dirs: usize, n: usize) -> Vec<(String, Vec<u8>)> {
    (0..n)
        .map(|i| {
            let dir = format!("d{:02}", i % dirs);
            let rel = if i % 2 == 0 {
                format!("{dir}/f{i:04}.txt")
            } else {
                format!("{dir}/inner/f{i:04}.txt")
            };
            let data = pattern(100 + (i * 37) % 3000, i as u8);
            let path = root.join(&rel);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, &data).unwrap();
            (rel, data)
        })
        .collect()
}

/// Whether every one of `files` is below `root` as it should be.
fn same_files(root: &Path, files: &[(String, Vec<u8>)]) {
    for (rel, data) in files {
        assert_eq!(&std::fs::read(root.join(rel)).unwrap(), data, "{rel}");
    }
}

/// Bytes that differ along the file, so a misplaced block shows.
fn pattern(len: usize, seed: u8) -> Vec<u8> {
    (0..len)
        .map(|i| ((i / 7) as u8).wrapping_mul(31).wrapping_add(seed) ^ (i >> 13) as u8)
        .collect()
}

fn transfers() -> Transfers {
    Transfers::new(tokio::runtime::Handle::current())
}

fn link(remote: &Arc<Remote>) -> Arc<Link> {
    let link = Link::new("test");
    link.set(Some(Arc::clone(remote)));
    link
}

async fn copy(
    t: &Transfers,
    l: &Arc<Link>,
    direction: Direction,
    source: impl Into<String>,
    dest_dir: impl Into<String>,
    on_conflict: OnConflict,
) -> openward_sftp::JobView {
    let id = t.add(
        Arc::clone(l),
        Request {
            direction,
            source: source.into(),
            dest_dir: dest_dir.into(),
            on_conflict,
        },
    );
    t.wait(id).await.unwrap()
}

fn view(t: &Transfers, id: u64) -> openward_sftp::JobView {
    t.jobs().into_iter().find(|j| j.id == id).unwrap()
}

/// Waits until job `id` has copied `files` files.
async fn until(t: &Transfers, id: u64, files: u32) {
    while view(t, id).files_done < files {
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
}

/// The `.part` files anywhere below a local folder.
fn local_parts(root: &Path) -> Vec<PathBuf> {
    openward_sftp::local::walk(root)
        .unwrap()
        .into_iter()
        .map(|(rel, _)| rel)
        .filter(|rel| rel.to_string_lossy().ends_with(PART))
        .collect()
}

fn path_str(p: &Path) -> String {
    p.display().to_string()
}

#[cfg(unix)]
fn set_mode(p: &Path, mode: u32) {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(p, std::fs::Permissions::from_mode(mode)).unwrap();
}

#[cfg(unix)]
fn mode_of(p: &Path) -> u32 {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p).unwrap().permissions().mode() & 0o777
}

#[tokio::test]
async fn lists_and_changes_files() {
    let fx = servers!();
    let s = server(&fx, OPENSSH, "ops").await;
    s.sh(
        "mkdir -p sub && printf hola > a.txt && chmod 754 a.txt && printf x > sub/s.txt \
         && chmod 644 sub/s.txt && ln -s sub dirlink && ln -s a.txt filelink",
    )
    .await;

    let mut list = s.remote.list(&s.dir).await.unwrap();
    list.sort_by(|a, b| a.name.cmp(&b.name));
    let names: Vec<_> = list.iter().map(|e| (e.name.as_str(), e.kind)).collect();
    assert_eq!(
        names,
        [
            ("a.txt", Kind::File),
            ("dirlink", Kind::Link),
            ("filelink", Kind::Link),
            ("sub", Kind::Dir)
        ]
    );
    let a = &list[0];
    assert_eq!((a.size, a.mode), (4, Some(0o754)));
    assert_eq!(a.owner.as_deref(), Some("demo"));
    assert!(a.modified.is_some());
    let dirlink = &list[1];
    assert!(dirlink.link_dir && dirlink.is_dir());
    assert_eq!(dirlink.link_target.as_deref(), Some("sub"));
    let filelink = &list[2];
    assert!(!filelink.link_dir);
    assert_eq!(filelink.size, 4, "a link to a file has the file's size");

    // Many links, more than are asked about at once: all of them answered.
    s.sh("mkdir many && for i in $(seq 1 100); do ln -s ../a.txt many/l$i; done")
        .await;
    let many = s.remote.list(&join(&s.dir, "many")).await.unwrap();
    assert_eq!(many.len(), 100);
    assert!(
        many.iter()
            .all(|e| e.link_target.as_deref() == Some("../a.txt") && e.size == 4)
    );
    s.sh("rm -r many").await;

    // Folders, renames and what already exists.
    let p = |rel: &str| join(&s.dir, rel);
    assert_eq!(
        s.remote.mkdir(&p("sub")).await,
        Err(openward_sftp::Error::Exists(p("sub")))
    );
    s.remote.mkdir(&p("new")).await.unwrap();
    s.remote
        .rename(&p("a.txt"), &p("b.txt"), false)
        .await
        .unwrap();
    assert!(s.entry("a.txt").await.is_none());
    assert_eq!(
        s.remote.rename(&p("b.txt"), &p("sub"), false).await,
        Err(openward_sftp::Error::Exists(p("sub")))
    );
    s.sh("printf old > c.txt").await;
    s.remote
        .rename(&p("b.txt"), &p("c.txt"), true)
        .await
        .unwrap();
    assert_eq!(s.cat("c.txt").await, b"hola");

    // chmod -R with X: the folder and files that ran keep execute.
    s.sh("chmod 755 c.txt").await;
    s.remote
        .rename(&p("c.txt"), &p("sub/run.sh"), false)
        .await
        .unwrap();
    assert_eq!(s.remote.chmod(&p("sub"), 0o750, true).await.unwrap(), 3);
    assert_eq!(s.entry("sub").await.unwrap().mode, Some(0o750));
    assert_eq!(s.entry("sub/run.sh").await.unwrap().mode, Some(0o750));
    assert_eq!(s.entry("sub/s.txt").await.unwrap().mode, Some(0o640));

    // Removing a link leaves what it points to.
    s.remote.remove(&p("dirlink")).await.unwrap();
    assert!(s.entry("sub/s.txt").await.is_some());
    s.remote.remove(&p("sub")).await.unwrap();
    assert!(s.entry("sub").await.is_none());
    assert_eq!(
        s.remote.list(&p("nothing")).await.err(),
        Some(openward_sftp::Error::NotFound(p("nothing")))
    );
    s.done().await;
}

/// Walking a folder, what a download does first, on every server of the
/// matrix; and far away, with several listings at once.
#[tokio::test]
async fn walks_a_folder_several_listings_at_once() {
    let fx = servers!();
    for port in ALL {
        let s = server(&fx, port, "walk").await;
        s.sh(
            "mkdir -p t/a/b/c t/d && printf x > t/a/b/c/f && printf yy > t/a/one \
             && printf z > t/d/z && ln -s a t/dirlink && ln -s a/one t/filelink",
        )
        .await;
        let walked = s.remote.walk(&join(&s.dir, "t")).await.unwrap();
        let rels: Vec<&str> = walked.iter().map(|(rel, _)| rel.as_str()).collect();
        // Folders before what they hold, in the order of one listing after
        // another; the link to a folder is not followed.
        assert_eq!(
            rels,
            [
                "a", "d", "filelink", "d/z", "a/b", "a/one", "a/b/c", "a/b/c/f"
            ],
            "port {port}"
        );
        let filelink = &walked[2].1;
        assert_eq!(
            (filelink.kind, filelink.link_dir, filelink.size),
            (Kind::Link, false, 2),
            "port {port}"
        );
        s.done().await;
    }

    // Far away, the listings overlap.
    let s = server(&fx, OPENSSH, "walk-far").await;
    s.sh("for i in $(seq 10 25); do mkdir -p w/d$i/in && printf x > w/d$i/in/f; done")
        .await;
    let rtt = Duration::from_millis(50);
    let far = Far::new(OPENSSH, rtt / 2).await;
    let sent = Sent::default();
    let (_ssh, remote) = far.remote(&fx, &sent).await;
    let w = join(&s.dir, "w");
    sent.take();
    let started = Instant::now();
    let walked = remote.walk(&w).await.unwrap();
    let took = started.elapsed();
    assert_eq!(walked.len(), 16 * 3);
    let folders = 1 + 16 * 2;
    assert_eq!(sent.take().get(&11), Some(&folders), "an opendir each");
    // One after another, each folder costs 4 round trips.
    let one_by_one = rtt * 4 * folders as u32;
    assert!(took < one_by_one / 2, "{took:?}, one by one {one_by_one:?}");

    // One that cannot be read fails the walk, and the session goes on.
    s.sh("mkdir w/d17/locked && chmod 000 w/d17/locked").await;
    assert_eq!(
        remote.walk(&w).await.map(|walked| walked.len()),
        Err(openward_sftp::Error::Denied(join(&w, "d17/locked")))
    );
    assert_eq!(remote.list(&join(&w, "d17")).await.unwrap().len(), 2);
    s.sh("chmod 755 w/d17/locked").await;
    s.done().await;
}

/// A folder up and back down, on every server of the matrix.
#[tokio::test]
async fn copies_a_folder_both_ways_everywhere() {
    let fx = servers!();
    for port in ALL {
        let s = server(&fx, port, "both").await;
        let local = tempfile::tempdir().unwrap();
        let site = local.path().join("site");
        std::fs::create_dir_all(site.join("assets/img")).unwrap();
        let big = pattern(3 << 20, 7);
        std::fs::write(site.join("big.bin"), &big).unwrap();
        std::fs::write(site.join("empty"), b"").unwrap();
        std::fs::write(site.join("assets/img/logo.svg"), b"<svg/>").unwrap();
        std::fs::write(site.join("deploy.sh"), b"#!/bin/sh\n").unwrap();
        #[cfg(unix)]
        {
            set_mode(&site.join("deploy.sh"), 0o755);
            set_mode(&site.join("big.bin"), 0o640);
        }

        let t = transfers();
        let l = link(&s.remote);
        let up = copy(
            &t,
            &l,
            Direction::Upload,
            path_str(&site),
            &s.dir,
            OnConflict::Replace,
        )
        .await;
        assert_eq!(up.state, JobState::Done, "port {port}: {:?}", up.error);
        assert!(up.is_dir);
        assert_eq!((up.files, up.files_done, up.skipped), (4, 4, 0));
        assert_eq!(up.total, (3 << 20) + 6 + 10);
        assert_eq!(up.done, up.total);
        assert_eq!(s.entry("site/big.bin").await.unwrap().size, 3 << 20);
        assert_eq!(s.entry("site/empty").await.unwrap().size, 0);
        assert!(s.entry("site/assets/img").await.unwrap().is_dir());
        assert!(s.parts("site").await.is_empty());
        let mtime = |p: &Path| {
            std::fs::metadata(p)
                .unwrap()
                .modified()
                .unwrap()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64
        };
        assert_eq!(
            s.entry("site/big.bin").await.unwrap().modified,
            Some(mtime(&site.join("big.bin"))),
            "the date goes with the file"
        );
        #[cfg(unix)]
        {
            assert_eq!(s.entry("site/deploy.sh").await.unwrap().mode, Some(0o755));
            assert_eq!(s.entry("site/big.bin").await.unwrap().mode, Some(0o640));
        }

        // Private on the server, private here.
        s.sh("chmod 600 site/empty").await;

        let back = tempfile::tempdir().unwrap();
        let down = copy(
            &t,
            &l,
            Direction::Download,
            join(&s.dir, "site"),
            path_str(back.path()),
            OnConflict::Replace,
        )
        .await;
        assert_eq!(down.state, JobState::Done, "port {port}: {:?}", down.error);
        let got = back.path().join("site");
        assert_eq!(std::fs::read(got.join("big.bin")).unwrap(), big);
        assert_eq!(mtime(&got.join("big.bin")), mtime(&site.join("big.bin")));
        assert_eq!(
            std::fs::read(got.join("assets/img/logo.svg")).unwrap(),
            b"<svg/>"
        );
        assert_eq!(std::fs::read(got.join("empty")).unwrap(), b"");
        #[cfg(unix)]
        {
            assert_eq!(
                mode_of(&got.join("deploy.sh")) & 0o100,
                0o100,
                "stays runnable"
            );
            assert_eq!(mode_of(&got.join("big.bin")) & 0o007, 0, "0640 there");
            assert_eq!(mode_of(&got.join("empty")), 0o600, "0600 there");
        }
        s.done().await;
    }
}

#[tokio::test]
async fn conflicts_skip_replace_newer_or_keep_both() {
    let fx = servers!();
    let s = server(&fx, OPENSSH, "conflicts").await;
    let local = tempfile::tempdir().unwrap();
    let file = local.path().join("x.txt");
    std::fs::write(&file, b"mine").unwrap();
    s.sh("printf theirs > x.txt && chmod 751 x.txt").await;
    let (t, l) = (transfers(), link(&s.remote));
    let up = |on| copy(&t, &l, Direction::Upload, path_str(&file), &s.dir, on);

    let skip = up(OnConflict::Skip).await;
    assert_eq!(
        (skip.state, skip.skipped, skip.files_done),
        (JobState::Done, 1, 0)
    );
    assert_eq!(s.cat("x.txt").await, b"theirs");

    // Ours is older: "only if newer" leaves theirs.
    std::fs::File::options()
        .write(true)
        .open(&file)
        .unwrap()
        .set_modified(std::time::UNIX_EPOCH + Duration::from_secs(1_000_000))
        .unwrap();
    let newer = up(OnConflict::Newer).await;
    assert_eq!(newer.skipped, 1);
    assert_eq!(s.cat("x.txt").await, b"theirs");

    let both = up(OnConflict::KeepBoth).await;
    assert_eq!(both.state, JobState::Done);
    assert_eq!(s.cat("x (1).txt").await, b"mine");
    assert_eq!(s.cat("x.txt").await, b"theirs");

    // Replacing keeps the permissions the server's file had.
    let replace = up(OnConflict::Replace).await;
    assert_eq!((replace.files_done, replace.skipped), (1, 0));
    assert_eq!(s.cat("x.txt").await, b"mine");
    assert_eq!(s.entry("x.txt").await.unwrap().mode, Some(0o751));

    // A folder that exists: skipped whole, or merged.
    let dir = local.path().join("d");
    std::fs::create_dir(&dir).unwrap();
    std::fs::write(dir.join("new.txt"), b"n").unwrap();
    s.sh("mkdir d && printf keep > d/old.txt").await;
    let skip_dir = copy(
        &t,
        &l,
        Direction::Upload,
        path_str(&dir),
        &s.dir,
        OnConflict::Skip,
    )
    .await;
    assert_eq!(skip_dir.skipped, 1);
    assert!(s.entry("d/new.txt").await.is_none());
    let merge = copy(
        &t,
        &l,
        Direction::Upload,
        path_str(&dir),
        &s.dir,
        OnConflict::Replace,
    )
    .await;
    assert_eq!(merge.files_done, 1);
    assert_eq!(s.cat("d/new.txt").await, b"n");
    assert_eq!(s.cat("d/old.txt").await, b"keep");
    s.done().await;
}

/// Replacing through a link writes the file it leads to: the link stays.
/// Replacing someone else's file writes over it where it is: it stays
/// theirs (`/srv/shared/notes.txt`, `otp`'s, that `demo` may write).
#[tokio::test]
async fn an_upload_leaves_links_and_owners_as_they_were() {
    let fx = servers!();
    let s = server(&fx, OPENSSH, "owners").await;
    let local = tempfile::tempdir().unwrap();
    let file = local.path().join("notes.txt");
    std::fs::write(&file, b"ours now").unwrap();
    s.sh("mkdir real && printf old > real/notes.txt && ln -s real/notes.txt notes.txt")
        .await;
    let (t, l) = (transfers(), link(&s.remote));
    let up = copy(
        &t,
        &l,
        Direction::Upload,
        path_str(&file),
        &s.dir,
        OnConflict::Replace,
    )
    .await;
    assert_eq!((up.state, up.files_done), (JobState::Done, 1), "{up:?}");
    assert_eq!(s.entry("notes.txt").await.unwrap().kind, Kind::Link);
    assert_eq!(s.cat("real/notes.txt").await, b"ours now");

    let shared = "/srv/shared/notes.txt";
    let theirs = s.remote.owner_ids(shared).await.unwrap().unwrap();
    let up = copy(
        &t,
        &l,
        Direction::Upload,
        path_str(&file),
        "/srv/shared",
        OnConflict::Replace,
    )
    .await;
    assert_eq!((up.state, up.files_done), (JobState::Done, 1), "{up:?}");
    let out = s.ssh.exec(&format!("cat {shared}")).await.unwrap();
    assert_eq!(out.stdout, b"ours now");
    assert_eq!(s.remote.owner_ids(shared).await.unwrap(), Some(theirs));
    let left: Vec<String> = s
        .remote
        .list("/srv/shared")
        .await
        .unwrap()
        .into_iter()
        .map(|e| e.name)
        .collect();
    assert_eq!(left, ["notes.txt"], "no part left behind");
    s.done().await;
}

/// What the app asks a server (os-release, tmux) keeps to a short answer,
/// whatever the server sends.
#[tokio::test]
async fn a_short_command_keeps_its_answer_short() {
    let fx = servers!();
    let s = server(&fx, OPENSSH, "short").await;
    let out = s.ssh.exec_short("head -c 1000000 /dev/zero").await.unwrap();
    assert_eq!(out.stdout.len(), openward_ssh::client::EXEC_OUTPUT);
    let out = s.ssh.exec_short("echo hola").await.unwrap();
    assert_eq!((out.text().as_str(), out.status), ("hola", Some(0)));
    s.done().await;
}

/// An upload finds the `.part` a previous one of the same file left and
/// goes on from it, rewriting the last [`RESUME_OVERLAP`] bytes. The test
/// leaves a marker in the part's first bytes: had it started over, the
/// marker would be gone. Someone else's `name.part` is neither used nor
/// deleted.
#[tokio::test]
async fn uploads_and_downloads_resume_from_the_part() {
    let fx = servers!();
    let s = server(&fx, OPENSSH, "resume").await;
    let local = tempfile::tempdir().unwrap();
    let len = (RESUME_OVERLAP + (8 << 20)) as usize;
    let data = pattern(len, 3);
    let file = local.path().join("big.bin");
    std::fs::write(&file, &data).unwrap();
    // A part of the right length but with zeros where the overlap does not
    // reach: only a resumed upload keeps them.
    let mut part = data[..len - (1 << 20)].to_vec();
    part[..1024].fill(0);
    let staged = local.path().join("stage");
    std::fs::create_dir(&staged).unwrap();
    let modified = openward_sftp::local::stat(&file).unwrap().unwrap().modified;
    let ours = part_path("big.bin", &path_str(&file), len as u64, modified);
    // A browser's download of a file with the same name.
    let theirs = format!("big.bin{PART}");
    std::fs::write(staged.join(&ours), &part).unwrap();
    std::fs::write(staged.join(&theirs), b"someone else's").unwrap();
    let (t, l) = (transfers(), link(&s.remote));
    for name in [&ours, &theirs] {
        let stage = copy(
            &t,
            &l,
            Direction::Upload,
            path_str(&staged.join(name)),
            &s.dir,
            OnConflict::Replace,
        )
        .await;
        assert_eq!(stage.state, JobState::Done);
    }

    let up = copy(
        &t,
        &l,
        Direction::Upload,
        path_str(&file),
        &s.dir,
        OnConflict::Replace,
    )
    .await;
    assert_eq!(up.state, JobState::Done, "{:?}", up.error);
    let got = s.cat("big.bin").await;
    assert_eq!(got.len(), len);
    assert_eq!(&got[..1024], &[0u8; 1024], "went on from the part");
    assert_eq!(&got[1024..], &data[1024..]);
    assert_eq!(s.parts("").await, std::slice::from_ref(&theirs));
    assert_eq!(s.cat(&theirs).await, b"someone else's");

    // Downloads go on from the local part's length exactly; a part of
    // another version of the file is left as it was.
    let back = tempfile::tempdir().unwrap();
    let remote = join(&s.dir, "big.bin");
    let modified = s.remote.stat(&remote).await.unwrap().unwrap().modified;
    let ours = part_path("big.bin", &remote, len as u64, modified);
    let old = part_path("big.bin", &remote, len as u64 - 1, modified);
    std::fs::write(back.path().join(&ours), vec![1u8; 4096]).unwrap();
    std::fs::write(back.path().join(&old), vec![2u8; 8192]).unwrap();
    std::fs::write(back.path().join(&theirs), b"someone else's").unwrap();
    let down = copy(
        &t,
        &l,
        Direction::Download,
        join(&s.dir, "big.bin"),
        path_str(back.path()),
        OnConflict::Replace,
    )
    .await;
    assert_eq!(down.state, JobState::Done, "{:?}", down.error);
    let mine = std::fs::read(back.path().join("big.bin")).unwrap();
    assert_eq!(&mine[..4096], &[1u8; 4096]);
    assert_eq!(&mine[4096..], &got[4096..]);
    assert!(!back.path().join(&ours).exists());
    assert_eq!(std::fs::read(back.path().join(&old)).unwrap(), [2u8; 8192]);
    assert_eq!(
        std::fs::read(back.path().join(&theirs)).unwrap(),
        b"someone else's"
    );
    s.done().await;
}

#[tokio::test]
async fn pause_resume_and_cancel() {
    let fx = servers!();
    let s = server(&fx, OPENSSH, "pause").await;
    let local = tempfile::tempdir().unwrap();
    let data = pattern(96 << 20, 9);
    let file = local.path().join("video.bin");
    std::fs::write(&file, &data).unwrap();
    let (t, l) = (transfers(), link(&s.remote));
    let request = || Request {
        direction: Direction::Upload,
        source: path_str(&file),
        dest_dir: s.dir.clone(),
        on_conflict: OnConflict::Replace,
    };
    let progress = |t: &Transfers, id| t.jobs().into_iter().find(|j| j.id == id).unwrap();

    let id = t.add(Arc::clone(&l), request());
    while progress(&t, id).done < 4 << 20 {
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    t.pause(id);
    assert_eq!(progress(&t, id).state, JobState::Paused);
    assert_eq!(t.active(), 1);
    let parts = s.parts("").await;
    assert_eq!(parts.len(), 1);
    let part = s.entry(&parts[0]).await.unwrap();
    assert!(part.size < data.len() as u64);
    assert!(s.entry("video.bin").await.is_none());
    t.resume(id);
    let done = t.wait(id).await.unwrap();
    assert_eq!(done.state, JobState::Done);
    assert_eq!(s.entry("video.bin").await.unwrap().size, data.len() as u64);
    t.clear_finished();
    assert!(t.jobs().is_empty());

    // Cancelled: the part goes, nothing takes the name.
    s.remote.remove(&join(&s.dir, "video.bin")).await.unwrap();
    let id = t.add(Arc::clone(&l), request());
    while progress(&t, id).done < 4 << 20 {
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    t.cancel(id);
    assert_eq!(progress(&t, id).state, JobState::Cancelled);
    for _ in 0..100 {
        if s.parts("").await.is_empty() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert!(s.parts("").await.is_empty());
    assert!(s.entry("video.bin").await.is_none());
    assert_eq!(t.active(), 0);
    s.done().await;
}

#[tokio::test]
async fn a_link_without_a_session_fails_and_resumes_later() {
    let fx = servers!();
    let s = server(&fx, OPENSSH, "relink").await;
    let local = tempfile::tempdir().unwrap();
    let file = local.path().join("a.txt");
    std::fs::write(&file, b"a").unwrap();
    let t = transfers();
    let l = Link::new("web-1");
    let id = t.add(
        Arc::clone(&l),
        Request {
            direction: Direction::Upload,
            source: path_str(&file),
            dest_dir: s.dir.clone(),
            on_conflict: OnConflict::Replace,
        },
    );
    let failed = t.wait(id).await.unwrap();
    assert_eq!(failed.state, JobState::Failed);
    assert_eq!(failed.error, Some(openward_sftp::Error::Lost));
    assert_eq!(failed.host, "web-1");
    // The connection comes back: the same job goes on.
    l.set(Some(Arc::clone(&s.remote)));
    t.resume(id);
    assert_eq!(t.wait(id).await.unwrap().state, JobState::Done);
    assert_eq!(s.cat("a.txt").await, b"a");
    s.done().await;
}

/// A folder of a few hundred small files, several at once, on every
/// server: up, again with each conflict choice, and back down.
#[tokio::test]
async fn many_small_files_both_ways_everywhere() {
    let fx = servers!();
    for port in ALL {
        let s = server(&fx, port, "many").await;
        let local = tempfile::tempdir().unwrap();
        let tree = local.path().join("tree");
        let files = small_files(&tree, 6, 300);
        let total: u64 = files.iter().map(|(_, data)| data.len() as u64).sum();
        let (t, l) = (transfers(), link(&s.remote));
        let up = |on| copy(&t, &l, Direction::Upload, path_str(&tree), &s.dir, on);

        let first = up(OnConflict::Replace).await;
        assert_eq!(
            first.state,
            JobState::Done,
            "port {port}: {:?}",
            first.error
        );
        assert_eq!(
            (first.files, first.files_done, first.skipped),
            (300, 300, 0)
        );
        assert_eq!((first.total, first.done), (total, total));
        assert_eq!(s.files_below("tree").await, 300);
        assert!(s.parts_below("tree").await.is_empty());

        // Again: every file is there, and each is left or replaced by the
        // choice; "keep both" goes to a folder of its own.
        for (on, done, skipped) in [
            (OnConflict::Newer, 0, 300),
            (OnConflict::Replace, 300, 0),
            (OnConflict::KeepBoth, 300, 0),
        ] {
            let again = up(on).await;
            assert_eq!(
                (again.state, again.files_done, again.skipped),
                (JobState::Done, done, skipped),
                "port {port}: {on:?} {:?}",
                again.error
            );
            assert_eq!(again.done, total);
        }
        assert_eq!(s.files_below("tree (1)").await, 300);
        assert!(s.parts_below("").await.is_empty());

        let back = tempfile::tempdir().unwrap();
        let down = |on| {
            copy(
                &t,
                &l,
                Direction::Download,
                join(&s.dir, "tree"),
                path_str(back.path()),
                on,
            )
        };
        let first = down(OnConflict::Replace).await;
        assert_eq!(
            first.state,
            JobState::Done,
            "port {port}: {:?}",
            first.error
        );
        assert_eq!((first.files_done, first.skipped), (300, 0));
        assert_eq!(first.done, total);
        same_files(&back.path().join("tree"), &files);
        let again = down(OnConflict::Newer).await;
        assert_eq!((again.files_done, again.skipped), (0, 300));
        assert!(local_parts(back.path()).is_empty());
        s.done().await;
    }
}

/// Names that differ only in case go one after the other: here, if this
/// machine takes them for one (a Mac does), the second is a conflict like
/// any other.
#[tokio::test]
async fn names_that_differ_in_case_keep_the_conflict_choice() {
    let fx = servers!();
    let s = server(&fx, OPENSSH, "case").await;
    s.sh("mkdir twins && printf upper > twins/Twin.txt && printf lower > twins/twin.txt")
        .await;
    let probe = tempfile::tempdir().unwrap();
    std::fs::write(probe.path().join("A"), b"").unwrap();
    let one_name = probe.path().join("a").exists();
    let (t, l) = (transfers(), link(&s.remote));
    let down = |dir: &Path, on| {
        copy(
            &t,
            &l,
            Direction::Download,
            join(&s.dir, "twins"),
            path_str(dir),
            on,
        )
    };

    let skip = tempfile::tempdir().unwrap();
    let job = down(skip.path(), OnConflict::Skip).await;
    assert_eq!(job.state, JobState::Done, "{:?}", job.error);
    let got = |dir: &Path, name| std::fs::read(dir.join("twins").join(name)).unwrap();
    if one_name {
        // `Twin` comes first (`T` before `t`): it stays.
        assert_eq!((job.files_done, job.skipped), (1, 1));
        assert_eq!(got(skip.path(), "twin.txt"), b"upper");
    } else {
        assert_eq!((job.files_done, job.skipped), (2, 0));
        assert_eq!(got(skip.path(), "twin.txt"), b"lower");
    }
    // Replacing, the second wins, as one after the other.
    let replace = tempfile::tempdir().unwrap();
    let job = down(replace.path(), OnConflict::Replace).await;
    assert_eq!((job.files_done, job.skipped), (2, 0));
    assert_eq!(got(replace.path(), "twin.txt"), b"lower");
    assert_eq!(
        got(replace.path(), "Twin.txt"),
        if one_name { b"lower" } else { b"upper" }
    );
    s.done().await;
}

/// A folder of many small files paused in the middle and resumed, and
/// cancelled in the middle both ways: every part under way goes, and the
/// counts stay right. Through a far server, to have a middle.
#[tokio::test]
async fn pause_and_cancel_in_the_middle_of_many_files() {
    let fx = servers!();
    let s = server(&fx, OPENSSH, "many-pause").await;
    let far = Far::new(OPENSSH, Duration::from_millis(5)).await;
    let (_ssh, remote) = far.remote(&fx, &Sent::default()).await;
    let local = tempfile::tempdir().unwrap();
    let tree = local.path().join("tree");
    let files = small_files(&tree, 6, 300);
    let (t, l) = (transfers(), link(&remote));
    let upload = |dest_dir: &str| Request {
        direction: Direction::Upload,
        source: path_str(&tree),
        dest_dir: dest_dir.to_owned(),
        on_conflict: OnConflict::Replace,
    };
    let settle = || tokio::time::sleep(Duration::from_millis(100));

    let id = t.add(Arc::clone(&l), upload(&s.dir));
    until(&t, id, 60).await;
    t.pause(id);
    let paused = view(&t, id);
    assert_eq!(paused.state, JobState::Paused);
    assert!(paused.files_done < 300);
    // What was on its way lands; then nothing moves. Whole files are those
    // counted, and perhaps some whose answer the pause did not wait for.
    settle().await;
    let (whole, parts) = (s.files_below("tree").await, s.parts_below("tree").await);
    let counted = paused.files_done as usize;
    assert!(
        (counted..=counted + FILES_AT_ONCE).contains(&whole),
        "{whole}"
    );
    assert!(parts.len() <= FILES_AT_ONCE, "{parts:?}");
    settle().await;
    assert_eq!(view(&t, id).files_done, paused.files_done);
    assert_eq!(s.files_below("tree").await, whole);
    t.resume(id);
    let done = t.wait(id).await.unwrap();
    assert_eq!(
        (done.state, done.files_done, done.skipped),
        (JobState::Done, 300, 0),
        "{:?}",
        done.error
    );
    assert_eq!(done.done, done.total);
    assert!(s.parts_below("tree").await.is_empty());
    let back = tempfile::tempdir().unwrap();
    let check = copy(
        &t,
        &link(&s.remote),
        Direction::Download,
        join(&s.dir, "tree"),
        path_str(back.path()),
        OnConflict::Replace,
    )
    .await;
    assert_eq!(check.files_done, 300);
    same_files(&back.path().join("tree"), &files);

    // Cancelled: every part under way goes, nothing more is counted.
    let again = join(&s.dir, "again");
    s.remote.mkdir(&again).await.unwrap();
    let id = t.add(Arc::clone(&l), upload(&again));
    until(&t, id, 60).await;
    t.cancel(id);
    assert_eq!(view(&t, id).state, JobState::Cancelled);
    let counted = view(&t, id).files_done;
    for _ in 0..100 {
        if s.parts_below("again").await.is_empty() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    settle().await;
    assert!(s.parts_below("again").await.is_empty());
    assert_eq!(view(&t, id).files_done, counted);
    let whole = s.files_below("again").await;
    let counted = counted as usize;
    assert!(
        (counted..=counted + FILES_AT_ONCE).contains(&whole),
        "{whole}"
    );

    // And down: the parts here go.
    let down = tempfile::tempdir().unwrap();
    let id = t.add(
        Arc::clone(&l),
        Request {
            direction: Direction::Download,
            source: join(&s.dir, "tree"),
            dest_dir: path_str(down.path()),
            on_conflict: OnConflict::Replace,
        },
    );
    until(&t, id, 60).await;
    t.cancel(id);
    let counted = view(&t, id).files_done;
    for _ in 0..100 {
        if local_parts(down.path()).is_empty() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    settle().await;
    assert!(local_parts(down.path()).is_empty());
    assert!(counted < 300);
    assert_eq!(view(&t, id).files_done, counted);
    assert_eq!(t.active(), 0);
    s.done().await;
}

/// The connection drops in the middle of a folder, up and then down: the
/// job fails, and once the connection is back it goes on, with every file
/// counted once.
#[tokio::test]
async fn a_folder_goes_on_after_the_connection_drops() {
    let fx = servers!();
    let s = server(&fx, OPENSSH, "many-drop").await;
    let far = Far::new(OPENSSH, Duration::from_millis(5)).await;
    let sent = Sent::default();
    let (_ssh, remote) = far.remote(&fx, &sent).await;
    let local = tempfile::tempdir().unwrap();
    let tree = local.path().join("tree");
    let files = small_files(&tree, 6, 300);
    let (t, l) = (transfers(), link(&remote));
    let back = tempfile::tempdir().unwrap();
    let requests = [
        Request {
            direction: Direction::Upload,
            source: path_str(&tree),
            dest_dir: s.dir.clone(),
            on_conflict: OnConflict::Replace,
        },
        Request {
            direction: Direction::Download,
            source: join(&s.dir, "tree"),
            dest_dir: path_str(back.path()),
            on_conflict: OnConflict::Replace,
        },
    ];
    let mut connections = Vec::new();
    for request in requests {
        let id = t.add(Arc::clone(&l), request);
        until(&t, id, 60).await;
        far.cut();
        let failed = t.wait(id).await.unwrap();
        assert_eq!(
            (failed.state, failed.error),
            (JobState::Failed, Some(openward_sftp::Error::Lost))
        );
        assert!(failed.files_done < 300);
        let (ssh, remote) = far.remote(&fx, &sent).await;
        connections.push(ssh);
        l.set(Some(remote));
        t.resume(id);
        let done = t.wait(id).await.unwrap();
        assert_eq!(
            (done.state, done.files_done, done.skipped),
            (JobState::Done, 300, 0),
            "{:?}",
            done.error
        );
        assert_eq!(done.done, done.total);
    }
    assert!(s.parts_below("tree").await.is_empty());
    assert_eq!(s.files_below("tree").await, 300);
    same_files(&back.path().join("tree"), &files);
    assert!(local_parts(back.path()).is_empty());
    s.done().await;
}

/// A part left in a folder the job made itself is found when the job goes
/// on: only the run that made a folder knows it holds nothing.
#[tokio::test]
async fn a_part_in_a_folder_the_job_made_resumes() {
    let fx = servers!();
    let s = server(&fx, OPENSSH, "made-resume").await;
    let local = tempfile::tempdir().unwrap();
    let tree = local.path().join("tree");
    small_files(&tree, 2, 20);
    let len = (RESUME_OVERLAP + (48 << 20)) as usize;
    let big = pattern(len, 5);
    std::fs::write(tree.join("d00/big.bin"), &big).unwrap();
    let (t, l) = (transfers(), link(&s.remote));
    let id = t.add(
        Arc::clone(&l),
        Request {
            direction: Direction::Upload,
            source: path_str(&tree),
            dest_dir: s.dir.clone(),
            on_conflict: OnConflict::Replace,
        },
    );
    while view(&t, id).done < RESUME_OVERLAP + (4 << 20) {
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    t.pause(id);
    tokio::time::sleep(Duration::from_millis(100)).await;
    let parts = s.parts("tree/d00").await;
    let part = parts.iter().find(|p| p.starts_with("big.bin")).unwrap();
    let rel = format!("tree/d00/{part}");
    assert!(s.entry(&rel).await.unwrap().size > RESUME_OVERLAP + 1024);
    // A marker the overlap does not reach: only a part that is gone on
    // from keeps it.
    s.sh(&format!(
        "dd if=/dev/zero of='{rel}' bs=1024 count=1 conv=notrunc 2>/dev/null"
    ))
    .await;
    t.resume(id);
    let done = t.wait(id).await.unwrap();
    assert_eq!(
        (done.state, done.files_done, done.skipped),
        (JobState::Done, 21, 0),
        "{:?}",
        done.error
    );
    let got = s.cat("tree/d00/big.bin").await;
    assert_eq!(got.len(), len);
    assert_eq!(&got[..1024], &[0u8; 1024], "went on from the part");
    assert_eq!(&got[1024..], &big[1024..]);
    assert!(s.parts_below("tree").await.is_empty());
    s.done().await;
}

/// DT-7, measured: a folder of many small files on a far server, up and
/// back down, with the requests each file costs. 500 files and 80 ms there
/// and back unless `OW_FILES` and `OW_RTT_MS` say otherwise. It takes
/// minutes, so it runs on its own:
/// `cargo test -p openward-sftp --test servers -- --ignored --nocapture`.
#[tokio::test]
#[ignore]
async fn measure_many_small_files_far_away() {
    let fx = servers!();
    let var = |name, default| {
        std::env::var(name)
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(default)
    };
    let (n, rtt) = (var("OW_FILES", 500), var("OW_RTT_MS", 80));
    let s = server(&fx, OPENSSH, "measure").await;
    let far = Far::new(OPENSSH, Duration::from_millis(rtt as u64 / 2)).await;
    let sent = Sent::default();
    let (_ssh, remote) = far.remote(&fx, &sent).await;
    let local = tempfile::tempdir().unwrap();
    let tree = local.path().join("tree");
    let files = small_files(&tree, 10, n);
    let (t, l) = (transfers(), link(&remote));

    sent.take();
    let started = Instant::now();
    let up = copy(
        &t,
        &l,
        Direction::Upload,
        path_str(&tree),
        &s.dir,
        OnConflict::Replace,
    )
    .await;
    let (up_time, up_sent) = (started.elapsed(), sent.take());
    assert_eq!(
        (up.state, up.files_done),
        (JobState::Done, n as u32),
        "{up:?}"
    );
    // Again, over what is there: each name is asked about first.
    let mut again = Vec::new();
    for on in [OnConflict::Newer, OnConflict::Replace] {
        let started = Instant::now();
        let job = copy(&t, &l, Direction::Upload, path_str(&tree), &s.dir, on).await;
        assert_eq!(job.state, JobState::Done, "{job:?}");
        again.push((on, started.elapsed(), sent.take()));
    }

    // What a download does first, alone: walk the folder.
    let started = Instant::now();
    let walked = remote.walk(&join(&s.dir, "tree")).await.unwrap();
    let (walk_time, walk_sent) = (started.elapsed(), sent.take());
    assert_eq!(
        walked.iter().filter(|(_, e)| e.kind == Kind::File).count(),
        n
    );

    let back = tempfile::tempdir().unwrap();
    let started = Instant::now();
    let down = copy(
        &t,
        &l,
        Direction::Download,
        join(&s.dir, "tree"),
        path_str(back.path()),
        OnConflict::Replace,
    )
    .await;
    let (down_time, down_sent) = (started.elapsed(), sent.take());
    assert_eq!(
        (down.state, down.files_done),
        (JobState::Done, n as u32),
        "{down:?}"
    );
    same_files(&back.path().join("tree"), &files);

    let mut folders: std::collections::BTreeSet<&str> = files
        .iter()
        .flat_map(|(rel, _)| rel.match_indices('/').map(|(k, _)| &rel[..k]))
        .collect();
    folders.insert("");
    println!(
        "DT-7: {n} files in {} folders, {rtt} ms there and back",
        folders.len()
    );
    println!(
        "  up:   {:.1} s, {}",
        up_time.as_secs_f64(),
        requests(&up_sent, n)
    );
    for (on, time, sent) in &again {
        println!(
            "  up again, {on:?}: {:.1} s, {}",
            time.as_secs_f64(),
            requests(sent, n)
        );
    }
    println!(
        "  walk: {:.1} s, {}",
        walk_time.as_secs_f64(),
        requests(&walk_sent, n)
    );
    println!(
        "  down: {:.1} s, {}",
        down_time.as_secs_f64(),
        requests(&down_sent, n)
    );
    s.done().await;
}
