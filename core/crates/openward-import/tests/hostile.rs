//! What another program's files may hold, and what someone may hand over
//! as one: any bytes are read or refused, never a panic, a hang or memory
//! without end.

use std::path::Path;

use openward_import::ssh_config::{Paths, SshConfig};
use openward_import::{csv, detect, mobaxterm, putty, securecrt, tabby};
use proptest::prelude::*;

/// Text that looks a little like each format, so the parsers get past
/// their first checks: their own words, separators and arbitrary text.
fn shaped(words: &'static [&'static str]) -> impl Strategy<Value = String> {
    let piece = prop_oneof![
        proptest::sample::select(words).prop_map(str::to_owned),
        "[ -~]{0,12}",
        Just("\n".to_owned()),
        Just("\r\n".to_owned()),
        "[\\u{0}-\\u{ffff}]{0,4}",
    ];
    proptest::collection::vec(piece, 0..64).prop_map(|p| p.concat())
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    fn any_bytes_are_read_or_refused(bytes in proptest::collection::vec(any::<u8>(), 0..2048)) {
        let _ = putty::from_reg(&bytes);
        let _ = securecrt::from_xml(&bytes);
        let _ = mobaxterm::parse(&bytes);
        let _ = tabby::parse(&bytes);
        let _ = csv::parse(&bytes);
        let text = String::from_utf8_lossy(&bytes);
        let home = tempfile::tempdir().unwrap();
        let _ = SshConfig::parse(&text, &home.path().join("config"), &Paths::new(home.path()));
    }

    #[test]
    fn putty_like_text(text in shaped(&[
        "Windows Registry Editor Version 5.00", "REGEDIT4",
        "[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\a]",
        "\"HostName\"=\"", "\"PortNumber\"=dword:", "\"UserName\"=\"", "=", "\"",
    ])) {
        let _ = putty::from_reg(text.as_bytes());
    }

    #[test]
    fn securecrt_like_text(text in shaped(&[
        "<?xml version=\"1.0\"?>", "<VanDyke>", "<key name=\"Sessions\">", "<key name=\"",
        "<string name=\"Hostname\">", "<dword name=\"[SSH2] Port\">", "</string>", "</key>",
        "</dword>", "\">", "&amp;", "&#", "<!--", "-->",
    ])) {
        let _ = securecrt::from_xml(text.as_bytes());
    }

    #[test]
    fn mobaxterm_like_text(text in shaped(&[
        "[Bookmarks]", "[Bookmarks_1]", "SubRep=", "ImgNum=", "=#109#0%", "%", "#", "\\",
    ])) {
        let _ = mobaxterm::parse(text.as_bytes());
    }

    #[test]
    fn tabby_like_text(text in shaped(&[
        "profiles:", "version: 1", "  - type: ssh", "    options:", "      host: ", "      port: ",
        "groups:", "&a", "*a", "<<: *a", "- ", ": ", "{", "}", "[", "]", "!!str", "|", ">",
    ])) {
        let _ = tabby::parse(text.as_bytes());
    }

    #[test]
    fn csv_like_text(text in shaped(&[
        "label,address,user,port,group", ",", "\"", "\"\"", "22", "ssh://",
    ])) {
        let _ = csv::parse(text.as_bytes());
    }

    #[test]
    fn ssh_config_like_text(text in shaped(&[
        "Host ", "Match ", "HostName ", "Port ", "User ", "ProxyJump ", "IdentityFile ",
        "LocalForward ", "DynamicForward ", "exec ", "all", "*", "!", ",", "=", "\"", "%h", "${",
    ])) {
        let home = tempfile::tempdir().unwrap();
        let _ = SshConfig::parse(&text, &home.path().join("config"), &Paths::new(home.path()));
    }

    /// Recognizing a file reads it whole and tries each format in turn.
    #[test]
    fn any_file_is_recognized_or_not(bytes in proptest::collection::vec(any::<u8>(), 0..1024)) {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("export");
        std::fs::write(&file, &bytes).unwrap();
        let _ = detect::read(&file, None);
    }
}

/// Nested deeper than any configuration is: refused or read, without
/// running out of stack.
#[test]
fn deep_nesting_does_not_overflow() {
    let deep = 100_000;
    let yaml = format!(
        "profiles: {}{}\nversion: 1\n",
        "[".repeat(deep),
        "]".repeat(deep)
    );
    let _ = tabby::parse(yaml.as_bytes());
    let yaml = format!(
        "profiles:\n{}",
        (0..deep)
            .map(|i| format!("{}- a\n", " ".repeat(i % 2000)))
            .collect::<String>()
    );
    let _ = tabby::parse(yaml.as_bytes());

    let xml = format!(
        "<?xml version=\"1.0\"?><VanDyke>{}{}</VanDyke>",
        "<key name=\"Sessions\">".repeat(deep),
        "</key>".repeat(deep)
    );
    let _ = securecrt::from_xml(xml.as_bytes());

    let reg = format!(
        "Windows Registry Editor Version 5.00\n\n[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\{}]\n\"HostName\"=\"a\"\n",
        "x%5C".repeat(deep)
    );
    let _ = putty::from_reg(reg.as_bytes());
}

/// A folder that includes itself, and a file that includes itself, stop.
#[test]
fn includes_that_loop_stop() {
    let home = tempfile::tempdir().unwrap();
    let ssh = home.path().join(".ssh");
    std::fs::create_dir_all(&ssh).unwrap();
    let config = ssh.join("config");
    std::fs::write(
        &config,
        "Include config\nInclude ~/.ssh/*\nHost a\n  HostName a.example.com\n",
    )
    .unwrap();
    let parsed = SshConfig::load(&config, &Paths::new(home.path()));
    assert!(parsed.aliases().iter().any(|a| a == "a"));
    let _ = Path::new("unused");
}

/// A config of thousands of hosts (some keep one per server) imports in
/// moments: each alias looks only at the blocks that can be its own, and
/// still in file order, the first value winning.
#[test]
fn a_big_config_imports_in_time() {
    let home = tempfile::tempdir().unwrap();
    let paths = Paths::new(home.path());
    let mut text = String::from("Host web-*\n  User web\n  Port 2200\n");
    for i in 0..10_000u32 {
        text.push_str(&format!(
            "Host h{i} H{i}-alias\n  HostName 10.0.{}.{}\n  ProxyJump h{}\n",
            i / 250,
            i % 250,
            i.saturating_sub(1)
        ));
    }
    text.push_str("Host web-1\n  User other\n  HostName web-1.example.com\nHost *\n  User everyone\n  Port 22\n");
    let started = std::time::Instant::now();
    let config = SshConfig::parse(&text, &home.path().join("config"), &paths);
    let import = openward_import::ssh_config::import(&config);
    assert!(
        started.elapsed() < std::time::Duration::from_secs(10),
        "{:?}",
        started.elapsed()
    );
    assert_eq!(import.hosts.len(), 20_001);

    let web = config.resolve("web-1");
    assert_eq!(
        web.user.as_deref(),
        Some("web"),
        "the wildcard block came first"
    );
    assert_eq!(web.port, Some(2200));
    assert_eq!(web.hostname.as_deref(), Some("web-1.example.com"));
    let h = config.resolve("H7-ALIAS");
    assert_eq!(h.hostname.as_deref(), Some("10.0.0.7"));
    assert_eq!(h.user.as_deref(), Some("everyone"));
    assert_eq!(config.resolve("nowhere").port, Some(22));
}
