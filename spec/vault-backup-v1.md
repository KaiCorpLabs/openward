# Vault backup v1 (D7)

Implemented 2026-11-12; [tracking #36](https://github.com/KaiCorpLabs/openward/issues/36).
This specifies data copies, not synchronization or release onboarding.

## Scope and authorization

A backup contains all current vault item heads (including stored private keys,
passwords and passphrases), IDs, local revision counters, original CBOR bodies
and encrypted-store private metadata. Unsupported item types/fields survive
without reinterpretation. It excludes external files referenced by path, device
settings, history, recents, session recordings and native keyring enrollments.
Store private keys in the vault before exporting if they must travel in the copy;
external certificates and hardware signers still require their own files/device.

Export requires an unlocked encrypted vault. JSON additionally requires a
separate explicit plaintext acknowledgement and independent verification of the
current master password, even if the session was unlocked with biometrics or kit.
JSON necessarily exposes saved secrets; only file bytes in Rust receive them.
The FFI returns counts, format, destination eligibility and a SHA-256 file digest,
never archive contents, saved credentials or private key text. Entered credentials
move into zeroizing Rust buffers; Dart strings cannot be promised a forensic wipe.

Restore requires an unlocked, **new empty encrypted destination vault**, including
an empty private-metadata record. It never overwrites or merges existing items.
Create the destination password and mandatory kit first. Source credentials open
the copy only; destination password, kit, account/device identity and vault key
remain unchanged. Data is re-encrypted and signed under that destination identity.
Stored item IDs and local revisions stay intact so internal references survive;
new signed snapshots start with empty revision parents and a new local HLC.
This does not clone a source device identity for future synchronization.

Preview authenticates/parses the whole copy but does not mutate the destination.
The user separately confirms restoration. Commit rereads/authenticates the file,
checks its digest against preview, rechecks destination emptiness/header/metadata,
and inserts all rows and metadata in one FULL-synchronous SQLite transaction.
Ciphertexts are roundtrip-verified and reread before commit. The in-memory index
changes only after commit. An invalid file, changed preview, stale lock epoch,
occupied destination or disk failure leaves destination data intact. Unknown items
are counted as unreadable and retained; they are never omitted silently.

## Encrypted `.owvault`: OWVA1

All integers are unsigned big endian. No filename/path participates in the format,
so a copy may be renamed or moved between operating systems.

| Field | Encoding |
|---|---|
| magic/version | ASCII `OWVA`, byte `01` |
| source header | u16 length, OWVH1 bytes; maximum 16 KiB |
| source recovery wrapper | u16 length, Recovery-purpose OWLU1 bytes; maximum 512 bytes |
| nonce | 24 fresh random bytes |
| payload | XChaCha20-Poly1305 ciphertext followed by its 16-byte tag |

The 32-byte encryption key is HKDF-Expand-SHA256 from the uniform random source
vault key as PRK, info exactly `openward vault backup v1\0`. AAD is the entire
prefix from magic through nonce inclusive. The authenticated cleartext is the
JSON snapshot below. There is one authenticated message for the whole copy,
protecting item removal, reordering, metadata, header/wrapper substitutions,
truncation and trailing bytes. A new random nonce is generated for every export.

Opening by password uses OWVH1's bounded Argon2id path; opening by kit uses the
Recovery-purpose wrapper. Both yield the same source vault key and then verify
the whole archive tag. Export verifies the current recovery wrapper using its
encrypted local kit cache before making a copy; older vaults missing that cache
must regenerate their kit first. No OS-specific native unlock record is exported.
Unknown archive/header versions and excessive KDF/length parameters fail closed.
Limits: cleartext at most 64 MiB, archive at most 64 MiB + 17 KiB. This is a bounded
in-memory format; it is not intended to carry multi-gigabyte session recordings.

A copy retains the password/kit valid when it was made. Later changes on the
source do not revoke old copies. Keep factors separately and protect old backups.

## Plaintext JSON snapshot

UTF-8, format `openward-vault`, version integer `1`. Top-level members are exactly
`format`, `version`, `private_metadata_hex`, `items`. A row has exactly `id`,
`revision`, `body_cbor_hex`, `body`. Duplicate fields/IDs, unknown container fields,
noncanonical UUID text, unsupported versions, oversized data, invalid hex or
nonpositive/out-of-range local revisions are rejected. At most 100,000 rows are
accepted, subject to the stricter 64 MiB whole-document limit. Revision integers
must be preserved exactly (1 through i64::MAX; do not round through JS Number).

- `body_cbor_hex`: lowercase hexadecimal of the original inner CBOR body. It is
  authoritative and preserves unknown byte strings, tags and other CBOR types.
  A body must be exactly one CBOR map with no trailing data.
- `body`: readable informational projection when this version understands and can render the
  body as JSON; null for opaque or unrenderable items. If present, its JSON representation must agree
  with the lossless body. Editing only the projection is rejected, not ignored.
  Consumers writing this format must encode their authoritative body consistently.
- `private_metadata_hex`: lowercase hex of the OWPM1 binary map documented in
  [vault-sqlite-v2](vault-sqlite-v2.md). Managed master keys/recovery seeds/native
  factors are not part of this logical metadata export.

Hex is encoding, **not encryption**. The readable projection includes saved
secret values. JSON has structural validation, not cryptographic authenticity;
an attacker able to rewrite a plaintext file can rewrite its data consistently.
Only import copies whose origin you trust. Neither representation is a SQLite
file, so importing never opens an attacker-supplied database or executes its SQL.
The public fixtures in `core/crates/openward-vault/tests/fixtures/vault-d7.*`
show the exact version1 encodings and are restored by Linux/macOS/Windows CI.

## File installation, failure and lock behavior

Files are bounded before reading; symlink/nonregular leaves and Unix hardlinks
are rejected. Export uses a create-new 0600 temporary file in the chosen parent,
flushes/syncs it, closes its writer for Windows, and installs without clobbering
any existing destination (including a symlink). Unix additionally syncs the
parent directory. Windows uses tempfile's same-volume replacement semantics.
A failed write removes the staging file through RAII; no final destination is
published before staging completes and the export's access epoch is rechecked.
Plaintext export staging is itself sensitive; secure erasure is not promised.

Import performs parsing and cryptographic preparation before taking the short
commit lease. A lock/unlock cycle invalidates the operation's epoch; a lock before
commit prevents installation. An operation already committing finishes under its
lease before lock proceeds. SQLite rollback keeps the destination empty on a
failed insert/metadata write. Export failure after final installation (for example
parent sync failure) can leave a complete destination; it does not claim that
an existing file has been replaced. Retry to a new filename after inspection.

## Reproducible recovery

1. In Settings → Security, create and save a `.owvault` copy. Keep its password or
   recovery kit separately. Preserve any external SSH files/certificates needed.
2. On another computer, start with a new empty data folder, enable encryption,
   and save/confirm that destination's new kit. Existing vaults are rejected by
   restore; do not delete or rename your working data to make room.
3. Select Restore backup, choose the copy, enter its source password or choose
   its recovery kit, and Check backup. JSON needs no source credential.
4. Verify item/secret/opaque counts and explicitly confirm. Check hosts, stored
   keys and fingerprints before connecting. Lock/reopen with the **destination**
   password/kit. The copy's original factors do not unlock this destination.
5. Keep the original copy until recovery has been checked. History, recents,
   recordings, device settings and external file paths are not reconstructed.

For an isolated recovery on the same computer, close OpenWard and launch its
executable with `OPENWARD_DATA` set to a new private folder. POSIX shells:
`OPENWARD_DATA=/path/to/new-private-folder /path/to/OpenWard`; PowerShell:
`$env:OPENWARD_DATA='C:\path\new-private-folder'; & 'C:\path\openward.exe'`.
Remove the override to return to the original profile. Do not run both profiles
against the same data folder. The committed portability test creates independent
destination identities and follows both factor paths plus JSON without touching
any real user data.

Validation includes current-password enforcement, consent, locked actions,
renamed copies, preview TOCTOU, whole-file corruption/truncation, future formats,
duplicated IDs, rollback, existing destination preservation, portable fixtures,
private-key identity preservation and the generated native FFI flow.
