#!/usr/bin/env bash
set -euo pipefail

# Tartigrade Step 1: Buildroot Hello World (Option 3: root-only BusyBox, hello at boot)
# This script:
#  - Fetches Buildroot (pinned release) into .buildroot/
#  - Applies raspberrypi3 base defconfig and overlays a rootfs with a hello init script
#  - Builds an sdcard image suitable for Raspberry Pi Zero 2 W (32-bit)
#  - Outputs: .buildroot/output/images/sdcard.img

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
BR_DIR="$ROOT_DIR/.buildroot"
BR_EXT_DIR="$ROOT_DIR/br/external"

BR_TAG="2024.02.2"
BR_REPO="https://gitlab.com/buildroot.org/buildroot.git"

mkdir -p "$BR_DIR" "$BR_EXT_DIR"

# 1) Fetch Buildroot if missing (pinned tag)
if git -C "$BR_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[tartigrade] Buildroot already present at $BR_DIR (git work tree detected)"
else
  echo "[tartigrade] Cloning Buildroot $BR_TAG..."
  rm -rf "$BR_DIR"
  git clone --depth 1 --branch "$BR_TAG" "$BR_REPO" "$BR_DIR"
fi

# 2) Prepare external overlay (hello init script is already placed in br/external/overlay)
HELLO_SCRIPT="$BR_EXT_DIR/overlay/etc/init.d/S99hello"
if [[ ! -f "$HELLO_SCRIPT" ]]; then
  echo "Error: hello init script not found at $HELLO_SCRIPT" >&2
  exit 1
fi

# 3) Configure Buildroot using raspberrypi3_defconfig as a base
#    Then append minimal overrides for overlay and Zero 2 W DTS
export BR2_EXTERNAL="$BR_EXT_DIR"
make -C "$BR_DIR" raspberrypi3_defconfig

# Append our overrides into .config and then normalize with olddefconfig
# - Rootfs overlay to inject hello init script
# - Post-build to ensure permissions
# - Use Zero 2 W DTB (bcm2710-rpi-zero-2-w)
{
  echo "BR2_ROOTFS_OVERLAY=\"$BR_EXT_DIR/overlay\""
  echo "BR2_ROOTFS_POST_BUILD_SCRIPT=\"$BR_EXT_DIR/board/hvacx/rpi0_2w/post-build.sh\""
  echo "BR2_LINUX_KERNEL_INTREE_DTS_NAME=\"bcm2710-rpi-zero-2-w\""
} >> "$BR_DIR/.config"

make -C "$BR_DIR" olddefconfig

# 4) Build image (unattended)
#    Note: first run will download toolchain and kernel; may take a while.
JOBS="$(nproc 2>/dev/null || echo 2)"
make -C "$BR_DIR" -j"$JOBS"

IMG_PATH="$BR_DIR/output/images/sdcard.img"
if [[ ! -f "$IMG_PATH" ]]; then
  echo "Error: expected image not found at $IMG_PATH" >&2
  exit 1
fi

echo "[tartigrade] Build complete: $IMG_PATH"
echo "[tartigrade] Next step: flash with 'make tartigrade-flash' or:\n  sudo bash scripts/flash.sh $IMG_PATH"

