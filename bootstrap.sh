#!/usr/bin/env bash
set -e

REPO="MasterHide/pkgwatch"
BRANCH="main"
TMP="/tmp/pkgwatch.$$"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP"
cd "$TMP"

# Download tarball (no git needed)
curl -fsSL "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" -o pkgwatch.tgz
tar -xzf pkgwatch.tgz
cd "pkgwatch-${BRANCH}"

# Ensure required tools
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y dos2unix curl coreutils util-linux auditd >/dev/null
else
  echo "Unsupported system: apt-get not found"
  exit 1
fi

# Auto-fix CRLF -> LF for all relevant files
find . -type f \( -name "*.sh" -o -name "*.service" -o -name "*.timer" -o -name "*.path" \) -print0 \
  | xargs -0 dos2unix -q || true

# Run the real installer from the fixed files
chmod +x ./install.sh 2>/dev/null || true
chmod +x ./pkgwatch_install.sh 2>/dev/null || true

if [[ -f ./install.sh ]]; then
  bash ./install.sh
elif [[ -f ./pkgwatch_install.sh ]]; then
  bash ./pkgwatch_install.sh
else
  echo "No installer found (install.sh / pkgwatch_install.sh)."
  exit 1
fi
