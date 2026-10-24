//! Local terminal for desktop: a shell on a pseudo-terminal (ConPTY on
//! Windows), with the environment a modern terminal advertises.
//!
//! The reader is handed to the caller, which runs it on its own thread and
//! feeds the terminal engine; writes, resizes and the child's lifetime go
//! through [`Pty`].

use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use portable_pty::{Child, ChildKiller, CommandBuilder, MasterPty, PtySize, native_pty_system};

/// How long a program that ignores the hang-up has before it is killed.
const GRACE: Duration = Duration::from_secs(1);
/// How many times, 50 ms apart, a killed program is looked for to reap it;
/// after that, [`Pty::exit_code`] does.
const REAP_TRIES: u32 = 100;

/// What to start and how.
#[derive(Clone, Debug, Default)]
pub struct Spawn {
    /// Program to run; `None` for the user's shell ([`default_shell`]).
    pub program: Option<String>,
    pub args: Vec<String>,
    /// Extra environment, on top of the inherited one and the terminal's.
    pub env: Vec<(String, String)>,
    /// Working directory; the home directory if `None`.
    pub cwd: Option<PathBuf>,
    pub cols: u16,
    pub rows: u16,
}

/// The user's login shell: `$SHELL` on Unix, PowerShell on Windows.
pub fn default_shell() -> String {
    if cfg!(windows) {
        "powershell.exe".to_owned()
    } else {
        std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_owned())
    }
}

pub struct Pty {
    // Mutexes: callers share a Pty across threads; these are only Send.
    master: Mutex<Box<dyn MasterPty + Send>>,
    writer: Mutex<Box<dyn Write + Send>>,
    child: Arc<Mutex<Box<dyn Child + Send + Sync>>>,
    /// Signals the program without waiting, as the child's own kill does
    /// (on Unix, its process groups are signalled instead).
    #[cfg_attr(unix, allow(dead_code))]
    killer: Mutex<Box<dyn ChildKiller + Send + Sync>>,
}

fn lock<T: ?Sized>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

fn size(cols: u16, rows: u16) -> PtySize {
    PtySize {
        rows: rows.max(1),
        cols: cols.max(1),
        pixel_width: 0,
        pixel_height: 0,
    }
}

impl Pty {
    /// Starts the program. Returns the PTY and its output stream; reading
    /// it blocks, and it ends (EOF or error) when the program exits.
    pub fn spawn(spawn: &Spawn) -> anyhow::Result<(Self, Box<dyn Read + Send>)> {
        let pair = native_pty_system().openpty(size(spawn.cols, spawn.rows))?;
        let program = spawn.program.clone().unwrap_or_else(default_shell);
        let mut cmd = CommandBuilder::new(&program);
        if spawn.program.is_none() && !cfg!(windows) {
            cmd.arg("-l"); // a login shell, as terminal apps start it
        }
        cmd.args(&spawn.args);
        cmd.env("TERM", "xterm-256color");
        cmd.env("COLORTERM", "truecolor");
        cmd.env("TERM_PROGRAM", "OpenWard");
        cmd.env("TERM_PROGRAM_VERSION", env!("CARGO_PKG_VERSION"));
        // Apps started from Finder or a launcher often have no locale.
        if !cfg!(windows)
            && ["LANG", "LC_ALL", "LC_CTYPE"]
                .iter()
                .all(|v| std::env::var_os(v).is_none())
        {
            cmd.env("LANG", system_locale());
        }
        for (k, v) in &spawn.env {
            cmd.env(k, v);
        }
        match &spawn.cwd {
            Some(dir) => cmd.cwd(dir),
            None => {
                let home = std::env::var_os(if cfg!(windows) { "USERPROFILE" } else { "HOME" });
                if let Some(home) = home {
                    cmd.cwd(home);
                }
            }
        }
        let child = Arc::new(Mutex::new(pair.slave.spawn_command(cmd)?));
        let killer = lock(&child).clone_killer();
        drop(pair.slave);
        #[cfg(unix)]
        let reader: Box<dyn Read + Send> = Box::new(unix::Output::new(&*pair.master, &child)?);
        #[cfg(not(unix))]
        let reader = pair.master.try_clone_reader()?;
        let writer = pair.master.take_writer()?;
        Ok((
            Self {
                master: Mutex::new(pair.master),
                writer: Mutex::new(writer),
                child,
                killer: Mutex::new(killer),
            },
            reader,
        ))
    }

