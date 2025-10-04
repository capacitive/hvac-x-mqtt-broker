## Buildroot Migration Plan for HVACX Broker (Raspberry Pi Zero 2 W)

This document captures the complete plan and implementation notes to migrate from Raspberry Pi OS Lite to a minimal, unattended Buildroot image tailored for Raspberry Pi Zero 2 W, with zero first‑boot interaction and OTA-only lifecycle.

### Goals
- Minimal OS: kernel + essential userland only (busybox, wpa_supplicant, ssh, dhcp client).
- One unprivileged user with a single private group; no sudo; no interactive setup on first boot.
- Wi‑Fi + static IP preseeded at image build time.
- SSH enabled by default; key installed automatically (generated if missing) for unattended OTA.
- Broker binary installed at /opt/$APP_NAME/releases/$VERSION with current symlink; service starts on boot.
- Keep existing OTA scripts (scp/ssh-based) working unchanged from the host.

### High-level Approach
- Use Buildroot with an external tree (BR2_EXTERNAL) kept in-repo: br/external/.
- Start from a Raspberry Pi reference defconfig (e.g., raspberrypi3_defconfig) adapted for Zero 2 W in 32‑bit armv7 hard-float mode.
- Provide a custom defconfig (hvacx_rpi0_2w_defconfig) and overlays to:
  - Enable required firmware for Wi‑Fi (brcmfmac) and Bluetooth (optional).
  - Include wpa_supplicant, a DHCP client (udhcpc or dhcpcd), and openssh or dropbear (openssh recommended for scp/ssh OTA).
  - Install broker and init script in rootfs.
- Use a post-build script to inject: user account, authorized_keys, hostname, Wi‑Fi credentials, static IP, timezone, app layout, and ownership.

### Target and Toolchain
- Hardware: Raspberry Pi Zero 2 W (BCM2710A1, Cortex‑A53). We’ll target 32‑bit ARMv7 (hard‑float) for maximum compatibility with Go builds and existing tooling.
- Buildroot will build: cross toolchain, bootloader/firmware, kernel, userspace.

### Repository Layout
- br/external/
  - configs/hvacx_rpi0_2w_defconfig
  - overlay/ (root filesystem overlay)
    - etc/
      - hostname (templated via post-build)
      - network/ (optional if using udhcpc scripts)
      - init.d/S90-hvacx (start broker at boot)
      - wpa_supplicant/wpa_supplicant.conf (templated via post-build)
    - opt/$APP_NAME/ (created by post-build with releases layout)
  - board/hvacx/rpi0_2w/
    - post-build.sh (injection of user, keys, configs, app install)
    - post-image.sh (optional; e.g., tweak cmdline.txt)

### Makefile Targets (Host)
- br-init: Fetches a pinned Buildroot release into .buildroot/
- build-armv7: CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 build to build/$APP_NAME
- ensure-ssh-key: Already implemented (ed25519 key with no passphrase if missing)
- br-image: End-to-end, unattended Buildroot image build using BR2_EXTERNAL, applying overlay and post-build customization. Passes APP_NAME, HOSTNAME, WIFI_SSID, WIFI_PSK, STATIC_IP, ROUTER_IP, DNS, RPI_USER, RPI_PASS, RPI_SSH_PUBKEY, TIMEZONE as environment.
- br-flash: Reuses scripts/flash.sh to write output/images/sdcard.img to the selected device.

### Variables and Defaults
- APP_NAME, HOSTNAME, WIFI_SSID, WIFI_PSK, STATIC_IP, ROUTER_IP, DNS.
- RPI_USER, RPI_PASS: minimal user; single private group; no sudo.
- RPI_SSH_PUBKEY: auto-generated if absent via ensure-ssh-key; content injected into authorized_keys.
- TIMEZONE: optional; if set, will be applied.

### Defconfig Highlights (hvacx_rpi0_2w_defconfig)
- Toolchain: external glibc or musl (musl is smaller; glibc better compatibility). Choose musl for minimal footprint unless there’s a hard requirement.
- Kernel: Raspberry Pi downstream kernel via rpi-firmware/rpi-kernel packages.
- Filesystem: ext4, plus sdcard.img generation with firmware and boot partition.
- Packages:
  - busybox
  - openssh (server + scp/sftp); alternatively dropbear for smaller footprint
  - wpa_supplicant
  - dhcpcd or busybox udhcpc; dhcpcd is closer to Raspberry Pi defaults, udhcpc is simpler
  - ca-certificates (optional, useful for secure fetches / future OTA enhancements)
  - rng-tools or haveged (optional; improve SSH keygen entropy at first boot if needed)
  - rpi-firmware and linux-firmware-brcm: include brcmfmac43430/43436 as needed (Zero 2 W typically needs brcmfmac43430/43436 SDIO variants). We can include both if size is acceptable.

