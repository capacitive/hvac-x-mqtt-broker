# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

HVAC-X Hub is an MQTT broker-based IoT control system for HVAC devices. It acts as a middleware hub that receives sensor data and controls smart plugs/switches via MQTT, specifically designed for Raspberry Pi Zero deployment.

## Architecture

### Core Components

1. **MQTT Broker (`main.go`)**: Custom MQTT broker using mochi-mqtt/server that:
   - Listens for sensor data on topic `starcaf/contrl/sensor/hvac/sail/attributes`
   - Publishes control commands to Switchbot devices
   - Implements custom connection hooks (`ConnectionHandler`) to manage client lifecycle
   - Auto-reboots the system when specific clients expire
   - Uses inline client mode to allow the broker to pub/sub its own messages

2. **Configuration Module (`config/`)**: YAML-based configuration system that:
   - Loads `broker-config.yml` from the executable's directory at runtime
   - Defines server settings (host, port)
   - Manages device lists (plugs, switches) and their command templates
   - Cloud API endpoints (currently disabled via `callsenabled: false`)

3. **Test Sensor (`test-sensor/`)**: Interactive TUI application using Bubble Tea framework that:
   - Simulates HVAC sail sensor for testing
   - Publishes ON/OFF fan-sensor states
   - Supports manual and auto-toggle modes
   - Star Trek/LCARS themed UI

4. **RPi Zero Build Tools (`rpizero/`)**: Go utilities for managing Buildroot external tree structure for embedded deployment

### Data Flow

```
Sensor (test-sensor) → MQTT Publish → Broker (subscribeCallbackSail) → Parse JSON → 
Lookup plugs in config → Publish commands → Switchbot devices
```

Key topic structure:
- Sensor input: `starcaf/contrl/sensor/hvac/sail/attributes` (JSON: `{"fan-sensor": "ON|OFF"}`)
- Device control: `switchbot/blower-ctrl/plug/{device-id}/set` (Payload: `ON|OFF`)
- Blower state: `starcaf/contrl/sensor/hvac/blower-ctrl/state`

## Development Commands

### Build the broker
```bash
go build -o mqtt-broker main.go
```

### Run the broker
```bash
./mqtt-broker
# Requires broker-config.yml in same directory as executable
```

### Build test sensor
```bash
cd test-sensor
go build -o test-sensor main.go
```

### Run test sensor
```bash
cd test-sensor
./test-sensor
# Configure via environment variables or .env file
# BROKER_URL, CLIENT_ID, TOPIC, INTERVAL
```

### Run tests
```bash
# Test rpizero filesystem utilities
cd rpizero
go test -v

# Run all tests in repo
go test ./...
```

### Build RPi Zero filesystem tool
```bash
cd rpizero
go build -o filetests main.go
```

## Configuration

The broker requires `broker-config.yml` in the same directory as the executable. Key config sections:

- **server**: MQTT broker host/port
- **devices.plugs**: List of plug IDs and command template with `%s` placeholder
- **devices.switches**: Similar structure for switches
- **cloudapi**: External API endpoints (currently unused)

Example: `idlist: [hvac-f, hvac-r]` with `command: "switchbot/blower-ctrl/plug/%s/set"` generates topics like `switchbot/blower-ctrl/plug/hvac-f/set`

## Important Patterns

### Custom MQTT Hooks
The broker uses a custom `ConnectionHandler` hook to:
- Subscribe to sensor topics when clients connect
- Publish connection state for specific clients (e.g., `blower-ctrl`)
- Trigger system reboots on client expiration (embedded system recovery)
- Clean up subscriptions on disconnect

### JSON Payload Parsing
Uses `jsonquery` library to parse incoming MQTT payloads with XPath-like queries:
```go
toggled := jsonquery.FindOne(incomingPayload, "fan-sensor").Value().(string)
```

### Config Hot-Reloading
Config is loaded on each sensor message via `config.LoadConfig()` to support runtime changes without restart.

## Module Structure

This project uses Go workspace (`go.work`) with local module replacement:
```
replace mqtt-broker/config v1.0.0 => ./config
```

The `config` package is a separate module but developed in-tree.

## Testing Notes

- Tests use standard Go testing with table-driven patterns
- `rpizero/build_test.go` includes directory creation/deletion tests
- Test sensor can be used for end-to-end manual testing of the broker

## Embedded Deployment

The `rpi-zero-minimal-buildroot/` directory is a git submodule containing Buildroot configuration for cross-compiling to Raspberry Pi Zero. The `rpizero/` package provides Go tooling to generate the required external tree structure.

Binary `mqtt-broker` should be deployed alongside `broker-config.yml` to the target device.
