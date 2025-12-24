#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/pkgwatch"
CONF="${INSTALL_DIR}/etc/pkgwatch.conf"

[[ -r "${CONF}" ]] || exit 0
# shellcheck disable=SC1090
source "${CONF}"

DPKG_LOG="${DPKG_LOG:-/var/log/dpkg.log}"
QUIET_SECONDS="${QUIET_SECONDS:-120}"
MAX_PKGS_PER_SECTION="${MAX_PKGS_PER_SECTION:-60}"

BOT_TOKEN="${BOT_TOKEN:-}"
CHAT_ID="${CHAT_ID:-}"

QUEUE_FILE="${INSTALL_DIR}/queue/dpkg.events"
LAST_EVENT_FILE="${INSTALL_DIR}/state/last_event_epoch"
LOCK_FILE="${INSTALL_DIR}/state/lock.flush"

mkdir -p "${INSTALL_DIR}/queue" "${INSTALL_DIR}/state" "${INSTALL_DIR}/log"

exec 9>"${LOCK_FILE}"
flock -n 9 || exit 0

# Require Telegram config
if [[ -z "${BOT_TOKEN}" || -z "${CHAT_ID}" || "${BOT_TOKEN}" == "CHANGE_ME" || "${CHAT_ID}" == "CHANGE_ME" ]]; then
  # Don't spam logs; just do nothing until configured
  exit 0
fi

# Nothing queued
[[ -s "${QUEUE_FILE}" ]] || exit 0
[[ -f "${LAST_EVENT_FILE}" ]] || exit 0

now="$(date +%s)"
last="$(cat "${LAST_EVENT_FILE}" 2>/dev/null || echo 0)"

# Wait for quiet period
if (( now - last < QUIET_SECONDS )); then
  exit 0
fi

# Build unique package lists, drop arch suffix
installs="$(awk '$3=="install"{print $4}' "${QUEUE_FILE}" | sed 's/:.*$//' | sort -u)"
upgrades="$(awk '$3=="upgrade"{print $4}' "${QUEUE_FILE}" | sed 's/:.*$//' | sort -u)"
removes="$(awk '$3=="remove"{print $4}' "${QUEUE_FILE}" | sed 's/:.*$//' | sort -u)"

host="$(hostname)"
ts="$(date -Is)"

# Telegram Markdown: escape special chars to avoid formatting breaks
md_escape() {
  # Escapes: _ * [ ] ( ) ~ ` > # + - = | { } . !
  sed -e 's/\\/\\\\/g' \
      -e 's/_/\\_/g'  -e 's/\*/\\*/g' -e 's/\[/\\[/g' -e 's/\]/\\]/g' \
      -e 's/(/\\(/g'  -e 's/)/\\)/g' -e 's/~/\\~/g'  -e 's/`/\\`/g' \
      -e 's/>/\\>/g'  -e 's/#/\\#/g'  -e 's/+/\\+/g' -e 's/-/\\-/g' \
      -e 's/=/\\=/g'  -e 's/|/\\|/g'  -e 's/{/\\{/g' -e 's/}/\\}/g' \
      -e 's/\./\\./g' -e 's/!/\\!/g'
}

format_list() {
  local title="$1"
  local list="$2"
  local max="$3"
  local count
  count="$(printf "%s\n" "${list}" | sed '/^$/d' | wc -l | awk '{print $1}')"

  echo "${title}:"
  if [[ "${count}" -eq 0 ]]; then
    echo " - none"
    return
  fi

  if [[ "${count}" -le "${max}" ]]; then
    printf "%s\n" "${list}" | sed '/^$/d' | sed 's/^/ - /'
  else
    printf "%s\n" "${list}" | sed '/^$/d' | head -n "${max}" | sed 's/^/ - /'
    echo " - … (+$((count - max)) more)"
  fi
}

msg_raw="$(cat <<EOF
📦 Package changes on ${host}
🕒 ${ts}

$(format_list "Installs" "${installs}" "${MAX_PKGS_PER_SECTION}")
$(format_list "Upgrades" "${upgrades}" "${MAX_PKGS_PER_SECTION}")
$(format_list "Removals" "${removes}" "${MAX_PKGS_PER_SECTION}")
EOF
)"

msg="$(printf "%s" "${msg_raw}" | md_escape)"

# Send via Telegram (MarkdownV2 for reliable escaping)
curl -fsS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "text=${msg}" \
  -d "parse_mode=MarkdownV2" \
  >/dev/null

# Clear queue after successful send
: > "${QUEUE_FILE}"
