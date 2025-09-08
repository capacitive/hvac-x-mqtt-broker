#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo ./scripts/flash-usb.sh"
    exit 1
fi

if [ ! -f "pi-hvac.img" ]; then
    echo "Image not found. Run: make image"
    exit 1
fi

# Get image size in MB
IMAGE_SIZE_MB=$(du -m pi-hvac.img | cut -f1)
MIN_SIZE_MB=$((IMAGE_SIZE_MB + 100))  # Add 100MB buffer

# Function to scan for USB devices
scan_devices() {
    USB_DEVICES=()
    while IFS= read -r line; do
        if [[ $line == *"usb"* && $line == *"MassStorageClass"* ]]; then
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

# Initial scan
echo "Scanning for USB mass storage devices (min ${MIN_SIZE_MB}MB)..."
scan_devices

# If no devices found, start monitoring for new insertions
if [ ${#USB_DEVICES[@]} -eq 0 ]; then
    echo "No suitable devices found. Insert a USB device or press 'm' for manual entry..."
    
    # Monitor for USB device insertions
    {
        inotifywait -m /dev -e create 2>/dev/null | while read path action file; do
            if [[ $file == sd* ]]; then
                sleep 1  # Wait for device to settle
                scan_devices
                if [ ${#USB_DEVICES[@]} -gt 0 ]; then
                    echo -e "\n✓ USB device detected!"
                    pkill -P $$ inotifywait 2>/dev/null
                    break
                fi
            fi
        done
    } &
    MONITOR_PID=$!
    
    # Wait for device or manual input
    while [ ${#USB_DEVICES[@]} -eq 0 ]; do
        read -t 1 -n 1 input
        if [[ $input == "m" ]]; then
            kill $MONITOR_PID 2>/dev/null
            break
        fi
        scan_devices
    done
    
    kill $MONITOR_PID 2>/dev/null
fi

if [ ${#USB_DEVICES[@]} -eq 0 ]; then
    echo "Enter device manually:"
    read -p "Device path (e.g., /dev/sdb): " USB_DEVICE
else
    echo "Found USB devices:"
    for i in "${!USB_DEVICES[@]}"; do
        IFS=':' read -r dev model size <<< "${USB_DEVICES[$i]}"
        echo "$((i+1))) $model ${size} (/dev/$dev)"
    done
    echo "$((${#USB_DEVICES[@]}+1))) Manual entry"
    
    read -p "Select device [1-$((${#USB_DEVICES[@]}+1))]: " choice
    
    if [[ $choice -ge 1 && $choice -le ${#USB_DEVICES[@]} ]]; then
        IFS=':' read -r dev model size <<< "${USB_DEVICES[$((choice-1))]}"
        USB_DEVICE="/dev/$dev"
        DEVICE_INFO="$model $size"
    elif [[ $choice -eq $((${#USB_DEVICES[@]}+1)) ]]; then
        read -p "Device path (e.g., /dev/sdb): " USB_DEVICE
        DEVICE_INFO="$USB_DEVICE"
    else
        echo "Invalid selection. Exiting."
        exit 1
    fi
fi

echo
echo "Selected device: ${DEVICE_INFO:-$USB_DEVICE}"
echo "Image: pi-hvac.img"
echo "WARNING: This will erase ALL data on $USB_DEVICE"
read -p "Continue? [y/N]: " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Flashing to $USB_DEVICE..."
    dd if=pi-hvac.img of=$USB_DEVICE bs=4M status=progress
    echo "Syncing data to disk..."
    sync
    echo "Ejecting device..."
    eject $USB_DEVICE 2>/dev/null || echo "Manual eject required"
    echo "Flash complete! Device is safe to remove."
else
    echo "Cancelled."
fi