## Build Journal: HVACX Broker on Raspberry Pi Zero 2 W (Buildroot)

Principle: We proceed in lock step. Each step has a clear objective, procedure, and verification. We do not advance until the step is verified.

### Journal Process Guidelines
- Always include assistant responses verbatim in the journal by default for every conversation, unless the user requests otherwise.
- Proceed in lock step: each step has Objective, Procedure, Verification; do not advance until verified.
- Record all Q&A exchanges at each checkpoint, quoting user and assistant verbatim.



### Session Preamble and User Prompt (Recorded)

- User Prompt (verbatim):
  "OK - let's read the BUILDROOT doc and plan each minute step in detail.  For embedded/microcontroller/linux kernel/low level programming projects:
  Start with a document that serves as a journal of everything we do in lock step.  We can't move on to the next step until the first is successful and tested.  For an embedded device project, this is a very important approach to remember to do before working on items.  It's easy to get stuck down one course of action, so a detailed journal is vital to our success.

  I'd like you to start with a brief technical explanation of each work item, accompanied by an ELIM5 explanation.

  First - let's explain and then work on the most basic "Hello World" - a bare bones kernel that (pick the most possible/easiest/best for step by step buildup from basic to complex):
  OPTION 1: Boots into an environment with a userspace that allows me to use the `pwd` command to determine the user the bare OS is running under.
  OPTION 2: Boots into  a "userless" environment that prints hello to the screen and than continues the OS runloop.
  OPTION 3 (likely the most scaled down of them all, therefore much desired for a hello world): A root-only user environment that can run anything it needs (but only gets access to what it's needed to do - principle of minimal computing/contraints)"

- Assistant Preamble (verbatim):
  Great—let’s kick this off methodically with a lock-step journal and clear choices.

  Option analysis with brief technical and ELIM5 explanations
- Procedure (implemented):
  - Create tardigrade/ orchestration with build-image.sh
  - Scaffold Buildroot external tree at br/external with overlay and post-build hook
  - Add Makefile targets: tardigrade-image, tardigrade-flash
  - Use raspberrypi3_defconfig as base, override DTS to bcm2710-rpi-zero-2-w and add overlay
- Expected output: .buildroot/output/images/sdcard.img
- Current status: Building image (first build may take 20–60 minutes). I’ll prompt when it’s time to flash.

### Step 1 Verification Outcome (User Test Report)
- User report: Boot sequence healthy; keyboard/mouse hotplug events printed to console.
- Observation: Hello message not visible.
- Action taken: Updated S99hello to:
  - log via `logger -t tartigrade` (if syslogd is active)
  - wait briefly for `/dev/tty1` and write directly to it
  - append message to `/etc/motd` to be visible at login
- Next verification: Reboot and confirm:
  - Message appears on console (tty1)
  - Message present in `/etc/motd`
- Result: Build and flash successful (user report).

  - If syslog present, `logread | grep tartigrade` shows the entry

### Flashing: Auto-Expand to Full Device Capacity
- Requirement: Use entire device capacity (e.g., 128GB) instead of fixed ~34GB rootfs
- Action taken (host-side, in `scripts/flash.sh`):
  - After dd + sync, run `partprobe` and `parted` to resize partition 2 to 100%
  - Run `e2fsck -f -p` and `resize2fs` on rootfs partition to expand filesystem
- Notes:
  - Handles `/dev/sdX2` and `/dev/mmcblk0p2` naming schemes
  - Requires `parted`, `e2fsck` and `resize2fs` on the host; skips gracefully if missing

### Repository hygiene: Buildroot as submodule
- Action: Registered .buildroot as a git submodule using its existing remote URL (https://gitlab.com/buildroot.org/buildroot.git).
- Rationale: Makes the Buildroot tree explicit, reproducible, and easy to update via standard submodule flows.
- Script safeguard: Updated tardigrade/build-image.sh to detect a git work tree (covers submodules where .git is a file) and skip re-cloning.
- Next steps: Commit with an appropriate message when ready (we have not committed on your behalf).

- Next verification:

### Checkpoint: Rename execution (tartigrade → tardigrade)
- Action: Renamed directory via git mv tartigrade → tardigrade.
- Updated files:
  - Makefile targets and help: tardigrade-image, tardigrade-flash; path: bash tardigrade/build-image.sh
  - tardigrade/build-image.sh: log prefixes updated to [tardigrade]
  - br/external/overlay/etc/init.d/S99hello: message, logger tag, and header updated to tardigrade
  - br/external/board/hvacx/rpi0_2w/post-build.sh: banner updated to “tardigrade Step 1 (Hello World)”
  - br/external/external.desc and external.mk: updated descriptions to tardigrade
- Journal policy: Prior quotes remain verbatim (so earlier occurrences of “tartigrade” in Q&A/logs are preserved); going forward we use “tardigrade”.
- Build verification: Ran `make tardigrade-image`.
  - Result: Success. Image generated at .buildroot/output/images/sdcard.img
  - Notes:
    - Warnings: kconfig override warnings for BR2_ROOTFS_OVERLAY/POST_BUILD_SCRIPT/DTB (expected; we append overrides).
    - mke2fs note: 64-bit ext4 feature disabled by design (Buildroot default for small images); harmless.
    - Missing path during cleanup (usr/libexec) printed by find is benign.

- Next verification: make tardigrade-image; make tardigrade-flash

  - After flashing, run `lsblk` to confirm rootfs partition uses full capacity

### Checkpoint: Flash verification (host-side SD card)
- User report (verbatim):
  - "The boot of the device was successful, I see the hello message at the end of the boot sequence. I cannot use the keyboard to type any commands like `cat /etc/issue` (likely because there's no keyboard configured on our image), but that's ok for now."
- Assistant verification (host-side lsblk):
  - Detected device: sdc MassStorageClass usb RM=1 SIZE=115.9G
  - Partitions:
    - sdc1 32M vfat (boot)
    - sdc2 115.8G ext4 LABEL=rootfs (root filesystem)
  - Interpretation: Matches expected layout. Rootfs partition expanded to fill device capacity. Expansion successful.



  - Option 1: Minimal userspace with shell (pwd available)
    - Technical: Boot a tiny userspace (BusyBox) with an interactive shell on console. You can run pwd, ls, etc. This needs a working init and /sbin/getty for login.
    - ELIM5: We make a tiny computer that turns on and lets you type simple commands like “where am I?” It’s like turning on a calculator that also lets you see the folder you’re in.
  - Option 2: Kernel-only “hello” print and runloop
    - Technical: Modify kernel/initramfs to print “hello” and keep the scheduler running but provide no shell. Smallest, but not useful for later steps like Wi‑Fi/SSH without adding userspace back.
    - ELIM5: We turn on the brain and it says “hello,” but you can’t talk back to it yet. It’s very small, but we can’t do much with it.
  - Option 3: Root-only minimal userspace (BusyBox), prints hello, then continues
    - Technical: Boot BusyBox init, run a startup script that echoes “hello”, leave the shell available as root. No extra users, no sudo, minimal footprint. Easiest path to incrementally add Wi‑Fi/SSH later.
    - ELIM5: It turns on, says “hello,” and gives you the simplest set of tools so we can keep building without adding extra stuff.

  Recommendation
  - Choose Option 3 for Hello World. It’s minimal, yet it keeps the path open to add networking and SSH in small, safe steps.

  Journal created
  - I created docs/JOURNAL.md to log every step. We will not proceed to the next step until the current one is verified on real hardware.

  Next: Step 1 plan (Hello World — Option 3)
  - Objective: Boot to root-only BusyBox, print hello at boot, keep console usable.
  - What I will implement:
    - Buildroot external tree in br/external with:
      - hvacx_rpi0_2w_defconfig (Pi Zero 2 W, 32-bit ARMv7)
      - overlay/ with an init script that echoes “hello” at boot and continues
      - board/hvacx/rpi0_2w/post-build.sh (scaffold only for now)
    - Makefile targets:
      - br-init: fetch Buildroot into .buildroot (pinned)
      - build-armv7: compile your Go app (not used yet for Hello World, but scaffolding ready)
      - br-image: run Buildroot unattended with BR2_EXTERNAL to produce sdcard.img
      - br-flash: reuse existing flash script to write sdcard.img
  - Verification on hardware:
    - Boot device, see “hello” in boot log, get to console, run pwd to confirm userspace works.

### Step 0: Orientation and Goal Lock

### Q&A Log (Recorded after Step 1 build/flash)

- Q1 (User, verbatim):
  "Is this a C/C++ build?"

  - Assistant (verbatim):
    Short answer: The Buildroot step is primarily a C build (with optional C++), while your application is Go.

    Details
    - What’s building now: Buildroot is compiling upstream components (Linux kernel, BusyBox, toolchain, etc.) which are almost entirely C, with some packages optionally using C++. It uses GCC/G++ cross-compilers.
    - Your code: Our repo’s application code is Go (build targets are go build). For Step 1 we didn’t add any C/C++ source of our own; only a tiny shell init script to echo “hello.”

    Evidence from the repo
    - Go build targets (your app):
      build:
        go build -o $(BUILD_DIR)/$(APP_NAME) ./

      build-arm:
        CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=6 go build -o $(BUILD_DIR)/$(APP_NAME) ./

    - Hello script (shell, not C/C++):
      #!/bin/sh
      echo "hello from tartigrade: minimal boot successful"
      exit 0

    - Buildroot uses C/C++ toolchains (CMake toolchain file references C/CXX compilers).

    Conclusion
    - The in-progress Buildroot pipeline is a C-first (and sometimes C++) build of the OS stack. Our own contribution for Step 1 is shell and configuration. Your broker remains a Go program; we’ll integrate its Go cross-build in a later step.

- Q2 (User, verbatim):
  "Where is the build running - my machine or remotely?  What can I do to see the progress of the build?"

  - Assistant (verbatim):
    Short answer
    - It’s running locally on your machine. The build script clones Buildroot into .buildroot inside your repo and runs make there.
    - To see progress, run the build in your own terminal (make tartigrade-image) to watch stdout, or monitor .buildroot/output/build to see which packages are being built in real time.

    Evidence from the repo
    - The tartigrade build runs in a local folder and invokes make locally:
      ROOT_DIR=... BR_DIR="$ROOT_DIR/.buildroot"; git clone ... "$BR_DIR"; make -C "$BR_DIR" -j"$JOBS"; IMG_PATH="$BR_DIR/output/images/sdcard.img"

    - Makefile target you can run locally to see all output:
      tartigrade-image:
        bash tartigrade/build-image.sh

    Ways to view progress
    - Run the build yourself so stdout is visible:
      make tartigrade-image
    - Or, if a build is already running, you can monitor which packages are building:
      watch -n 1 'ls -lt .buildroot/output/build | head -n 20'
    - Check the final image path appears:
      ls -l .buildroot/output/images/sdcard.img
    - For more verbose compiler lines (when launching your own build):

- Q3 (User, verbatim):
  "What's the OS runtime and userspace size on the target disk of this image?  We didn't discuss size targets for this kernel and userspace build."

  - Assistant (verbatim):
    Here’s what the image actually contains and how much space it uses on-disk.

    Measured sizes from the built artifacts
    I inspected the Buildroot output directory and used ls (apparent size) and du (actual disk usage). Buildroot images are sparse files, so ls -lh will look larger than what’s truly stored; du -h shows real usage.

    - sdcard.img
      - Apparent size: 153 MB
      - Actual disk usage: ~42 MB
    - boot.vfat (FAT boot partition image; includes kernel, DTB, firmware)
      - Actual disk usage: ~11 MB
    - rootfs.ext2 (root filesystem image)
      - Actual disk usage: ~31 MB
    - Kernel zImage (also packed into boot.vfat): ~6.8 MB
    - DTB (device tree): ~32 KB
    - rpi-firmware directory (also packed into boot.vfat): ~4.4 MB

    What that means on the target
    - Before expansion: The image writes a small boot + rootfs. Used space totals roughly boot.vfat (~11 MB) + rootfs (~31 MB) ≈ ~42 MB.
    - After expansion (we added automatic full-disk expansion after flashing):
      - The root partition grows to fill the entire device.
      - Used space remains roughly ~42 MB; the rest of the space is free.

    How to confirm on the device
    - Check used and free space after boot:
      - df -h /
    - See top-level usage breakdown:
      - du -xh --max-depth=1 /

    Notes on size targets
    - Current base (Option 3 Hello World) is very lean: ~42 MB used (OS + kernel + firmware + minimal BusyBox userspace).
    - Reasonable targets as we add features:
      - Base OS (kernel + BusyBox + essentials): <= 64 MB used
      - + Wi‑Fi (wpa_supplicant + DHCP) + SSH (dropbear or openssh): <= 80–90 MB used
      - + Your Go broker (static or dyn-linked): add ~5–15 MB depending on build
      - Overall target for production with networking + SSH + broker: <= ~100 MB used
    - If we want even smaller:
      - Prefer musl toolchain over glibc in Buildroot (typically shrinks userspace).
      - Keep BusyBox minimal, remove non-essential applets.
      - Avoid pulling in heavy packages; strip binaries/libraries (Buildroot’s default does).
      - Trim locales, docs, and kernel modules not needed (use a minimal defconfig + prune modules).
      - Optionally consider squashfs for root with an overlay (smaller at rest, read-only base).

    If you want, I can:
    - Add a size budget to docs/BUILDROOT.md and lock targets per milestone.
    - Switch to a musl toolchain and regenerate the image to quantify the savings.
    - Produce a size report script (host-side and on-device) for quick auditing with each build.

      make tartigrade-image V=1

- Q4 (User, verbatim):
  "How much effort would it be to rename all 'tartigrade' references/directories/filenames to 'tardigrade' (omit the quotes, of course).  Scripts will need to be updated too, and any other artifact bearing the name 'tartigrade'. I mispelled 'tardigrade' and I'm embarrassed."

  - Assistant (verbatim):
    Short answer
    Low effort. Expect ~20–40 minutes end-to-end:
    - 5–10 min to inventory all occurrences
    - 5–10 min to rename directory, update scripts/Makefile/docs
    - 10–20 min to rebuild and sanity‑boot test

    What changes are needed
    - Directory and filenames
      - Rename directory: tartigrade → tardigrade
      - Update any paths that reference tartigrade (Makefile targets, scripts)
    - Strings and identifiers
      - Update messages and tags (e.g., “hello from tartigrade…”, logger tag)
      - Update journal/docs references
    - Build/test
      - Rebuild image, reflash, verify boot and hello message still appear
      - Smoke check the flash script path updates

    Proposed steps (safe and reversible)
    - Inventory occurrences (fast)
      - Search all files for “tartigrade” to get a precise list
    - Apply renames
      - git mv tartigrade tardigrade
      - Update Makefile targets and calls (tartigrade-image/… → tardigrade-…)
      - Update scripts (paths and text strings)
      - Update hello script message and logger tag
      - Update docs (JOURNAL.md, BUILDROOT.md, etc.)
    - Verify
      - make tardigrade-image → now tardigrade-image (or your preferred target name)
      - Reflash; confirm console and motd show “tardigrade”
      - Quick on-device df -h sanity check (unchanged by rename)

    Example of minimal edits
    - Makefile target rename:
      tardigrade-image:
        bash tardigrade/build-image.sh

    - Hello script message/tag:
      MSG="hello from tardigrade: minimal boot successful"
      logger -t tardigrade "$MSG" 2>/dev/null || true

    Notes
    - Git submodule (.buildroot) is unaffected.
    - Journal updates will be included (verbatim) as part of the checkpoint once done.

    If you’d like, I can proceed now and keep this as a “rename checkpoint” in the journal. Prefer target names “tardigrade-image/tardigrade-flash,” or keep old target names for continuity?

  - Decision: Per user, skip the rename for now; captured here for a future checkpoint.


- Objective: Replace Raspberry Pi OS Lite with a minimal Buildroot-based OS that boots without any first-boot interaction and runs the broker under tight constraints.
- Decision: Start with the smallest practical boot target that still allows incremental growth.
- Options considered:
  - Option 1: Minimal userspace with shell (pwd available)
  - Option 2: Kernel-only or near-kernel print and runloop (no userspace)
  - Option 3: Root-only minimal userspace (busybox), prints hello, then continues — chosen for Hello World
- Rationale: Option 3 gives a working userspace for later networking/SSH while remaining extremely small. We will later add a non-root user for the broker.
- Status: Locked.

### Step 1: Hello World — Minimal Boot (Option 3)
- Objective: Boot on RPi Zero 2 W into a root-only busybox system that prints "hello" at boot and stays running; console responsive.
- Deliverables:
  - Buildroot external tree (br/external) with defconfig and overlay
  - Init script that echoes "hello" and continues
  - sdcard.img builds unattended via `make br-image`
  - Flash via `make br-flash` and verify on hardware
- Verification:
  - Device boots to console without wizard
  - Boot log shows our "hello" line
  - Login as root on serial/HDMI console; shell available
- Status: Complete.

### Step 2: Networking Bring-Up (Wi-Fi + Static IP)
- Objective: Add wpa_supplicant + dhcpcd (or udhcpc) to bring up wlan0 with static IP.
- Verification:
  - `ip addr` shows wlan0 with configured address
  - Host can ping device
- Status: Pending.

### Step 3: SSH Enablement and Key Injection
- Objective: Include OpenSSH server; install authorized_keys for unattended access.
- Verification:
  - Host can `ssh root@STATIC_IP` using the injected key
- Status: Pending.

### Step 4: App Layout and Init Integration
- Objective: Install /opt/$APP_NAME/releases/$VERSION layout; start app at boot using init script as root (temporary).
- Verification:
  - App runs on boot; logs show startup
- Status: Pending.

### Step 5: Drop Privileges (Non-root Runtime)
- Objective: Add minimal unprivileged user and run broker as that user.
- Verification:
  - Process UID is the unprivileged user; app functions normally
- Status: Pending.

### Step 6: OTA Compatibility Test
- Objective: Reuse existing host-side OTA scripts to deploy a new version over SSH.
- Verification:
  - Upload, switch `current` symlink, restart succeeds; rollback works
- Status: Pending.

---

Appendix: Success Criteria Summary
- No first-boot prompts, ever.
- Deterministic boot; console available.
- Minimal footprint; add only what is necessary.
- Every step is validated on real hardware.

