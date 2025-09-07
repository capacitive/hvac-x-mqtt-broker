#!/bin/bash

USB_DEVICE="${1:-/dev/sdb}"

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo ./scripts/flash-usb.sh [device]"
    exit 1
fi

if [ ! -f "pi-hvac-complete.img" ]; then
    echo "Image not found. Run: make image"
    exit 1
fi

echo "Flashing pi-hvac-complete.img to ${USB_DEVICE}..."
echo "WARNING: This will erase all data on ${USB_DEVICE}"
read -p "Continue? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    dd if=pi-hvac-complete.img of=${USB_DEVICE} bs=4M status=progress sync
    echo "Flash complete!"
else
    echo "Cancelled."
fi