# HVAC MQTT Broker Deployment

## Workflow

1. **Create minimal OS image**: `make image`
2. **Flash to SD card**: `make flash`
3. **Deploy updates via OTA**: `make deploy`

## Commands

### Create Bootable Image
```bash
# Creates pi-hvac-complete.img (512MB)
make image
```

### Flash to SD Card
```bash
# Flash image to SD card (replace /dev/sdb with your device)
make flash
```

### OTA Updates
```bash
# Build and deploy to Pi at 192.168.1.23
make deploy
```

## Configuration

- Pi IP: 192.168.1.23
- MQTT Port: 1883
- User: root (no password)
- App runs automatically on boot
- SSH enabled for OTA access

## Files

- `scripts/ota-deploy.sh` - OTA deployment
- `scripts/create-complete-image.sh` - Complete OS image creation
- `scripts/flash-usb.sh` - SD card flashing
- `Makefile` - Build commands