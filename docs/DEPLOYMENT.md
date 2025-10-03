# HVAC-X MQTT Broker: Raspberry Pi Zero W Image and OTA Deployment

This document describes how to build a Raspberry Pi Zero W image with the broker pre-installed and how to perform OTA updates.

## Requirements
- Linux or macOS host with:
  - Go 1.21+ installed (go in PATH)
  - curl, xz/unxz, losetup, mount, sed
  - sudo privileges for imaging/loop
  - ssh/scp for OTA
  - Optional: pv for flashing progress

## Build the Image (Raspberry Pi OS Lite base)

Configure via environment variables as needed (defaults shown):

- STATIC_IP: 192.168.1.23
- MQTT_PORT: 1883
- ROUTER_IP: 192.168.1.1
- DNS: "1.1.1.1 8.8.8.8"
- HOSTNAME: hvac-zero
- WIFI_SSID, WIFI_PSK: optional (Wi-Fi pre-config)
- APP_NAME: application name used for binary, service, and /opt directory (default: mqtt-broker)
- VERSION: release version stored in /opt/${APP_NAME}
- IMAGE_URL: override base image URL if needed (e.g., legacy)

Build:

```
make image STATIC_IP=192.168.1.23 MQTT_PORT=1883 HOSTNAME=hvac-zero \
  WIFI_SSID="MyWifi" WIFI_PSK="MyPassword" VERSION=1.0.0
```

Output: `./pi-hvac.img`

Notes:
- The image uses Raspberry Pi OS Lite (armhf). For Pi Zero W, you may need the legacy image. Override with:
  `IMAGE_URL=https://downloads.raspberrypi.com/raspios_lite_armhf_legacy_latest make image`
- SSH is enabled by default (touch /boot/ssh)
- The app is installed at `/opt/${APP_NAME}/releases/<VERSION>` with `current` symlink
- Systemd service `${APP_NAME}.service` is enabled on boot

## Flash the Image to SD Card

List devices (ensure the correct device path):

```
lsblk
```

Flash (this will erase the device):

```
sudo make flash DEVICE=/dev/sdX
```

## First Boot
- Insert SD card into Pi Zero W
- Power on; wait ~1–2 minutes on first boot
- The device should appear at the configured static IP (e.g., 192.168.1.23)
- SSH: `ssh root@192.168.1.23` (default user may be `pi` on some images; adjust PI_USER for OTA)

## OTA Deployment

From your development machine on the same network:

```
make deploy PI_HOST=192.168.1.23 PI_USER=root VERSION=1.0.1 MQTT_PORT=1883
```

What it does:
- Cross-compiles ARMv6 binary
- Packages broker + config with checksums
- Uploads to `/opt/hvac-mqtt/releases/<VERSION>`
- Verifies SHA256SUMS on device
- Atomically switches `current` symlink
- Restarts service; checks port 1883 (if `nc` available locally)

Rollback to previous version if needed:

```
make rollback PI_HOST=192.168.1.23 PI_USER=root
```

## Configuration Management
- Runtime config file: `/opt/${APP_NAME}/current/broker-config.yml`
- Build-time overrides:
  - Static IP via `dhcpcd.conf`
  - MQTT port baked into the installed `broker-config.yml`

To change network settings post-flash, edit `/etc/dhcpcd.conf` on device and reboot.

## Security
- Transport: OTA uses SSH (key or password auth). Ensure you configure SSH keys and disable password login for production.
- Integrity: Release package includes SHA256SUMS checked on device prior to activation.
- Optional hardening: Use GPG signing for packages and verify on device (requires gpg setup on both ends).

## Testing Procedures

Local:
- Build host binary and run against default config:
  - `make build`
  - `./build/${APP_NAME}`
- Unit tests: (none added yet) – consider adding tests for config load and topic handling.

Image:
- `make image` to generate image
- `make flash DEVICE=/dev/sdX`
- Boot Pi, `ssh` into it, check service:
  - `sudo systemctl status ${APP_NAME}`
  - `sudo journalctl -u ${APP_NAME} -f`

OTA:
- `make deploy PI_HOST=192.168.1.23 VERSION=1.0.2`
- Verify MQTT port:
  - On dev machine: `nc -zv 192.168.1.23 1883`
- Force failure test: deploy a bad binary to trigger rollback (modify deploy script to simulate failure) then `make rollback`.

## Alternate Implementation (Custom Minimal Linux)

For a from-scratch minimal image, consider Buildroot:
- Target: Raspberry Pi Zero W (arm1176jzf-s)
- Enable: busybox, dropbear (SSH), dhcpcd, wpa_supplicant, firmware (brcm/brcmfmac43430-sdio), bluetooth (optional)
- Add post-build script to install `/opt/hvac-mqtt` layout and service (sysvinit or systemd if enabled)
- Cross-compile the Go app with `GOARM=6`

This approach yields a smaller image but requires more setup/maintenance. The provided Pi OS Lite approach is recommended for reliability and hardware support.

