#!/usr/bin/env bash
set -euo pipefail

# Create auditd rules to detect suspicious script installs / persistence patterns

RULES_FILE="/etc/audit/rules.d/pkgwatch.rules"

mkdir -p /etc/audit/rules.d

cat > "${RULES_FILE}" <<'EOF'
# pkgwatch: git activity (repos / scripts)
-w /usr/bin/git -p x -k pkgwatch_git
-w /bin/git -p x -k pkgwatch_git

# pkgwatch: suspicious dirs often used by scripts
-w /usr/local/bin -p wa -k pkgwatch_shell
-w /usr/local/sbin -p wa -k pkgwatch_shell
-w /opt -p wa -k pkgwatch_shell

# pkgwatch: persistence locations
-w /etc/systemd/system -p wa -k pkgwatch_persist
-w /etc/cron.d -p wa -k pkgwatch_persist
-w /etc/crontab -p wa -k pkgwatch_persist
-w /var/spool/cron -p wa -k pkgwatch_persist

# pkgwatch: network fetch tools often used in installers
-w /usr/bin/curl -p x -k pkgwatch_net
-w /usr/bin/wget -p x -k pkgwatch_net
EOF

# Load rules
augenrules --load || true

# Print audit status (helpful diagnostics)
auditctl -s || true
