### Test App (mini service)

I would like you to create a small test app that emulates a sail-sensor's behaviour.
The application in this repo acts as an event server/broker and has a ./broker-config.yml configuration, and you can see what incoming connections and events look like on lines 110-127 of ./main.go. You can extrapolate a test app by referencing the various event handlers (OnConnect, OnDisconnect, etc.) in the existing code of ./main.go  I would like the test app to the emulate behaviour of each event type so that tests can cover a wide range of scenarios.I would also like the test app to be able to emulate a sensor getting sporadic readings of an ON/OFF state in rapid succession - this is for the purpose of improving the server/broker's event handler to ignore rapid-fire events and only act on stable states.  The test app should have two modes that can be live-toggled: 
1. Simulate the sensor's ON or OFF state (manual mode).
2. Simulate the sensor's ON/OFF state in rapid succession (auto mode).

### Test App (GUI)
 Give the test app mini service app a front-end that allows for live-toggling of modes and manual state changes. Use svelte or react/electron, or any other framework that allows for a zero dependency or self-contained build that can be served from an embedded device or any machine that can serve web pages. Assume the service will be running on a local device with an ARM architecture.