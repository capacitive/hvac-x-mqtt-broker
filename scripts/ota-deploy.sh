#!/bin/bash

PI_IP="192.168.1.23"
PI_USER="root"
APP_NAME="mqtt-broker"
REMOTE_PATH="/opt/hvac-mqtt"

echo "Building for Raspberry Pi Zero (ARM)..."
GOOS=linux GOARCH=arm GOARM=6 go build -o ${APP_NAME} .

echo "Stopping remote service..."
ssh ${PI_USER}@${PI_IP} "pkill mqtt-broker || true"

echo "Deploying binary..."
scp ${APP_NAME} ${PI_USER}@${PI_IP}:${REMOTE_PATH}/
scp broker-config.yml ${PI_USER}@${PI_IP}:${REMOTE_PATH}/

echo "Starting remote service..."
ssh ${PI_USER}@${PI_IP} "cd ${REMOTE_PATH} && ./mqtt-broker &"

echo "OTA deployment complete!"