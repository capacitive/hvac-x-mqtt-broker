# HVAC MQTT Broker Logging

## Console Logging
- Last 20 log entries displayed on Pi Zero console
- Real-time streaming with timestamps
- Automatic log rotation

## Remote Monitoring

### WebSocket Endpoint
```
ws://192.168.1.23:8080/logs
```

### gRPC Endpoint
```
192.168.1.23:9090
```

## Usage

### View Logs Locally
```bash
# Logs automatically display on Pi console
# Last 20 entries shown with timestamps
```

### Remote WebSocket Client
```javascript
const ws = new WebSocket('ws://192.168.1.23:8080/logs');
ws.onmessage = (event) => {
    const log = JSON.parse(event.data);
    console.log(log.message);
};
```

### Test Connection
```bash
# WebSocket test
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: test" -H "Sec-WebSocket-Version: 13" \
  http://192.168.1.23:8080/logs
```

## Features
- Real-time log streaming
- 20-entry rolling buffer
- WebSocket and gRPC endpoints
- Console display with timestamps
- Automatic startup with broker