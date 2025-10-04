## Plan and Deliverables
I’ve implemented a complete, practical deployment solution targeting Raspberry Pi Zero W with two options:

- Existing minimal distro (recommended): Raspberry Pi OS Lite-based image builder script
- Custom minimal Linux (outline via Buildroot; recommended as a future track if you need even smaller images)

What’s included now:

- Phase 1 (SD image): Scripted creation of a bootable SD card image with your Go app pre-installed and auto-started
- Phase 2 (OTA): Atomic, checksum-verified OTA deploy with rollback and version tracking
- Pre-build config for static IP (default 192.168.1.23) and MQTT port (default 1883)
- Makefile to tie it all together
- Documentation with step-by-step usage and testing

Below are the key files and how to use them.


Note on naming: APP_NAME is required by the scripts (enforced); the Makefile provides a default and passes it through. The output image is named `${APP_NAME}.img` and the service is `${APP_NAME}.service` under `/opt/${APP_NAME}`.

### What was added
- Makefile targets: build-arm, image, flash, deploy, rollback
- Scripts:
  - scripts/create-image.sh — builds the Pi image; configurable via env vars
  - scripts/flash.sh — safely flashes image to the SD device
  - scripts/ota/deploy.sh — atomic OTA deployment (SSH + checksum verification)
  - scripts/ota/rollback.sh — rollback to previous version

- Docs:
  - docs/DEPLOYMENT.md — end-to-end instructions
- .gitignore updated to ignore image/cache/artifacts

### Phase 1: SD card image creation
- Base: Raspberry Pi OS Lite (armhf). For Pi Zero W, if needed, set IMAGE_URL to the Legacy Lite URL.
- Static IP and MQTT port are configurable at build time:
  - Make variables: STATIC_IP, MQTT_PORT, ROUTER_IP, DNS, HOSTNAME, WIFI_SSID, WIFI_PSK, VERSION
- Installs your app into /opt/${APP_NAME}/releases/, sets current symlink, and installs/enables a systemd service

Run:
```bash
make image STATIC_IP=192.168.1.23 MQTT_PORT=1883 HOSTNAME=${HOSTNAME} VERSION=1.0.0
```
```bash
sudo make flash DEVICE=/dev/sdX
```


### About sudo --preserve-env
- When creating the image, the Makefile runs the script under sudo and uses `--preserve-env` to keep selected variables (e.g., `APP_NAME`, `STATIC_IP`, `MQTT_PORT`, etc.) in the root environment. Without this, those settings would be lost when the shell elevates, and the image build would not pick up your Makefile overrides.

Systemd service used for auto-start (excerpt):<br/>
**create-image.sh** (scripts/create-image.sh)
```bash
[Service]
Type=simple
User=root
WorkingDirectory=/opt/${APP_NAME}/current
ExecStart=/opt/${APP_NAME}/current/${APP_NAME}
Restart=always
```

Image builder entrypoint (excerpt):<br/>
**create-image.sh** (scripts/create-image.sh)
```bash
CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=6 "$GO_BIN" build -o "$BUILD_DIR/${APP_NAME}" ./
sed -i "s/^\(\s*port:\s*\).*/\1$MQTT_PORT/" "$REL_DIR/broker-config.yml"
ln -snf "$REL_DIR" "$APP_DIR/current"
```

### Phase 2: OTA update system
- Transport: SSH (set PI_HOST and PI_USER)
- Versioning: releases/, current symlink, previous recorded for rollback
- Integrity: SHA256 checksum verification on device (pre-activation)
- Rollback: automatic attempt on health-check failure and manual rollback provided

Deploy:
```bash
make deploy PI_HOST=192.168.1.23 PI_USER=root VERSION=1.0.1
```
```bash
make rollback PI_HOST=192.168.1.23
```

OTA atomic activation (excerpt):<br/>
**deploy.sh** (scripts/ota/deploy.sh)
```bash
sha256sum -c SHA256SUMS
```
```bash
echo "$CURRENT_REAL" > "$REMOTE_BASE/previous"
```
```bash
ln -snf "$REMOTE_REL" "$REMOTE_BASE/current"
```
```bash
systemctl restart ${APP_NAME}.service
```

Rollback script (excerpt):<br/>
**rollback.sh** (scripts/ota/rollback.sh)
```bash
PREV="$(cat "/opt/${APP_NAME}/previous")"
```
```bash
ln -snf "$PREV" "/opt/${APP_NAME}/current"
```
```bash
systemctl restart ${APP_NAME}.service
```

### Configuration management
- Runtime config file is colocated with the binary as required by your config loader:
  - /opt/${APP_NAME}/current/broker-config.yml
- Build-time overrides:
  - Static IP via dhcpcd.conf
  - MQTT port baked into installed broker-config.yml during image creation

