#!/usr/bin/env bash
set -euo pipefail

# Roll back to previous release on the Pi (uses /opt/hvac-mqtt/previous symlink target)
# Usage: ./scripts/ota/rollback.sh [host]

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
PI_HOST="${1:-${PI_HOST:-192.168.1.23}}"
PI_USER="${PI_USER:-root}"
SSH_OPTS=${SSH_OPTS:-"-o StrictHostKeyChecking=no"}

# App naming (overridable via env or Makefile)
APP_NAME="${APP_NAME:-mqtt-broker}"
APP_DIR="${APP_DIR:-/opt/$APP_NAME}"
SERVICE_NAME="${SERVICE_NAME:-$APP_NAME.service}"
LOG_FILE="${LOG_FILE:-/var/log/$APP_NAME.log}"

ssh $SSH_OPTS "$PI_USER@$PI_HOST" bash -s <<EOF
set -euo pipefail
REMOTE_BASE="$APP_DIR"
if [[ -f "$REMOTE_BASE/previous" ]]; then
  PREV="$(cat "$REMOTE_BASE/previous")"
  if [[ -d "$PREV" ]]; then
    echo "Rolling back to: $PREV"
    ln -snf "$PREV" "$REMOTE_BASE/current"
    if command -v systemctl >/dev/null 2>&1; then
      systemctl restart "$SERVICE_NAME" || true
    else
      pkill -f "$APP_DIR/current/$APP_NAME" || true
      nohup "$APP_DIR/current/$APP_NAME" >"$LOG_FILE" 2>&1 &
    fi
    echo "Rollback complete."
    exit 0
  fi
fi
echo "No previous release recorded or directory missing; cannot rollback." >&2
exit 1
EOF

