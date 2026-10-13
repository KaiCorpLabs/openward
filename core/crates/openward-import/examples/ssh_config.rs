//! What an import of `~/.ssh/config` would bring in, without writing
//! anything: `cargo run -p openward-import --example ssh_config [-- -v] [path]`.
//! Without `-v` it prints counts only, no host names.

use std::collections::BTreeMap;
use std::path::PathBuf;

use openward_import::ssh_config::{Paths, SshConfig, Warning, import};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let verbose = args.iter().any(|a| a == "-v");
    let paths = Paths::from_env().expect("no HOME");
    let file = args
        .iter()
        .find(|a| *a != "-v")
        .map(PathBuf::from)
        .unwrap_or_else(|| paths.user_config());

    let imported = import(&SshConfig::load(&file, &paths));
    println!("{}: {} hosts", file.display(), imported.hosts.len());
    let mut kinds: BTreeMap<String, usize> = BTreeMap::new();
    for w in &imported.warnings {
        let kind = match w {
            Warning::Unsupported { keyword, .. } => format!("unsupported {keyword}"),
            Warning::Match { .. } => "Match block skipped".into(),
            Warning::BadValue { keyword, .. } => format!("bad value for {keyword}"),
            Warning::Stricter { .. } => "StrictHostKeyChecking no → accept-new".into(),
            Warning::IncludeTooDeep { .. } => "Include too deep".into(),
            Warning::Unreadable { .. } => "unreadable file".into(),
            Warning::JumpLossy { .. } => "jump kept as a bare address".into(),
        };
        *kinds.entry(kind).or_default() += 1;
    }
    for (kind, n) in kinds {
        println!("  {n:>3} × {kind}");
    }
    if verbose {
        for (_, host) in &imported.hosts {
            println!("{} → {} {:?}", host.label, host.address, host.settings);
        }
        for w in &imported.warnings {
            println!("{w:?}");
        }
    }
}
