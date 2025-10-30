# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Development Commands

### Building and Running
```bash
# Build for local development (host architecture)
make build

# Cross-compile for Raspberry Pi Zero W (ARMv6)
make build-arm

# Run the broker locally (for testing)
./build/hvacx-broker

# Run test sensor for local development
cd test-sensor && go run main.go
```

### Raspberry Pi Deployment
```bash
# Create bootable SD card image with pre-installed app
make image STATIC_IP=192.168.1.100 MQTT_PORT=1883 HOSTNAME=hvacx-broker

# Flash image to SD card (interactive device selection)
make flash

# Over-the-air deployment to running Pi
make deploy PI_HOST=192.168.1.100 PI_USER=root

# Rollback to previous version on device
make rollback PI_HOST=192.168.1.100
```

### Testing and Development
```bash
# Test MQTT connectivity (requires netcat)
nc -zv <PI_HOST> 1883

# View systemd service logs on Pi (via SSH)
ssh root@<PI_HOST> "journalctl -u hvacx-broker.service -f"

# Check service status on Pi
ssh root@<PI_HOST> "systemctl status hvacx-broker.service"
```

### Cleanup
```bash
# Remove build artifacts and images
make clean
```

## Architecture Overview

### Core Components

**MQTT Broker (`main.go`)**
- Custom MQTT broker built on mochi-mqtt/server
- Handles HVAC sensor connections and device control
- Features connection lifecycle management with auto-restart on client expiry
- Implements custom subscription callback for sail sensor data processing

**Configuration System (`config/`)**
- YAML-based configuration loaded from executable directory
- Supports server settings, device mappings, and cloud API configuration
- Runtime configuration reloading for device control commands

**Test Infrastructure (`test-sensor/`)**
- Interactive TUI-based sensor emulator using Bubble Tea
- Emulates sail sensor behavior for development and testing
- Supports manual and automatic state toggling modes

### Data Flow Architecture

1. **Sensor Input**: Sail sensors publish JSON payloads to `starcaf/contrl/sensor/hvac/sail/attributes`
2. **Processing**: Broker parses JSON to extract `fan-sensor` state (ON/OFF)
3. **Device Control**: Based on state, broker publishes commands to configured plugs/switches
4. **State Management**: Connection handler manages client lifecycle and system health

### Configuration Structure

The broker uses a YAML configuration file (`broker-config.yml`) with these key sections:
- `server`: Host, port, and command sending settings  
- `devices.plugs`: List of plug IDs and command template for SwitchBot devices
- `devices.switches`: List of switch IDs and command template
- `cloudapi`: External API endpoints and feature flags

### Deployment Architecture

**Two-Phase Deployment System:**
1. **SD Card Image**: Creates complete Raspberry Pi OS Lite image with pre-installed broker
2. **OTA Updates**: Atomic deployments with SHA256 verification and rollback capability

**File System Layout on Pi:**
- `/opt/hvacx-broker/current/` - Active broker binary and config
- `/opt/hvacx-broker/releases/` - Version history for rollback
- `/opt/hvacx-broker/previous` - Previous version tracker

## Development Notes

### MQTT Topics
- **Sensor Input**: `starcaf/contrl/sensor/hvac/sail/attributes`
- **Device Commands**: `switchbot/blower-ctrl/plug/{device-id}/set`
- **Status**: `starcaf/contrl/sensor/hvac/blower-ctrl/state`

### Key Constants
- Special client ID `blower-ctrl` gets automatic state publishing on connect
- Hardcoded subscription ID `2909` for sail sensor callbacks
- Default MQTT port `1883`, configurable via build variables

### Environment Variables (Test Sensor)
- `BROKER_URL`: MQTT broker connection string (default: tcp://localhost:1883)
- `CLIENT_ID`: MQTT client identifier (default: test-sail-sensor)
- `TOPIC`: Publish topic for sensor data
- `INTERVAL`: Auto-mode toggle interval (default: 100ms)

### Build System
The Makefile supports extensive customization via environment variables including network settings (STATIC_IP, ROUTER_IP, DNS), WiFi credentials (WIFI_SSID, WIFI_PSK), and deployment options. All sensitive values are redacted in the default configuration and must be provided at build time.

### Local Module Dependencies
The project uses a local Go module replacement for `mqtt-broker/config v1.0.0 => ./config` to maintain configuration as a separate package while keeping it in the same repository.