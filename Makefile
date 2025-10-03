.PHONY: help build build-arm image flash deploy rollback clean

APP_NAME := mqtt-broker
BUILD_DIR := build
OUTPUT_IMG := pi-hvac.img

# Configurable defaults
STATIC_IP ?= 192.168.1.23
MQTT_PORT ?= 1883
ROUTER_IP ?= 192.168.1.1
DNS       ?= 1.1.1.1 8.8.8.8
HOSTNAME  ?= hvac-zero
WIFI_SSID ?=
WIFI_PSK  ?=
PI_HOST   ?= 192.168.1.23
PI_USER   ?= root
VERSION   ?= $(shell date +%Y%m%d-%H%M%S)

help:
	@echo "Targets:"
	@echo "  build         - Build local binary for host"
	@echo "  build-arm     - Cross-compile for Raspberry Pi Zero W (ARMv6)"
	@echo "  image         - Create Pi OS Lite image with app pre-installed"
	@echo "  flash         - Flash $(OUTPUT_IMG) to SD card (DEVICE=/dev/sdX)"
	@echo "  deploy        - OTA deploy to running Pi (PI_HOST=$(PI_HOST))"
	@echo "  rollback      - OTA rollback to previous version on device"
	@echo "  clean         - Remove build artifacts"

build:
	go build -o $(BUILD_DIR)/$(APP_NAME) ./

build-arm:
	CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=6 go build -o $(BUILD_DIR)/$(APP_NAME) ./

image: build-arm
	APP_NAME=$(APP_NAME) STATIC_IP=$(STATIC_IP) MQTT_PORT=$(MQTT_PORT) ROUTER_IP=$(ROUTER_IP) DNS="$(DNS)" HOSTNAME=$(HOSTNAME) \
	WIFI_SSID="$(WIFI_SSID)" WIFI_PSK="$(WIFI_PSK)" VERSION=$(VERSION) \
	bash scripts/create-image.sh

flash:
	@if [ -z "$(DEVICE)" ]; then echo "Usage: make flash DEVICE=/dev/sdX" && exit 1; fi
	sudo bash scripts/flash.sh $(DEVICE) $(OUTPUT_IMG)

deploy: build-arm
	APP_NAME=$(APP_NAME) PI_HOST=$(PI_HOST) PI_USER=$(PI_USER) VERSION=$(VERSION) PORT=$(MQTT_PORT) \
	bash scripts/ota/deploy.sh $(PI_HOST)

rollback:
	APP_NAME=$(APP_NAME) PI_HOST=$(PI_HOST) PI_USER=$(PI_USER) bash scripts/ota/rollback.sh $(PI_HOST)

clean:
	rm -rf $(BUILD_DIR) $(OUTPUT_IMG)

