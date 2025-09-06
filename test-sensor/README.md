# Test Sensor

Emulates a sail-sensor's behavior for testing the HVAC MQTT broker.

## Environment Variables

- `BROKER_URL` - MQTT broker URL (default: tcp://localhost:1883)
- `CLIENT_ID` - MQTT client ID (default: test-sail-sensor)
- `TOPIC` - Publish topic (default: starcaf/contrl/sensor/hvac/sail/attributes)
- `INTERVAL` - Auto mode interval (default: 100ms)

## Usage

1. Start the MQTT broker first
2. Run: `./test-sensor`

## Commands

- `on` - Set sensor ON
- `off` - Set sensor OFF
- `auto` - Toggle rapid succession mode
- `quit` - Exit