    pub fn write(&self, bytes: &[u8]) -> std::io::Result<()> {
        let mut w = lock(&self.writer);
        w.write_all(bytes)?;
        w.flush()
    }

    pub fn resize(&self, cols: u16, rows: u16) -> anyhow::Result<()> {
        lock(&self.master).resize(size(cols, rows))?;
        Ok(())
    }

    /// The exit code once the program has finished.
    pub fn exit_code(&self) -> Option<u32> {
        lock(&self.child)
            .try_wait()
            .ok()
            .flatten()
            .map(|s| s.exit_code())
    }

    /// Ends the program without making the caller (the UI) wait: a hang-up
    /// now, as closing a terminal window sends, and from a thread of its
    /// own, a kill if it is still there a moment later. On Unix both go to
    /// the shell's process group and to the one in the foreground (`vim`,
    /// `top`, a pipeline), as the kernel does when a terminal goes away.
    pub fn kill(&self) {
        // Already gone and reaped: its pid may be someone else's now.
        if !matches!(lock(&self.child).try_wait(), Ok(None)) {
            return;
        }
        #[cfg(unix)]
        let groups = {
            let shell = lock(&self.child).process_id();
            let front = lock(&self.master).process_group_leader();
            let groups = unix::Groups::new(shell, front);
            groups.signal(nix::sys::signal::Signal::SIGHUP);
            groups
        };
        #[cfg(not(unix))]
        let _ = lock(&self.killer).kill();
        let child = Arc::clone(&self.child);
        let _ = std::thread::Builder::new()
            .name("openward-pty-kill".into())
            .spawn(move || {
                std::thread::sleep(GRACE);
                let running = || matches!(lock(&child).try_wait(), Ok(None));
                if !running() {
                    return;
                }
                #[cfg(unix)]
                groups.signal(nix::sys::signal::Signal::SIGKILL);
                #[cfg(not(unix))]
                let _ = lock(&child).kill();
                // Reaped without holding the lock while it waits: on macOS
                // a shell on its way out waits for its last output to be
                // read, and the reader needs the lock to see it go.
                for _ in 0..REAP_TRIES {
                    if !running() {
                        break;
                    }
                    std::thread::sleep(Duration::from_millis(50));
                }
            });
    }
}

impl Drop for Pty {
    fn drop(&mut self) {
        self.kill();
    }
}

/// `LANG` for a program started without one: the system's language with
/// UTF-8 (macOS keeps it in `AppleLocale`, not in the environment), when
/// that locale exists; else one that always does.
fn system_locale() -> String {
    static LOCALE: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    LOCALE
        .get_or_init(|| {
            if cfg!(target_os = "macos") {
                let asked = std::process::Command::new("/usr/bin/defaults")
                    .args(["read", "-g", "AppleLocale"])
                    .output()
                    .ok()
                    .filter(|o| o.status.success())
                    .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned());
                // `es_ES@rg=eszzzz`: the region settings go.
                let name = asked
                    .as_deref()
                    .and_then(|l| l.split('@').next())
                    .map(|l| format!("{l}.UTF-8"));
                match name {
                    Some(n) if std::path::Path::new("/usr/share/locale").join(&n).is_dir() => n,
                    _ => "en_US.UTF-8".to_owned(),
                }
            } else {
                // In every glibc since 2.35 and in musl.
                "C.UTF-8".to_owned()
            }
        })
        .clone()
}

#[cfg(unix)]
mod unix {
    use std::io::{self, Read};
    use std::os::fd::{AsFd, BorrowedFd};
    use std::sync::{Arc, Mutex};

    use nix::poll::{PollFd, PollFlags, PollTimeout, poll};
    use nix::sys::signal::{Signal, killpg};
    use nix::unistd::Pid;
    use portable_pty::{Child, MasterPty};

    use super::lock;

    /// How often a quiet terminal checks that its shell is still there.
    const CHECK_MS: u16 = 250;

    /// The terminal's output. It ends when the program has exited, even if
    /// something it left behind (`nohup job &`) still holds the terminal
    /// and no end of file would ever come.
    pub(super) struct Output {
        file: std::fs::File,
        child: Arc<Mutex<Box<dyn Child + Send + Sync>>>,
    }

