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
    /// Signals the program without waiting, as the child's own kill does.
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
        if std::env::var_os("LANG").is_none() && !cfg!(windows) {
            cmd.env("LANG", "en_US.UTF-8");
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
        let child = pair.slave.spawn_command(cmd)?;
        let killer = child.clone_killer();
        drop(pair.slave);
        let reader = pair.master.try_clone_reader()?;
        let writer = pair.master.take_writer()?;
        Ok((
            Self {
                master: Mutex::new(pair.master),
                writer: Mutex::new(writer),
                child: Arc::new(Mutex::new(child)),
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
    /// own, a kill if it is still there a moment later.
    pub fn kill(&self) {
        // Already gone and reaped: its pid may be someone else's now.
        if !matches!(lock(&self.child).try_wait(), Ok(None)) {
            return;
        }
        let _ = lock(&self.killer).kill();
        let child = Arc::clone(&self.child);
        let _ = std::thread::Builder::new()
            .name("openward-pty-kill".into())
            .spawn(move || {
                std::thread::sleep(GRACE);
                let mut child = lock(&child);
                if matches!(child.try_wait(), Ok(None)) {
                    let _ = child.kill();
                    let _ = child.wait();
                }
            });
    }
}

impl Drop for Pty {
    fn drop(&mut self) {
        self.kill();
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
}
