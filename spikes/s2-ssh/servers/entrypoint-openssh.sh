#!/usr/bin/env bash
# Installs the mounted test material (/fixtures) and runs sshd in the
# foreground. Host keys are fresh per container and certified by the host CA.
set -euo pipefail

ssh-keygen -A >/dev/null
ssh-keygen -q -s /fixtures/host_ca -I "s2-$(hostname)" -h \
  -n "localhost,127.0.0.1,$(hostname),bastion,target1,target2" -V -5m:+52w \
  /etc/ssh/ssh_host_ed25519_key.pub
cp /fixtures/user_ca.pub /etc/ssh/user_ca.pub

pw() { sed -n "s/^$1=//p" /fixtures/passwords; }
echo "demo:$(pw demo)" | chpasswd
echo "otp:$(pw otp)" | chpasswd

install -d -m 700 -o demo -g demo /home/demo/.ssh
install -m 600 -o demo -g demo /fixtures/authorized_keys /home/demo/.ssh/authorized_keys
# Same keys for hops between containers (jump tests).
install -m 600 -o demo -g demo /fixtures/id_ed25519 /home/demo/.ssh/id_ed25519

secret="$(cat /fixtures/totp_secret)"
printf '%s\n" RATE_LIMIT 100 30\n" WINDOW_SIZE 17\n" TOTP_AUTH\n' "$secret" \
  > /home/otp/.google_authenticator
chown otp:otp /home/otp/.google_authenticator
chmod 400 /home/otp/.google_authenticator

# A known page for the port-forwarding tests, reachable only inside.
mkdir -p /srv/www && echo "s2-forward-ok $(hostname)" > /srv/www/index.html
(cd /srv/www && python3 -m http.server 8080 --bind 127.0.0.1 >/dev/null 2>&1 &)

exec /usr/sbin/sshd -D -e
