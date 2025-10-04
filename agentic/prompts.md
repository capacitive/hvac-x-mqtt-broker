## Amazon Q

### Standalone Go Modules (execution independence)
I'm trying to figure out how to create a utility Go project in a subfolder of this main project. The problem is that any subfolder based app requires the mod.go to contain its dependcencies. Is there a way to create completely isolated Go apps in subfolders that don't affect the main project Go app in any way? Please research related Go documentation on the web, and learn how to do this, if you're able to get access to the www.

### Test App (mini service)

I would like you to create a small test app that emulates a sail-sensor's behaviour.
The application in this repo acts as an event server/broker and has a ./broker-config.yml configuration, and you can see what incoming connections and events look like on lines 110-127 of ./main.go. You can extrapolate a test app by referencing the various event handlers (OnConnect, OnDisconnect, etc.) in the existing code of ./main.go  I would like the test app to the emulate behaviour of each event type so that tests can cover a wide range of scenarios.I would also like the test app to be able to emulate a sensor getting sporadic readings of an ON/OFF state in rapid succession - this is for the purpose of improving the server/broker's event handler to ignore rapid-fire events and only act on stable states.  The test app should have two modes that can be live-toggled: 
1. Simulate the sensor's ON or OFF state (manual mode).
2. Simulate the sensor's ON/OFF state in rapid succession (auto mode).

### Test App (GUI)
 Give the test app mini service app a front-end that allows for live-toggling of modes and manual state changes. Use svelte or react/electron, or any other framework that allows for a zero dependency or self-contained build that can be served from an embedded device or any machine that can serve web pages. Assume the service will be running on a local device with an ARM architecture.

 ## Local SD card and subsequent OTA deloyment for RPI Zero W
 Set up this application for direct deployment of a small footprint Linux OS image (with this app pre-installed) to a mounted USB drive (a micro SD card adapter or directly inserted micro sd card). This freshly created OS image will meet all the requirements for running on a Raspberry Pi Zero W. This app will need to run at startup on the Pi. The IP address of the Pi needs to be 192.168.1.23, and the app server is to listen on port 1883 (make both these configurable pre-build).

 Once this is accomplished, set up this application for OTA (Over the Air) build deployment with versioning. 

**1. Hardware Abstraction (Bootloader)**
- `bootcode.bin` - Pi's GPU bootloader
- `start.elf` - Loads the kernel

**2. Kernel Layer**
- `kernel.img` - The actual Linux kernel compiled for ARM
- Provides syscalls, device drivers, memory management
- This is what makes it "Linux"

**3. Userspace (Your Application)**
- This app's Go binary + minimal shell/utilities
- Runs on top of kernel via syscalls

Attempt a custom linux image build, but provide options for using a recognized, tested and available minimal RPI Zero Linux distro for the image's OS.  Keep in mind this device we're creating an image for is a RPI Zero W (wireless and bluetooth).

#### bare bones RPI Zero 2 W OS
Proceed to implement Step 1 now.  Create a directory named `tartigrade` to contain your work. This will be the name of the application we create to codify the process of creating this explain, build, test, and flash process.  Reuse the existing flash script and a create new one for this image building process.  Prompt me when it's time to flash and I'll execute it.  We'll use this script for now, but I'd like a compiled app to govern the process, not shell scripts.  The script world is rife with issues and features it does not have, and lacks testability.  We'll convert our image building and flashing process to a Golang app later on, but before we get too locked in to scripts. We'll leverage Go's ability to run program code as scripts, but have a mainline tool that automates the entire process end-to-end.  I'd like the app to have verbose and interactive modes to support teaching newcomers to the embedded microcontroller space.

#### build progress notification tool
Create a small UI Rust app that allows you to start a progress bar and signal it to progress over the build time.  The app also needs to: estimate total build time and report progress against the estimate, update  the estimate, suppress the host system from sleeping.

#### 'tardigrade' rename
I'm almost certain that 35 occurences of 'tartigrade' in 8 files will NOT take 40 minutes! Rebuilding everything is not necessary as this is a very targeted change. I've also switched to a new branch to contain the blast radius if anything should go wrong.  Simple VSCode find and replace would be a good thing to give you access to.