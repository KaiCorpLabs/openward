//! SSH for OpenWard on `russh` (ADR-003): a generic transport (TCP,
//! ProxyCommand, or a `direct-tcpip` channel of another session, so jumps
//! and proxies compose), authentication, host trust decided in the core, and
//! forwarding. Validated against real servers in spike S2
//! (`spikes/s2-ssh/sshprobe`, run in CI).

pub mod client;
pub mod forward;
pub mod keyfile;
pub mod known_hosts;
pub mod proxy;
#[cfg(feature = "test-auth")]
pub mod totp;

/// The `russh` version these pieces are built on, for callers that need its
/// channel types.
pub use russh;
