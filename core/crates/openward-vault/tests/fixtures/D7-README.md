# Public D7 v1 portability fixtures

These synthetic files contain no production secrets. Generated on macOS by
`gen-d7-backup.rs`, using password `Public D7 fixture password` and the recovery
kit whose raw bytes are `[42; 32]`. Includes one synthetic host and one public
password value. Both files encode the same lossless snapshot. CI restores them
on Linux/macOS/Windows into newly generated destination identities and confirms
that destination credentials, not source credentials, unlock the restored data.

To regenerate from repository root:

```sh
mkdir -p core/crates/openward-vault/examples
cp core/crates/openward-vault/tests/fixtures/gen-d7-backup.rs core/crates/openward-vault/examples/gen-d7-backup.rs
(cd core && cargo run -p openward-vault --example gen-d7-backup)
rm core/crates/openward-vault/examples/gen-d7-backup.rs
rmdir core/crates/openward-vault/examples
```

Random account/device/vault keys and nonces mean regeneration changes ciphertext.
See `spec/vault-backup-v1.md` for the normative format and limits.
