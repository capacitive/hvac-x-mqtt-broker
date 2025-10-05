#!/usr/bin/env bash
set -euo pipefail
# Buildroot post-image hook for tardigrade: quiet boot and cmdline/config hygiene

# Expected env from Buildroot:
#  - BINARIES_DIR: directory for final images (contains rpi-firmware/*)
#  - HOST_DIR, TARGET_DIR, STAGING_DIR also available but unused here

CMDLINE_FILE="${BINARIES_DIR:-}/rpi-firmware/cmdline.txt"
if [[ -n "${BINARIES_DIR:-}" && -f "$CMDLINE_FILE" ]]; then
  orig_line=$(cat "$CMDLINE_FILE" || true)
  line="$orig_line"
  # Drop serial console spam tokens
  line=${line//console=serial0,115200/}
  line=${line//console=ttyAMA0,115200/}
  # Remove any existing loglevel and quiet to re-add cleanly
  line=$(printf '%s\n' "$line" | sed -E 's/(^| )loglevel=[0-9]( |$)/ /g; s/(^| )quiet( |$)/ /g')
  # Ensure console=tty1 present
  if ! printf '%s\n' "$line" | grep -q 'console=tty1'; then
    line+=" console=tty1"
  fi
  # Add quiet and desired loglevel
  line+=" quiet loglevel=3"
  # Add rootfs mount flags to reduce metadata writes
  if ! printf '%s\n' "$line" | grep -q 'rootflags='; then
    line+=" rootflags=noatime,nodiratime"
  fi
  # Squeeze whitespace
  line=$(printf '%s\n' "$line" | tr -s ' ')
  printf '%s\n' "$line" > "$CMDLINE_FILE"
  echo "[tardigrade/post-image] Updated cmdline.txt -> $(basename "$CMDLINE_FILE")"
else
  echo "[tardigrade/post-image] WARN: cmdline.txt not found; BINARIES_DIR='${BINARIES_DIR:-}'" >&2
fi

# Also tweak rpi-firmware/config.txt for faster, quieter boot
CONF_FILE="${BINARIES_DIR:-}/rpi-firmware/config.txt"
if [[ -n "${BINARIES_DIR:-}" && -f "$CONF_FILE" ]]; then
  # Ensure/replace key settings
  ensure_kv() {
    local key="$1"; shift
    local val="$*"
    if grep -qE "^${key}=" "$CONF_FILE"; then
      sed -i -E "s|^(${key}=).*|\1${val}|" "$CONF_FILE"
    else
      printf "%s=%s\n" "$key" "$val" >> "$CONF_FILE"
    fi
  }
  ensure_kv boot_delay 0
  ensure_kv disable_splash 1
  ensure_kv gpu_mem 16
  echo "[tardigrade/post-image] Updated config.txt -> $(basename "$CONF_FILE")"
else
  echo "[tardigrade/post-image] WARN: config.txt not found; BINARIES_DIR='${BINARIES_DIR:-}'" >&2
fi

