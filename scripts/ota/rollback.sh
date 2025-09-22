#!/usr/bin/env bash
set -euo pipefail

# Roll back to previous release on the Pi (uses /opt/hvac-mqtt/previous symlink target)
# Usage: ./scripts/ota/rollback.sh [host]

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
PI_HOST="${1:-${PI_HOST:-192.168.1.23}}"
PI_USER="${PI_USER:-root}"
SSH_OPTS=${SSH_OPTS:-"-o StrictHostKeyChecking=no"}

ssh $SSH_OPTS "$PI_USER@$PI_HOST" bash -s <<'EOF'
set -euo pipefail
REMOTE_BASE="/opt/hvac-mqtt"
if [[ -f "$REMOTE_BASE/previous" ]]; then
  PREV="$(cat "$REMOTE_BASE/previous")"
  if [[ -d "$PREV" ]]; then
    echo "Rolling back to: $PREV"
    ln -snf "$PREV" "$REMOTE_BASE/current"
    if command -v systemctl >/dev/null 2>&1; then
      systemctl restart hvac-mqtt.service || true
    else
      pkill -f "/opt/hvac-mqtt/current/mqtt-broker" || true
      nohup /opt/hvac-mqtt/current/mqtt-broker >/var/log/hvac-mqtt.log 2>&1 &
    fi
    echo "Rollback complete."
    exit 0
  fi
fi
echo "No previous release recorded or directory missing; cannot rollback." >&2
exit 1
EOF

