#!/usr/bin/env bash
set -euo pipefail
# Buildroot post-image hook for tardigrade: ensure our custom cmdline/config are used

# Expected env from Buildroot:
#  - BINARIES_DIR: directory for final images (contains rpi-firmware/*)
#  - HOST_DIR: host tools (includes mcopy/mtype from mtools if enabled)
#  - TARGET_DIR, STAGING_DIR available but unused here

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SRC_CMDLINE="$SCRIPT_DIR/cmdline.txt"
SRC_CONFIG="$SCRIPT_DIR/config.txt"
DEST_DIR="${BINARIES_DIR:-}/rpi-firmware"

if [[ -z "${BINARIES_DIR:-}" ]]; then
  echo "[tardigrade/post-image] ERROR: BINARIES_DIR is not set" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

# 1) Copy our source files into the rpi-firmware staging dir (for transparency)
if [[ -f "$SRC_CMDLINE" ]]; then
  install -m 0644 "$SRC_CMDLINE" "$DEST_DIR/cmdline.txt"
  echo "[tardigrade/post-image] Installed cmdline.txt -> $DEST_DIR/cmdline.txt"
else
  echo "[tardigrade/post-image] WARN: missing $SRC_CMDLINE" >&2
fi

if [[ -f "$SRC_CONFIG" ]]; then
  install -m 0644 "$SRC_CONFIG" "$DEST_DIR/config.txt"
  echo "[tardigrade/post-image] Installed config.txt -> $DEST_DIR/config.txt"
else
  echo "[tardigrade/post-image] WARN: missing $SRC_CONFIG" >&2
fi

# 2) If boot.vfat already exists (e.g., upstream post-image ran first), patch it in-place
BOOT_VFAT="${BINARIES_DIR}/boot.vfat"
MCOPY_BIN="${HOST_DIR:-}/bin/mcopy"
if [[ -f "$BOOT_VFAT" ]]; then
  if [[ -x "$MCOPY_BIN" ]]; then
    if [[ -f "$SRC_CMDLINE" ]]; then
      "$MCOPY_BIN" -i "$BOOT_VFAT" -o "$SRC_CMDLINE" ::cmdline.txt
      echo "[tardigrade/post-image] Updated boot.vfat::cmdline.txt"
    fi
    if [[ -f "$SRC_CONFIG" ]]; then
      "$MCOPY_BIN" -i "$BOOT_VFAT" -o "$SRC_CONFIG" ::config.txt
      echo "[tardigrade/post-image] Updated boot.vfat::config.txt"
    fi
  else
    echo "[tardigrade/post-image] WARN: mcopy not found at $MCOPY_BIN; boot.vfat not patched" >&2
  fi
fi
