#!/bin/bash

PI_IP="192.168.1.23"
APP_NAME="mqtt-broker"

echo "Building for Raspberry Pi Zero (ARM)..."
GOOS=linux GOARCH=arm GOARM=6 go build -o ${APP_NAME} .

echo "Deploying via HTTP..."
curl -X POST --data-binary @${APP_NAME} http://${PI_IP}:8081/update

echo "Deploying config..."
curl -X POST --data-binary @broker-config.yml http://${PI_IP}:8081/config

echo "OTA deployment complete!"