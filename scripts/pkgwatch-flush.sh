#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/pkgwatch"
CONF="${INSTALL_DIR}/etc/pkgwatch.conf"
LOG_DIR="${INSTALL_DIR}/log"
LOG_FILE="${LOG_DIR}/flush.debug.log"
RESP_FILE="${LOG_DIR}/flush.last_response"
QUEUE_FILE="${INSTALL_DIR}/queue/dpkg.events"
LAST_EVENT_FILE="${INSTALL_DIR}/state/last_event_epoch"
LAST_SEND_FILE="${INSTALL_DIR}/state/last_send_epoch"
LOCK_FILE="${INSTALL_DIR}/state/lock.flush"

mkdir -p "${INSTALL_DIR}/state" "${LOG_DIR}" "${INSTALL_DIR}/queue"

log() { echo "[$(date -Is)] $*" | tee -a "${LOG_FILE}" >/dev/null; }

if [[ ! -r "${CONF}" ]]; then
  log "EXIT: config missing: ${CONF}"
  exit 0
fi

# shellcheck disable=SC1090
source "${CONF}"

BOT_TOKEN="${BOT_TOKEN:-}"
CHAT_ID="${CHAT_ID:-}"
QUIET_SECONDS="${QUIET_SECONDS:-120}"
MAX_PKGS="${MAX_PKGS:-60}"

if [[ -z "${BOT_TOKEN}" || -z "${CHAT_ID}" || "${BOT_TOKEN}" == "CHANGE_ME" || "${CHAT_ID}" == "CHANGE_ME" ]]; then
  log "EXIT: BOT_TOKEN/CHAT_ID not set correctly (BOT_TOKEN len=${#BOT_TOKEN}, CHAT_ID='${CHAT_ID}')"
  exit 0
fi

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  log "EXIT: another flush running (lock busy)"
  exit 0
fi

if [[ ! -s "${QUEUE_FILE}" ]]; then
  log "EXIT: queue empty or missing: ${QUEUE_FILE}"
  exit 0
fi

now="$(date +%s)"

if [[ "${FORCE_SEND:-0}" != "1" ]]; then
  last_event="0"
  [[ -f "${LAST_EVENT_FILE}" ]] && last_event="$(cat "${LAST_EVENT_FILE}" 2>/dev/null || echo 0)"
  if [[ "${last_event}" -gt 0 ]]; then
    quiet_for=$(( now - last_event ))
    if [[ "${quiet_for}" -lt "${QUIET_SECONDS}" ]]; then
      log "EXIT: quiet window not reached (quiet_for=${quiet_for}s < QUIET_SECONDS=${QUIET_SECONDS}s)"
      exit 0
    fi
  fi

  last_send="0"
  [[ -f "${LAST_SEND_FILE}" ]] && last_send="$(cat "${LAST_SEND_FILE}" 2>/dev/null || echo 0)"
  if [[ "${last_send}" -gt 0 ]]; then
    since=$(( now - last_send ))
    if [[ "${since}" -lt "${QUIET_SECONDS}" ]]; then
      log "EXIT: rate limit not reached (since_last_send=${since}s < QUIET_SECONDS=${QUIET_SECONDS}s)"
      exit 0
    fi
  fi
else
  log "FORCE_SEND=1 set: bypassing quiet/rate-limit checks"
fi

tmp="$(mktemp)"
cp "${QUEUE_FILE}" "${tmp}"

installs="$(awk '$3=="install"{print $4}' "${tmp}" | sed 's/:amd64$//;s/:all$//' | sort | uniq -c | sort -nr | head -n "${MAX_PKGS}")"
upgrades="$(awk '$3=="upgrade"{print $4}' "${tmp}" | sed 's/:amd64$//;s/:all$//' | sort | uniq -c | sort -nr | head -n "${MAX_PKGS}")"
removes="$(awk '$3=="remove"{print $4}' "${tmp}" | sed 's/:amd64$//;s/:all$//' | sort | uniq -c | sort -nr | head -n "${MAX_PKGS}")"

host="$(hostname)"
ts="$(date -Is)"

# Escape for MarkdownV2
md_escape() {
  sed -e 's/\\/\\\\/g' \
      -e 's/_/\\_/g'  -e 's/\*/\\*/g' -e 's/\[/\\[/g' -e 's/\]/\\]/g' \
      -e 's/(/\\(/g'  -e 's/)/\\)/g' -e 's/~/\\~/g'  -e 's/`/\\`/g' \
      -e 's/>/\\>/g'  -e 's/#/\\#/g'  -e 's/+/\\+/g' -e 's/-/\\-/g' \
      -e 's/=/\\=/g'  -e 's/|/\\|/g'  -e 's/{/\\{/g' -e 's/}/\\}/g' \
      -e 's/\./\\./g' -e 's/!/\\!/g'
}

section() {
  local title="$1" body="$2"
  if [[ -n "${body// }" ]]; then
    printf "*%s*\n" "${title}"
    printf '```\n%s\n```\n' "${body}"
  fi
}

msg_raw="📦 *PkgWatch* on ${host}
🕒 ${ts}

$(section "Installs" "${installs}")
$(section "Upgrades" "${upgrades}")
$(section "Removals" "${removes}")
"

msg="$(printf "%s" "${msg_raw}" | md_escape)"
msg="${msg:0:3800}"

log "SENDING: queue_lines=$(wc -l < "${QUEUE_FILE}") BOT_TOKEN_len=${#BOT_TOKEN} CHAT_ID=${CHAT_ID}"

# Try send
if curl -fsS --max-time 20 --retry 3 --retry-delay 2 \
  -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "text=${msg}" \
  -d "parse_mode=MarkdownV2" \
  >"${RESP_FILE}" 2>&1; then
  : > "${QUEUE_FILE}"
  echo "${now}" > "${LAST_SEND_FILE}"
  log "OK: sent message, cleared queue, wrote ${RESP_FILE}"
else
  log "FAIL: curl send failed. See ${RESP_FILE}"
  exit 1
fi

rm -f "${tmp}"
