package main

import (
	"bytes"
	"encoding/json"
	"log"
	"mqtt/config"
	"net/http"
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
	broker := mqtt.New(&mqtt.Options{
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

	//inline client for subscription (callback func POSTs to Exchange cloud service):
	subscribeCallback := func(caller *mqtt.Client, sub packets.Subscription, packet packets.Packet) {
		deviceName := packet.TopicName[27:31]
		MQTTPayload := string(packet.Payload)
		incomingPayload, err := jsonquery.Parse(strings.NewReader(MQTTPayload))

		if err != nil {
			broker.Log.Warn("jsonquery.Parse FAIL", "error", err)
			return
		}

		watts := jsonquery.FindOne(incomingPayload, "energy").Value().(float64)
		rssi := jsonquery.FindOne(incomingPayload, "rssi").Value().(float64)

		broker.Log.Info("[sub:"+caller.ID+"]", "memberId", sub.Identifier, "deviceName", deviceName, "watts", watts, "rssi", rssi, "payload", MQTTPayload)

		if cfg.CloudApi.CallsEnabled {
			event := TelemetryEvent{
				DeviceId:   sub.Identifier,
				MemberId:   sub.Identifier,
				DeviceName: deviceName,
				Wattage:    watts,
				Rssi:       rssi,
			}

			var arr []TelemetryEvent
			arr = append(arr, event)
			outgoingPayload, err := json.Marshal(arr)
			if err != nil {
				log.Fatal(err)
				return
			}

			telemetryResponse, err := http.Post(cfg.CloudApi.BaseUrl+cfg.CloudApi.Telemetry, "application/json", bytes.NewReader(outgoingPayload))
			if err != nil {
				broker.Log.Warn("Could not POST to Exchange Cloud Service")
			}
			defer telemetryResponse.Body.Close()
			broker.Log.Info("POST successful.", "status code", telemetryResponse.StatusCode)
		}

		// cronStatusResponse, err := http.Get(cfg.CloudApi.BaseUrl + cfg.CloudApi.Cron)
		// if err != nil {
		// 	broker.Log.Warn("Could not GET Exchange order status")
		// }
		// defer cronStatusResponse.Body.Close()
		// cron := CronSetup{}
		// errDecode := json.NewDecoder(cronStatusResponse.Body).Decode(&cron)
		// if errDecode != nil {
		// 	broker.Log.Warn("error decoding cron data:", "error", errDecode)
		// } else {
		// 	broker.Log.Info("Latest Exchange order:", "data", cron)
		// }
	}

	subscribeCallbackSail := func(caller *mqtt.Client, sub packets.Subscription, packet packets.Packet) {
		deviceName := packet.TopicName[27:31]
		MQTTPayload := string(packet.Payload)
		incomingPayload, err := jsonquery.Parse(strings.NewReader(MQTTPayload))

		if err != nil {
			broker.Log.Warn("jsonquery.Parse FAIL", "error", err)
			return
		}

		toggled := jsonquery.FindOne(incomingPayload, "fan-sensor").Value().(string)

		broker.Log.Info("[sub:"+caller.ID+"]", "id", sub.Identifier, "deviceName", deviceName, "payload", MQTTPayload)
		if toggled == "ON" && cfg.Server.ControlDevices {
			broker.Publish("switchbot/blower-ctrl/plug/heat/set", []byte("ON"), false, 0)
		} else if cfg.Server.ControlDevices {
			broker.Publish("switchbot/blower-ctrl/plug/heat/set", []byte("OFF"), false, 0)
		}

	}
	//broker.Subscribe("switchbot/blower-ctrl/plug/heat/attributes", 3804, subscribeCallback)
	broker.Subscribe("switchbot/blower-ctrl/plug/hvac/attributes", 3804, subscribeCallback)
	broker.Subscribe("starcaf/contrl/sensor/hvac/sail/attributes", 2909, subscribeCallbackSail)

	//create a TCP Listener on a standard port:
	tcp := listeners.NewTCP("mqtt-broker", ":1883", nil)
	listenError := broker.AddListener(tcp)
	if listenError != nil {
		log.Fatal(listenError)
	}

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

type BroekerHook struct {
	mqtt.HookBase
}
