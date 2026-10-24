//! One vault, two processes: the second is refused while the first has it,
//! and gets it once the first is gone, however it went (here, killed).

use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};

use openward_vault::{Error, Vault};

const HOLD: &str = "OPENWARD_TEST_HOLD_VAULT";

/// The other process: opens the vault, says so, and holds it until its
/// input closes. Only run by the test below.
#[test]
#[ignore = "run by a_second_process_waits_its_turn"]
fn hold_the_vault() {
    let Some(path) = std::env::var_os(HOLD) else {
        return;
    };
    let _vault = Vault::open(std::path::Path::new(&path)).unwrap();
    println!("held");
    let _ = std::io::stdin().lines().count();
}

#[test]
fn a_second_process_waits_its_turn() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    let mut other = Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "hold_the_vault",
            "--ignored",
            "--nocapture",
            "--test-threads=1",
        ])
        .env(HOLD, &path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut out = BufReader::new(other.stdout.take().unwrap());
    let mut line = String::new();
    while !line.contains("held") {
        line.clear();
        assert_ne!(
            out.read_line(&mut line).unwrap(),
            0,
            "the other process ended"
        );
    }
    assert!(matches!(Vault::open(&path), Err(Error::OpenElsewhere)));

    other.kill().unwrap();
    other.wait().unwrap();
    let v = Vault::open(&path).unwrap();
    drop(v);
}
