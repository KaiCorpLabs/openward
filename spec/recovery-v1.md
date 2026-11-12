# Recovery kit and credential changes, v1 (D5)

Implemented after the [local session boundary](vault-session-v1.md), according to
[ADR-004](../docs/adr/ADR-004-vault-y-jerarquia-de-claves.md) and D0-1. This is a
local desktop feature; no server or sync backend is contacted.

## User contract

- Setup requires a random 256-bit kit and re-entry of groups 3 and 12 before the
  staged encrypted database is installed. The D4 `OWRK1` text/checksum remains
  compatible. QR encodes the complete text, without a URL or device information.
- A bilingual single-page A4 PDF contains the same text and a vector QR with a
  quiet border. It can be printed using an ordinary PDF viewer. Rust writes a
  new private file atomically without replacing an existing file or symlink.
  The sheet warns that the kit must first be confirmed, that it opens a local
  vault copy without a password, and that a kit is not a backup of the data.
- Settings → Security changes the password after re-authenticating with the
  current password **or** the active kit. An already unlocked/biometric session
  alone is insufficient. A new password follows setup's 12–128 Unicode-character
  and zxcvbn score ≥3 policy; existing passwords still unlock normally.
- Password change preserves account/device/vault keys, generation, item bytes,
  and the kit. The native factor is removed in the same database transaction;
  the user can enable it again. OS cleanup happens after commit and can leave
  an unusable orphan if the OS refuses deletion.
- Kit regeneration requires the current password and confirmation of the new
  sheet. Until commit, cancellation, wrong proof or a storage error preserves
  the old kit. After commit, the old kit fails for the updated database/package.
  Password and native enrollment remain valid during a kit-only change.
- Cancellation, manual/idle/suspend lock drop pending password/kit state.
  Expensive derivation runs without an access lease; a short epoch-checked
  lease protects only the commit. A lock during preparation prevents its commit.
- Earlier D4 vaults have a recovery wrapper but no locally sealed kit/package.
  Authorizing a password change with their existing kit initializes D5 records.
  Alternatively, regenerate and confirm a kit using the current password first.
  There is no reset that silently erases a vault.

Revocation applies to the current database. Old offline copies, rollback images,
previously exported PDFs and remembered secrets cannot be remotely revoked.
An attacker who already extracted account/vault keys is not removed by rewrapping
credentials; re-encryption/key rotation is a different operation. Encrypted data
backup/import (`.owvault`) remains D7. Device approval remains a future sync flow.

## Portable account package: `OWRP`, version 1

Only this record is intended for a future server. It contains the account's two
32-byte seeds, **not** a local header, local password box/KEK, kit cache, device
seed, or raw vault key. The recipient reconstructs and verifies `AccountPublic`;
it can unwrap account-addressed HPKE vault keys and certify a fresh device.

All integers are big endian. Fields, in order:

| Field | Size |
|---|---:|
| `OWRP` + version `01` | 5 |
| Account-public length (`u16`) + canonical `OWAP` | 2 + bounded ≤2048 |
| Argon2id memory KiB + passes (`u32` each) | 8 |
| Independent random salt | 16 |
| Independent XChaCha nonce | 24 |
| Encrypted account seeds + Poly1305 tag | 64 + 16 |

The entire record is bounded at 2200 bytes, with exact ciphertext length and no
trailing bytes. `OWAP` validates its suite/key lengths and signing key. Argon2id
v19 uses `KdfParams`' resource and input limits before allocating memory (minimum
64 MiB, parallelism 1, output 32 bytes). Its salt is independent of the local KEK.

Let `P` be all fields before ciphertext:

```
password_key = Argon2id(password, package_salt, recorded_parameters)
PRK = HKDF-Extract-SHA256(salt=kit_secret, IKM=password_key)
package_key = HKDF-Expand-SHA256(PRK,
    info="openward remote account package v1\0" || P, L=32)
ciphertext = XChaCha20Poly1305(package_key, nonce,
    plaintext=account_seeds, AAD=P)
```

The kit has 256 uniformly random bits. Possession of the package and public
account identity alone provides no password-guess oracle without this factor.
A wrong password/kit, modified prefix/ciphertext, or mismatched reconstructed
account fails. If both factors are compromised, the package is decryptable.

## Local records and transaction boundary

SQLite `meta` stores:

| Key | Contents |
|---|---|
| `crypto_header_v1` | Existing local password header, never uploaded |
| `local_recovery_v1` | Existing `OWLU1` purpose 2, unlocks with kit alone |
| `local_recovery_secret_v1` | Local-only `OWKS1` kit cache |
| `remote_account_package_v1` | Portable `OWRP1` account package |
| `local_native_v1` | Optional existing native factor, removed on password change |

`OWKS1` is exactly 77 bytes: magic/version 5 + random nonce 24 + encrypted kit
32 + tag 16. Its key is HKDF-Expand-SHA256 using the random vault key as PRK and
`"openward local recovery cache v1"` as info. AAD is its 29-byte prefix followed
by SHA256 of `"openward local recovery cache identity v1\0"`, vault ID, device
ID, generation (`u32`), canonical account-public bytes. This separate domain
prevents reuse as item/private-metadata ciphertext. It allows password-only
changes to preserve the kit without retaining plaintext on disk. It is validated
against the active recovery wrapper before reuse and never leaves the device.

Setup creates and verifies all records inside the staged migration transaction.
Changes prepare and reopen the serialized wrappers/cache/package before a short
SQLite transaction commits all records together. The in-memory header is updated
only after commit. A prepared update is bound to the current header **and** recovery
record; stale and foreign updates fail. An oversized malformed recovery record
has no usable factor and is represented by a bounded invalid-state marker, so
password-authorized kit regeneration can repair it without allocating its value. Failure leaves the old header, kit,
package and native wrapper usable. Neither change rewrites encrypted items.
Reads bound SQL value length before allocation (cache 77, package 2200, recovery
512 bytes). Damaged optional records do not remove independent password access.

## Secret handling and verification

Rust owns password/kit staging, Argon2/HKDF buffers and account/device/vault keys
with zeroizing storage. Only entered passwords and intentionally displayed kit
text/QR cross Dart; derived and account/device/vault keys do not. Controllers and
prepared UI references are cleared on completion/disposal. Dart's immutable
strings, QR renderer internals, OS printing and user-chosen PDF copies cannot
promise forensic erasure. No automatic clipboard copy, network, analytics or
secret-valued errors/logging is introduced.

Coverage includes both factors, malformed/bounded records, authentication/tamper,
cache identity/password rewrap, stable public account-package fixture, independent
credential reauthorization, kit confirmation/cancellation, lock cancellation,
transaction rollback injection, stale/foreign updates, old-factor rejection,
D4 upgrade and ciphertext preservation. The **same encrypted database fixture
created on macOS** is recovered, rewrapped and reopened by the Linux, macOS and
Windows Rust jobs. Flutter tests cover proof, errors/retries and disposed widgets;
the generated-bridge integration test exercises setup, QR/PDF, rotation, both
password-change authorizations and old-factor rejection. The PDF is rendered and
its QR independently decoded against the complete extracted printable code.

## D7 backup integration

[Vault backup v1](vault-backup-v1.md) now specifies portable encrypted and JSON
copies. Restoration re-encrypts logical items under a new destination identity;
it preserves that destination's password/kit. Device-local history/recordings and
external key files are excluded. The original D4/D5/D6 scope above is historical.
