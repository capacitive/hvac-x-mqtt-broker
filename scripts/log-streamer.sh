#!/bin/bash

FIFO_PATH="/tmp/mqtt-logs"

# Create named pipe for log streaming
mkfifo $FIFO_PATH 2>/dev/null || true

# Function to display last 20 lines on console
display_logs() {
    tail -n 20 -f $FIFO_PATH | while read line; do
        echo "$(date '+%H:%M:%S') $line"
    done
}

# Start log display in background
display_logs &

# Keep script running
wait