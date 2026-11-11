#!/usr/bin/env bash
# Dependencies for disposable Ubuntu Actions runners. Preserve the Ubuntu
# keyring/signature policy when the Canonical archive's DNS is unavailable.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'Actions runner required' >&2; exit 2; }

if ! timeout 5 getent ahostsv4 archive.ubuntu.com >/dev/null \
  || ! timeout 5 getent ahostsv4 azure.archive.ubuntu.com >/dev/null \
  || ! timeout 5 getent ahostsv4 security.ubuntu.com >/dev/null; then
  timeout 10 getent ahostsv4 mirrors.edge.kernel.org >/dev/null
  for source in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -f "$source" ]] || continue
    sudo sed -i -E \
      -e 's#mirror\+file:/etc/apt/apt-mirrors.txt#https://mirrors.edge.kernel.org/ubuntu#g' \
      -e 's#https?://([a-zA-Z0-9-]+\.)?archive\.ubuntu\.com/ubuntu#https://mirrors.edge.kernel.org/ubuntu#g' \
      -e 's#https?://security\.ubuntu\.com/ubuntu#https://mirrors.edge.kernel.org/ubuntu#g' "$source"
  done
fi

# A stale/empty index must not count as a successful update.
sudo apt-get -o APT::Update::Error-Mode=any -o Acquire::Retries=2 update -qq
sudo apt-get install -y "$@"
