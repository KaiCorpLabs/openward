#!/usr/bin/env bash
# Generates the S2 test material: client keys, user and host CAs, a user
# certificate, passwords and a TOTP secret. Throwaway values for local test
# servers only; written outside the repository and never committed.
#
#   fixtures.sh <dir>
set -euo pipefail

dir="${1:?usage: fixtures.sh <dir>}"
mkdir -p "$dir"
cd "$dir"

key() { # type bits file [passphrase]
  [[ -f "$3" ]] || ssh-keygen -q -t "$1" ${2:+-b "$2"} -N "${4:-}" -C "s2-$3" -f "$3"
}
key ed25519 "" id_ed25519
key ecdsa 256 id_ecdsa
key rsa 3072 id_rsa
key ed25519 "" id_ed25519_pass s2-passphrase
# Only usable through its certificate: not in authorized_keys.
key ed25519 "" id_cert
key ed25519 "" user_ca
key ed25519 "" host_ca

[[ -f id_cert-cert.pub ]] ||
  ssh-keygen -q -s user_ca -I s2-demo -n demo -V -5m:+52w id_cert.pub

cat id_ed25519.pub id_ecdsa.pub id_rsa.pub id_ed25519_pass.pub > authorized_keys
printf '@cert-authority * %s\n' "$(cat host_ca.pub)" > known_hosts_ca

# Test-only credentials for the throwaway servers.
[[ -f passwords ]] || printf 'demo=s2-demo-password\notp=s2-otp-password\n' > passwords
if [[ ! -f totp_secret ]]; then
  # 160-bit secret, base32 without padding (RFC 6238 / Google Authenticator).
  python3 -c 'import base64,os; print(base64.b32encode(os.urandom(20)).decode().rstrip("="))' > totp_secret
fi

chmod 600 id_* user_ca host_ca
echo "fixtures in $dir"
