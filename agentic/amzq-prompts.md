### Minimal Image Deployment & Subsequent OTA Deployment
Set up this application for OTA (Over the Air) build deployment. I'm currently running the app on a Raspberry Pi Zero running a Debian OS. The IP address of the Pi is 192.168.1.23. The app server is listening on port 1883.

Also set up this application for direct deployment of a small footprint Linux OS image (with this app pre-installed) to a mounted USB drive. This freshly created OS image will meet all the requirements for running on a Raspberry Pi Zero. This app will need to run at sartup on the Pi.

---------------------------------------

I'm experiencing a paradigm shift in terms of Linux image building. My usual assumption is to see a Linux OS distribution image being downloaded and used to create a Linux OS for my apps to run on.

Acting as an engaging yet professional embedded technology instructor (in the style of Sal Khan), please explain how an ARM binary is created and how a typical distribution of Linux is not required to create a minimal Linux OS for which to run apps on top of. Some questions among the others I'd like answered:

1. Do the commands in the crate-image,sh script use the Linux kernel of the host Linux OS (the one running now)?

2. My above question aside, what flavour of Linux (kernel and file system) will be running once the image is deployed onto the mounted Pi drive?

---------------------------------------

1. Make sure the OTA deploy system is congruent with the minimal OS image configuration - I can see that the setup-pi.sh script may be overlapping some of the items already completed in the create-complete-image.sh script. The goal is to use the min OS image script to make the image, then use the flash-usb.sh script to flash it onto the SD drive for the RPI Zero, then use the OTA deployment command in the makefile to continuously deploy to the RPI Zero.
2. Make both the OTA and min image scripts available via makefile commands.  The OTA may not need the pi setup, since the flashed image already has things like the /opt/hvac-mqtt directory.  Make sure to include all the things required for the mqtt-broker app to run at device startup.

---------------------------------------

### Logging
1. All log output of the mqtt-broker is required to stream to the shell prompt of the minimal linux OS running on the RPI Zero, for all users. Tail the last 20 outputs - only those need be printed on the screen at one time.
2. All log output is required to be streamed to a web socket for remote monitoring and debugging.  Also provide a gRPC endpoint for remote log output monitoring and debugging.

---------------------------------------

### RPI Zero bootup testing results
The green activity light is flashing intermittently, but I see no video output from the device, to which I've connected a mini HDMI cable and a monitor. I also have connected a USB header to the Zero, to which I've attached a keyboard and mouse. The keyboard has LEDs which do not light up when the Zero is booted. Something isn't bootstrapping properly on the Zero device.

---------------------------------------

### RPI Zero bootup testing results 2
Same as the previous two attempts - no change to the situation.

Why don't you just use a recognized, tested and available minimal RPI Zero Linux distro for the image's OS? Keep in mind this device we're creating an image for is a RPI Zero W (wireless and bluetooth).

---------------------------------------

The setup of the mqtt server is not present or being respected on the RPI OS:
1. the OS needs to start up without requiring a user login (it's a real server)
2. the mqtt server needs to start up automatically.
3. the country and Wifi configuration needs to be set up automatically (derive wifi config for network name/password from the mqtt config)

Is it possible (and are *you* able) to make customization changes to a standard RPI OS Lite image/distribution and strip out any features/programs that the mqtt server doesn't need (retaining keyboard, and HDMI support)?

---------------------------------------

This output line from the create image script:

Note: Edit /boot/wpa_supplicant.conf with your WiFi credentials

Please create an interaction that allows me to enter the wifi credentials that will be used for the image creation. This speeds up the image deployment process.

---------------------------------------

the setup wizard is still in place, and the resulting configuration does NOT include static IP address 192.168.1.23, as far as I can see from the last bootup sequence of the device. Please ensure that the wizard is disabled, and the configuration is completed for the OS image as expected.

---------------------------------------