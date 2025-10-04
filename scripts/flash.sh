#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo ./scripts/flash.sh <image.img>"
    exit 1
fi

if [ -z "${1:-}" ]; then
    : "${APP_NAME:?APP_NAME is required when image path is not provided}"
    IMG_PATH="${APP_NAME}.img"
else
    IMG_PATH="$1"
fi

if [ ! -f "$IMG_PATH" ]; then
    echo "Image not found: $IMG_PATH"
    exit 1
fi

# Get image size in MB
IMAGE_SIZE_MB=$(du -m "$IMG_PATH" | cut -f1)
MIN_SIZE_MB=$((IMAGE_SIZE_MB + 100))  # Add 100MB buffer

# Function to scan for USB devices
scan_devices() {
    USB_DEVICES=()
    while IFS= read -r line; do
        if [[ $line == *"usb"* ]]; then
            device=$(echo $line | awk '{print $1}')
            model=$(echo $line | awk '{print $2}')
            size=$(echo $line | awk '{print $3}')
            
            # Convert size to MB for comparison
            if [[ $size == *"G" ]]; then
                size_mb=$(echo $size | sed 's/G//' | awk '{print int($1 * 1024)}')
            elif [[ $size == *"M" ]]; then
                size_mb=$(echo $size | sed 's/M//' | awk '{print int($1)}')
            else
                size_mb=0
            fi
            
            # Only include devices with adequate capacity
            if [[ $size_mb -ge $MIN_SIZE_MB ]]; then
                USB_DEVICES+=("$device:$model:$size")
            fi
        fi
    done < <(lsblk -o NAME,MODEL,SIZE,TRAN -e7 | grep -v "^NAME")
}

# Continuous device scanning and in-place UI updates
SCAN_INTERVAL=1
PREV_LIST=""

render_menu() {
    clear
    echo "USB Mass Storage Device Selection (min ${MIN_SIZE_MB}MB)"
    echo "(List updates automatically when devices are inserted/removed)"
    echo
    if [ ${#USB_DEVICES[@]} -eq 0 ]; then
        echo "No suitable devices found. Waiting for USB device..."
        echo "Press 'm' then Enter for manual entry"
    else
        echo "Found USB devices:"
        for i in "${!USB_DEVICES[@]}"; do
            IFS=':' read -r dev model size <<< "${USB_DEVICES[$i]}"
            echo "  $((i+1))) $model ${size} (/dev/$dev)"
        done
        echo "  $((${#USB_DEVICES[@]}+1))) Manual entry"
        echo
        echo -n "Select device [1-$((${#USB_DEVICES[@]}+1)) or 'm']: "
    fi
}

# Initial draw
render_menu

# Main loop: scan, redraw on change, accept input non-blocking
while true; do
    # Scan devices
    scan_devices
    CUR_LIST="$(printf "%s|" "${USB_DEVICES[@]}")"

    # Redraw only if changed
    if [[ "$CUR_LIST" != "$PREV_LIST" ]]; then
        PREV_LIST="$CUR_LIST"
        render_menu
    fi

    # Read input with short timeout so we keep scanning
    if [ ${#USB_DEVICES[@]} -eq 0 ]; then
        read -r -t "$SCAN_INTERVAL" input || true
        if [[ "${input:-}" == "m" ]]; then
            echo
            read -r -p "Device path (e.g., /dev/sdb): " USB_DEVICE
            break
        fi
        continue
    else
        read -r -t "$SCAN_INTERVAL" choice || true
        if [[ -z "${choice:-}" ]]; then
            continue
        fi
        if [[ "$choice" == "m" || "$choice" == "M" ]]; then
            echo
            read -r -p "Device path (e.g., /dev/sdb): " USB_DEVICE
            break
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ $choice -ge 1 && $choice -le ${#USB_DEVICES[@]} ]]; then
                IFS=':' read -r dev model size <<< "${USB_DEVICES[$((choice-1))]}"
                USB_DEVICE="/dev/$dev"
                echo
                echo "Selected: $model $size ($USB_DEVICE)"
                read -r -p "Confirm selection? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    break
                else
                    render_menu
                    continue
                fi
            elif [[ $choice -eq $((${#USB_DEVICES[@]}+1)) ]]; then
                echo
                read -r -p "Device path (e.g., /dev/sdb): " USB_DEVICE
                break
            else
                echo
                echo "Invalid selection."
                sleep 1
                render_menu
                continue
            fi
        fi
    fi
done

DEVICE="$USB_DEVICE"

DEVICE="$USB_DEVICE"

echo
echo "Selected device: ${DEVICE_INFO:-$USB_DEVICE}"
echo "Image: $IMG_PATH"
echo "WARNING: This will erase ALL data on $USB_DEVICE"
read -p "Continue? [y/N]: " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Unmount any mounted partitions from the device
    for p in $(lsblk -ln -o NAME "/dev/$(basename "$DEVICE")" 2>/dev/null | tail -n +2); do
        mnt="/dev/$p"
        if mount | grep -q "^$mnt "; then
            umount "$mnt" 2>/dev/null || true
        fi
        if mount | grep -q "$mnt "; then
            umount -l "$mnt" 2>/dev/null || true
        fi
    done

    echo "Flashing to $USB_DEVICE..."
    # Use dd's progress which reflects actual bytes written; avoid pv's early 100% due to read-side completion
    dd if="$IMG_PATH" of="$USB_DEVICE" bs=4M iflag=fullblock oflag=direct conv=fsync status=progress
    echo "Finalizing writes (sync)..."
    # Extra flush for good measure; ignore if not supported
    blockdev --flushbufs "$USB_DEVICE" 2>/dev/null || true
    sync
    echo "Ejecting device..."
    eject $USB_DEVICE 2>/dev/null || echo "Manual eject required"
    echo "Flash complete! Device is safe to remove."
else
    echo "Cancelled."
fi

