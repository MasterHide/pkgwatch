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

STATE_FILE="${INSTALL_DIR}/state/audit.cursor"
LOCK_FILE="${INSTALL_DIR}/state/lock.auditflush"

mkdir -p "${INSTALL_DIR}/state" "${INSTALL_DIR}/log"

exec 9>"${LOCK_FILE}"
flock -n 9 || exit 0

# Cursor is a human timestamp ausearch understands: "YYYY-MM-DD HH:MM:SS"
# If missing, start from "now-10m" to avoid flooding on first run.
last_ts="now-10m"
if [[ -f "${STATE_FILE}" ]]; then
  last_ts="$(cat "${STATE_FILE}" || echo "now-10m")"
fi

# Always advance cursor first (prevents duplicates if send fails)
now_ts="$(date '+%Y-%m-%d %H:%M:%S')"
echo "${now_ts}" > "${STATE_FILE}"

# Collect audit events since last cursor (keys from audit rules)
out="$(
  {
    ausearch -k pkgwatch_git     -ts "${last_ts}" 2>/dev/null || true
    ausearch -k pkgwatch_net     -ts "${last_ts}" 2>/dev/null || true
    ausearch -k pkgwatch_shell   -ts "${last_ts}" 2>/dev/null || true
    ausearch -k pkgwatch_persist -ts "${last_ts}" 2>/dev/null || true
  } | tail -n 250
)"

[[ -n "${out// }" ]] || exit 0

host="$(hostname)"
ts="$(date -Is)"

# Telegram MarkdownV2 escape
md_escape() {
  sed -e 's/\\/\\\\/g' \
      -e 's/_/\\_/g'  -e 's/\*/\\*/g' -e 's/\[/\\[/g' -e 's/\]/\\]/g' \
      -e 's/(/\\(/g'  -e 's/)/\\)/g' -e 's/~/\\~/g'  -e 's/`/\\`/g' \
      -e 's/>/\\>/g'  -e 's/#/\\#/g'  -e 's/+/\\+/g' -e 's/-/\\-/g' \
      -e 's/=/\\=/g'  -e 's/|/\\|/g'  -e 's/{/\\{/g' -e 's/}/\\}/g' \
      -e 's/\./\\./g' -e 's/!/\\!/g'
}

msg_raw="🛡 Script/Repo activity on ${host}
🕒 ${ts}

Last audit events (trimmed):
${out}
"

msg="$(printf "%s" "${msg_raw}" | md_escape)"

# Explicit form encoding
curl -fsS -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "chat_id=${CHAT_ID}" \
  --data-urlencode "text=${msg}" \
  --data-urlencode "parse_mode=MarkdownV2" \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  >/dev/null
