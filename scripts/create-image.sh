#!/usr/bin/env bash
set -euo pipefail

# Create a bootable Raspberry Pi Zero W image (Pi OS Lite based) with this app pre-installed.
# Configurable via env vars:
#   STATIC_IP=192.168.1.23  MQTT_PORT=1883  ROUTER_IP=192.168.1.1  DNS="1.1.1.1 8.8.8.8"
#   WIFI_SSID=your-ssid     WIFI_PSK=your-pass   HOSTNAME=hvac-zero
#   IMAGE_URL overrides default download (e.g., legacy):
#     https://downloads.raspberrypi.com/raspios_lite_armhf_latest
#     https://downloads.raspberrypi.com/raspios_lite_armhf_legacy_latest
# Output image: ./pi-hvac.img

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
CACHE_DIR="$PROJECT_DIR/.cache"
mkdir -p "$BUILD_DIR" "$CACHE_DIR"

# Defaults
STATIC_IP="${STATIC_IP:-192.168.1.23}"
MQTT_PORT="${MQTT_PORT:-1883}"
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
DNS="${DNS:-1.1.1.1 8.8.8.8}"
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PSK="${WIFI_PSK:-}"
HOSTNAME="${HOSTNAME:-hvac-zero}"
IMAGE_URL="${IMAGE_URL:-https://downloads.raspberrypi.com/raspios_lite_armhf_latest}"
OUTPUT_IMG="$PROJECT_DIR/pi-hvac.img"
VERSION_FILE="$PROJECT_DIR/VERSION"
VERSION="${VERSION:-}"
# App naming (shared for binary name, directory under /opt, and service name)
APP_NAME="${APP_NAME:-mqtt-broker}"

if [[ -z "$VERSION" ]]; then
  if [[ -f "$VERSION_FILE" ]]; then VERSION="$(cat "$VERSION_FILE")"; else VERSION="0.1.0"; fi
fi

# Build Go binary for ARMv6 (Pi Zero W)
GO_BIN="${GO_BIN:-go}"
echo "Building $APP_NAME for ARMv6 (GOARM=6)..."
mkdir -p "$BUILD_DIR"
( cd "$PROJECT_DIR" && \
  CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=6 "$GO_BIN" build -o "$BUILD_DIR/$APP_NAME" ./ )
cp -f "$PROJECT_DIR/broker-config.yml" "$BUILD_DIR/broker-config.yml"

# Fetch Raspberry Pi OS Lite image (cached)
XZ_PATH="$CACHE_DIR/raspios-lite.img.xz"
echo "Downloading Raspberry Pi OS Lite (cached at $XZ_PATH) if missing..."
if [[ ! -f "$XZ_PATH" ]]; then
  curl -L "$IMAGE_URL" -o "$XZ_PATH"
else
  echo "Using cached image: $XZ_PATH"
fi

# Extract to working image
TMP_IMG="$BUILD_DIR/base.img"
if [[ -f "$TMP_IMG" ]]; then rm -f "$TMP_IMG"; fi
unxz -c "$XZ_PATH" > "$TMP_IMG"
cp -f "$TMP_IMG" "$OUTPUT_IMG"
echo "Working image at: $OUTPUT_IMG"

cleanup() {
  set +e
  echo "Cleaning up mounts..."
  sync
  [[ -n "${BOOT_MNT:-}" && -d "$BOOT_MNT" ]] && umount "$BOOT_MNT" 2>/dev/null || true
  [[ -n "${ROOT_MNT:-}" && -d "$ROOT_MNT" ]] && umount "$ROOT_MNT" 2>/dev/null || true
  if [[ -n "${LOOP_DEV:-}" ]]; then
    losetup -d "$LOOP_DEV" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Map partitions
LOOP_DEV="$(losetup --find --show -P "$OUTPUT_IMG")"
BOOT_PART="${LOOP_DEV}p1"
ROOT_PART="${LOOP_DEV}p2"
# Some systems name partitions like /dev/loop0p1; others use /dev/loop0p1 consistently with -P
if [[ ! -b "$BOOT_PART" || ! -b "$ROOT_PART" ]]; then
  # Fallback for systems where partitions appear as /dev/loop0p1 already handled; otherwise try kpartx
  echo "Error: Partition block devices not found (expected $BOOT_PART and $ROOT_PART)."
  exit 1
fi

BOOT_MNT="$(mktemp -d)"
ROOT_MNT="$(mktemp -d)"
mount "$BOOT_PART" "$BOOT_MNT"
mount "$ROOT_PART" "$ROOT_MNT"

echo "Configuring hostname, SSH, networking, and application..."
# Enable SSH by creating an empty file in /boot
: > "$BOOT_MNT/ssh"

# Hostname
echo "$HOSTNAME" > "$ROOT_MNT/etc/hostname"
sed -i "/127.0.1.1/d" "$ROOT_MNT/etc/hosts"
echo "127.0.1.1    $HOSTNAME" >> "$ROOT_MNT/etc/hosts"

# Static IP for wlan0 via dhcpcd
cat >> "$ROOT_MNT/etc/dhcpcd.conf" <<EOF

# HVAC MQTT static IP
interface wlan0
static ip_address=$STATIC_IP/24
static routers=$ROUTER_IP
static domain_name_servers=$DNS
EOF

# Optional Wi-Fi config via wpa_supplicant (placed in /boot for first-boot copy)
if [[ -n "$WIFI_SSID" && -n "$WIFI_PSK" ]]; then
  cat > "$BOOT_MNT/wpa_supplicant.conf" <<EOF
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$WIFI_SSID"
    psk="$WIFI_PSK"
}
EOF
fi

# Install application layout with A/B-friendly structure
APP_DIR="$ROOT_MNT/opt/$APP_NAME"
REL_DIR="$APP_DIR/releases/$VERSION"
mkdir -p "$REL_DIR"
install -m 0755 "$BUILD_DIR/$APP_NAME" "$REL_DIR/$APP_NAME"
install -m 0644 "$BUILD_DIR/broker-config.yml" "$REL_DIR/broker-config.yml"
# Current symlink and version markers
ln -snf "$REL_DIR" "$APP_DIR/current"
echo "$VERSION" > "$APP_DIR/VERSION"

# Systemd service
mkdir -p "$ROOT_MNT/etc/systemd/system"
SERVICE_PATH="$ROOT_MNT/etc/systemd/system/$APP_NAME.service"
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=$APP_NAME service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/$APP_NAME/current
ExecStart=/opt/$APP_NAME/current/$APP_NAME
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Enable service on boot
mkdir -p "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
ln -snf ../$APP_NAME.service "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/$APP_NAME.service"

# Update MQTT port in config inside the image
# Overwrite port in broker-config.yml within current release
sed -i "s/^\(\s*port:\s*\).*/\1$MQTT_PORT/" "$REL_DIR/broker-config.yml"

sync
umount "$BOOT_MNT" && rmdir "$BOOT_MNT"; BOOT_MNT=""
umount "$ROOT_MNT" && rmdir "$ROOT_MNT"; ROOT_MNT=""
losetup -d "$LOOP_DEV"; LOOP_DEV=""

trap - EXIT

echo "\n✓ Image created: $OUTPUT_IMG"
echo "  - Hostname: $HOSTNAME"
echo "  - Static IP: $STATIC_IP (wlan0)"
echo "  - MQTT Port: $MQTT_PORT"
echo "  - OTA layout: /opt/$APP_NAME/releases/$VERSION, current -> releases/$VERSION"
echo "  - SSH: enabled"

