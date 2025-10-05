#!/usr/bin/env bash
set -euo pipefail
# Host-side size report for tardigrade images

IMAGES_DIR=".buildroot/output/images"
ROOTFS_IMG="$IMAGES_DIR/rootfs.ext2"
BOOT_IMG="$IMAGES_DIR/boot.vfat"
SD_IMG="$IMAGES_DIR/sdcard.img"

bytes() { stat -c%s "$1" 2>/dev/null || echo 0; }
hsize() { numfmt --to=iec "$1" 2>/dev/null || echo "$1"; }

printf "tardigrade size report (host)\n"
printf "  images dir: %s\n" "$IMAGES_DIR"

if [[ -f "$SD_IMG" ]]; then
  printf "  sdcard.img: %s\n" "$(hsize "$(bytes "$SD_IMG")")"
fi
if [[ -f "$BOOT_IMG" ]]; then
  printf "  boot.vfat:  %s\n" "$(hsize "$(bytes "$BOOT_IMG")")"
fi
if [[ -f "$ROOTFS_IMG" ]]; then
  printf "  rootfs.ext2:%s\n" "$(hsize "$(bytes "$ROOTFS_IMG")")"
fi

# If loop mount support is available, show rootfs contents summary
if command -v lsblk >/dev/null 2>&1 && command -v df >/dev/null 2>&1; then
  echo ""
  echo "Top-level in target (from last build target snapshot):"
  TARGET_DIR=".buildroot/output/target"
  if [[ -d "$TARGET_DIR" ]]; then
    du -sh "$TARGET_DIR"/* 2>/dev/null | sort -h | tail -n 20 || true
  else
    echo "  (target dir missing; build not complete)"
  fi
fi

