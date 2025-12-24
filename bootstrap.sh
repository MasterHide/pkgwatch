#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/MasterHide/pkgwatch.git"
TMPDIR="$(mktemp -d /tmp/pkgwatch.XXXXXX)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "[pkgwatch] ERROR: run as root"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl git

git clone --depth 1 "$REPO" "$TMPDIR/pkgwatch"
cd "$TMPDIR/pkgwatch"

# Normalize CRLF -> LF (fixes your pipefail/\r errors automatically)
find . -type f \( -name "*.sh" -o -name "*.service" -o -name "*.timer" -o -name "*.path" -o -name "*.conf" -o -name "*.example" -o -name "README.md" \) \
  -print0 | while IFS= read -r -d '' f; do
    sed -i 's/\r$//' "$f"
  done

chmod +x ./pkgwatch_install.sh
./pkgwatch_install.sh
