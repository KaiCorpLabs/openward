//! termbench — spike S1 harness (docs/spikes/S1-terminal.md).
//!
//! Measures the core side of the terminal pipeline for each candidate engine:
//! parsing throughput, damage-frame encoding, keystroke echo and memory. The
//! Flutter side (paint latency, IME, accessibility) is measured separately by
//! the render harness.

mod bench;
mod cast;
mod corpus;
mod rss;

use std::path::PathBuf;
use std::process::ExitCode;

use openward_term::{Size, TermEngine};

const USAGE: &str = "\
termbench — compare terminal engines (spike S1)

USAGE:
  termbench gen <dir> [--mb N] [--cols C] [--rows R]
  termbench run <file>... [--engine E] [--cols C] [--rows R] [--chunk B] [--frame-bytes B] [--json]
  termbench replay <file.cast>... [--engine E] [--chunk B] [--frame-bytes B] [--json]
  termbench echo [--engine E] [--cols C] [--rows R] [--iterations N] [--json]
  termbench mem [--engine E] [--tabs N] [--scrollback L] [--cols C] [--rows R] [--json]

ENGINES:
  alacritty (default), ghostty (needs --features ghostty), all

DEFAULTS:
  --mb 16  --cols 200  --rows 50  --chunk 4096  --frame-bytes 65536
  --iterations 20000  --tabs 10  --scrollback 40000
";

pub struct Opts {
    pub engines: Vec<String>,
    pub cols: u16,
    pub rows: u16,
    pub chunk: usize,
    pub frame_bytes: usize,
    pub mb: usize,
    pub iterations: usize,
    pub tabs: usize,
    pub scrollback: usize,
    pub json: bool,
    pub positional: Vec<String>,
}

fn parse(args: &[String]) -> Result<Opts, String> {
    let mut o = Opts {
        engines: vec!["alacritty".into()],
        cols: 200,
        rows: 50,
        chunk: 4096,
        frame_bytes: 65_536,
        mb: 16,
        iterations: 20_000,
        tabs: 10,
        scrollback: 40_000,
        json: false,
        positional: Vec::new(),
    };
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        let mut value = |name: &str| -> Result<String, String> {
            it.next()
                .cloned()
                .ok_or_else(|| format!("{name} needs a value"))
        };
        let num = |s: String, name: &str| -> Result<usize, String> {
            s.parse().map_err(|_| format!("{name}: not a number: {s}"))
        };
        match arg.as_str() {
            "--engine" => {
                let e = value("--engine")?;
                o.engines = if e == "all" {
                    ENGINES.iter().map(|s| s.to_string()).collect()
                } else {
                    vec![e]
                };
            }
            "--cols" => o.cols = num(value("--cols")?, "--cols")? as u16,
            "--rows" => o.rows = num(value("--rows")?, "--rows")? as u16,
            "--chunk" => o.chunk = num(value("--chunk")?, "--chunk")?.max(1),
            "--frame-bytes" => {
                o.frame_bytes = num(value("--frame-bytes")?, "--frame-bytes")?.max(1)
            }
            "--mb" => o.mb = num(value("--mb")?, "--mb")?.max(1),
            "--iterations" => o.iterations = num(value("--iterations")?, "--iterations")?.max(1),
            "--tabs" => o.tabs = num(value("--tabs")?, "--tabs")?.max(1),
            "--scrollback" => o.scrollback = num(value("--scrollback")?, "--scrollback")?,
            "--json" => o.json = true,
            flag if flag.starts_with("--") => return Err(format!("unknown option {flag}")),
            other => o.positional.push(other.to_owned()),
        }
    }
    Ok(o)
}

/// Engines compiled into this build.
#[cfg(not(feature = "ghostty"))]
pub const ENGINES: &[&str] = &["alacritty"];
#[cfg(feature = "ghostty")]
pub const ENGINES: &[&str] = &["alacritty", "ghostty"];

pub fn make_engine(
    name: &str,
    size: Size,
    scrollback: usize,
) -> Result<Box<dyn TermEngine>, String> {
    match name {
        "alacritty" => Ok(Box::new(openward_term::alacritty::AlacrittyEngine::new(
            size, scrollback,
        ))),
        #[cfg(feature = "ghostty")]
        "ghostty" => Ok(Box::new(ghostty_engine::GhosttyEngine::new(
            size, scrollback,
        ))),
        #[cfg(not(feature = "ghostty"))]
        "ghostty" => {
            Err("built without the ghostty engine: cargo build --release --features ghostty".into())
        }
        other => Err(format!("unknown engine {other}")),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some((cmd, rest)) = args.split_first() else {
        eprint!("{USAGE}");
        return ExitCode::from(2);
    };
    let opts = match parse(rest) {
        Ok(o) => o,
        Err(e) => {
            eprintln!("error: {e}\n\n{USAGE}");
            return ExitCode::from(2);
        }
    };
    let result = match cmd.as_str() {
        "gen" => match opts.positional.first() {
            Some(dir) => corpus::generate(&PathBuf::from(dir), &opts),
            None => Err("gen needs an output directory".into()),
        },
        "run" => bench::run_files(&opts),
        "replay" => bench::replay_casts(&opts),
        "echo" => bench::echo(&opts),
        "mem" => bench::mem(&opts),
        "-h" | "--help" | "help" => {
            print!("{USAGE}");
            Ok(())
        }
        other => Err(format!("unknown command {other}")),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}
