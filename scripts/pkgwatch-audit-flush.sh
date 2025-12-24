#!/usr/bin/env bash
set -eu
( set -o pipefail ) 2>/dev/null && set -o pipefail || true

INSTALL_DIR="/opt/pkgwatch"
CONF="${INSTALL_DIR}/etc/pkgwatch.conf"
[[ -r "${CONF}" ]] || exit 0
# shellcheck disable=SC1090
source <(sed 's/\r$//' "${CONF}")

BOT_TOKEN="${BOT_TOKEN:-}"
CHAT_ID="${CHAT_ID:-}"
[[ -n "${BOT_TOKEN}" && -n "${CHAT_ID}" && "${BOT_TOKEN}" != "CHANGE_ME" && "${CHAT_ID}" != "CHANGE_ME" ]] || exit 0

STATE_FILE="${INSTALL_DIR}/state/audit.cursor"
LOCK_FILE="${INSTALL_DIR}/state/lock.auditflush"

mkdir -p "${INSTALL_DIR}/state" "${INSTALL_DIR}/log"

exec 9>"${LOCK_FILE}"
flock -n 9 || exit 0

last_ts="now-10m"
if [[ -f "${STATE_FILE}" ]]; then
  last_ts="$(cat "${STATE_FILE}" || echo "now-10m")"
fi

# advance cursor early to avoid duplicates
now_ts="$(date '+%Y-%m-%d %H:%M:%S')"
echo "${now_ts}" > "${STATE_FILE}"

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
MAX_CHARS=3800
if (( ${#msg} > MAX_CHARS )); then
  msg="${msg:0:MAX_CHARS}..."
fi

curl -fsS -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "chat_id=${CHAT_ID}" \
  --data-urlencode "text=${msg}" \
  --data-urlencode "parse_mode=MarkdownV2" \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  >/dev/null
