//! What a server runs, for its logo in the sidebar: told from the banner
//! it sends before anything else (`SSH-2.0-OpenSSH_9.2p1
//! Debian-2+deb12u3`), which runs nothing, or, when the host asks for it,
//! from `/etc/os-release` and `uname -s` (which is all there is on macOS).
//! A system chosen by hand stays as it is.

use std::time::Duration;

use openward_vault::proto::{System, SystemSource};

/// The command that reads the system, under `sh` whatever the login shell.
/// The kernel's name goes last, so that a distribution this does not know
/// is still told as Linux.
pub(crate) const OS_RELEASE: &str = "sh -c 'cat /etc/os-release 2>/dev/null; uname -s'";

/// How long reading it may take before it is left for another time.
pub(crate) const OS_RELEASE_WITHIN: Duration = Duration::from_secs(5);

/// Unknown: «?».
pub(crate) const UNKNOWN: &str = "?";

/// Linux, without knowing which distribution.
const LINUX: &str = "lnx";

/// From the server's banner; «?» when it does not say.
pub(crate) fn from_banner(banner: &str) -> System {
    let (code, name) = told_by_banner(banner).unwrap_or((UNKNOWN, String::new()));
    System {
        code: code.to_owned(),
        name,
        source: SystemSource::Banner,
        evidence: banner.to_owned(),
        extra: Default::default(),
    }
}

fn told_by_banner(banner: &str) -> Option<(&'static str, String)> {
    // `SSH-2.0-<software> <comment>`.
    let rest = banner
        .strip_prefix("SSH-2.0-")
        .or(banner.strip_prefix("SSH-1.99-"))?;
    let (software, comment) = rest.split_once(' ').unwrap_or((rest, ""));
    let lower = comment.to_ascii_lowercase();
    if software.starts_with("OpenSSH_for_Windows") {
        return Some(("win", "Windows".into()));
    }
    if software.starts_with("NetBSD") {
        return Some(("nbsd", "NetBSD".into()));
    }
    if lower.starts_with("raspbian") {
        return Some(("rpi", "Raspberry Pi OS".into()));
    }
    if lower.starts_with("debian") {
        // `+deb12u3`: Debian 12.
        let release = lower
            .split("+deb")
            .nth(1)
            .map(|r| {
                r.chars()
                    .take_while(char::is_ascii_digit)
                    .collect::<String>()
            })
            .filter(|r| !r.is_empty());
        return Some((
            "deb",
            release.map_or_else(|| "Debian".into(), |r| format!("Debian {r}")),
        ));
    }
    if lower.starts_with("ubuntu") {
        // Each LTS release keeps its OpenSSH.
        let release = match software {
            s if s.starts_with("OpenSSH_8.2") => Some("20.04"),
            s if s.starts_with("OpenSSH_8.9") => Some("22.04"),
            s if s.starts_with("OpenSSH_9.6") => Some("24.04"),
            _ => None,
        };
        return Some((
            "ubu",
            release.map_or_else(|| "Ubuntu".into(), |r| format!("Ubuntu {r}")),
        ));
    }
    if lower.starts_with("freebsd") {
        return Some(("bsd", "FreeBSD".into()));
    }
    None
}

