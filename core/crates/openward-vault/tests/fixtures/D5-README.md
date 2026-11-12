# Public recovery fixture

`vault-d5-recovery.sqlite` was generated on macOS for D5. It contains one
synthetic host (`recovery.invalid`), no real credentials, and deliberately public
keys. Never use it as a real vault.

- Password: `Public portability fixture only`.
- Recovery secret: 32 bytes of `0x2a`, rendered with `RecoveryKit::text()`.
- Source: `gen-d5-recovery.rs` (run as a temporary example of openward-vault).
- The account header, local recovery wrapper, locally sealed kit and D0-1
  account package are included. Nonces, salts, vault/device IDs and account keys
  are random; regeneration produces different bytes with the same test contract.

`recovery_portability.rs` recovers the same bytes on all three desktop CI
platforms, rewraps the password using only the kit, reopens the database and
checks the original data and account identity. The separate crypto fixture
`openward-crypto/tests/vectors/recovery-v1.json` pins a portable account-package
record with public test factors.
