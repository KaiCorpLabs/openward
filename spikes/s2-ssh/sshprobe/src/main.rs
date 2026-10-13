//! sshprobe — spike S2 (docs/spikes/S2-ssh.md): `russh` against real SSH
//! servers. Start them first with `spikes/s2-ssh/servers/up.sh`.

mod bench;
mod matrix;

use std::path::PathBuf;
use std::process::ExitCode;

const USAGE: &str = "\
sshprobe — russh against real SSH servers (spike S2)

USAGE:
  sshprobe matrix [--json] [--only NAME] [--fixtures DIR]
  sshprobe bench [--json] [--port P] [--fixtures DIR]   (default port 22100)

  --fixtures  test material from servers/up.sh (default: $S2_FIXTURES, or
              the user cache: ~/Library/Caches/openward/s2-fixtures)
";

fn default_fixtures() -> PathBuf {
    if let Some(dir) = std::env::var_os("S2_FIXTURES") {
        return dir.into();
    }
    let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
    if cfg!(target_os = "macos") {
        home.join("Library/Caches/openward/s2-fixtures")
    } else {
        std::env::var_os("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".cache"))
            .join("openward/s2-fixtures")
    }
}

#[tokio::main]
async fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut json = false;
    let mut only = None;
    let mut port = 22100u16;
    let mut fixtures = default_fixtures();
    let mut it = args.iter().skip(1);
    while let Some(a) = it.next() {
        match a.as_str() {
            "--json" => json = true,
            "--only" => only = it.next().cloned(),
            "--port" => port = it.next().and_then(|p| p.parse().ok()).unwrap_or(port),
            "--fixtures" => fixtures = it.next().map(PathBuf::from).unwrap_or(fixtures),
            other => {
                eprintln!("unknown option {other}\n\n{USAGE}");
                return ExitCode::from(2);
            }
        }
    }
    let result = match args.first().map(String::as_str) {
        Some("matrix") => match matrix::Fixtures::new(fixtures) {
            Ok(fx) => matrix::run(&fx, json, only.as_deref()).await,
            Err(e) => Err(e),
        },
        Some("bench") => match matrix::Fixtures::new(fixtures) {
            Ok(fx) => bench::run(&fx, port, json).await,
            Err(e) => Err(e),
        },
        _ => {
            eprint!("{USAGE}");
            return ExitCode::from(2);
        }
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e:#}");
            ExitCode::FAILURE
        }
    }
}
