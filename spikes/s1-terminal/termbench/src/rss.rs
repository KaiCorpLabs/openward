//! Peak resident memory of this process.

/// Peak RSS in bytes since process start, if the platform reports it.
#[cfg(unix)]
pub fn peak_bytes() -> Option<u64> {
    let mut usage: libc::rusage = unsafe { std::mem::zeroed() };
    // SAFETY: getrusage only writes into the struct we pass.
    if unsafe { libc::getrusage(libc::RUSAGE_SELF, &mut usage) } != 0 {
        return None;
    }
    let max = usage.ru_maxrss as u64;
    // macOS reports bytes, Linux and the BSDs kilobytes.
    Some(if cfg!(target_os = "macos") {
        max
    } else {
        max * 1024
    })
}

#[cfg(not(unix))]
pub fn peak_bytes() -> Option<u64> {
    None
}
