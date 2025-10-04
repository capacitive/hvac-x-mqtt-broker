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

# App naming (APP_NAME is required; used for binary, /opt dir, and service name)
: "${APP_NAME:?APP_NAME is required (set via Makefile or env)}"

# Defaults
STATIC_IP="${STATIC_IP:-192.168.1.23}"
MQTT_PORT="${MQTT_PORT:-1883}"
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
DNS="${DNS:-1.1.1.1 8.8.8.8}"
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PSK="${WIFI_PSK:-}"
HOSTNAME="${HOSTNAME:-hvac-zero}"
IMAGE_URL="${IMAGE_URL:-https://downloads.raspberrypi.com/raspios_lite_armhf_latest}"
OUTPUT_IMG="$PROJECT_DIR/$APP_NAME.img"

# Semantic versioning from VERSION file
VERSION_FILE="$PROJECT_DIR/VERSION"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Error: VERSION file not found at $VERSION_FILE" >&2
  echo "Create it with: echo '0.1.0' > VERSION" >&2
  exit 1
fi
VERSION="$(cat "$VERSION_FILE")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: VERSION must be semantic (e.g., 0.1.0), got: $VERSION" >&2
  exit 1
fi

# Use prebuilt ARMv6 binary (built by Makefile's build-arm). Avoid building under sudo.
BIN_PATH="$BUILD_DIR/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Error: $BIN_PATH not found. Run 'make build-arm' before 'make image'." >&2
  exit 1
fi
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

echo "Configuring hostname, SSH, networking, minimal user, and application..."
# Enable SSH by creating an empty file in /boot
: > "$BOOT_MNT/ssh"

# Minimal user provisioning inside the image (single user, single private group)
RPI_USER="${RPI_USER:-}"
RPI_PASS="${RPI_PASS:-}"
if [[ -n "$RPI_USER" && -n "$RPI_PASS" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    USER_HASH="$(openssl passwd -6 "$RPI_PASS")"
  else
    echo "Error: openssl is required to generate password hash" >&2
    exit 1
  fi
  PASSWD_FILE="$ROOT_MNT/etc/passwd"
  SHADOW_FILE="$ROOT_MNT/etc/shadow"
  GROUP_FILE="$ROOT_MNT/etc/group"
  # Find next free UID/GID >=1000
  NEXT_UID=$(awk -F: '($3>=1000 && $3<65534){if($3>m)m=$3} END{print (m?m:999)+1}' "$PASSWD_FILE")
  NEXT_GID=$(awk -F: '($3>=1000 && $3<65534){if($3>m)m=$3} END{print (m?m:999)+1}' "$GROUP_FILE")
  # Create group and user with no supplementary groups
  echo "$RPI_USER:x:$NEXT_GID:" >> "$GROUP_FILE"
  echo "$RPI_USER:x:$NEXT_UID:$NEXT_GID::/home/$RPI_USER:/bin/bash" >> "$PASSWD_FILE"
  echo "$RPI_USER:$USER_HASH:19000:0:99999:7:::" >> "$SHADOW_FILE"
  # Home directory and optional SSH key
  mkdir -p "$ROOT_MNT/home/$RPI_USER"
  chown -R "$NEXT_UID:$NEXT_GID" "$ROOT_MNT/home/$RPI_USER"
  if [[ -n "${RPI_SSH_PUBKEY:-}" ]]; then
    mkdir -p "$ROOT_MNT/home/$RPI_USER/.ssh"
    echo "$RPI_SSH_PUBKEY" > "$ROOT_MNT/home/$RPI_USER/.ssh/authorized_keys"
    chmod 700 "$ROOT_MNT/home/$RPI_USER/.ssh"
    chmod 600 "$ROOT_MNT/home/$RPI_USER/.ssh/authorized_keys"
    chown -R "$NEXT_UID:$NEXT_GID" "$ROOT_MNT/home/$RPI_USER/.ssh"
  fi
fi
# Disable first-boot wizard and remove default 'pi' user if present
if [[ -n "$RPI_USER" ]]; then
  # Remove legacy default user 'pi' to avoid rename prompts
  sed -i -e '/^pi:/d' "$ROOT_MNT/etc/passwd" 2>/dev/null || true
  sed -i -e '/^pi:/d' "$ROOT_MNT/etc/shadow" 2>/dev/null || true
  sed -i -e '/^pi:/d' "$ROOT_MNT/etc/group" 2>/dev/null || true
  rm -rf "$ROOT_MNT/home/pi" 2>/dev/null || true

  # Proactively disable first-boot services if present
  for d in \
    "$ROOT_MNT/etc/systemd/system/multi-user.target.wants" \
    "$ROOT_MNT/etc/systemd/system/sysinit.target.wants" \
    "$ROOT_MNT/etc/systemd/system" \
  ; do
    rm -f "$d/raspi-config.service" 2>/dev/null || true
    rm -f "$d/raspi-firstboot.service" 2>/dev/null || true
    rm -f "$d/firstboot.service" 2>/dev/null || true
  done
fi
# Belt-and-suspenders: mask first-boot units and add kernel cmdline masks
# Mask units in rootfs so even if present they won't start
for svc in raspi-config.service firstboot.service raspi-firstboot.service; do
  ln -snf /dev/null "$ROOT_MNT/etc/systemd/system/$svc" 2>/dev/null || true
  rm -f "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/$svc" 2>/dev/null || true
  rm -f "$ROOT_MNT/etc/systemd/system/sysinit.target.wants/$svc" 2>/dev/null || true
  rm -f "$ROOT_MNT/lib/systemd/system/$svc" 2>/dev/null || true
  rm -f "$ROOT_MNT/usr/lib/systemd/system/$svc" 2>/dev/null || true
done
# Also add systemd.mask=... on kernel cmdline to prevent activation at boot
if [ -f "$BOOT_MNT/cmdline.txt" ]; then
  if ! grep -q "systemd.mask=raspi-config.service" "$BOOT_MNT/cmdline.txt"; then
    sed -i 's/$/ systemd.mask=raspi-config.service systemd.mask=firstboot.service systemd.mask=raspi-firstboot.service/' "$BOOT_MNT/cmdline.txt"
  fi
fi



# Optional timezone (e.g., TIMEZONE="America/Los_Angeles")
if [[ -n "${TIMEZONE:-}" ]]; then
  echo "$TIMEZONE" > "$ROOT_MNT/etc/timezone"
  ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$ROOT_MNT/etc/localtime" 2>/dev/null || true
fi

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
# If a minimal user was provisioned, ensure ownership of app tree so the service can read/execute
if [[ -n "$RPI_USER" ]]; then
  # Resolve UID:GID for chown
  _UID=$(awk -F: -v u="$RPI_USER" '($1==u){print $3}' "$ROOT_MNT/etc/passwd" )
  _GID=$(awk -F: -v g="$RPI_USER" '($1==g){print $3}' "$ROOT_MNT/etc/group" )
  if [[ -n "$_UID" && -n "$_GID" ]]; then
    chown -R "$_UID:$_GID" "$APP_DIR"
  fi
fi

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
User=${RPI_USER:-root}
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