    impl Output {
        pub(super) fn new(
            master: &dyn MasterPty,
            child: &Arc<Mutex<Box<dyn Child + Send + Sync>>>,
        ) -> io::Result<Self> {
            let fd = master
                .as_raw_fd()
                .ok_or_else(|| io::Error::other("no descriptor for the terminal"))?;
            // SAFETY: `master` owns `fd` and outlives this borrow, which
            // only lasts for the `dup` that gives us a descriptor of our own.
            #[allow(unsafe_code)]
            let borrowed = unsafe { BorrowedFd::borrow_raw(fd) };
            let own = borrowed.try_clone_to_owned()?;
            Ok(Self {
                file: std::fs::File::from(own),
                child: Arc::clone(child),
            })
        }
    }

    impl Read for Output {
        fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
            loop {
                let mut fds = [PollFd::new(self.file.as_fd(), PollFlags::POLLIN)];
                match poll(&mut fds, PollTimeout::from(CHECK_MS)) {
                    // Output, or the terminal hung up: the read says which.
                    Ok(n) if n > 0 => return self.file.read(buf),
                    Ok(_) => {
                        if !matches!(lock(&self.child).try_wait(), Ok(None)) {
                            return Ok(0);
                        }
                    }
                    Err(nix::errno::Errno::EINTR) => {}
                    Err(e) => return Err(e.into()),
                }
            }
        }
    }

    /// The process groups to signal: the shell's (it leads its session)
    /// and the foreground one, when it is another.
    pub(super) struct Groups(Vec<Pid>);

    impl Groups {
        pub(super) fn new(shell: Option<u32>, front: Option<i32>) -> Self {
            let mut groups: Vec<Pid> = shell
                .and_then(|p| i32::try_from(p).ok())
                .into_iter()
                .chain(front)
                .filter(|&g| g > 1)
                .map(Pid::from_raw)
                .collect();
            groups.dedup();
            Self(groups)
        }

        pub(super) fn signal(&self, signal: Signal) {
            for &g in &self.0 {
                let _ = killpg(g, signal);
            }
        }
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

    fn read_until(reader: &mut dyn Read, needle: &str) -> String {
        let deadline = Instant::now() + Duration::from_secs(5);
        let mut seen = Vec::new();
        let mut buf = [0u8; 4096];
        while !String::from_utf8_lossy(&seen).contains(needle) {
            assert!(
                Instant::now() < deadline,
                "{}",
                String::from_utf8_lossy(&seen)
            );
            match reader.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => seen.extend_from_slice(&buf[..n]),
            }
        }
        String::from_utf8_lossy(&seen).into_owned()
    }

    #[test]
    fn runs_a_program_with_terminal_environment_and_size() {
        let (pty, mut reader) = Pty::spawn(&Spawn {
            program: Some("/bin/sh".into()),
            cols: 100,
            rows: 30,
            ..Default::default()
        })
        .unwrap();
        pty.write(b"echo T=$TERM P=$TERM_PROGRAM; stty size\n")
            .unwrap();
        let out = read_until(&mut *reader, "30 100");
        assert!(out.contains("T=xterm-256color P=OpenWard"), "{out}");
        pty.resize(120, 40).unwrap();
        pty.write(b"stty size; exit 3\n").unwrap();
        read_until(&mut *reader, "40 120");
        // Drain to EOF, as the reader thread does: the program has exited.
        let mut rest = Vec::new();
        let _ = reader.read_to_end(&mut rest);
        let deadline = Instant::now() + Duration::from_secs(5);
        while pty.exit_code().is_none() {
            assert!(Instant::now() < deadline);
            std::thread::sleep(Duration::from_millis(20));
        }
        assert_eq!(pty.exit_code(), Some(3));
    }
}

#[cfg(all(test, unix))]
mod kill_tests {
    use super::*;
    use std::time::Instant;

    fn spawn(program: &str, args: &[&str]) -> Pty {
        Pty::spawn(&Spawn {
            program: Some(program.into()),
            args: args.iter().map(|a| (*a).to_owned()).collect(),
            cols: 80,
            rows: 24,
            ..Spawn::default()
        })
        .unwrap()
        .0
    }

