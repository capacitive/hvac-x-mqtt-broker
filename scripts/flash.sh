#!/usr/bin/env bash
set -euo pipefail

# Flash the built image to an SD card device safely.
# Usage: sudo ./scripts/flash.sh <image.img>
# Device selection is always interactive.

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

if [[ -z "${1:-}" ]]; then
  : "${APP_NAME:?APP_NAME is required when image path is not provided}"
  IMG_PATH="${APP_NAME}.img"
else
  IMG_PATH="$1"
fi

# Always perform interactive device selection
# Ensure image exists before we compute size/filters
if [[ ! -f "$IMG_PATH" ]]; then
  echo "Error: Image not found: $IMG_PATH" >&2
  exit 1
fi

# Compute minimum device size (image + 100MB buffer)
IMAGE_SIZE_MB=$(du -m "$IMG_PATH" | cut -f1)
MIN_SIZE_MB=$((IMAGE_SIZE_MB + 100))

scan_devices() {
  USB_DEVICES=()
  while IFS= read -r line; do
    # Prefer key=value pairs for robust parsing
    # Example: NAME="sdb" MODEL="SanDisk Extreme" SIZE="59.5G" TRAN="usb"
    eval "$line"
    # Require USB transport and size >= MIN_SIZE_MB
    if [[ "${TRAN:-}" == "usb" ]]; then
      size_mb=0
      case "${SIZE:-}" in
        *T) base=${SIZE%T}; size_mb=$(awk "BEGIN{print int($base*1024*1024)}") ;;
        *G) base=${SIZE%G}; size_mb=$(awk "BEGIN{print int($base*1024)}") ;;
        *M) base=${SIZE%M}; size_mb=$(awk "BEGIN{print int($base)}") ;;
        *)  size_mb=0 ;;
      esac
      if [[ $size_mb -ge $MIN_SIZE_MB ]]; then
        USB_DEVICES+=("${NAME:-}:${MODEL:-}:${SIZE:-}")
      fi
    fi
  done < <(lsblk -d -P -o NAME,MODEL,SIZE,TRAN -e7)
}

echo "Scanning for USB mass storage devices (min ${MIN_SIZE_MB}MB)..."
scan_devices

if [[ ${#USB_DEVICES[@]} -eq 0 ]]; then
  echo "No suitable devices found. Insert a USB device or press 'm' for manual entry..."

  MONITORING=0
  if command -v inotifywait >/dev/null 2>&1; then
    MONITORING=1
    {
      inotifywait -q -m /dev -e create 2>/dev/null | while read _ _ file; do
        if [[ $file == sd* ]]; then
          sleep 1
          scan_devices
          if [[ ${#USB_DEVICES[@]} -gt 0 ]]; then
            echo -e "\nUSB device detected."
            pkill -P $$ inotifywait 2>/dev/null || true
            break
          fi
        fi
      done
    } &
    MONITOR_PID=$!
  fi

  while [[ ${#USB_DEVICES[@]} -eq 0 ]]; do
    # Non-fatal read for 'm'
    set +e
    read -r -t 1 -n 1 input
    rc=$?
    set -e
    if [[ $rc -eq 0 && "$input" == "m" ]]; then
      [[ $MONITORING -eq 1 ]] && kill "$MONITOR_PID" 2>/dev/null || true
      break
    fi
    scan_devices
  done

  [[ $MONITORING -eq 1 ]] && kill "$MONITOR_PID" 2>/dev/null || true
fi

if [[ ${#USB_DEVICES[@]} -eq 0 ]]; then
  read -r -p "Device path (e.g., /dev/sdb): " USB_DEVICE
  DEVICE="$USB_DEVICE"
else
  while true; do
    echo "Found USB devices:"
    for i in "${!USB_DEVICES[@]}"; do
      IFS=':' read -r dev model size <<< "${USB_DEVICES[$i]}"
      echo "$((i+1))) $model $size (/dev/$dev)"
    done
    echo "$(( ${#USB_DEVICES[@]} + 1 ))) Manual entry"
    echo "r) Rescan devices"
    read -r -p "Select device [1-$(( ${#USB_DEVICES[@]} + 1 ))], 'r' to rescan: " choice
    if [[ "$choice" == "r" ]]; then
      echo "Rescanning..."
      scan_devices
      continue
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 && $choice -le ${#USB_DEVICES[@]} ]]; then
      IFS=':' read -r dev model size <<< "${USB_DEVICES[$((choice-1))]}"
      DEVICE="/dev/$dev"
      echo "Selected: $model $size ($DEVICE)"
      read -r -p "Confirm selection? [y/N/r=reselect]: " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        break
      elif [[ "$confirm" == "r" ]]; then
        continue
      else
        echo "Selection cancelled. Choose again."
        continue
      fi
    elif [[ "$choice" -eq $(( ${#USB_DEVICES[@]} + 1 )) ]]; then
      read -r -p "Device path (e.g., /dev/sdb): " USB_DEVICE
      DEVICE="$USB_DEVICE"
      break
    else
      echo "Invalid selection. Try again."
      continue
    fi
  done
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

