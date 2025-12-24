#!/usr/bin/env bash
set -euo pipefail

APP="pkgwatch"
INSTALL_DIR="/opt/pkgwatch"
SYSTEMD_DIR="/etc/systemd/system"

say() { echo -e "[$APP] $*"; }
die() { echo -e "[$APP] ERROR: $*" >&2; exit 1; }

[[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root: sudo bash uninstall.sh"

say "Stopping/disabling services..."
systemctl disable --now pkgwatch-collect.path 2>/dev/null || true
systemctl disable --now pkgwatch-flush.timer 2>/dev/null || true
systemctl disable --now pkgwatch-audit.timer 2>/dev/null || true


say "Removing systemd unit files..."
rm -f \
  "${SYSTEMD_DIR}/pkgwatch-collect.service" \
  "${SYSTEMD_DIR}/pkgwatch-collect.path" \
  "${SYSTEMD_DIR}/pkgwatch-flush.service" \
  "${SYSTEMD_DIR}/pkgwatch-flush.timer"
  "${SYSTEMD_DIR}/pkgwatch-audit.service" \
  "${SYSTEMD_DIR}/pkgwatch-audit.timer" \


systemctl daemon-reload

say "Removing ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}"

say "✅ Uninstalled."

