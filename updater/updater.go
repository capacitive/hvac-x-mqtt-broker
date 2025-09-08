package updater

import (
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"time"
)

func StartUpdateServer() {
	http.HandleFunc("/update", handleUpdate)
	http.HandleFunc("/config", handleConfig)
	http.HandleFunc("/status", handleStatus)
	
	go announcePresence()
	
	log.Println("Update server starting on :8081")
	http.ListenAndServe(":8081", nil)
}

func handleUpdate(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	
	file, err := os.Create("/tmp/mqtt-broker-new")
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer file.Close()
	
	_, err = io.Copy(file, r.Body)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	
	os.Chmod("/tmp/mqtt-broker-new", 0755)
	
	// Replace binary and restart
	go func() {
		time.Sleep(1 * time.Second)
		exec.Command("pkill", "mqtt-broker").Run()
		os.Rename("/tmp/mqtt-broker-new", "/opt/hvac-mqtt/mqtt-broker")
		exec.Command("/opt/hvac-mqtt/mqtt-broker").Start()
	}()
	
	fmt.Fprintf(w, "Update scheduled")
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "HVAC MQTT Broker - Ready for updates")
}

func handleConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	
	file, err := os.Create("/opt/hvac-mqtt/broker-config.yml")
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer file.Close()
	
	_, err = io.Copy(file, r.Body)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	
	fmt.Fprintf(w, "Config updated")
}

func announcePresence() {
	conn, err := net.Dial("udp", "255.255.255.255:9999")
	if err != nil {
		return
	}
	defer conn.Close()
	
	for {
		conn.Write([]byte("HVAC-MQTT-192.168.1.23"))
		time.Sleep(30 * time.Second)
	}
}