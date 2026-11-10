//! Mosh on desktop, with the programs of the mosh project itself (GPL) run
//! apart, never linked: SSH starts `mosh-server` on the server, which says
//! `MOSH CONNECT <port> <key>`, and the installed `mosh-client` carries the
//! session over UDP in the terminal's PTY, with the key in `MOSH_KEY`
//! (ADR-009, revised for desktop in P1 of docs/plan/community.md).
//!
//! When it cannot (no `mosh-client` here, no `mosh-server` there, no UDP
//! getting through), the session goes on over SSH, in tmux.

use std::time::Duration;

/// How long the server has to start and say where to connect.
pub(crate) const SERVER_START: Duration = Duration::from_secs(15);

/// How long `mosh-client` has to hear from the server before the session
/// goes over SSH instead. It says so on the screen when nothing came.
pub(crate) const UDP_WAIT: Duration = Duration::from_secs(20);

/// What `mosh-client` writes when no packet came back.
pub(crate) const NOTHING_RECEIVED: &str = "Nothing received from server on UDP port";

/// A server left with nobody (the laptop never woke up) ends after a week
/// without word from its client.
const NETWORK_TIMEOUT_SECS: u32 = 7 * 24 * 3600;

/// The command that starts the server: `program` (`mosh-server` unless
/// the host says where it is), in UTF-8, which it needs, whichever of the
/// two usual locales the server has. `bind_ssh`: listen only on the
/// address the SSH connection came to (no jumps: that is where the client
/// will send its packets).
pub(crate) fn server_command(program: &str, bind_ssh: bool) -> String {
    let program = shell_word(program);
    let bind = if bind_ssh { " -s" } else { "" };
    let start = |locale: &str| {
        format!(
            "MOSH_SERVER_NETWORK_TMOUT={NETWORK_TIMEOUT_SECS} {program} new{bind} -c 256 -l LANG={locale}"
        )
    };
    format!("{} 2>&1 || {} 2>&1", start("C.UTF-8"), start("en_US.UTF-8"))
}

/// A word the shell takes as it is: quoted unless it is plain.
fn shell_word(word: &str) -> String {
    let plain = !word.is_empty()
        && word
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "/._-~+".contains(c));
    if plain {
        word.to_owned()
    } else {
        format!("'{}'", word.replace('\'', r"'\''"))
    }
}

/// `MOSH CONNECT <port> <key>`, from what the server wrote.
pub(crate) fn connect_line(output: &str) -> Option<(u16, String)> {
    output.lines().find_map(|line| {
        let mut words = line.split_whitespace();
        match (words.next(), words.next(), words.next(), words.next()) {
            (Some("MOSH"), Some("CONNECT"), Some(port), Some(key)) => {
                let port = port.parse().ok()?;
                let ok = key.len() >= 16
                    && key
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || "+/=".contains(c));
                ok.then(|| (port, key.to_owned()))
            }
            _ => None,
        }
    })
}

/// Why the server did not start, from what it wrote and how it ended.
pub(crate) fn server_problem(output: &str, status: Option<u32>) -> crate::events::MoshFallback {
    use crate::events::MoshFallback;
    let text = output.to_lowercase();
    if status == Some(127) || text.contains("command not found") || text.contains("not found") {
        MoshFallback::NoServer
    } else {
        let said: Vec<&str> = output
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .collect();
        MoshFallback::Other(said.last().copied().unwrap_or("no answer").to_owned())
    }
}

/// Whether `window` (the last bytes seen, with room for a needle cut in
/// two) holds `needle`.
pub(crate) fn seen(window: &[u8], needle: &str) -> bool {
    window.windows(needle.len()).any(|w| w == needle.as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::events::MoshFallback;

    #[test]
    fn the_server_says_where_to_connect() {
        let out = "\r\nmosh-server (mosh 1.4.0) [build mosh 1.4.0]\r\nCopyright 2012 Keith Winstein\r\n\
                   \r\nMOSH CONNECT 60001 4NeCCgvZFe2RnPgrcU1PQw\r\n\r\n[mosh-server detached, pid = 4242]\r\n";
        assert_eq!(
            connect_line(out),
            Some((60001, "4NeCCgvZFe2RnPgrcU1PQw".to_owned()))
        );
        assert_eq!(connect_line("MOSH CONNECT x y"), None);
        assert_eq!(connect_line("MOSH CONNECT 60001 short"), None);
        assert_eq!(
            connect_line("MOSH CONNECT 60001 rm;-rf/ab;cdefghijklmn"),
            None
        );
    }

    #[test]
    fn the_command_quotes_what_it_must() {
        let c = server_command("mosh-server", true);
        assert!(c.starts_with(
            "MOSH_SERVER_NETWORK_TMOUT=604800 mosh-server new -s -c 256 -l LANG=C.UTF-8 2>&1 || "
        ));
        assert!(c.ends_with("LANG=en_US.UTF-8 2>&1"));
        assert!(!server_command("/opt/homebrew/bin/mosh-server", false).contains(" -s"));
        assert!(
            server_command("/Apps/My Mosh/mosh-server", false)
                .contains("'/Apps/My Mosh/mosh-server' new")
        );
        assert!(server_command("a'b", false).contains(r"'a'\''b' new"));
    }

    #[test]
    fn why_the_server_did_not_start() {
        assert_eq!(
            server_problem("sh: 1: mosh-server: not found", Some(127)),
            MoshFallback::NoServer
        );
        assert_eq!(
            server_problem(
                "mosh-server needs a UTF-8 native locale to run.\nUnfortunately, the locale environment variables currently specify\nthe character set \"ANSI_X3.4-1968\".",
                Some(1)
            ),
            MoshFallback::Other("the character set \"ANSI_X3.4-1968\".".into())
        );
    }

    #[test]
    fn a_needle_cut_in_two_is_seen() {
        let mut window = b"...mosh: Nothing received from se".to_vec();
        assert!(!seen(&window, NOTHING_RECEIVED));
        window.extend(b"rver on UDP port 60001. [To quit: Ctrl-^ .]");
        assert!(seen(&window, NOTHING_RECEIVED));
    }
}
