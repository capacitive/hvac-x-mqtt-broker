package main

import (
	"bytes"
	"fmt"
	"log"
	"mqtt-broker/config"
	"mqtt-broker/logger"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"

	"github.com/antchfx/jsonquery"
	mqtt "github.com/mochi-mqtt/server/v2"
	"github.com/mochi-mqtt/server/v2/hooks/auth"
	"github.com/mochi-mqtt/server/v2/listeners"
	"github.com/mochi-mqtt/server/v2/packets"
)

var broker *mqtt.Server

const blowerCtrlClientID = "blower-ctrl"

type ConnectionHandlerOptions struct {
	Server *mqtt.Server
}

type ConnectionHandler struct {
	mqtt.HookBase
	config *ConnectionHandlerOptions
}

func (ch *ConnectionHandler) ID() string {
	return "connection-handler"
}

func (ch *ConnectionHandler) Provides(b byte) bool {
	return bytes.Contains([]byte{
		mqtt.OnConnect,
		mqtt.OnDisconnect,
		mqtt.OnSubscribe,
		mqtt.OnUnsubscribe,
		mqtt.OnPublished,
		mqtt.OnPublish,
		mqtt.OnClientExpired,
	}, []byte{b})
}

func (ch *ConnectionHandler) Init(config any) error {
	ch.Log.Info("initialized")
	if _, ok := config.(*ConnectionHandlerOptions); !ok && config != nil {
		return mqtt.ErrInvalidConfigType
	}

	ch.config = config.(*ConnectionHandlerOptions)
	if ch.config.Server == nil {
		return mqtt.ErrInvalidConfigType
	}
	return nil
}

func (ch *ConnectionHandler) OnConnect(client *mqtt.Client, packet packets.Packet) error {
	ch.Log.Info("client connected", "client", client.ID)
	broker.Subscribe("starcaf/contrl/sensor/hvac/sail/attributes", 2909, subscribeCallbackSail)

	if client.ID == blowerCtrlClientID {
		broker.Publish("starcaf/contrl/sensor/hvac/blower-ctrl/state", []byte("CONNECTED"), false, 0)
	}

	return nil
}

func (ch *ConnectionHandler) OnDisconnect(client *mqtt.Client, err error, expire bool) {
	ch.Log.Info("client disconnected", "client", client.ID, "IP", client.Net.Conn.LocalAddr(), "expire", expire, "error", err)
	broker.Unsubscribe("starcaf/contrl/sensor/hvac/sail/attributes", 2909)
	client.Stop(err)
	//client.Net.Conn.Close()
}

func (ch *ConnectionHandler) OnClientExpired(client *mqtt.Client) {
	ch.Log.Info("client expired", "client", client.ID, "IP", client.Net.Conn.LocalAddr())
	broker.Unsubscribe("starcaf/contrl/sensor/hvac/sail/attributes", 2909)
	client.Stop(nil)
	rebootRestartBroker()
	//client.Net.Conn.Close()
}

func rebootRestartBroker() {
	cmd := exec.Command("sudo", "reboot")
	//cmd.Stdout = os.Stdout
	//cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	if err != nil {
		fmt.Println(err)
	}
	fmt.Println(string(out))
}

var subscribeCallbackSail = func(caller *mqtt.Client, sub packets.Subscription, packet packets.Packet) {
	deviceName := packet.TopicName[27:33]
	MQTTPayload := string(packet.Payload)
	incomingPayload, err := jsonquery.Parse(strings.NewReader(MQTTPayload))

	if err != nil {
		broker.Log.Warn("jsonquery.Parse FAIL", "error", err)
		return
	}

	toggled := jsonquery.FindOne(incomingPayload, "fan-sensor").Value().(string)

	broker.Log.Info("[sub:"+caller.ID+"]", "id", sub.Identifier, "deviceName", deviceName, "payload", MQTTPayload)

	cfg, _ := config.LoadConfig()
	broker.Log.Info("Devices in config", "plugs", cfg.Devices.Plugs)

	for _, plug := range cfg.Devices.Plugs.IDList {
		plugCommand := fmt.Sprintf(cfg.Devices.Plugs.Command, plug)
		if toggled == "ON" {
			broker.Publish(plugCommand, []byte("ON"), false, 0)
			broker.Log.Info("[PUBLISH] command sent", "Command", plugCommand, "Payload", "ON")
		} else if toggled == "OFF" {
			broker.Publish(plugCommand, []byte("OFF"), false, 0)
			broker.Log.Info("[PUBLISH] command sent", "Command", plugCommand, "Payload", "OFF")
		}
	}
}

func main() {
	//create signals channel to run server until interrupted
	sigs := make(chan os.Signal, 1)
	done := make(chan bool, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigs
		done <- true
	}()

	/*
		create new MQTT broker
		options: inline client enables server to pub/sub messages of its own
	*/
	broker = mqtt.New(&mqtt.Options{
		InlineClient: true,
	})

	_ = broker.AddHook(new(auth.AllowHook), nil)

	cfg, err := config.LoadConfig()
	if err != nil {
		broker.Log.Info("Error loading broker's extended config")
		log.Fatal(err)
	} else {
		broker.Log.Info("Extended config successfully loaded.", "Devices", cfg.Devices.Plugs.IDList)

		for _, plug := range cfg.Devices.Plugs.IDList {
			plugCommand := fmt.Sprintf(cfg.Devices.Plugs.Command, plug)
			broker.Log.Info("[PUBLISH] pre-command TEST", "Command", plugCommand)
		}

		for _, plug := range cfg.Devices.Switches.IDList {
			plugCommand := fmt.Sprintf(cfg.Devices.Switches.Command, plug)
			broker.Log.Info("[PUBLISH] pre-command TEST", "Command", plugCommand)
		}
	}

	//create a TCP Listener on a standard port:
	tcp := listeners.NewTCP("mqtt-broker", cfg.Server.Host+":"+cfg.Server.Port, nil)
	listenError := broker.AddListener(tcp)
	if listenError != nil {
		log.Fatal(listenError)
	}

	err = broker.AddHook(new(ConnectionHandler), &ConnectionHandlerOptions{
		Server: broker,
	})
	if err != nil {
		log.Fatal(err)
	}

	// Start log streaming services
	logger.StartLogServices()

	go func() {
		systemError := broker.Serve()
		if systemError != nil {
			log.Fatal(systemError)
		}
	}()

	//run broker until interrupted:
	<-done
	broker.Log.Warn("Captured signal, stopping...")
	_ = broker.Close()
	broker.Log.Info("Broker main thread finished.")
}
