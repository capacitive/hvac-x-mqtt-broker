.PHONY: help build build-arm ensure-ssh-key image flash deploy rollback clean

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

# Optional image/timezone and minimal user defaults
IMAGE_URL ?= https://downloads.raspberrypi.com/raspios_lite_armhf_latest
TIMEZONE  ?= America/New York 
RPI_USER  ?= hvacx
RPI_PASS  ?= hv@cmqttbr0k3r
# Auto-pick an existing local SSH public key if present (non-destructive)
RPI_SSH_PUBKEY ?= $(shell if [ -f "$$HOME/.ssh/id_ed25519.pub" ]; then cat "$$HOME/.ssh/id_ed25519.pub"; elif [ -f "$$HOME/.ssh/id_rsa.pub" ]; then cat "$$HOME/.ssh/id_rsa.pub"; fi)

# Prompt for sudo during deploy/rollback if your environment needs it (0 or 1)
DEPLOY_NEEDS_SUDO ?= 0

help:
	@echo "Targets:"
	@echo "  build         - Build local binary for host"
	@echo "  build-arm     - Cross-compile for Raspberry Pi Zero W (ARMv6)"
	@echo "  image         - Create Pi OS Lite image with app pre-installed"
	@echo "  flash         - Flash $(OUTPUT_IMG) to SD card (interactive device selection)"
	@echo "  deploy        - OTA deploy to running Pi (PI_HOST=$(PI_HOST))"
	@echo "  rollback      - OTA rollback to previous version on device"
	@echo "  clean         - Remove build artifacts"

build:
	go build -o $(BUILD_DIR)/$(APP_NAME) ./

build-arm:
	CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=6 go build -o $(BUILD_DIR)/$(APP_NAME) ./

ensure-ssh-key:
	@mkdir -p "$$HOME/.ssh"
	@chmod 700 "$$HOME/.ssh"
	@if [ ! -f "$$HOME/.ssh/id_ed25519" ]; then \
		echo "Generating SSH key at $$HOME/.ssh/id_ed25519 (no passphrase)"; \
		ssh-keygen -t ed25519 -N "" -f "$$HOME/.ssh/id_ed25519" -q; \
	else \
		echo "SSH key already exists at $$HOME/.ssh/id_ed25519"; \
	fi

image: build-arm
	@echo "Sudo credentials are required to create loop devices and mount partitions."
	@sudo -v
	@if [ -z "$(RPI_SSH_PUBKEY)" ]; then $(MAKE) ensure-ssh-key; fi
	@RPI_SSH_PUBKEY_CONTENT="$(RPI_SSH_PUBKEY)"; \
	  if [ -z "$$RPI_SSH_PUBKEY_CONTENT" ]; then \
	    if [ -f "$$HOME/.ssh/id_ed25519.pub" ]; then RPI_SSH_PUBKEY_CONTENT="$$(cat $$HOME/.ssh/id_ed25519.pub)"; \
	    elif [ -f "$$HOME/.ssh/id_rsa.pub" ]; then RPI_SSH_PUBKEY_CONTENT="$$(cat $$HOME/.ssh/id_rsa.pub)"; \
	    else RPI_SSH_PUBKEY_CONTENT=""; fi; \
	  fi; \
	  APP_NAME=$(APP_NAME) STATIC_IP=$(STATIC_IP) MQTT_PORT=$(MQTT_PORT) ROUTER_IP=$(ROUTER_IP) DNS="$(DNS)" HOSTNAME=$(HOSTNAME) \
	  WIFI_SSID="$(WIFI_SSID)" WIFI_PSK="$(WIFI_PSK)" IMAGE_URL="$(IMAGE_URL)" RPI_USER="$(RPI_USER)" RPI_PASS="$(RPI_PASS)" \
	  RPI_SSH_PUBKEY="$$RPI_SSH_PUBKEY_CONTENT" TIMEZONE="$(TIMEZONE)" \
	  sudo --preserve-env=APP_NAME,STATIC_IP,MQTT_PORT,ROUTER_IP,DNS,HOSTNAME,WIFI_SSID,WIFI_PSK,IMAGE_URL,RPI_USER,RPI_PASS,RPI_SSH_PUBKEY,TIMEZONE bash scripts/create-image.sh

flash:
	@# Device selection is always interactive inside scripts/flash.sh
	sudo bash scripts/flash.sh $(OUTPUT_IMG)

deploy: build-arm
	@if [ "$(DEPLOY_NEEDS_SUDO)" = "1" ]; then echo "Sudo credentials may be required for host-side steps."; sudo -v; fi
	APP_NAME=$(APP_NAME) PI_HOST=$(PI_HOST) PI_USER=$(PI_USER) PORT=$(MQTT_PORT) \
	bash scripts/ota/deploy.sh $(PI_HOST)

rollback:
	@if [ "$(DEPLOY_NEEDS_SUDO)" = "1" ]; then echo "Sudo credentials may be required for host-side steps."; sudo -v; fi
	APP_NAME=$(APP_NAME) PI_HOST=$(PI_HOST) PI_USER=$(PI_USER) bash scripts/ota/rollback.sh $(PI_HOST)

clean:
	rm -rf $(BUILD_DIR) $(OUTPUT_IMG)

