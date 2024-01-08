package main

import (
	"bytes"
	"fmt"
	"log"
	"mqtt-broker/config"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/antchfx/jsonquery"
	mqtt "github.com/mochi-mqtt/server/v2"
	"github.com/mochi-mqtt/server/v2/hooks/auth"
	"github.com/mochi-mqtt/server/v2/listeners"
	"github.com/mochi-mqtt/server/v2/packets"
)

type TelemetryEvent struct {
	MemberId   int     `json:"memberId"`
	DeviceId   int     `json:"deviceId"`
	DeviceName string  `json:"deviceName"`
	Wattage    float64 `json:"wattage"`
	Rssi       float64 `json:"rssi"`
}

type DeviceRegistration struct {
	Name       string `json:"deviceName"`
	MemberId   int    `json:"memberId"`
	DeviceId   int    `json:"deviceId"`
	MacAddress string `json:"macAddress"`
}

type CronSetup struct {
	ThresholdLT  float32  `json:"thresholdLT"`
	Enabled      bool     `json:"enabled"`
	LastExchange Exchange `json:"lastExchange"`
}

type Exchange struct {
	Type               string `json:"type"`
	WpId               string `json:"wpId"`
	UserId             string `json:"userId"`
	ConfirmationEmail  string `json:"confirmationEmail"`
	ConfirmationNumber string `json:"confirmationNumber"`
	CreatedAt          string `json:"createdAt"`
	ExpiresAt          string `json:"expiresAt"`
	OrderLink          string `json:"orderLink"`
	OrderId            string `json:"orderId"`
	Status             string `json:"status"`
	UpdatedAt          string `json:"updatedAt"`
	To                 FromTo `json:"to"`
	From               FromTo `json:"from"`
}

type FromTo struct {
	Amount   int    `json:"amount"`
	LpId     string `json:"lpId"`
	MemberId string `json:"memberId"`
}

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
	//broker.Subscribe("switchbot/blower-ctrl/plug/hvac/attributes", 3804, subscribeCallbackInlineFan)
	//broker.Subscribe("switchbot/blower-ctrl/plug/test/attributes", 3804, subscribeCallbackInlineFan)
	return nil
}

func (ch *ConnectionHandler) OnDisconnect(client *mqtt.Client, err error, expire bool) {
	broker.Unsubscribe("starcaf/contrl/sensor/hvac/sail/attributes", 2909)

	if err != nil {
		ch.Log.Info("client disconnected", "client", client.ID, "IP", client.Net.Conn.LocalAddr(), "expire", expire, "error", err)
		client.Net.Conn.Close()
		client.Stop(err)
	} else {
		ch.Log.Info("client disconnected", "client", client.ID, "expire", expire)
		client.Stop(nil)
	}
}

func (ch *ConnectionHandler) OnClientExpired(client *mqtt.Client) {
	ch.Log.Info("client expired", "client", client.ID)
	broker.Unsubscribe("starcaf/contrl/sensor/hvac/sail/attributes", 2909)
	client.Net.Conn.Close()
	client.Stop(nil)
}

var broker *mqtt.Server
var cfg config.Config

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

	// if toggled == "ON" {
	// 	broker.Publish("switchbot/blower-ctrl/plug/hvac-f/set", []byte("ON"), false, 0)
	// } else {
	// 	broker.Publish("switchbot/blower-ctrl/plug/hvac-f/set", []byte("OFF"), false, 0)
	// }

	for _, plug := range cfg.Devices.Plugs {
		plugCommand := fmt.Sprintf("switchbot/blower-ctrl/plug/%s/set", plug)
		if toggled == "ON" {
			broker.Publish(plugCommand, []byte("ON"), false, 0)
			broker.Log.Info("[PUBLISH] command sent", "Command", plugCommand+"ON", "BLE MAC", plug)
		} else if toggled == "OFF" {
			broker.Publish(plugCommand, []byte("OFF"), false, 0)
			broker.Log.Info("[PUBLISH] command sent", "Command", plugCommand+"OFF", "BLE MAC", plug)
		}
	}
}

// var subscribeCallbackInlineFan = func(caller *mqtt.Client, sub packets.Subscription, packet packets.Packet) {
// 	deviceName := packet.TopicName[27:31]
// 	MQTTPayload := string(packet.Payload)
// 	incomingPayload, err := jsonquery.Parse(strings.NewReader(MQTTPayload))

// 	if err != nil {
// 		broker.Log.Warn("jsonquery.Parse FAIL", "error", err)
// 		return
// 	}

// 	broker.Log.Info("[sub:"+caller.ID+"]", "id", sub.Identifier, "deviceName", deviceName, "payload", incomingPayload)
// }

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
		// Capabilities: &mqtt.Capabilities{
		// 	MaximumSessionExpiryInterval: 1000,
		// },
		InlineClient: true,
	})

	_ = broker.AddHook(new(auth.AllowHook), nil)

	cfg, err := config.LoadConfig()
	if err != nil {
		broker.Log.Info("Error loading broker's extended config")
		log.Fatal(err)
	} else {
		broker.Log.Info("Extended config successfully loaded.", "baseUrl", cfg.CloudApi.BaseUrl)
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

	// subscribeCallbackSail := func(caller *mqtt.Client, sub packets.Subscription, packet packets.Packet) {
	// 	deviceName := packet.TopicName[27:31]
	// 	MQTTPayload := string(packet.Payload)
	// 	incomingPayload, err := jsonquery.Parse(strings.NewReader(MQTTPayload))

	// 	if err != nil {
	// 		broker.Log.Warn("jsonquery.Parse FAIL", "error", err)
	// 		return
	// 	}

	// 	toggled := jsonquery.FindOne(incomingPayload, "fan-sensor").Value().(string)

	// 	broker.Log.Info("[sub:"+caller.ID+"]", "id", sub.Identifier, "deviceName", deviceName, "payload", MQTTPayload)
	// 	if toggled == "ON" && cfg.Server.ControlDevices {
	// 		broker.Publish("switchbot/blower-ctrl/plug/heat/set", []byte("ON"), false, 0)
	// 	} else if cfg.Server.ControlDevices {
	// 		broker.Publish("switchbot/blower-ctrl/plug/heat/set", []byte("OFF"), false, 0)
	// 	}

	// }
	//broker.Subscribe("switchbot/blower-ctrl/plug/heat/attributes", 3804, subscribeCallback)
	//broker.Subscribe("switchbot/blower-ctrl/plug/hvac/attributes", 3804, subscribeCallback)
	//broker.Subscribe("starcaf/contrl/sensor/hvac/sail/attributes", 2909, subscribeCallbackSail)

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