/// From what [`OS_RELEASE`] printed; `None` when it says nothing useful.
pub(crate) fn from_os_release(text: &str) -> Option<System> {
    let value = |key: &str| {
        text.lines().find_map(|line| {
            let (k, v) = line.split_once('=')?;
            (k.trim() == key).then(|| v.trim().trim_matches(['"', '\'']).to_owned())
        })
    };
    // `uname -s`: the last line that is not `KEY=value`.
    let kernel = text
        .lines()
        .map(str::trim)
        .rfind(|line| !line.is_empty() && !line.contains('='))
        .unwrap_or_default();
    let (code, name, evidence) = match value("ID") {
        Some(id) => {
            let like = value("ID_LIKE").unwrap_or_default();
            let code = code_of(&id)
                .or_else(|| like.split_whitespace().find_map(family_of))
                .unwrap_or(if kernel == "Linux" { LINUX } else { UNKNOWN });
            let name = value("NAME").unwrap_or_default();
            let name = name.trim_end_matches(" GNU/Linux");
            let version = value("VERSION_ID").unwrap_or_default();
            let name = format!("{name} {version}").trim().to_owned();
            let evidence = value("PRETTY_NAME").unwrap_or_else(|| name.clone());
            (code, name, evidence)
        }
        // No os-release, as on macOS: the kernel.
        None => match kernel {
            "Darwin" => ("mac", "macOS".to_owned(), kernel.to_owned()),
            "FreeBSD" => ("bsd", kernel.to_owned(), kernel.to_owned()),
            "OpenBSD" => ("obsd", kernel.to_owned(), kernel.to_owned()),
            "NetBSD" => ("nbsd", kernel.to_owned(), kernel.to_owned()),
            "Linux" => (LINUX, "Linux".to_owned(), kernel.to_owned()),
            _ => return None,
        },
    };
    // What a server says goes into the vault: within reason.
    let short = |s: String, max: usize| s.chars().take(max).collect::<String>();
    Some(System {
        code: code.to_owned(),
        name: short(name, 64),
        source: SystemSource::OsRelease,
        evidence: short(evidence, 128),
        extra: Default::default(),
    })
}

/// The code for an os-release `ID`: each distribution with a logo of its
/// own has its code.
fn code_of(id: &str) -> Option<&'static str> {
    Some(match id {
        "debian" => "deb",
        "raspbian" => "rpi",
        "ubuntu" => "ubu",
        "linuxmint" => "mint",
        "pop" => "pop",
        "elementary" => "elem",
        "zorin" => "zor",
        "kali" => "kali",
        "fedora" => "fed",
        "rhel" | "ol" => "rhel",
        "centos" => "cent",
        "rocky" => "rock",
        "almalinux" => "alma",
        "alpine" => "alp",
        "arch" => "arch",
        "manjaro" | "manjaro-arm" => "manj",
        "endeavouros" => "endv",
        "opensuse"
        | "opensuse-leap"
        | "opensuse-tumbleweed"
        | "opensuse-microos"
        | "sles"
        | "sled" => "suse",
        "nixos" => "nix",
        "gentoo" => "gent",
        "void" => "void",
        "openwrt" => "owrt",
        "freebsd" => "bsd",
        "openbsd" => "obsd",
        "netbsd" => "nbsd",
        _ => return None,
    })
}

/// The family for one of an os-release's `ID_LIKE`, for a distribution
/// without a code of its own (Amazon Linux goes as Red Hat).
fn family_of(like: &str) -> Option<&'static str> {
    Some(match like {
        "debian" => "deb",
        "ubuntu" => "ubu",
        "fedora" => "fed",
        "rhel" | "centos" => "rhel",
        "arch" => "arch",
        "suse" | "opensuse" => "suse",
        "alpine" => "alp",
        "gentoo" => "gent",
        _ => return None,
    })
}

