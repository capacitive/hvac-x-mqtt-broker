PI_IP=192.168.1.23
PI_USER=root
APP_NAME=mqtt-broker

.PHONY: build deploy image flash clean

build:
	GOOS=linux GOARCH=arm GOARM=6 go build -o $(APP_NAME) .

deploy: build
	./scripts/ota-deploy.sh

image:
	sudo ./scripts/create-image.sh

flash:
	sudo ./scripts/flash-usb.sh

clean:
	rm -f $(APP_NAME) pi-hvac.img