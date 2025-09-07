#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo ./scripts/create-complete-image.sh"
    exit 1
fi

echo "Creating complete bootable Raspberry Pi image..."

# Build ARM binary
GOOS=linux GOARCH=arm GOARM=6 go build -o mqtt-broker .

# Download minimal kernel and bootloader for Pi Zero
wget -q https://github.com/raspberrypi/firmware/raw/master/boot/kernel.img -O kernel.img
wget -q https://github.com/raspberrypi/firmware/raw/master/boot/bootcode.bin -O bootcode.bin
wget -q https://github.com/raspberrypi/firmware/raw/master/boot/start.elf -O start.elf

# Create 512MB image (minimal)
dd if=/dev/zero of=pi-hvac-complete.img bs=1M count=512

# Create partition table
parted pi-hvac-complete.img mklabel msdos
parted pi-hvac-complete.img mkpart primary fat32 1MiB 64MiB
parted pi-hvac-complete.img mkpart primary ext4 64MiB 100%

# Setup loop device
LOOP_DEV=$(losetup --find --show pi-hvac-complete.img)
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

# Enable SSH for OTA updates
/usr/sbin/sshd -D &

# Start MQTT broker
cd /opt/hvac-mqtt
./mqtt-broker &

# Keep system running
while true; do sleep 3600; done
EOF
chmod +x /mnt/root/sbin/init

# Copy SSH daemon for OTA access
cp /usr/sbin/sshd /mnt/root/usr/sbin/ 2>/dev/null || echo "SSH not available"

# Cleanup
umount /mnt/boot /mnt/root
losetup -d $LOOP_DEV
rm -f kernel.img bootcode.bin start.elf

echo "Complete bootable image created: pi-hvac-complete.img"