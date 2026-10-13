#!/bin/sh
# Installs the mounted test material and runs dropbear in the foreground.
# Dropbear has no certificates and no keyboard-interactive 2FA.
set -eu

echo "demo:$(sed -n 's/^demo=//p' /fixtures/passwords)" | chpasswd
install -d -m 700 -o demo -g demo /home/demo/.ssh
install -m 600 -o demo -g demo /fixtures/authorized_keys /home/demo/.ssh/authorized_keys

mkdir -p /srv/www && echo "s2-forward-ok $(hostname)" > /srv/www/index.html
busybox-extras httpd -p 127.0.0.1:8080 -h /srv/www

# -R: create host keys on first use; -E: log to stderr; -F: foreground.
exec dropbear -R -E -F -p 22
