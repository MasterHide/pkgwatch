#!/usr/bin/env bash
set -e

REPO="MasterHide/pkgwatch"
BRANCH="main"
TMP="/tmp/pkgwatch.$$"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP"
cd "$TMP"

# Get repo as tarball (no git required)
curl -fsSL "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" -o pkgwatch.tgz
tar -xzf pkgwatch.tgz
cd "pkgwatch-${BRANCH}"

# Ensure deps needed for install + CRLF fix
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y bash curl coreutils util-linux dos2unix auditd git >/dev/null

# Fix CRLF -> LF in repo files before running installer
find . -type f \( -name "*.sh" -o -name "*.service" -o -name "*.timer" -o -name "*.path" -o -name "*.conf*" \) -print0 \
  | xargs -0 dos2unix -q || true

# Run installer
if [[ -f ./install.sh ]]; then
  bash ./install.sh
elif [[ -f ./pkgwatch_install.sh ]]; then
  bash ./pkgwatch_install.sh
else
  echo "ERROR: No installer found (install.sh or pkgwatch_install.sh)."
  exit 1
fi