### Post-build Customization (board/hvacx/rpi0_2w/post-build.sh)
- Create minimal user:
  - Add group and user entries directly (no sudo or extra groups); set home /home/$RPI_USER.
  - Hash password via openssl passwd -6 "$RPI_PASS".
- Authorized keys:
  - Install RPI_SSH_PUBKEY into /home/$RPI_USER/.ssh/authorized_keys (600), chown to user.
- Hostname:
  - Write into /etc/hostname and /etc/hosts.
- Timezone (optional):
  - Write /etc/timezone and link /etc/localtime.
- Wi‑Fi:
  - Write /etc/wpa_supplicant/wpa_supplicant.conf with WIFI_SSID/WIFI_PSK.
- Networking:
  - For static IP with udhcpc: provide appropriate ifup/ifdown scripts or configure dhcpcd.conf if using dhcpcd.
- App install:
  - Copy build/$APP_NAME to /opt/$APP_NAME/releases/$VERSION/$APP_NAME.
  - Write broker-config.yml to that release.
  - Create current symlink and chown to $RPI_USER.
- Init script:
  - Install /etc/init.d/S90-hvacx to start the broker on boot as $RPI_USER.

### Init Script (Busybox example)
- /etc/init.d/S90-hvacx (executable):
```
#!/bin/sh
### BEGIN INIT INFO
# Provides:          hvacx
# Required-Start:    $network
# Required-Stop:     $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
### END INIT INFO

APP_DIR=/opt/${APP_NAME}/current
USER=${RPI_USER:-hvac}
start() {
    echo "Starting ${APP_NAME}"
    start-stop-daemon -S -b -u "$USER" -x "$APP_DIR/${APP_NAME}" --chdir "$APP_DIR"
}
stop() { start-stop-daemon -K -x "$APP_DIR/${APP_NAME}" || true; }
case "$1" in start) start ;; stop) stop ;; restart) stop; start ;; *) echo "Usage: $0 {start|stop|restart}"; exit 1 ;; esac
exit 0
```

### Makefile Integration (Host)
- br-init:
  - git clone --depth=1 https://git.busybox.net/buildroot .buildroot (or pinned release tarball)
- br-image:
  - $(MAKE) -C .buildroot BR2_EXTERNAL=$(PWD)/br/external hvacx_rpi0_2w_defconfig
  - $(MAKE) -C .buildroot BR2_EXTERNAL=$(PWD)/br/external APP_NAME=$(APP_NAME) HOSTNAME=$(HOSTNAME) WIFI_SSID=... WIFI_PSK=... RPI_USER=... RPI_PASS=... RPI_SSH_PUBKEY=... STATIC_IP=... ROUTER_IP=... DNS=... all
  - Output sdcard image at .buildroot/output/images/sdcard.img
- br-flash:
  - sudo bash scripts/flash.sh .buildroot/output/images/sdcard.img

### OTA Compatibility
- openssh server included; scp/ssh works as before.
- scripts/ota/deploy.sh remains unchanged from the host’s perspective.

### Build Performance and Caching
- First build downloads toolchains, kernel, and packages (tens of minutes). Completely unattended.
- Subsequent builds reuse the download cache and build artifacts (much faster).

### Testing Plan
- Host: make br-init; make build-armv7; make br-image; make br-flash.
- Device: boot; verify no prompts; confirm Wi‑Fi up; SSH reachable; broker running as $RPI_USER on boot.

### Risks / Considerations
- Wi‑Fi firmware mapping: Zero 2 W typically uses brcmfmac SDIO variants (43430/43436). We will include both if size allows.
- If systemd is required later (journald, cgroups, advanced hardening), we can switch; busybox init is chosen for minimalism now.
- If Go binary uses libc/glibc-specifics, prefer glibc toolchain; otherwise musl is smaller and usually fine for static binaries.

### Next Steps (Automated by Targets)
1) Add br/external tree, defconfig, overlay, post-build scripts.
2) Implement Makefile targets: br-init, build-armv7, br-image, br-flash.
3) Run make br-image (auto‑ensure SSH key, pass config).
4) Flash and boot.

---

This document is the authoritative reference for the Buildroot migration in this repository. Any deviations will be reflected here alongside the corresponding Makefile targets and scripts.