Your config loader will continue to work as-is:<br/>
**config.go** (config/config.go)
```bash
exe, _ := os.Executable()
file, err := os.Open(filepath.Dir(exe) + "/broker-config.yml")
```

### How to use
- Build image:
   - make image STATIC_IP=192.168.1.23 MQTT_PORT=1883 HOSTNAME=hvac-zero VERSION=1.0.0
- Flash SD:
   - sudo make flash DEVICE=/dev/sdX
- First boot:
   - Pi will boot, SSH enabled, hostname set, service auto-starts
- OTA deploy:
   - make deploy PI_HOST=192.168.1.23 PI_USER=root VERSION=1.0.1
- Rollback:
  - make rollback PI_HOST=192.168.1.23

### Files created
- Makefile
- scripts/create-image.sh
- scripts/flash.sh
- scripts/ota/deploy.sh
- scripts/ota/rollback.sh
- docs/DEPLOYMENT.md
- .gitignore updated

### - Option 1: Custom minimal Linux (Buildroot outline)
- Use Buildroot with target arm1176jzf-s (Pi Zero W)
- Enable firmware (brcmfmac for Wi-Fi), dhcpcd, wpa_supplicant, dropbear, busybox
- Add post-build script to create /opt/hvac-mqtt layout and init/systemd unit (depending on init system)
- Cross-compile Go app with GOARM=6
- This yields a smaller footprint but increases complexity; the Pi OS Lite route is already robust and hardware-proven.

### Testing procedures
- Local smoke: make build; run build/mqtt-broker locally (won’t test ARM-specifics, just config and startup)
- Image creation smoke: make image (downloads base, mounts, installs app, config)
- Flash and boot: sudo make flash; boot Pi; journalctl -u ${APP_NAME}; nc -zv 192.168.1.23 1883
- OTA: make deploy; verify service restarts; connect to port 1883; simulate failure and test rollback

### Notes and next steps
- Raspberry Pi OS “Lite (Legacy)” may be needed for Zero W; you can override IMAGE_URL in make image
- Security: You can upgrade integrity to signed artifacts (GPG) if desired; I can add that if you want
- Do you want Wi-Fi credentials baked into /boot/wpa_supplicant.conf by default, or prefer manual provisioning?


---

### Glossary of variables (Makefile and scripts)
- APP_NAME: hvacx-broker — App binary/service/dir name; used for /opt/${APP_NAME}, ${APP_NAME}.service, ${APP_NAME}.img
- BUILD_DIR: build — Local build output directory; contains the prebuilt ARMv6 binary and release artifacts
- OUTPUT_IMG: ${APP_NAME}.img — Image filename that flash.sh writes to the SD card
- STATIC_IP: 192.168.1.23 — Baked into dhcpcd.conf for wlan0 on the image
- MQTT_PORT: 1883 — Injected into broker-config.yml on the image and used for deploy health check
- ROUTER_IP: 192.168.1.1 — Default gateway for wlan0 in dhcpcd.conf
- DNS: "1.1.1.1 8.8.8.8" — DNS servers in dhcpcd.conf
- HOSTNAME: hvacx-broker — Set in /etc/hostname and /etc/hosts on the image
- WIFI_SSID: mywifi — Optional; generates wpa_supplicant.conf on /boot for first boot
- WIFI_PSK: secretpass — Optional; Wi-Fi PSK placed with SSID in wpa_supplicant.conf
- IMAGE_URL: https://downloads.raspberrypi.com/raspios_lite_armhf_latest — Source URL for Raspberry Pi OS Lite (override for legacy)
- PI_HOST: 192.168.1.23 — Target Pi hostname/IP for OTA deploy/rollback
- PI_USER: root — SSH user for OTA operations
- VERSION: 0.1.0 — Semantic version from VERSION file; used as releases/<VERSION> and package naming
- PORT: 1883 — TCP port used in deploy health check (nc) against the target
- SSH_OPTS: -o StrictHostKeyChecking=no — Extra SSH/SCP options during OTA
- APP_DIR: /opt/${APP_NAME} — Install base on the Pi; contains releases/, current, previous
- SERVICE_NAME: ${APP_NAME}.service — systemd unit name managed during deploy/rollback
- LOG_FILE: /var/log/${APP_NAME}.log — Fallback log file when not using systemd on the Pi
- DEVICE: /dev/sdX — Block device for flashing the image (used by make flash)
- DEPLOY_NEEDS_SUDO: 0 — If 1, make deploy/rollback will prompt for sudo (host-side)

### Would you like me to:
- Add GPG signing and verification for OTA packages?
- Add a health-check binary/endpoint for more reliable post-deploy validation?
- Provide a Buildroot defconfig and post-build scripts to support the “Custom minimal Linux” option fully?