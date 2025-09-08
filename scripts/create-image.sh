#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo ./scripts/create-image.sh"
    exit 1
fi

echo "Creating Pi Zero W image with Raspberry Pi OS Lite..."

# Get WiFi credentials
echo "WiFi Configuration:"
read -p "WiFi Network Name (SSID) [starcaf]: " WIFI_SSID
WIFI_SSID=${WIFI_SSID:-starcaf}
echo -n "WiFi Password: "
WIFI_PASSWORD=""
while IFS= read -r -s -n1 char; do
    if [[ $char == $'\0' ]]; then
        break
    elif [[ $char == $'\177' ]]; then
        if [ ${#WIFI_PASSWORD} -gt 0 ]; then
            WIFI_PASSWORD="${WIFI_PASSWORD%?}"
            echo -ne '\b \b'
        fi
    else
        WIFI_PASSWORD+="$char"
        echo -n '*'
    fi
done
echo
read -p "WiFi Country Code [CA]: " WIFI_COUNTRY
WIFI_COUNTRY=${WIFI_COUNTRY:-CA}
echo

# Remove existing output image
rm -f pi-hvac.img

# Build ARM binary
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"
GOOS=linux GOARCH=arm GOARM=6 /usr/local/go/bin/go build -buildvcs=false -o mqtt-broker .

# Check if we need to download Pi OS
if [ ! -f "raspios-lite.img.xz" ]; then
    echo "Downloading Raspberry Pi OS Lite..."
    wget -O raspios-lite.img.xz "https://downloads.raspberrypi.org/raspios_lite_armhf_latest"
else
    echo "Using cached Pi OS image (use 'rm raspios-lite.img.xz' to force re-download)"
fi

# Extract the image
echo "Extracting OS image..."
cp raspios-lite.img.xz raspios-lite-temp.img.xz
unxz raspios-lite-temp.img.xz
mv raspios-lite-temp.img pi-hvac.img

# Check if image exists
if [ ! -f "pi-hvac.img" ]; then
    echo "Error: Failed to create pi-hvac.img"
    exit 1
fi

# Mount the Pi OS image partitions
echo "Mounting Pi OS partitions..."
LOOP_DEV=$(losetup --find --show pi-hvac.img)
if [ -z "$LOOP_DEV" ]; then
    echo "Error: Failed to create loop device"
    exit 1
fi

partprobe $LOOP_DEV
sleep 2

# Mount existing partitions
mkdir -p /mnt/{boot,root}
mount ${LOOP_DEV}p1 /mnt/boot || { echo "Failed to mount boot partition"; exit 1; }
mount ${LOOP_DEV}p2 /mnt/root || { echo "Failed to mount root partition"; exit 1; }

# Customize Pi OS boot config for our needs
echo "Configuring boot settings..."
cat >> /mnt/boot/config.txt << 'EOF'

# HVAC MQTT Broker customizations
enable_uart=1
dtparam=spi=on
dtparam=i2c_arm=on
EOF

# Enable SSH by creating ssh file
echo "Enabling SSH access..."
touch /mnt/boot/ssh

# Configure WiFi with user-provided credentials
echo "Configuring WiFi ($WIFI_SSID)..."
cat > /mnt/boot/wpa_supplicant.conf << EOF
country=$WIFI_COUNTRY
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$WIFI_SSID"
    psk="$WIFI_PASSWORD"
    key_mgmt=WPA-PSK
}
EOF

# Create application directory
echo "Creating application directory..."
mkdir -p /mnt/root/opt/hvac-mqtt

# Configure static IP using dhcpcd (Pi OS standard)
echo "Configuring static IP (192.168.1.23)..."
cat > /mnt/root/etc/dhcpcd.conf << 'EOF'
# dhcpcd configuration for Pi Zero
hostname
clientid
persistent
option rapid_commit
option domain_name_servers, domain_name, domain_search, host_name
option classless_static_routes
option interface_mtu
require dhcp_server_identifier
slaac private

# Static IP for HVAC MQTT Broker
interface wlan0
static ip_address=192.168.1.23/24
static routers=192.168.1.1
static domain_name_servers=8.8.8.8 8.8.4.4
EOF

# Configure pi auto-login without password
echo "Configuring auto-login..."
mkdir -p /mnt/root/etc/systemd/system/getty@tty1.service.d
cat > /mnt/root/etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I $TERM
EOF

# Create pi user with password 'raspberry'
echo "pi:$(echo 'raspberry' | openssl passwd -6 -stdin)" > /mnt/boot/userconf
touch /mnt/boot/ssh

# Copy our application
echo "Installing HVAC MQTT Broker application..."
cp mqtt-broker /mnt/root/opt/hvac-mqtt/
cp broker-config.yml /mnt/root/opt/hvac-mqtt/
chmod +x /mnt/root/opt/hvac-mqtt/mqtt-broker
echo "Application files installed to /opt/hvac-mqtt/"

# Create systemd service for MQTT broker
echo "Creating systemd service for auto-startup..."
cat > /mnt/root/etc/systemd/system/hvac-mqtt.service << 'EOF'
[Unit]
Description=HVAC MQTT Broker
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/hvac-mqtt
ExecStart=/opt/hvac-mqtt/mqtt-broker
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable the service (create symlink manually since chroot won't work)
echo "Enabling HVAC MQTT service for startup..."
mkdir -p /mnt/root/etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/hvac-mqtt.service /mnt/root/etc/systemd/system/multi-user.target.wants/hvac-mqtt.service
echo "Service enabled - will start automatically on boot"

# Remove unnecessary services to minimize system
echo "Removing unnecessary services..."
rm -f /mnt/root/etc/systemd/system/multi-user.target.wants/bluetooth.service
rm -f /mnt/root/etc/systemd/system/multi-user.target.wants/hciuart.service
rm -f /mnt/root/etc/systemd/system/multi-user.target.wants/triggerhappy.service
rm -f /mnt/root/etc/systemd/system/multi-user.target.wants/avahi-daemon.service
echo "Unnecessary services removed"



# Cleanup
umount /mnt/boot /mnt/root 2>/dev/null || true
if [ -n "$LOOP_DEV" ]; then
    losetup -d $LOOP_DEV
fi

echo "✓ Pi Zero W image created: pi-hvac.img"
echo "✓ Image based on Raspberry Pi OS Lite with HVAC MQTT Broker pre-installed"
echo ""
echo "Configuration Summary:"
echo "  - Static IP: 192.168.1.23 (eth0 & wlan0)"
echo "  - MQTT Port: 1883"
echo "  - SSH: Enabled"
echo "  - Auto-login: pi user (no password required)"
echo "  - WiFi: $WIFI_SSID ($WIFI_COUNTRY)"
echo "  - Auto-start: hvac-mqtt.service"
echo "  - Application: /opt/hvac-mqtt/mqtt-broker"
echo "  - Minimized: Removed bluetooth, avahi, triggerhappy"
echo ""
echo "Ready to flash with: sudo make flash"