/// What to store after connecting, if it changed: never over a system
/// chosen by hand, and not over what os-release told when the banner says
/// nothing new (os-release is off now, or failed this time).
pub(crate) fn learned(stored: Option<&System>, mut told: System) -> Option<System> {
    if let Some(stored) = stored {
        // What a newer version wrote in it stays.
        told.extra = stored.extra.clone();
        if stored.source == SystemSource::Manual || *stored == told {
            return None;
        }
        if stored.source == SystemSource::OsRelease
            && told.source == SystemSource::Banner
            && (told.code == UNKNOWN || told.code == stored.code)
        {
            return None;
        }
    }
    Some(told)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn banner(text: &str) -> (String, String) {
        let s = from_banner(text);
        assert_eq!(s.source, SystemSource::Banner);
        assert_eq!(s.evidence, text);
        (s.code, s.name)
    }

    #[test]
    fn the_banner_tells_some_systems() {
        let cases = [
            (
                "SSH-2.0-OpenSSH_9.2p1 Debian-2+deb12u3",
                ("deb", "Debian 12"),
            ),
            (
                "SSH-2.0-OpenSSH_10.0p2 Debian-7+deb13u4",
                ("deb", "Debian 13"),
            ),
            ("SSH-2.0-OpenSSH_7.4p1 Debian-10", ("deb", "Debian")),
            (
                "SSH-2.0-OpenSSH_9.2p1 Raspbian-2+deb12u3",
                ("rpi", "Raspberry Pi OS"),
            ),
            (
                "SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.10",
                ("ubu", "Ubuntu 22.04"),
            ),
            (
                "SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.5",
                ("ubu", "Ubuntu 24.04"),
            ),
            ("SSH-2.0-OpenSSH_9.7p1 Ubuntu-7ubuntu4", ("ubu", "Ubuntu")),
            ("SSH-2.0-OpenSSH_9.7 FreeBSD-20240806", ("bsd", "FreeBSD")),
            (
                "SSH-2.0-NetBSD_Secure_Shell-20240801-hpn13v14-lpk",
                ("nbsd", "NetBSD"),
            ),
            ("SSH-2.0-OpenSSH_for_Windows_9.5", ("win", "Windows")),
        ];
        for (text, (code, name)) in cases {
            assert_eq!(banner(text), (code.to_owned(), name.to_owned()), "{text}");
        }
    }

    #[test]
    fn a_plain_banner_says_nothing() {
        for text in [
            "SSH-2.0-OpenSSH_9.8",
            "SSH-2.0-dropbear_2025.88",
            "SSH-2.0-ROSSSH",
            "SSH-2.0-Tailscale",
            "garbage",
            "",
        ] {
            assert_eq!(banner(text), ("?".to_owned(), String::new()), "{text}");
        }
    }

    #[test]
    fn os_release_tells_the_rest() {
        let fedora = "NAME=\"Fedora Linux\"\nVERSION_ID=40\nID=fedora\nPRETTY_NAME=\"Fedora Linux 40 (Server Edition)\"\n";
        let s = from_os_release(fedora).unwrap();
        assert_eq!(
            (s.code.as_str(), s.name.as_str(), s.evidence.as_str()),
            ("fed", "Fedora Linux 40", "Fedora Linux 40 (Server Edition)")
        );
        assert_eq!(s.source, SystemSource::OsRelease);
        // What a server says goes into the vault within reason.
        let long = format!(
            "ID=fedora\nNAME=\"{}\"\nPRETTY_NAME=\"{}\"\n",
            "F".repeat(500),
            "P".repeat(5000)
        );
        let s = from_os_release(&long).unwrap();
        assert_eq!(
            (s.name.chars().count(), s.evidence.chars().count()),
            (64, 128)
        );
        let debian = "PRETTY_NAME=\"Debian GNU/Linux 12 (bookworm)\"\nNAME=\"Debian GNU/Linux\"\nVERSION_ID=\"12\"\nID=debian\n";
        assert_eq!(from_os_release(debian).unwrap().name, "Debian 12");
        let alpine = "NAME=\"Alpine Linux\"\nID=alpine\nVERSION_ID=3.20.3\n";
        let s = from_os_release(alpine).unwrap();
        assert_eq!(
            (s.code.as_str(), s.name.as_str()),
            ("alp", "Alpine Linux 3.20.3")
        );
        // A distribution with a logo of its own goes by its own code.
        let mint =
            "NAME=\"Linux Mint\"\nID=linuxmint\nID_LIKE=\"ubuntu debian\"\nVERSION_ID=\"22\"\n";
        assert_eq!(from_os_release(mint).unwrap().code, "mint");
        let rocky = "NAME=\"Rocky Linux\"\nID=\"rocky\"\nID_LIKE=\"rhel centos fedora\"\nVERSION_ID=\"9.4\"\n";
        assert_eq!(from_os_release(rocky).unwrap().code, "rock");
        let suse = "NAME=\"openSUSE Leap\"\nID=\"opensuse-leap\"\nID_LIKE=\"suse opensuse\"\nVERSION_ID=\"15.6\"\n";
        let s = from_os_release(suse).unwrap();
        assert_eq!(
            (s.code.as_str(), s.name.as_str()),
            ("suse", "openSUSE Leap 15.6")
        );
        // One without, by what it is like.
        let amazon = "NAME=\"Amazon Linux\"\nID=\"amzn\"\nID_LIKE=\"centos rhel fedora\"\nVERSION_ID=\"2023\"\nLinux\n";
        assert_eq!(from_os_release(amazon).unwrap().code, "rhel");
        let nobara = "NAME=\"Nobara Linux\"\nID=nobara\nID_LIKE=\"rhel centos fedora\"\n";
        assert_eq!(from_os_release(nobara).unwrap().code, "rhel");
        // Neither: Linux, if the kernel says so.
        let clear = "NAME=\"Clear Linux OS\"\nID=clear-linux-os\nVERSION_ID=43000\nLinux\n";
        let s = from_os_release(clear).unwrap();
        assert_eq!(
            (s.code.as_str(), s.name.as_str()),
            ("lnx", "Clear Linux OS 43000")
        );
        let indiana = "NAME=\"OpenIndiana Hipster\"\nID=openindiana\nSunOS\n";
        assert_eq!(from_os_release(indiana).unwrap().code, "?");
        // No os-release: `uname -s`.
        let s = from_os_release("Darwin\n").unwrap();
        assert_eq!((s.code.as_str(), s.name.as_str()), ("mac", "macOS"));
        assert_eq!(from_os_release("FreeBSD").unwrap().code, "bsd");
        assert_eq!(from_os_release("OpenBSD").unwrap().code, "obsd");
        assert_eq!(from_os_release("NetBSD\n").unwrap().code, "nbsd");
        let s = from_os_release("Linux\n").unwrap();
        assert_eq!((s.code.as_str(), s.name.as_str()), ("lnx", "Linux"));
        assert_eq!(from_os_release("SunOS"), None);
        assert_eq!(from_os_release(""), None);
    }

    #[test]
    fn every_distribution_has_its_code() {
        let cases = [
            ("debian", "deb"),
            ("raspbian", "rpi"),
            ("ubuntu", "ubu"),
            ("linuxmint", "mint"),
            ("pop", "pop"),
            ("elementary", "elem"),
            ("zorin", "zor"),
            ("kali", "kali"),
            ("fedora", "fed"),
            ("rhel", "rhel"),
            ("ol", "rhel"),
            ("centos", "cent"),
            ("rocky", "rock"),
            ("almalinux", "alma"),
            ("alpine", "alp"),
            ("arch", "arch"),
            ("manjaro", "manj"),
            ("endeavouros", "endv"),
            ("opensuse-tumbleweed", "suse"),
            ("sles", "suse"),
            ("nixos", "nix"),
            ("gentoo", "gent"),
            ("void", "void"),
            ("openwrt", "owrt"),
            ("freebsd", "bsd"),
        ];
        for (id, code) in cases {
            let text = format!("NAME=x\nID={id}\nLinux\n");
            assert_eq!(from_os_release(&text).unwrap().code, code, "{id}");
            // Four letters at most: an older version shows it as text.
            assert!(code.len() <= 4, "{code}");
        }
    }

    #[test]
    fn what_is_stored_changes_only_for_something_new() {
        let deb = from_banner("SSH-2.0-OpenSSH_9.2p1 Debian-2+deb12u3");
        let plain = from_banner("SSH-2.0-OpenSSH_9.8");
        let fedora = from_os_release("NAME=Fedora\nID=fedora\nVERSION_ID=40").unwrap();
        let manual = System {
            code: "arch".into(),
            name: String::new(),
            source: SystemSource::Manual,
            evidence: String::new(),
            extra: Default::default(),
        };
        assert_eq!(learned(None, deb.clone()), Some(deb.clone()));
        assert_eq!(learned(Some(&deb), deb.clone()), None);
        assert_eq!(learned(Some(&manual), deb.clone()), None);
        // os-release told more than this banner does.
        assert_eq!(learned(Some(&fedora), plain.clone()), None);
        // A banner that tells another system: the server changed.
        assert_eq!(learned(Some(&fedora), deb.clone()), Some(deb.clone()));
        assert_eq!(learned(Some(&plain), fedora.clone()), Some(fedora));
    }
}
