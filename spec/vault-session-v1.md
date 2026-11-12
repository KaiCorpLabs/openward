# Local vault session v1 (D4)

D4 activates the D3 encrypted format from Settings → Security. An existing
plaintext vault remains explicitly labelled as such until setup succeeds. This
is an opt-in development path, not the completed v0.4 onboarding contract:
mandatory onboarding / “Later”, complete recovery/export and derived-data
protection remain D5–D8. Updating the binary never silently migrates user data.

## Authority and lifetime

`VaultSession` owns one process-locked SQLite vault and an epoch access gate.
Encrypted files open without keys or an item index. Password authentication runs
Argon2id on a Rust worker, authenticates private metadata, and loads the index
before opening access. Wrong credentials retain the file and process lock.
Locking revokes access, invalidates pending results, drops keys and the item
index, clears device defaults and cancels pending connection questions. Keys
and KDF buffers use `Zeroizing`. Dropping the index is not a forensic guarantee
that all previously allocated application strings have been overwritten.

Terminal/SFTP handles retain their owning gate. Cross-instance connection and
transfer calls reject foreign handles before touching a connection or queue.
Short FFI frame/metadata reads and input enqueues hold a read lease; lock takes
the write lease. Blocking native, file and network work keeps an epoch ticket
and rejects results after revocation. Native prompts hold neither the vault
mutex nor a read lease. An old authentication completion cannot reopen a newer
lock epoch. Initial and subsequent security events are serialized so an old
unlocked snapshot cannot follow a newer locked notification.

Established SSH/PTY/SFTP sessions, transfers and tunnels continue. Their live
Rust state is an explicit exception to “no plaintext while locked”: terminating
connections is not the lock operation. UI terminal frame, selection, search and
input APIs return empty/denied results while locked; trusted network output
continues. Flutter hides the entire navigator, including dialogs, from painting,
focus, input and semantics; it drops cached terminal pictures/text and refreshes
vault views after unlock. Home is not mounted on an initial locked startup.

The Rust timer checks monotonic inactivity every second. Only keyboard/pointer
activity reported by the app resets it, not network output. Default: 900 seconds;
0 disables idle locking, maximum 86400. `vault.security.json` holds only the
bounded timeout, written by private temporary-file replacement. A same-user
malicious process is outside this protection boundary.

Manual locking: Settings → Security or ⌘L / Ctrl+Alt+L. Native runners cover the
old surface immediately on suspend/session-lock signals, then request Rust
locking; they uncover it only after Flutter paints the privacy screen. Ordinary
focus loss is not a lock event: native authentication itself can change focus.
macOS observes NSWorkspace sleep/session changes and screen-lock notification;
Windows observes power and WTS session changes; Linux observes login1 sleep and
GNOME/Cinnamon/freedesktop ScreenSaver signals. Delivery depends on desktop
services and OS scheduling; no claim is made that a sleeping process executes
before the OS freezes it. Manual/idle locking remains available everywhere.

## Setup and alternate factors

Setup accepts 12–128 Unicode characters and zxcvbn score ≥3, displays strength,
requires the repeated password and presents a fresh 256-bit recovery kit. The
user must save it and confirm groups 3 and 12 after the full kit is hidden.
No clipboard copy of the kit is offered. Closing/cancelling setup drops its
pending Rust secrets. The kit wrapper is serialized, authenticated and inserted
inside the staged migration transaction before the atomic installation point.
There is no interval with a newly encrypted vault but no recovery wrapper.

An **OWLU1** record is exactly 174 bytes: `OWLU` + version 1, purpose byte,
32-byte context digest, random 24-byte nonce, 112-byte XChaCha20-Poly1305
ciphertext/tag. The plaintext is the 64-byte account seed and 32-byte device
seed. Header reconstruction verifies the account/device certificate and vault
key. Purpose 1 is native unlock, bound to the complete current header; purpose 2
is local recovery, bound to the stable vault/device/account/certificate/generation
and unaffected by a password-only rewrap. Purpose substitution is rejected.

`meta.local_native_v1` contains the 101-byte native identifier and OWLU1 record.
The identifier is `v1-<vault UUID hex>-<device UUID hex>-<random 128-bit hex>`;
it is checked against the current header before any OS read or deletion.
`meta.local_recovery_v1` contains the purpose-2 OWLU1 record. Both are bounded
before allocation. No clear factor key or password is stored in SQLite.

