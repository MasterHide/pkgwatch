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

# cursor = last processed audit event epoch seconds
last="0"
[[ -f "${STATE_FILE}" ]] && last="$(cat "${STATE_FILE}" || echo 0)"
now="$(date +%s)"

# Get audit events since last cursor (requires auditd running)
# We search by keys we set in rules
out="$(
  {
    ausearch -k pkgwatch_git   -ts "${last}" 2>/dev/null || true
    ausearch -k pkgwatch_net   -ts "${last}" 2>/dev/null || true
    ausearch -k pkgwatch_shell -ts "${last}" 2>/dev/null || true
    ausearch -k pkgwatch_persist -ts "${last}" 2>/dev/null || true
  } | tail -n 250
)"

# advance cursor early to avoid duplicates on failure
echo "${now}" > "${STATE_FILE}"

[[ -n "${out// }" ]] || exit 0

host="$(hostname)"
ts="$(date -Is)"

# Simple Telegram MarkdownV2 escape
md_escape() {
  sed -e 's/\\/\\\\/g' \
      -e 's/_/\\_/g'  -e 's/\*/\\*/g' -e 's/\[/\\[/g' -e 's/\]/\\]/g' \
      -e 's/(/\\(/g'  -e 's/)/\\)/g' -e 's/~/\\~/g'  -e 's/`/\\`/g' \
      -e 's/>/\\>/g'  -e 's/#/\\#/g'  -e 's/+/\\+/g' -e 's/-/\\-/g' \
      -e 's/=/\\=/g'  -e 's/|/\\|/g'  -e 's/{/\\{/g' -e 's/}/\\}/g' \
      -e 's/\./\\./g' -e 's/!/\\!/g'
}

msg_raw="🛡 *Script/Repo activity* on ${host}
🕒 ${ts}

Last audit events (trimmed):
${out}
"

msg="$(printf "%s" "${msg_raw}" | md_escape)"

curl -fsS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "text=${msg}" \
  -d "parse_mode=MarkdownV2" \
  >/dev/null
