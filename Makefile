.PHONY: help build build-arm image flash deploy rollback clean

APP_NAME := hvacx-broker
BUILD_DIR := build
OUTPUT_IMG := ${APP_NAME}.img

# Configurable defaults
STATIC_IP ?= 192.168.1.23
MQTT_PORT ?= 1883
ROUTER_IP ?= 192.168.1.1
DNS       ?= 1.1.1.1 8.8.8.8
HOSTNAME  ?= hvacx-broker
WIFI_SSID ?= starcaf
WIFI_PSK  ?= T3l3p0rt
PI_HOST   ?= 192.168.1.23
PI_USER   ?= root
VERSION   ?= $(shell date +%Y%m%d-%H%M%S)

# Prompt for sudo during deploy/rollback if your environment needs it (0 or 1)
DEPLOY_NEEDS_SUDO ?= 0

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
	@echo "Sudo credentials are required to create loop devices and mount partitions."
	@sudo -v
	APP_NAME=$(APP_NAME) STATIC_IP=$(STATIC_IP) MQTT_PORT=$(MQTT_PORT) ROUTER_IP=$(ROUTER_IP) DNS="$(DNS)" HOSTNAME=$(HOSTNAME) \
	WIFI_SSID="$(WIFI_SSID)" WIFI_PSK="$(WIFI_PSK)" VERSION=$(VERSION) IMAGE_URL="$(IMAGE_URL)" \
	sudo --preserve-env=APP_NAME,STATIC_IP,MQTT_PORT,ROUTER_IP,DNS,HOSTNAME,WIFI_SSID,WIFI_PSK,VERSION,IMAGE_URL bash scripts/create-image.sh

flash:
	@if [ -z "$(DEVICE)" ]; then echo "Usage: make flash DEVICE=/dev/sdX" && exit 1; fi
	sudo bash scripts/flash.sh $(DEVICE) $(OUTPUT_IMG)

deploy: build-arm
	@if [ "$(DEPLOY_NEEDS_SUDO)" = "1" ]; then echo "Sudo credentials may be required for host-side steps."; sudo -v; fi
	APP_NAME=$(APP_NAME) PI_HOST=$(PI_HOST) PI_USER=$(PI_USER) VERSION=$(VERSION) PORT=$(MQTT_PORT) \
	bash scripts/ota/deploy.sh $(PI_HOST)

rollback:
	@if [ "$(DEPLOY_NEEDS_SUDO)" = "1" ]; then echo "Sudo credentials may be required for host-side steps."; sudo -v; fi
	APP_NAME=$(APP_NAME) PI_HOST=$(PI_HOST) PI_USER=$(PI_USER) bash scripts/ota/rollback.sh $(PI_HOST)

clean:
	rm -rf $(BUILD_DIR) $(OUTPUT_IMG)

