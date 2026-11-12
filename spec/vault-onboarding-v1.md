# Vault onboarding v1 (D8)

Production `OpenWard.open` requires onboarding before exposing legacy data.
The Rust access gate denies reads, mutations, connection actions and derived
local data while Flutter shows setup. Only password strength, prepared-kit
QR/PDF and setup controls are available. Cancelling setup stays on onboarding.
The debug-only opt-out and alternate-home constructors exist for isolated
legacy fixtures; release builds reject the opt-out.

## Password and recovery kit

Setup creates a strong master password and a random recovery kit. Confirmation
of two kit groups commits the verified D3 migration. Protected local data must
also open successfully before publishing an unlocked state. A failed migration
preserves the original; a post-install failure stays locked. No plaintext Home
is displayed as an error fallback. Existing encrypted vaults start locked.

## Explicit beta “Later”

“Later” is a separate OS-session factor, never a biometric fallback. A random
256-bit key is stored in the macOS data-protection keychain, Windows credential
locker or Linux Secret Service. The Windows credential locker follows OS
account policy, including any roaming; no hardware or non-exportability claim
is made for this mode. Linux requires explicit session-protection acknowledgement.
Unavailable, cancelled or missing OS storage fails before migration and leaves
onboarding closed. Both creation and a read-back proof precede installation.

The key wraps the normal OWVH1 hierarchy through Argon2id (64 MiB, one pass;
this input has 256 bits of entropy). It never crosses FFI or persists in the
profile. `local_device_only_v1` contains only an identifier:
`v1-<vault UUID hex>-<device UUID hex>-<random 128-bit hex>`. Validation binds
it to the header before any OS lookup. A malformed marker is still classified
as device-only and fails closed. The marker is installed in the staged encrypted
SQLite transaction, with `user_version = 4`. Older readers reject format4.
Secret writes and restores never lower that version, including after conversion.

A crash before installation may leave an orphan OS key; after installation the
key must be retained even if opening protected resources fails. No migration
operation removes a key that might be the only route to an installed vault.
Startup, manual and idle locks require an explicit OS-account unlock action;
there is no automatic silent unlock on startup. This mode has no portable
recovery kit. Losing the original keyring may make the vault unrecoverable.
A permanent reminder remains until password + kit confirmation succeeds.

## Completing deferred setup

The same setup UI creates the password and a new confirmed kit. A fresh OS-key
read independently authenticates the existing header. Header, kit wrapper,
local kit cache, account package and deletion of the device marker commit
atomically. Item ciphertext, account/device/vault keys and derived local-data
keys remain unchanged. Only after commit is the obsolete OS key removed; failed
orphan cleanup cannot reactivate it. A lock epoch change rejects stale results.
Backups, native enrollment, kit rotation and password changes require this
conversion first. Stored credentials and normal locking work in device mode.

## Evidence and limits

Rust tests exercise mandatory gating, failed keystores, restart/unlock,
conversion rejection, ciphertext preservation and independent recovery. Flutter
tests cover hidden semantics, failure retention and the correct unlock method;
the native FFI integration covers confirmed onboarding and recovery using a
private fixture home. These do not prove physical Touch ID/Hello or a week of
use. Follow the [beta guide](../docs/plan/prueba-v0.4.md).
