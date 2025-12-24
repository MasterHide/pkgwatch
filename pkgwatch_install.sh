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

say() { echo -e "[$APP] $*"; }
die() { echo -e "[$APP] ERROR: $*" >&2; exit 1; }

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root: sudo bash install.sh"
}

detect_os() {
  [[ -f /etc/os-release ]] || die "Cannot find /etc/os-release"
  # shellcheck disable=SC1091
  source /etc/os-release

  case "${ID:-}" in
    ubuntu)
      # VERSION_ID like "20.04"
      ver_major="${VERSION_ID%%.*}"
      ver_minor="${VERSION_ID#*.}"
      [[ "${ver_major}" -ge 20 ]] || die "Ubuntu ${VERSION_ID} is not supported. Need Ubuntu 20.04+."
      ;;
    debian)
      # VERSION_ID like "12"
      [[ "${VERSION_ID}" -ge 12 ]] || die "Debian ${VERSION_ID} is not supported. Need Debian 12+."
      ;;
    *)
      die "Unsupported OS: ID=${ID:-unknown}. Supported: Ubuntu 20.04+ / Debian 12+."
      ;;
  esac
}

install_deps() {
  say "Installing dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl coreutils util-linux auditd
}

create_dirs() {
  say "Creating ${INSTALL_DIR} directories..."
  install -d -m 0700 "${ETC_DIR}" "${BIN_DIR}" "${QUEUE_DIR}" "${STATE_DIR}" "${LOG_DIR}"
}

install_files() {
  say "Installing scripts..."
  install -m 0700 "scripts/pkgwatch-collect.sh" "${BIN_DIR}/pkgwatch-collect.sh"
  install -m 0700 "scripts/pkgwatch-flush.sh"   "${BIN_DIR}/pkgwatch-flush.sh"
  install -m 0700 "scripts/pkgwatch-audit-setup.sh" "${BIN_DIR}/pkgwatch-audit-setup.sh"
  install -m 0700 "scripts/pkgwatch-audit-flush.sh" "${BIN_DIR}/pkgwatch-audit-flush.sh"

  say "Installing systemd units..."
  install -m 0644 "systemd/pkgwatch-collect.service" "${SYSTEMD_DIR}/pkgwatch-collect.service"
  install -m 0644 "systemd/pkgwatch-collect.path"    "${SYSTEMD_DIR}/pkgwatch-collect.path"
  install -m 0644 "systemd/pkgwatch-flush.service"   "${SYSTEMD_DIR}/pkgwatch-flush.service"
  install -m 0644 "systemd/pkgwatch-flush.timer"     "${SYSTEMD_DIR}/pkgwatch-flush.timer"
  install -m 0644 "systemd/pkgwatch-audit.service" "${SYSTEMD_DIR}/pkgwatch-audit.service"
  install -m 0644 "systemd/pkgwatch-audit.timer" "${SYSTEMD_DIR}/pkgwatch-audit.timer"
}

create_config() {
  say "Creating config..."
  if [[ -f "${ETC_DIR}/pkgwatch.conf" ]]; then
    say "Config already exists: ${ETC_DIR}/pkgwatch.conf (keeping it)"
    return
  fi

  install -m 0600 "config/pkgwatch.conf.example" "${ETC_DIR}/pkgwatch.conf"

  # Allow environment variables to pre-fill secrets during install:
  # BOT_TOKEN and CHAT_ID
  if [[ -n "${BOT_TOKEN:-}" ]]; then
    sed -i "s/^BOT_TOKEN=.*/BOT_TOKEN=\"${BOT_TOKEN//\"/\\\"}\"/" "${ETC_DIR}/pkgwatch.conf"
  fi
  if [[ -n "${CHAT_ID:-}" ]]; then
    sed -i "s/^CHAT_ID=.*/CHAT_ID=\"${CHAT_ID//\"/\\\"}\"/" "${ETC_DIR}/pkgwatch.conf"
  fi

  say "Config created at ${ETC_DIR}/pkgwatch.conf (root-only)"
}

enable_services() {
  say "Enabling services..."
  systemctl daemon-reload
  systemctl enable --now pkgwatch-collect.path
  systemctl enable --now pkgwatch-flush.timer

  # setup audit rules once (idempotent)
  "${BIN_DIR}/pkgwatch-audit-setup.sh" || true

  systemctl enable --now pkgwatch-audit.timer
}


post_install_message() {
  cat <<EOF

[$APP] ✅ Installed successfully.

Location:
  ${INSTALL_DIR}

IMPORTANT: Configure Telegram before expecting alerts:
  sudo nano ${ETC_DIR}/pkgwatch.conf

Then restart timer:
  sudo systemctl restart pkgwatch-flush.timer

Test:
  sudo apt-get install -y sl
  # Wait QUIET_SECONDS (default 120s) => you should receive ONE Telegram message.

Status:
  systemctl status pkgwatch-collect.path
  systemctl status pkgwatch-flush.timer
  systemctl status pkgwatch-audit.timer


Logs:
  journalctl -u pkgwatch-collect.service -n 50 --no-pager
  journalctl -u pkgwatch-flush.service -n 50 --no-pager
  journalctl -u pkgwatch-audit.service -n 50 --no-pager


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




