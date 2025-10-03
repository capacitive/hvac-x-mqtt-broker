#!/usr/bin/env bash
set -euo pipefail

# Flash the built image to an SD card device safely.
# Usage: sudo ./scripts/flash.sh /dev/sdX  [optional image path]
# Default image: ./pi-hvac.img

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

DEVICE="${1:-}"
if [[ -z "${2:-}" ]]; then
  : "${APP_NAME:?APP_NAME is required when image path is not provided}"
  IMG_PATH="${APP_NAME}.img"
else
  IMG_PATH="$2"
fi

if [[ -z "$DEVICE" ]]; then
  echo "Usage: sudo $0 /dev/sdX [image.img]" >&2
  exit 1
fi

if [[ ! -b "$DEVICE" ]]; then
  echo "Error: $DEVICE is not a block device." >&2
  lsblk
  exit 1
fi

if [[ ! -f "$IMG_PATH" ]]; then
  echo "Error: Image not found: $IMG_PATH" >&2
  exit 1
fi

echo "About to write $IMG_PATH to $DEVICE (this will ERASE it)."
echo -n "Type YES to proceed: "
read -r CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Aborted."
  exit 1
fi

# Unmount any mounted partitions from the device
for p in $(lsblk -ln -o NAME "/dev/$(basename "$DEVICE")" | tail -n +2); do
  mnt="/dev/$p"
  if mount | grep -q "^$mnt "; then
    umount "$mnt"
  fi
  if mount | grep -q "$mnt "; then
    umount -l "$mnt" || true
  fi
done

# Write image
if command -v pv >/dev/null 2>&1; then
  pv "$IMG_PATH" | dd of="$DEVICE" bs=4M conv=fsync status=progress
else
  dd if="$IMG_PATH" of="$DEVICE" bs=4M conv=fsync status=progress
fi
sync

echo ""
echo "\u2713 Flash complete. You can now insert the SD card into the Pi."

