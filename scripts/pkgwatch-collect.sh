#!/usr/bin/env bash
set -eu
( set -o pipefail ) 2>/dev/null && set -o pipefail || true


INSTALL_DIR="/opt/pkgwatch"
CONF="${INSTALL_DIR}/etc/pkgwatch.conf"

[[ -r "${CONF}" ]] || exit 0
# shellcheck disable=SC1090
source "${CONF}"

DPKG_LOG="${DPKG_LOG:-/var/log/dpkg.log}"

QUEUE_FILE="${INSTALL_DIR}/queue/dpkg.events"
STATE_FILE="${INSTALL_DIR}/state/dpkg.state"
LAST_EVENT_FILE="${INSTALL_DIR}/state/last_event_epoch"
LOCK_FILE="${INSTALL_DIR}/state/lock.collect"

mkdir -p "${INSTALL_DIR}/queue" "${INSTALL_DIR}/state" "${INSTALL_DIR}/log"

# Prevent races if systemd triggers multiple times quickly
exec 9>"${LOCK_FILE}"
flock -n 9 || exit 0

[[ -f "${DPKG_LOG}" ]] || exit 0

inode_now="$(stat -c '%i' "${DPKG_LOG}")"
size_now="$(stat -c '%s' "${DPKG_LOG}")"

inode_prev=""
offset_prev="0"
if [[ -f "${STATE_FILE}" ]]; then
  inode_prev="$(awk -F= '/^inode=/{print $2}' "${STATE_FILE}" 2>/dev/null || true)"
  offset_prev="$(awk -F= '/^offset=/{print $2}' "${STATE_FILE}" 2>/dev/null || echo 0)"
fi

# Handle rotation/truncation
if [[ "${inode_prev}" != "${inode_now}" || "${size_now}" -lt "${offset_prev}" ]]; then
  offset_prev="0"
fi

# No new content
if [[ "${size_now}" -le "${offset_prev}" ]]; then
  exit 0
fi

tmp="$(mktemp)"
dd if="${DPKG_LOG}" bs=1 skip="${offset_prev}" status=none > "${tmp}"

# Update offset immediately (avoid duplicates even if later steps fail)
cat > "${STATE_FILE}" <<EOF
inode=${inode_now}
offset=${size_now}
EOF

# Queue only relevant lines
# dpkg.log: "YYYY-MM-DD HH:MM:SS action package:arch oldver newver"
grep -E ' (install|upgrade|remove) ' "${tmp}" >> "${QUEUE_FILE}" || true
rm -f "${tmp}"

date +%s > "${LAST_EVENT_FILE}"

