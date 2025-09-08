#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo ./scripts/create-image.sh"
    exit 1
fi

echo "Creating bootable Raspberry Pi image..."

# Build ARM binary
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"
GOOS=linux GOARCH=arm GOARM=6 /usr/local/go/bin/go build -o mqtt-broker .

# Download minimal kernel and bootloader for Pi Zero
wget -q https://github.com/raspberrypi/firmware/raw/master/boot/kernel.img -O kernel.img
wget -q https://github.com/raspberrypi/firmware/raw/master/boot/bootcode.bin -O bootcode.bin
wget -q https://github.com/raspberrypi/firmware/raw/master/boot/start.elf -O start.elf

# Create 512MB image (minimal)
dd if=/dev/zero of=pi-hvac.img bs=1M count=512

# Create partition table
parted pi-hvac.img mklabel msdos
parted pi-hvac.img mkpart primary fat32 1MiB 64MiB
parted pi-hvac.img mkpart primary ext4 64MiB 100%

# Setup loop device
LOOP_DEV=$(losetup --find --show pi-hvac.img)
partprobe $LOOP_DEV

# Format partitions
mkfs.vfat ${LOOP_DEV}p1  # Boot partition
mkfs.ext4 ${LOOP_DEV}p2  # Root partition

# Mount partitions
mkdir -p /mnt/{boot,root}
mount ${LOOP_DEV}p1 /mnt/boot
mount ${LOOP_DEV}p2 /mnt/root

# Copy kernel and bootloader to boot partition
cp kernel.img bootcode.bin start.elf /mnt/boot/

# Create boot config
cat > /mnt/boot/config.txt << 'EOF'
arm_freq=700
core_freq=250
sdram_freq=400
over_voltage=0
disable_overscan=1
gpu_mem=16
EOF

# Create minimal root filesystem
mkdir -p /mnt/root/{bin,sbin,etc,proc,sys,dev,tmp,var,opt,home,usr/bin}
mkdir -p /mnt/root/etc/{systemd/system,init.d}
mkdir -p /mnt/root/opt/hvac-mqtt

# Copy essential binaries (from host - these are the "distribution" parts)
cp /bin/sh /mnt/root/bin/
cp /bin/bash /mnt/root/bin/
cp /usr/bin/pkill /mnt/root/usr/bin/
cp /sbin/init /mnt/root/sbin/

# Copy our application
cp mqtt-broker /mnt/root/opt/hvac-mqtt/
cp broker-config.yml /mnt/root/opt/hvac-mqtt/
chmod +x /mnt/root/opt/hvac-mqtt/mqtt-broker

# Create init script that starts MQTT broker at boot
cat > /mnt/root/sbin/init << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Start MQTT broker with log streaming
cd /opt/hvac-mqtt
./mqtt-broker 2>&1 | tee /tmp/mqtt-logs | tail -n 20 &

# Display logs on console
tail -n 20 -f /tmp/mqtt-logs &

# Keep system running
while true; do sleep 3600; done
EOF
chmod +x /mnt/root/sbin/init



# Cleanup
umount /mnt/boot /mnt/root
losetup -d $LOOP_DEV
rm -f kernel.img bootcode.bin start.elf

echo "Bootable image created: pi-hvac.img"