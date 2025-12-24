#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/pkgwatch"
CONF="${INSTALL_DIR}/etc/pkgwatch.conf"
[[ -r "${CONF}" ]] || exit 0
# shellcheck disable=SC1090
source "${CONF}"

BOT_TOKEN="${BOT_TOKEN:-}"
CHAT_ID="${CHAT_ID:-}"
[[ -n "${BOT_TOKEN}" && -n "${CHAT_ID}" && "${BOT_TOKEN}" != "CHANGE_ME" && "${CHAT_ID}" != "CHANGE_ME" ]] || exit 0

QUEUE_FILE="${INSTALL_DIR}/queue/dpkg.events"
LAST_EVENT_FILE="${INSTALL_DIR}/state/last_event_epoch"
LAST_SEND_FILE="${INSTALL_DIR}/state/last_send_epoch"
LOCK_FILE="${INSTALL_DIR}/state/lock.flush"

QUIET_SECONDS="${QUIET_SECONDS:-120}"
MAX_PKGS="${MAX_PKGS:-60}"

mkdir -p "${INSTALL_DIR}/state" "${INSTALL_DIR}/log" "${INSTALL_DIR}/queue"

exec 9>"${LOCK_FILE}"
flock -n 9 || exit 0

[[ -s "${QUEUE_FILE}" ]] || exit 0

now="$(date +%s)"

# FORCE_SEND=1 bypasses quiet time
if [[ "${FORCE_SEND:-0}" != "1" ]]; then
  last_event="0"
  [[ -f "${LAST_EVENT_FILE}" ]] && last_event="$(cat "${LAST_EVENT_FILE}" 2>/dev/null || echo 0)"
  if [[ "${last_event}" -gt 0 ]]; then
    quiet_for=$(( now - last_event ))
    [[ "${quiet_for}" -lt "${QUIET_SECONDS}" ]] && exit 0
  fi

  last_send="0"
  [[ -f "${LAST_SEND_FILE}" ]] && last_send="$(cat "${LAST_SEND_FILE}" 2>/dev/null || echo 0)"
  if [[ "${last_send}" -gt 0 ]]; then
    since=$(( now - last_send ))
    [[ "${since}" -lt "${QUIET_SECONDS}" ]] && exit 0
  fi
fi

# Snapshot queue
tmp="$(mktemp)"
cp "${QUEUE_FILE}" "${tmp}"

installs="$(awk '$3=="install"{print $4}' "${tmp}" | sed 's/:amd64$//;s/:all$//' | sort | uniq -c | sort -nr | head -n "${MAX_PKGS}")"
upgrades="$(awk '$3=="upgrade"{print $4}' "${tmp}" | sed 's/:amd64$//;s/:all$//' | sort | uniq -c | sort -nr | head -n "${MAX_PKGS}")"
removes="$(awk '$3=="remove"{print $4}' "${tmp}" | sed 's/:amd64$//;s/:all$//' | sort | uniq -c | sort -nr | head -n "${MAX_PKGS}")"

host="$(hostname)"
ts="$(date -Is)"

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

# Telegram hard limit ~4096 chars; keep safe
msg="${msg:0:3800}"

# x-www-form-urlencoded (curl -d does this already)
resp_file="${INSTALL_DIR}/log/flush.last_response"
if ! curl -fsS --max-time 15 --retry 3 --retry-delay 2 \
  -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "text=${msg}" \
  -d "parse_mode=MarkdownV2" \
  >"${resp_file}" 2>&1; then
  # leave queue intact on failure
  exit 1
fi

# Success: clear queue + mark send time
: > "${QUEUE_FILE}"
echo "${now}" > "${LAST_SEND_FILE}"
rm -f "${tmp}"
