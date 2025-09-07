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


