# HVACX Broker Conversation Dump (for continuity)

This document summarizes the conversation history and major changes so you can restart a fresh session and keep working seamlessly. It focuses on decisions, rationale, and the repository changes that were made.

## Scope and Goals
- Target device: Raspberry Pi Zero 2 W
- App: HVACX MQTT broker (Go)
- Requirements:
  - Zero first-boot interaction (no wizards)
  - Single minimal user (no sudo), Wi‑Fi + static IP preseeded
  - SSH enabled for OTA, key automated
  - OTA deploy/rollback via scp/ssh, integrity preserved
  - Flashing with interactive USB device selection and accurate progress
  - Prefer unattended, reproducible builds

## High-Level Timeline

1) Initial Deployment Framework
- Implemented Makefile targets: `build`, `build-arm`, `image`, `flash`, `deploy`, `rollback`.
- Scripts added: `scripts/create-image.sh`, `scripts/flash.sh`, `scripts/ota/deploy.sh`, `scripts/ota/rollback.sh`.
- Docs: `docs/DEPLOYMENT.md`, `scripts/README.md`.
- OTA structure: `/opt/$APP_NAME/releases/$VERSION` with `current` symlink; rollback support.

2) Parameterization and Enforcement
- Introduced `APP_NAME` as single source of truth; removed hard-coded names.
- Enforced `APP_NAME` as required.
- Fixed Go build under sudo by building prior to elevation; use prebuilt binary in `create-image.sh`.

3) Semantic Versioning
- Created `VERSION` file (e.g. `0.1.0`).
- Read/validate semantic version from `VERSION` in `create-image.sh` and OTA scripts.
- Removed date-based versioning.

4) Flashing UX and Progress
- Bash-based interactive USB device selection integrated into `scripts/flash.sh`.
- Continuous detection loop: redraws list only on changes; non-blocking input.
- Progress: experimented with `pv | dd` (early 100% issue), custom `dd` USR1 parsing (no output on some systems), and finally reverted to `dd status=progress` for robust, accurate write-side progress.
- Custom format request (e.g., `1274MB / 2400MB copied, 29.4 MB/s`) was prototyped but reverted for reliability.

5) First-Boot Wizard Issue (Raspberry Pi OS Lite)
- Preseeded hostname, SSH, Wi‑Fi, static IP, and service.
- Added minimal user provisioning and later enhancements to fully bypass first-boot wizard:
  - Create minimal user directly in rootfs (single private group; no sudo).
  - Remove legacy `pi` user from `passwd`, `shadow`, `group` and delete `/home/pi`.
  - Proactively remove and mask first-boot services (`raspi-config.service`, `firstboot.service`, `raspi-firstboot.service`).
  - Add kernel cmdline masks via `/boot/cmdline.txt`.

6) SSH Key Automation
- Makefile default variables extended: `RPI_USER`, `RPI_PASS`, `TIMEZONE`, `RPI_SSH_PUBKEY`.
- Added `ensure-ssh-key` target to auto-generate `~/.ssh/id_ed25519` when missing (no passphrase).
- `image` target now ensures a key exists and injects the pubkey content into the image if `RPI_SSH_PUBKEY` is not provided explicitly.

7) Buildroot Migration Plan
- Chosen to migrate away from Raspberry Pi OS Lite to a minimal Buildroot image to guarantee zero first-boot interaction and a smaller attack surface.
- Plan documented in `docs/BUILDROOT.md` with:
  - External tree layout (`br/external`), defconfig, overlays, post-build script.
  - Packages: busybox, openssh (or dropbear), wpa_supplicant, dhcp client, Wi‑Fi firmware, etc.
  - Post-build injection: user, authorized_keys, hostname, Wi‑Fi, static IP, timezone, app install.
  - Make targets: `br-init`, `build-armv7`, `br-image`, `br-flash`.

## Key Decisions and Rationale
- Raspberry Pi OS Lite first-boot wizard: complex to suppress reliably across variants, hence masking and removal steps applied; ultimately migrating to Buildroot for deterministic behavior.
- OTA via SSH: retained for simplicity and reliability; key automation implemented to avoid manual steps.
- Minimal user: single user/group, no sudo, broker runs unprivileged.
- Flashing: use `dd status=progress` for portable, accurate write-side progress; interactive device detection loop for better UX.

## Current Repository State (Highlights)

- Makefile
  - Added defaults for `RPI_USER`, `RPI_PASS`, `TIMEZONE`, `RPI_SSH_PUBKEY`, `IMAGE_URL`.
  - New target: `ensure-ssh-key` (auto-generate ed25519 key if missing).
  - `image` target: auto-runs `ensure-ssh-key` if `RPI_SSH_PUBKEY` empty; injects key content.
  - `deploy` and `rollback` use existing OTA scripts.

- scripts/create-image.sh
  - Reads semantic `VERSION`.
  - Uses prebuilt ARM binary from `build/`.
  - Enables SSH (`/boot/ssh`), sets hostname and `/etc/hosts`.
  - Static IP via `dhcpcd.conf`.
  - Wi‑Fi via `/boot/wpa_supplicant.conf`.
  - Minimal user: create in rootfs (`passwd`, `shadow`, `group`), home dir, optional `authorized_keys`.
  - Remove `pi` and mask first-boot services; add kernel cmdline masks.
  - Install app to `/opt/$APP_NAME/releases/$VERSION` with `current` symlink; chown to minimal user.
  - System V/systemd service (current repo uses systemd unit) runs as `${RPI_USER:-root}`.

- scripts/flash.sh
  - Interactive USB device selection with continuous scan and redraw-on-change logic.
  - Flash using `dd if=... of=... bs=4M iflag=fullblock oflag=direct conv=fsync status=progress`.
  - Flush and `sync` on completion.

- docs/BUILDROOT.md
  - Full Buildroot migration plan with external tree, packages, post-build steps, and Makefile integration.

## Usage Cheatsheet

- Build image (with minimal user, automated SSH key, Wi‑Fi, hostname, static IP):
```
make image \
  RPI_USER=hvac \
  RPI_PASS='S3cureP@ss' \
  WIFI_SSID='MySSID' \
  WIFI_PSK='MyWifiPassword' \
  HOSTNAME='hvac-zero' \
  TIMEZONE='America/New_York'
```
- Flash the image:
```
make flash
```
- OTA deploy:
```
make deploy PI_HOST=192.168.1.23 PI_USER=hvac
```
- Auto-generate SSH key if needed (usually run implicitly by `make image`):
```
make ensure-ssh-key
```

## Next Steps
- Implement Buildroot external tree, defconfig, overlay, and post-build scripts per `docs/BUILDROOT.md`.
- Add Makefile targets: `br-init`, `build-armv7`, `br-image`, `br-flash`.
- Kick off unattended Buildroot build and produce `sdcard.img`.

## Notes for a Fresh Assistant Session
- Refer to this dump plus `docs/BUILDROOT.md`.
- The final goal is a deterministic, zero-interaction boot with the broker running as a minimal user and OTA only for post-deploy changes.

