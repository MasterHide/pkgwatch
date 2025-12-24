#!/usr/bin/env bash
set -eu
( set -o pipefail ) 2>/dev/null && set -o pipefail || true


INSTALL_DIR="/opt/pkgwatch"
CONF="${INSTALL_DIR}/etc/pkgwatch.conf"
[[ -r "${CONF}" ]] || exit 0
# shellcheck disable=SC1090
source "${CONF}"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y auditd

# Track executions of common installer tools + persistence locations
cat >/etc/audit/rules.d/pkgwatch.rules <<'EOF'
# commands often used to install scripts/binaries (watch common paths)
-w /usr/bin/git  -p x -k pkgwatch_git
-w /bin/git      -p x -k pkgwatch_git

-w /usr/bin/curl -p x -k pkgwatch_net
-w /bin/curl     -p x -k pkgwatch_net

-w /usr/bin/wget -p x -k pkgwatch_net
-w /bin/wget     -p x -k pkgwatch_net

-w /bin/bash     -p x -k pkgwatch_shell
-w /usr/bin/bash -p x -k pkgwatch_shell
-w /bin/sh       -p x -k pkgwatch_shell
-w /usr/bin/sh   -p x -k pkgwatch_shell

# persistence targets
-w /etc/cron.d        -p wa -k pkgwatch_persist
-w /etc/crontab       -p wa -k pkgwatch_persist
-w /etc/cron.daily    -p wa -k pkgwatch_persist
-w /etc/cron.hourly   -p wa -k pkgwatch_persist
-w /etc/cron.weekly   -p wa -k pkgwatch_persist
-w /etc/cron.monthly  -p wa -k pkgwatch_persist
-w /etc/systemd/system -p wa -k pkgwatch_persist
-w /lib/systemd/system -p wa -k pkgwatch_persist
EOF

augenrules --load
systemctl enable --now auditd
systemctl restart auditd
