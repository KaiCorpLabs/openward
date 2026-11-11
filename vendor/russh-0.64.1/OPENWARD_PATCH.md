# OpenWard patch to russh 0.64.1

This directory contains the crates.io russh 0.64.1 package. Its archive SHA-256
is `ba61e87b9ec9a39a59a6bbed4c0b8ff7fb07073405b24a767a1f2c8560ac8f58`;
`.cargo_vcs_info.json` retains the upstream Git revision. The upstream Apache
license is included. Registry cache markers/checksums and the package's own
lockfile are omitted: OpenWard uses `core/Cargo.lock`.

Only two upstream source files are changed:

- `src/client/kex.rs`: the actual KEX signature must use the negotiated
  host-key algorithm before its cryptographic verification succeeds. The
  same path handles the initial exchange, rekeys and host certificates.
- `src/client/mod.rs`: exports that verification function so OpenWard's
  regression suite can exercise it with real RSA signatures, without a
  second implementation of the check.

No algorithms, trust checks or cryptographic verification are removed. The
guard enforces the negotiated algorithm, so explicitly negotiated legacy
`ssh-rsa` remains possible while a peer cannot send it after negotiating
RSA/SHA-2. The certificate authority's signature is distinct from the KEX
signature and retains its existing validation.

When replacing this patch with an upstream release, keep the mismatch tests
in `openward-ssh` and confirm the upstream check covers rekey as well as the
initial exchange. Do not drop the guard merely because key negotiation
filters SHA-1: the decoded signature carries its own algorithm.
