#!/bin/bash
THRESHOLD=500                         # Set threshold in MB 
CHECK_INTERVAL=15                     # Check every 15 seconds

while true; do
    FREE_RAM=$(free -m | awk '/^Mem:/{print $7}')  # Get available RAM in MB
    if [ "$FREE_RAM" -lt "$THRESHOLD" ]; then
        echo "Warning: Low RAM! Available RAM: ${FREE_RAM}MB"
        # Send an alert (can be customized)
        notify-send "Low RAM Alert" "Available RAM is below ${THRESHOLD}MB"
    fi
    sleep "$CHECK_INTERVAL"
done
