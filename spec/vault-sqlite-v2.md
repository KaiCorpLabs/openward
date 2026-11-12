# Vault SQLite format 2

D3 implements this local Rust format. D4 adds opt-in setup, locked startup,
password/native unlock and a mandatory minimal local recovery kit; see
[vault-session-v1](vault-session-v1.md). No automatic conversion runs on update.
Key seeds and decrypted cryptographic buffers stay in Rust.

## Records

`PRAGMA user_version=2` is the compatibility gate. The released format-1 reader
rejects it with `NewerFormat(2)` before loading any item. This number differs
from the item envelope version: format 1 contains envelope v0, format 2 v1.

The STRICT `meta(key TEXT PRIMARY KEY, value BLOB NOT NULL)` and
`items(vault_id BLOB, item_id BLOB PRIMARY KEY, head_rev INTEGER, envelope BLOB)`
tables keep their column names. Required columns remain NOT NULL.

- `vault_id` and `device_id`: public 16-byte UUIDs.
- `crypto_header_v1`: local OWVH1 header, at most 16 KiB; see [keys-v1](keys-v1.md).
- `private_metadata_v1`: envelope v1 under a separate metadata key. Its item UUID
  is zero; the key separation prevents substitution with an actual zero-UUID item.
- Items contain only authenticated envelope v1 bytes, with vault/item/generation
  checked against the expected slot. Only the admitted local device writes in D3.
  Local reads authenticate AEAD; migration verifies the device signatures before
  installation, as S4 requires. Remote ingress/certificate authorization is v0.5.

The metadata key is HKDF-SHA256 Expand from the uniform random vault key used as
PRK, with info `openward private metadata v1`, output 32 bytes. The encrypted
metadata packet is `OWPM` + byte 1 + u32 entry count, followed by entries in UTF-8
lexical name order: u32 name length, name, u32 value length, value. Integers are
big endian. The packet is at most 64 MiB, with at most 65,536 entries and 4,096
bytes per name. No duplicate/trailing entries are accepted. Every old metadata
entry except the public UUIDs is preserved here, even if its name collides with
a new internal key.

Item plaintext is S4 canonical CBOR `{hlc, base, body, unset, clocks}`. `body` is
the original inner CBOR **byte string**, including unknown types/fields. A D3
single-writer snapshot has `base=hlc` and empty `unset`/`clocks`. Local updates
advance the hybrid clock beyond every loaded head, and name the prior head by
its envelope revision hash. D3 stores current heads, not a synchronization log.
`head_rev` retains the local integer optimistic-write counter; it is not the
cryptographic revision identifier. Deletion removes the head. Generation 1 is
created randomly; the hierarchy API supports explicit subsequent generations.

## Install and recovery

`Vault::migrate_encrypted` requires a closed format-1 vault and a privately
controlled parent. It takes the same canonical-path process lock as opening the
vault, refuses symlink/hardlink files and sidecars, and treats filenames literally
(SQLite URI interpretation is disabled). Unix owner/mode ancestry is checked;
Windows DACL and Unix extended-ACL validation remain separate platform work.

The source is held in an exclusive SQLite snapshot. Unknown schema objects,
columns, malformed/foreign IDs, negative counters, oversized values or unsupported
outer envelopes abort conversion. Unknown **inner** bodies are copied opaquely.
No unreadable row is silently omitted. The destination is a create-new 0600
temporary file in the same parent, populated in one transaction with ciphertext
only. Every item is decrypted/signature-verified, reread and compared with the
source, along with metadata, row count and SQLite integrity.

After verification, the staged file is synced, the source WAL is checkpointed
with TRUNCATE, journal mode becomes DELETE, and SQLite is closed. Validated managed
sidecars are removed. Atomic replacement is the commit point; no plaintext
`.bak`/`VACUUM INTO` copy is created. The original inode is checked again before
replacement. A Unix parent-directory fsync follows. Windows uses tempfile's
same-volume atomic replacement; it has no portable directory-fsync equivalent.

Before replacement an error leaves the original logically readable (checkpointing
may change its physical bytes). After replacement, reopen/sync errors are reported
as `MigrationInstalled`, so callers reopen the encrypted file instead of retrying
as plaintext. Abrupt exits can leave an encrypted staging file; retry is safe.
The process lock coordinates OpenWard instances; same-user tools deliberately
ignoring it are outside this coordination contract.

Success leaves no plaintext in the managed database, freelist, WAL, journal or
new staging/backup files. This is a logical-file guarantee, not secure erasure of
SSD blocks, filesystem snapshots or pre-existing external backups. Historical
backups are not deleted implicitly. Locking consumes the unlocked Vault and drops
its index and key owners; LockedVault contains neither. D6 still owns the broader
audit of typed secret copies and derived data outside the vault.

## Evidence

Tests cover vaults written by tags 0.3.0/0.3.1, an actual frozen old reader,
reopen/update/lock, wrong passwords, tampering/slot substitution, opaque bodies,
private metadata, oversized inputs, aliases, writer contention, injected errors
and destructorless child-process exit at four install phases. Separate child
processes leave committed WAL and PERSIST journals; tests verify recovery and
scan every sibling file for a known plaintext marker after success.

Local release measurement (2026-11-12): **10,000 items, 44 ms** for decryption and
index loading, excluding password KDF. Run the ignored `ten_thousand` test in
release mode to measure another machine. Argon2 calibration is described in
[keys-v1](keys-v1.md). External cryptographic review remains required before Cloud.
