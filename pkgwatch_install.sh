#!/usr/bin/env bash
set -eu
( set -o pipefail ) 2>/dev/null && set -o pipefail || true

APP="pkgwatch"
INSTALL_DIR="/opt/pkgwatch"
ETC_DIR="${INSTALL_DIR}/etc"
BIN_DIR="${INSTALL_DIR}/bin"
QUEUE_DIR="${INSTALL_DIR}/queue"
STATE_DIR="${INSTALL_DIR}/state"
LOG_DIR="${INSTALL_DIR}/log"
SYSTEMD_DIR="/etc/systemd/system"

say() { echo "[$APP] $*"; }
die() { echo "[$APP] ERROR: $*" >&2; exit 1; }

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root: sudo bash install.sh"
}

detect_os() {
  [[ -f /etc/os-release ]] || die "Cannot find /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu)
      ver_major="${VERSION_ID%%.*}"
      [[ "${ver_major}" -ge 20 ]] || die "Ubuntu ${VERSION_ID} not supported. Need Ubuntu 20.04+."
      ;;
    debian)
      [[ "${VERSION_ID}" -ge 12 ]] || die "Debian ${VERSION_ID} not supported. Need Debian 12+."
      ;;
    *)
      die "Unsupported OS: ${ID:-unknown}"
      ;;
  esac
}

install_deps() {
  say "Installing dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y bash curl coreutils util-linux dos2unix auditd git >/dev/null
}

create_dirs() {
  say "Creating directories under ${INSTALL_DIR} ..."
  install -d -m 0700 "${ETC_DIR}" "${BIN_DIR}" "${QUEUE_DIR}" "${STATE_DIR}" "${LOG_DIR}"
}

install_files() {
  say "Installing scripts..."
  install -m 0700 "scripts/pkgwatch-collect.sh"      "${BIN_DIR}/pkgwatch-collect.sh"
  install -m 0700 "scripts/pkgwatch-flush.sh"        "${BIN_DIR}/pkgwatch-flush.sh"
  install -m 0700 "scripts/pkgwatch-audit-setup.sh"  "${BIN_DIR}/pkgwatch-audit-setup.sh"
  install -m 0700 "scripts/pkgwatch-audit-flush.sh"  "${BIN_DIR}/pkgwatch-audit-flush.sh"

  say "Installing systemd units..."
  install -m 0644 "systemd/pkgwatch-collect.service" "${SYSTEMD_DIR}/pkgwatch-collect.service"
  install -m 0644 "systemd/pkgwatch-collect.path"    "${SYSTEMD_DIR}/pkgwatch-collect.path"
  install -m 0644 "systemd/pkgwatch-flush.service"   "${SYSTEMD_DIR}/pkgwatch-flush.service"
  install -m 0644 "systemd/pkgwatch-flush.timer"     "${SYSTEMD_DIR}/pkgwatch-flush.timer"
  install -m 0644 "systemd/pkgwatch-audit.service"   "${SYSTEMD_DIR}/pkgwatch-audit.service"
  install -m 0644 "systemd/pkgwatch-audit.timer"     "${SYSTEMD_DIR}/pkgwatch-audit.timer"

  # CRLF hardening for installed scripts (protect against bad uploads)
  dos2unix -q "${BIN_DIR}/pkgwatch-collect.sh" "${BIN_DIR}/pkgwatch-flush.sh" "${BIN_DIR}/pkgwatch-audit-setup.sh" "${BIN_DIR}/pkgwatch-audit-flush.sh" 2>/dev/null || true
}

create_config() {
  say "Creating config..."
  if [[ -f "${ETC_DIR}/pkgwatch.conf" ]]; then
    say "Config exists: ${ETC_DIR}/pkgwatch.conf (keeping)"
    return
  fi

  install -m 0600 "config/pkgwatch.conf.example" "${ETC_DIR}/pkgwatch.conf"

  # allow env prefill
  if [[ -n "${BOT_TOKEN:-}" ]]; then
    sed -i "s/^BOT_TOKEN=.*/BOT_TOKEN=\"${BOT_TOKEN//\"/\\\"}\"/" "${ETC_DIR}/pkgwatch.conf"
  fi
  if [[ -n "${CHAT_ID:-}" ]]; then
    sed -i "s/^CHAT_ID=.*/CHAT_ID=\"${CHAT_ID//\"/\\\"}\"/" "${ETC_DIR}/pkgwatch.conf"
  fi

  # CRLF hardening (your exact bug)
  sed -i 's/\r$//' "${ETC_DIR}/pkgwatch.conf" || true
  chmod 0600 "${ETC_DIR}/pkgwatch.conf"

  say "Config created: ${ETC_DIR}/pkgwatch.conf"
}

enable_services() {
  say "Enabling services..."
  systemctl daemon-reload
  systemctl enable --now pkgwatch-collect.path
  systemctl enable --now pkgwatch-flush.timer

  # audit rules setup once (idempotent)
  "${BIN_DIR}/pkgwatch-audit-setup.sh" || true
  systemctl enable --now pkgwatch-audit.timer
}

post_install_message() {
  cat <<EOF

[$APP] ✅ Installed successfully.

One-line install (recommended):
  curl -fsSL https://raw.githubusercontent.com/MasterHide/pkgwatch/main/bootstrap.sh | sudo bash

Config:
  sudo nano ${ETC_DIR}/pkgwatch.conf

Force test (no 120s wait):
  sudo FORCE_SEND=1 systemctl start pkgwatch-flush.service

Normal test:
  sudo apt-get install -y cowsay
  # wait QUIET_SECONDS (default 120s) => one message

Services:
  systemctl status pkgwatch-collect.path
  systemctl status pkgwatch-flush.timer
  systemctl status pkgwatch-audit.timer

EOF
}

main() {
  require_root
  detect_os
  install_deps
  create_dirs
  install_files
  create_config
  enable_services
  post_install_message
}

main "$@"
