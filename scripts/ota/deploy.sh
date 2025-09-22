#!/usr/bin/env bash
set -euo pipefail

# OTA deployment to a running Raspberry Pi Zero W over SSH.
# Performs atomic release install with checksum verification and rollback on failure.
#
# Env/config:
#   PI_HOST=192.168.1.23    PI_USER=${PI_USER:-root}
#   SSH_OPTS="-o StrictHostKeyChecking=no"
#   VERSION=1.2.3            (default: date-based)
#   PORT=1883                (for basic health check)
#
# Usage: ./scripts/ota/deploy.sh [host]

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
PI_HOST="${1:-${PI_HOST:-192.168.1.23}}"
PI_USER="${PI_USER:-root}"
SSH_OPTS=${SSH_OPTS:-"-o StrictHostKeyChecking=no"}
VERSION="${VERSION:-$(date +%Y%m%d-%H%M%S)}"
PORT="${PORT:-1883}"

# Build ARMv6 binary
mkdir -p "$BUILD_DIR"
echo "Building ARMv6 binary for OTA..."
( cd "$PROJECT_DIR" && CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=6 go build -o "$BUILD_DIR/mqtt-broker" ./ )
cp -f "$PROJECT_DIR/broker-config.yml" "$BUILD_DIR/broker-config.yml"

# Package release
REL_DIR="$BUILD_DIR/release-$VERSION"
PKG="$BUILD_DIR/mqtt-broker-$VERSION.tar.gz"
rm -rf "$REL_DIR"
mkdir -p "$REL_DIR"
cp "$BUILD_DIR/mqtt-broker" "$REL_DIR/"
cp "$BUILD_DIR/broker-config.yml" "$REL_DIR/"
( cd "$REL_DIR" && sha256sum mqtt-broker broker-config.yml > SHA256SUMS )
( cd "$BUILD_DIR" && tar -czf "$PKG" "release-$VERSION" )

REMOTE_BASE="/opt/hvac-mqtt"
REMOTE_REL="$REMOTE_BASE/releases/$VERSION"

# Upload and install atomically
ssh $SSH_OPTS "$PI_USER@$PI_HOST" "sudo mkdir -p '$REMOTE_REL' '$REMOTE_BASE/tmp' '$REMOTE_BASE/releases'"
scp $SSH_OPTS "$PKG" "$PI_USER@$PI_HOST:$REMOTE_BASE/tmp/"

ssh $SSH_OPTS "$PI_USER@$PI_HOST" bash -s <<EOF
set -euo pipefail
TMP_PKG=
TMP_PKG="
$REMOTE_BASE/tmp/$(basename "$PKG")
"
mkdir -p "$REMOTE_REL"
cd "$REMOTE_BASE/tmp"
tar -xzf "
$(basename "$PKG")
" -C "$REMOTE_BASE/releases/"
# Verify checksums
cd "$REMOTE_REL"
sha256sum -c SHA256SUMS
# Prepare rollback info
if [[ -L "$REMOTE_BASE/current" ]]; then
  CURRENT_REAL="
$(readlink -f "$REMOTE_BASE/current")
"
  echo "$CURRENT_REAL" > "$REMOTE_BASE/previous"
fi
# Activate new release atomically via symlink swap
ln -snf "$REMOTE_REL" "$REMOTE_BASE/current"
# Restart service
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  systemctl restart hvac-mqtt.service
else
  # Fallback: try killing existing process (very minimal systems)
  pkill -f "/opt/hvac-mqtt/current/mqtt-broker" || true
  nohup /opt/hvac-mqtt/current/mqtt-broker >/var/log/hvac-mqtt.log 2>&1 &
fi
EOF

# Basic health check: verify port open
sleep 2
echo "Checking MQTT port $PORT on $PI_HOST..."
if command -v nc >/dev/null 2>&1; then
  if ! nc -z -w3 "$PI_HOST" "$PORT"; then
    echo "Health check failed; attempting rollback..." >&2
    ./scripts/ota/rollback.sh "$PI_HOST"
    exit 1
  fi
else
  echo "nc not available locally; skipping port check."
fi

echo "\n✓ OTA deployment $VERSION completed successfully."

