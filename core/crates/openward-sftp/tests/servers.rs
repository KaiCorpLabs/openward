//! `openward-sftp` against the S2 test servers
//! (`spikes/s2-ssh/servers/up.sh`). Skipped when they are not running.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use openward_sftp::transfer::{PART, RESUME_OVERLAP};
use openward_sftp::{
    Direction, Entry, JobState, Kind, Link, OnConflict, Remote, Request, Transfers, join,
};
use openward_ssh::client::{self, Auth, Hop, Options, Session, Target};
use openward_ssh::known_hosts::{KnownHosts, Unknown};

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

async fn server(fx: &Path, port: u16, name: &str) -> Server {
    let opts = Options {
        user: "demo".into(),
        known_hosts: Arc::new(Mutex::new(KnownHosts::new(Unknown::Learn))),
        host_certificates: false,
        keepalive: None,
        agent_forward: None,
        on_untrusted: None,
    };
    let auth = Auth::Key {
        path: fx.join("id_ed25519"),
        passphrase: None,
    };
    let ssh = client::connect(&Target::new(HOST, port), Hop::Tcp, &auth, &opts)
        .await
        .unwrap();
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

    async fn done(self) {
        self.remote.remove(&self.dir).await.unwrap();
        assert!(self.remote.lstat(&self.dir).await.unwrap().is_none());
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
        assert!(s.entry(&format!("site/big.bin{PART}")).await.is_none());
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
        assert_eq!(
            mode_of(&got.join("deploy.sh")) & 0o100,
            0o100,
            "stays runnable"
        );
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

/// An upload finds the `.part` a previous one left and goes on from it,
/// rewriting the last [`RESUME_OVERLAP`] bytes. The test leaves a marker
/// in the part's first bytes: had it started over, the marker would be gone.
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
    std::fs::write(staged.join(format!("big.bin{PART}")), &part).unwrap();
    let (t, l) = (transfers(), link(&s.remote));
    let stage = copy(
        &t,
        &l,
        Direction::Upload,
        path_str(&staged.join(format!("big.bin{PART}"))),
        &s.dir,
        OnConflict::Replace,
    )
    .await;
    assert_eq!(stage.state, JobState::Done);

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
    assert!(s.entry(&format!("big.bin{PART}")).await.is_none());

    // Downloads go on from the local part's length exactly.
    let back = tempfile::tempdir().unwrap();
    std::fs::write(back.path().join(format!("big.bin{PART}")), vec![1u8; 4096]).unwrap();
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
    let part = s.entry(&format!("video.bin{PART}")).await.unwrap();
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
        if s.entry(&format!("video.bin{PART}")).await.is_none() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert!(s.entry(&format!("video.bin{PART}")).await.is_none());
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