The kit text is `OWRK1`, sixteen groups of four uppercase hex digits, and an
8-hex-digit domain-separated SHA-256 checksum. Parsing is ASCII/bounded, accepts
case/whitespace and rejects checksum errors. The kit can open this vault copy
without the password. **This local wrapper is not a remote account package**:
D5 must still implement the password+kit HKDF account package, rotation,
password changes, QR/PDF and independent export/recovery. Derived keys never
enter Dart. Entered passwords and deliberately displayed kit text do enter
Flutter; fields/controllers are cleared, but immutable Dart strings cannot be
reliably overwritten (the existing D6 memory-copy limitation).

## Native protection (off by default)

- **macOS:** a random 32-byte factor in the Data Protection Keychain, not
  synchronized, AccessibleWhenUnlockedThisDeviceOnly + biometryCurrentSet.
  Enrollment must read the protected item successfully before committing its
  wrapper. There is no silent fallback to ordinary Keychain protection.
- **Windows:** a dedicated Windows Hello KeyCredential performs an RSA-2048
  PKCS#1/SHA-256 signature of a fixed local-only domain and identifier. The
  deterministic signature is a zeroizing, domain-separated SHA-256 KDF input
  for the local wrapper. Neither this signature nor its key is used for remote
  authentication. This uses an actual protected operation, not a consent boolean
  followed by an unprotected key read. Unpackaged Windows applications share the
  OS-user boundary; this does not isolate against malware running as that user.
- **Linux:** Secret Service with encrypted D-Bus session, no shell command or
  plaintext file fallback. The UI explicitly requires acknowledgement that an
  unlocked OS session may release the factor without another authentication.
  It is not labelled biometrics. Missing keyring/service leaves password unlock.

New OS keys are removed if enrollment cannot commit. Disabling first removes
the vault wrapper, then deletes the OS item, so an OS deletion error cannot leave
native unlock enabled. Missing/cancelled/unavailable factors preserve password
and kit access. A crash can leave an unreferenced OS item; it cannot enable a
factor without its authenticated wrapper. Unreferenced-item cleanup is future
maintenance, not an automatic scan/delete of the user's Keychain.

Pinned additions: security-framework 3.7.0, windows 0.62.2, secret-service
6.0.0-rc.1 (zbus 6; 5.2.0 brought three unmaintained dependencies and was rejected),
zxcvbn 3.1.1. No advisory exceptions were added. The distributed license inventory
is regenerated for all targets.

Native API contracts: [Apple biometryCurrentSet](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset),
[Windows KeyCredential.RequestSignAsync](https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.keycredential.requestsignasync),
[Secret Service API](https://specifications.freedesktop.org/secret-service-spec/latest/),
[WTS session notifications](https://learn.microsoft.com/en-us/windows/win32/termserv/wm-wtssession-change),
[login1 sleep signals](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html).

## Evidence and remaining gates

Local checks: complete Rust/Flutter suites and focused concurrency/install-failure
regressions, strict clippy/analyze, dependency
policy and macOS Debug build. New tests cover password retry/process locking,
idle deadlines, stale epochs/native cancellation, Linux acknowledgement,
mandatory kit setup, factor bounds/tampering, recovery/native roundtrips and
locked deletion rejection, notification ordering and pre/post-install failures. A real `/bin/cat` PTY test proves that FFI input is
rejected and content is redacted during lock while background output and the
same session survive. Widget tests cover hidden semantics/state preservation,
password error, native cancellation and suspend. Desktop CI is a separate gate
before merge; mocks and compilation do not prove hardware authentication.

Ad-hoc probe on 2026-11-12 (`tool/probe-macos-vault.swift`):
`biometryAvailable=false policyError=-4` (SystemCancel),
`secureEnclaveAvailable=true`, `ephemeralPrivateKeyExportable=false`,
`touchIdAuthentication=notPerformed`. It created only an ephemeral key and read
no existing Keychain item. Reproduce with `swiftc -module-cache-path /tmp/ow-swift
 tool/probe-macos-vault.swift -o /tmp/ow-vault-probe`, `codesign --sign -
 /tmp/ow-vault-probe`, then run it. This does not validate protected Keychain
readability in the shipped bundle or physical Touch ID/Hello. Those remain
manual gates before a Developer ID decision. No certificate was purchased.

Issue #33 stays open for its original mockup review (no source available in this
workspace), physical native authentication and the roadmap's separate SSH
Secure Enclave signing feature. This probe is not that SSH feature. D5–D8,
Windows ACL/DACL work and external cryptographic review retain their existing
gates; D4 does not make history/recent/log files encrypted.
