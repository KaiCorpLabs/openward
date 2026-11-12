# D6: vault secrets and protected local data v1

Implemented 2026-11-12. Tracking: [D6 / #35](https://github.com/KaiCorpLabs/openward/issues/35).
This extends [vault format2](vault-sqlite-v2.md), [keys-v1](keys-v1.md) and
[the session boundary](vault-session-v1.md); it does not implement D7 archives.

## Consent and private-key references

`Data::Secret` is a normal signed/encrypted v1 item, with revision ancestry,
`SecretKind` (PrivateKey, Password, Passphrase), label, binding and a zeroizing
UTF-8 value. Unknown fields survive updates. Neither its Debug implementation
nor the credentials FFI projection exposes values. Password/passphrase metadata
has a separate list/delete API; there is no secret-value getter in Dart.

Creation/import defaults to files. An explicit switch stores a private key in
the unlocked encrypted vault. File imports are read in Rust; pasted material
necessarily enters through Dart. References are canonical `vault:<item UUID>`
strings in existing identity-file settings, resolved in Rust before SSH signing.
Generated private material and decrypted stored values never return through FFI.
OpenSSH, PEM and PuTTY input use the existing bounded parsers; OpenSSH's own
optional passphrase remains an independent layer. Hardware keys remain file
references to their native signer. Files by path remain supported.

“Store in vault” atomically commits the encrypted key and direct host/group/
identity references, retaining implicit certificate paths. “Remove original” is
separately opt-in and happens only after commit, verification and an unchanged
source check. On failure it retains the source; it never falls back to writing
cleartext. Explicit private-key export writes a new private file without
clobbering an existing destination, with an on-screen warning.

Authentication prompts default to **not saving**. Only a correctly decrypted
key passphrase or a server-accepted SSH password can be remembered. Passwords
are bound to endpoint, port, user and the verified server-key fingerprint.
Keyboard-interactive saving is offered only for one hidden `Password:` question;
its binding additionally includes the complete name, instructions and question.
Other challenges, echoing questions, OTP, PIN and proxy login are ineligible.
Classification is deliberately narrow, not proof that a server's label is honest.
The server must accept the reusable factor before saving; a failed cached value is tried
only once and then the app asks again. Changing a host key/challenge does not
reuse the old value. Locking revokes prompt tickets and prevents late saving.

## Format3 barrier and migration

SQLite `user_version = 3` is committed with FULL synchronization **before**
auxiliary data is encrypted, or in the same transaction as the first Secret.
Format3 has format2's tables/header/envelopes. D3–D5 clients reject version3;
otherwise they could overwrite an encrypted local document with plaintext.
This app accepts format2 and format3; format2 is upgraded on app unlock. The
legacy migration still stages and verifies format2 before installation, then
D6 runs before the unlocked state is published. There is no downgrade path.

A new random key per recording is wrapped by a device-local key derived using
HKDF-Expand-SHA256 from the random vault key, with info
`openward protected local data v1\0 || vault_uuid16 || device_uuid16`.
Changing password or recovery kit does not change that vault key or invalidate
local data. Local data does not sync; the source vault header/identity and each
recording's wrapper must accompany a backup if that backup includes recordings.

Legacy history/recent documents, `.json.tmp` and `.json.bad` aliases, and session
metadata/recordings migrate idempotently with verified ciphertext staged in a
0600 temporary file and atomic replacement. Unix directory entries are synced
after installation, in particular before a new recording uses its key wrapper.
Verification/source file handles are closed before replacement for Windows.
Other platforms retain the file synchronization and replacement semantics used
by the vault installer. Source files are retained if sealing
or verification fails. Symlinks and Unix hardlinks are refused. Authentication,
missing-wrapper, bounds or I/O failures leave the app locked, preserving data;
retry/restore is explicit. Malformed JSON is preserved as encrypted `.bad`
quarantine. No reset or plaintext fallback is performed. Active legacy sessions
must close before enabling vault encryption; existing encrypted sessions can
continue recording while locked.

## OWLD1 documents and key wrappers

`OWLD || 01 || nonce24 || ciphertext || tag16`, XChaCha20-Poly1305. Nonces are
random per write; AAD is `openward local blob v1\0 || first29bytes || label`.
Plaintext and label limits are 16 MiB and 512 bytes; lengths/magic are checked
before decoding/decryption. History/recent labels are `history` and `recent`.
The filename is fixed by a closed enum, not supplied as an arbitrary path.
An opaque canonical recording UUID names its `<id>.key` wrapper: label is the
UUID string, plaintext is exactly 32 random bytes (77 bytes on disk). Recording
metadata `<id>.json` uses that recording key and the filename as label. Host,
user, label, address, command and output are absent from managed cleartext files.
Filenames, sizes, timestamps, public SQLite IDs and non-sensitive settings remain
observable. JSON documents are authenticated before parsing, never treated as
legacy after an authentication failure.

## OWLF1 streaming recordings

Cast/text gzip bytes are streamed into `OWLF || 01 || random_stream_id16`.
Each frame is `ciphertext_length_u32_be || OWLD1_blob`. The blob label is
`filename_utf8 || stream_header21 || sequence_u64_be`, starting at zero. A data
frame's plaintext is `00 || data` (at most 64 KiB); an authenticated terminal
frame is `01` with no payload. Filename, stream identity and ordering prevent
cross-stream/frame substitution. Reader allocation is bounded per frame, not by
the full recording size. Closed recordings require a terminal frame and reject
trailing data. Only explicitly open/crash-ended recordings tolerate an
incomplete final frame; a complete frame with a bad MAC is always rejected.
The complete available stream is authenticated before gzip/JSON parsing, since
those legacy parsers can tolerate parse errors. Migrated ciphertext is verified
before replacing the original; later unlocks authenticate metadata and defer
large recording validation to reading/search/export.

An active recorder retains only its recording key, not the vault/local master
key. Lock clears local-document keys and the visible log index. Existing
recorders can write ciphertext and finish without repopulating that index;
new recording, reading/search/export and deletion are gated while locked.
Session close drops its key. Delete/prune removes metadata, streams and wrapper.
Deleting live recordings is rejected by the existing session rules.

## Validation and limits

Tests cover wrong vault/device/label, byte tampering, nonce uniqueness, truncated
and reordered/named streams, locked access, continued recording after lock,
missing wrappers, malformed JSON quarantine, symlink refusal, migration aliases,
transaction failure preserving a key source and references, phrase changes,
secret redaction/persistence/deletion and format3 reopening. Real SSH fixtures
exercise consent, failed answers, password/PAM reuse, forgetting and vault-key
passphrase reuse. The generated FFI integration exercises key creation/import/
copy/move/export, ciphertext files, blocked handles, recovery/password change
preserving local data, and deletion. Flutter tests cover opt-in prompts,
excluded challenges and discarded UI projections without filesystem fallback.

Encryption protects the current managed copy at rest, not prior backups,
filesystem snapshots/free blocks, explicit exports, clipboard content, an
unlocked compromised process or a malicious remote host. It is not secure erase.
Rust buffers use Zeroizing where owned APIs allow it, including queued russh
keyboard responses and Termius key buffers; upstream cryptographic types have
their own lifecycle. Dart-entered secrets and transient library allocations
cannot be promised a forensic wipe. History can contain secrets typed inside
commands and recording can contain displayed secrets; encryption does not
sanitize them. Leading-space history suppression, including edited lines,
already existed on main and remains tested. Final onboarding and complete
release/security review remain D8; physical D4 gates remain in #33.

## D7 backup integration

[Vault backup v1](vault-backup-v1.md) now specifies portable encrypted and JSON
copies. Restoration re-encrypts logical items under a new destination identity;
it preserves that destination's password/kit. Device-local history/recordings and
external key files are excluded. The original D4/D5/D6 scope above is historical.
