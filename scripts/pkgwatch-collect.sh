#!/usr/bin/env bash
set -eu
( set -o pipefail ) 2>/dev/null && set -o pipefail || true

INSTALL_DIR="/opt/pkgwatch"
CONF="${INSTALL_DIR}/etc/pkgwatch.conf"

# CRLF-proof config sourcing:
[[ -r "${CONF}" ]] || exit 0
# shellcheck disable=SC1090
source <(sed 's/\r$//' "${CONF}")

DPKG_LOG="${DPKG_LOG:-/var/log/dpkg.log}"
QUEUE_FILE="${INSTALL_DIR}/queue/dpkg.events"
STATE_FILE="${INSTALL_DIR}/state/dpkg.offset"
LAST_EVENT_FILE="${INSTALL_DIR}/state/last_event_epoch"
LOCK_FILE="${INSTALL_DIR}/state/lock.collect"

mkdir -p "${INSTALL_DIR}/queue" "${INSTALL_DIR}/state" "${INSTALL_DIR}/log"

exec 9>"${LOCK_FILE}"
flock -n 9 || exit 0

inode_now="$(stat -c '%i' "${DPKG_LOG}" 2>/dev/null || echo 0)"
size_now="$(stat -c '%s' "${DPKG_LOG}" 2>/dev/null || echo 0)"

inode_prev=0
offset_prev=0
if [[ -f "${STATE_FILE}" ]]; then
  IFS=' ' read -r inode_prev offset_prev < "${STATE_FILE}" || true
fi

# If rotated/truncated, restart offset
if [[ "${inode_now}" != "${inode_prev}" ]] || (( size_now < offset_prev )); then
  offset_prev=0
fi

# Read new lines
dd if="${DPKG_LOG}" bs=1 skip="${offset_prev}" 2>/dev/null \
| awk '$3=="install" || $3=="upgrade" || $3=="remove"{print}' >> "${QUEUE_FILE}" || true

echo "${inode_now} ${size_now}" > "${STATE_FILE}"
date +%s > "${LAST_EVENT_FILE}"