    /// Closing returns at once; a program that ignores the hang-up still
    /// goes, a moment later.
    #[test]
    fn closing_does_not_wait_and_ignoring_the_hangup_does_not_help() {
        let pty = spawn("sh", &["-c", "trap '' HUP; sleep 30"]);
        // Time for the trap to be set.
        std::thread::sleep(Duration::from_millis(300));
        let started = Instant::now();
        pty.kill();
        assert!(
            started.elapsed() < Duration::from_millis(50),
            "{:?}",
            started.elapsed()
        );
        let deadline = Instant::now() + GRACE + Duration::from_secs(5);
        while pty.exit_code().is_none() && lock(&pty.child).try_wait().ok().flatten().is_none() {
            assert!(Instant::now() < deadline, "still running");
            std::thread::sleep(Duration::from_millis(50));
        }
    }

    /// Whether process `pid` is still there.
    fn alive(pid: i32) -> bool {
        nix::sys::signal::kill(nix::unistd::Pid::from_raw(pid), None).is_ok()
    }

    /// What `pid_file` says, once something has written it.
    fn pid_in(pid_file: &std::path::Path) -> i32 {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            if let Ok(text) = std::fs::read_to_string(pid_file)
                && let Ok(pid) = text.trim().parse()
            {
                return pid;
            }
            assert!(Instant::now() < deadline, "no pid");
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    /// A job left holding the terminal (`nohup`, a daemon that forgot to
    /// let go) does not keep it open once the shell is gone.
    #[test]
    fn the_output_ends_with_the_shell_not_with_its_jobs() {
        let dir = tempfile_dir();
        let pid_file = dir.join("job");
        // The shell waits for the job to be started: it may not see the
        // hang-up coming before it has ignored it.
        let script = format!(
            "(trap '' HUP; sh -c 'echo $$ > {f}; exec sleep 20') & \
             while [ ! -s {f} ]; do sleep 0.05; done; exit 4",
            f = pid_file.display()
        );
        let (pty, mut reader) = Pty::spawn(&Spawn {
            program: Some("/bin/sh".into()),
            args: vec!["-c".into(), script],
            cols: 80,
            rows: 24,
            ..Spawn::default()
        })
        .unwrap();
        let job = pid_in(&pid_file);
        let started = Instant::now();
        let mut rest = Vec::new();
        let _ = reader.read_to_end(&mut rest);
        assert!(
            started.elapsed() < Duration::from_secs(3),
            "{:?}",
            started.elapsed()
        );
        // The end can come a moment before the shell is reaped.
        let deadline = Instant::now() + Duration::from_secs(5);
        while pty.exit_code().is_none() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(20));
        }
        assert_eq!(pty.exit_code(), Some(4));
        assert!(alive(job), "the job itself is left alone, as nohup wants");
        let _ = nix::sys::signal::kill(
            nix::unistd::Pid::from_raw(job),
            nix::sys::signal::Signal::SIGKILL,
        );
    }

    /// Closing reaches the program in the foreground too, not only the
    /// shell that started it.
    #[test]
    fn closing_hangs_up_on_the_foreground_program() {
        let dir = tempfile_dir();
        let pid_file = dir.join("front");
        let (pty, mut reader) = Pty::spawn(&Spawn {
            program: Some("/bin/sh".into()),
            args: vec!["-i".into()],
            cols: 80,
            rows: 24,
            ..Spawn::default()
        })
        .unwrap();
        pty.write(format!("sh -c 'echo $$ > {}; exec sleep 20'\n", pid_file.display()).as_bytes())
            .unwrap();
        let front = pid_in(&pid_file);
        // Read, as the app does: a shell on its way out waits for that.
        let drain = std::thread::spawn(move || {
            let mut rest = Vec::new();
            let _ = reader.read_to_end(&mut rest);
        });
        std::thread::sleep(Duration::from_millis(200));
        let started = Instant::now();
        pty.kill();
        while alive(front) {
            assert!(
                started.elapsed() < Duration::from_secs(5),
                "the program is still running"
            );
            std::thread::sleep(Duration::from_millis(50));
        }
        // The hang-up did it, not the kill a moment later.
        assert!(started.elapsed() < GRACE, "{:?}", started.elapsed());
        drain.join().unwrap();
    }

    fn tempfile_dir() -> std::path::PathBuf {
        static NEXT: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
        let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("openward-pty-{}-{n}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn a_locale_that_exists() {
        let l = system_locale();
        assert!(l.ends_with(".UTF-8"), "{l}");
        #[cfg(target_os = "macos")]
        assert!(std::path::Path::new("/usr/share/locale").join(&l).is_dir());
    }
}
