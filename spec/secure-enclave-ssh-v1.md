# Secure Enclave SSH keys v1

Implemented for macOS by `openward-app::enclave`. This is independent of the
local vault-unlock key: SSH keys are never used to derive vault keys, and the
unlock factor is never offered to a server. The production backend has no
software fallback and exposes no private-key export API.

## Native key and authentication

- P-256 only (`ecdsa-sha2-nistp256`), generated using Security.framework
  `SecKeyCreateRandomKey` / `Token::SecureEnclave`. No private key is imported.
- Permanent, non-synchronizing Data Protection Keychain item, labelled
  `dev.openward.ssh.secure-enclave.v1/<random canonical UUID>`.
- `AccessibleWhenUnlockedThisDeviceOnly`, `privateKeyUsage` and
  `biometryCurrentSet`. The OS authorizes the protected operation; a UI boolean
  cannot authorize a signature. Changing the enrolled biometric set may make
  the key unusable. A new lookup is performed for each operation.
- Creation proves an authenticated signature before saving a vault reference.
  Failure/cancellation removes the new local key. A cleanup failure reports
  the local identifier in error details so it can be removed from the keychain.
- Lookup is restricted to private, non-synchronizing keys in the Data Protection
  Keychain and this namespace. The public key must match the saved descriptor.
  Deletion additionally pins the key's application label (public-key hash).
- Sign the original SSH user-authentication bytes using
  `ECDSASignatureMessageX962SHA256`; convert Apple's DER ECDSA response to SSH's
  positive `r`/`s` mpints. Verify the response against the exact message and
  expected public key before returning it to `russh`.

Apple documents [Secure Enclave key protection](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave)
and [Data Protection Keychain queries, including deletion](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain).
The safe wrapper is pinned to `security-framework 3.7.0`; no handwritten unsafe
code is added to the application.

## Vault reference and UI

The encrypted item's kind is `SecureEnclaveKey`. Its binding is the native UUID
and its value is a strict JSON descriptor:

```json
{"version":1,"id":"<native UUID>","public_key":"ecdsa-sha2-nistp256 ... comment"}
```

It contains only public material and a local handle. The SSH identity setting
uses `enclave:<vault item UUID>` without expanding it into a filesystem path.
Unknown versions, noncanonical identifiers, mismatched bindings and algorithms
other than P-256 are rejected. Descriptor size and comment length are bounded.
Clients predating this kind cannot use the hardware identity; use a compatible
client to restore it. The existing backup format retains its record.

With an encrypted, unlocked vault, macOS offers **Keys → New key → Create in
Secure Enclave (Touch ID)**. Other systems show imported references but cannot
generate or sign with them. The user can copy/install the public half, assign
it to a host/identity using the managed-key chooser (by name), rename its vault
label or delete it. No passphrase,
private export or reveal-in-Finder action is offered. The FFI independently
rejects private export and passphrase changes; metadata never grants signing.
This first implementation authenticates with the ordinary public key, not an
OpenSSH user certificate wrapping a hardware key.

## Lock, cancellation and recovery limits

OS operations run on blocking workers without holding vault/gate locks. A gate
epoch is checked before and after signing and before committing generation.
Locking and then unlocking cannot publish a result from the previous epoch.
Failed/cancelled/missing native signing terminates that authentication attempt;
an agent advertising the same public key is excluded, so it cannot bypass the
selected hardware identity. Normal host-key verification still runs first.

An already authorized network connection remains subject to the normal vault
UI-lock policy. Deleting a native key cannot revoke an established connection
or remove `authorized_keys` entries from servers.

`.owvault` and JSON exports include **only the public reference**, never the
Secure Enclave private key. Restoring on a different machine does not make it
usable there. A vault recovery kit cannot recover a lost/deleted hardware key.
Keep another server-login method and install a new public key after device loss.
Deleting a reference on another system cannot delete the original Mac's key;
deleting it on its original Mac removes the hardware key first. If locking
interrupts deletion, retry after unlocking to remove the remaining reference.
Old backup references do not resurrect a deleted hardware key.

## Automated and physical validation

`cargo test --locked -p openward-app enclave` exercises verified DER/SSH framing,
public metadata, persistence, recovery on another device, cancellation, missing
keys and late results after lock/unlock. `openward-ffi` tests public-only access,
rename/delete and rejection of private export/passphrases. Flutter widget tests
cover P-256 selection, recovery warnings, cancelled creation, platform visibility
and the actions menu.

The S2 server regression runs in Linux CI with `OPENWARD_REQUIRE_SERVERS=1`:
it uses real OpenSSH, `russh`, the encrypted vault and DER/SSH conversion, with
only the native device backend replaced. It also offers the same key through a
test agent and verifies that native failure cannot be bypassed by that agent.
A passing mock/CI run is **not physical Touch ID evidence**.

Manual macOS diagnostic (a disposable key is deleted at exit):

```sh
cd core
OPENWARD_TEST_SECURE_ENCLAVE=1 cargo test --locked -p openward-app \
  physical_touch_id_signs_and_private_key_is_not_exportable -- --ignored --nocapture
```

The real shipped bundle must also pass creation, SSH login, restart/reuse,
cancellation, lock during the prompt, biometric-set change and deletion on a
physical Touch ID Mac. Record architecture, OS, signing identity/entitlements,
commit and results in #33; do not attach private profiles or keys. Validate
Windows Hello separately for vault unlock. Original mockup review and physical
platform/signing evidence remain open in #33; no Developer ID requirement is
inferred from mocks and no certificate is purchased by this implementation.
