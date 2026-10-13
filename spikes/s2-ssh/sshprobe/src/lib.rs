//! SSH client pieces of spike S2 on `russh`, shaped like the future
//! `core/crates/openward-ssh`: generic transport (TCP, ProxyCommand, jump
//! channel), authentication, host trust and forwarding. The `sshprobe`
//! binary runs them against real servers; the S1 render harness uses them
//! for its SSH terminal.

pub mod client;
pub mod forward;
pub mod known_hosts;
pub mod totp;

/// The `russh` version these pieces are built on, for callers that need its
/// channel types.
pub use russh;
