#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/pkgwatch"
CONF="${INSTALL_DIR}/etc/pkgwatch.conf"

[[ -r "${CONF}" ]] || exit 0
# shellcheck disable=SC1090
source "${CONF}"

LOG_SRC="${DPKG_LOG:-/var/log/dpkg.log}"
QUEUE_FILE="${INSTALL_DIR}/queue/dpkg.events"
STATE_FILE="${INSTALL_DIR}/state/dpkg.offset"
LAST_EVENT_FILE="${INSTALL_DIR}/state/last_event_epoch"
LOCK_FILE="${INSTALL_DIR}/state/lock.collect"

mkdir -p "${INSTALL_DIR}/queue" "${INSTALL_DIR}/state" "${INSTALL_DIR}/log"

exec 9>"${LOCK_FILE}"
flock -n 9 || exit 0

[[ -r "${LOG_SRC}" ]] || exit 0
touch "${QUEUE_FILE}"

last_offset="0"
[[ -f "${STATE_FILE}" ]] && last_offset="$(cat "${STATE_FILE}" 2>/dev/null || echo 0)"

curr_size="$(stat -c%s "${LOG_SRC}" 2>/dev/null || echo 0)"

# log rotated/truncated
if [[ "${curr_size}" -lt "${last_offset}" ]]; then
  last_offset="0"
fi

new_bytes=$(( curr_size - last_offset ))
[[ "${new_bytes}" -le 0 ]] && exit 0

tail -c "${new_bytes}" "${LOG_SRC}" | grep -E ' (install|upgrade|remove) ' >> "${QUEUE_FILE}" || true

echo "${curr_size}" > "${STATE_FILE}"
date +%s > "${LAST_EVENT_FILE}"
