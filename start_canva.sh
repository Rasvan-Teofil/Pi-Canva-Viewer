#!/bin/bash
# This script starts Chromium in kiosk mode, waits for the visible window, and
# then switches to fullscreen mode via a keyboard shortcut.
# Afterwards, it simulates mouse actions (with coordinates previously obtained via slop):
# first, it moves the mouse to display the Canva menu bar,
# then clicks the menu and the autoplay button.
# Finally, it performs one more click to hide the menu again.

# --- Debug mode (enable for troubleshooting; disable by setting DEBUG=0) ---
DEBUG=0
[ "$DEBUG" = "1" ] && set -x

# --- Path to the file that contains the Canva link ---
URL_FILE="/home/teofilwetzel/Pi-Canva-Viewer/canva_url.txt"

# --- Variables ---
DISPLAY_NUM=":0"
TIMEOUT=20            # Maximum waiting time (in seconds) for the Chromium window
SLEEP_INTERVAL=2      # Waiting interval in the loop
KEY_SEND_DELAY=25     # Waiting time (in seconds) to allow the page to fully load
CLICK_DELAY=5         # Waiting time (in seconds) before performing mouse actions

# Function for printing log messages with timestamp
log() {
    echo "[$(date +'%H:%M:%S')] $*"
}

# --- 1) Check if URL file exists and read the URL ---
if [ ! -f "$URL_FILE" ]; then
    echo "Error: URL file not found at $URL_FILE. Exiting."
    exit 1
fi

URL="$(cat "$URL_FILE" | tr -d '[:space:]')" 
# Remove whitespace or newlines; adjust if your file has extra data

if [ -z "$URL" ]; then
    echo "Error: The URL in $URL_FILE is empty. Exiting."
    exit 1
fi

# --- 2) Terminate any existing Chromium instances ---
if pgrep -x "chromium" > /dev/null; then
    log "Chromium is already running. Terminating old instance..."
    pkill -x chromium
    sleep 2
fi

# --- 3) Wait for the X server ---
log "Waiting for the X server..."
export DISPLAY="$DISPLAY_NUM"
sleep 5
# unclutter the mouse
unclutter -idle 1 -root &
log "Mouse unclutter"

# --- 4) Start Chromium in kiosk mode ---
log "Starting Chromium in kiosk mode with URL: $URL"
chromium-browser --kiosk --noerrdialogs --disable-infobars --ozone-platform=x11 "$URL" \
    > /dev/null 2>&1 &
# Short wait time to allow Chromium to launch
sleep 2

# --- 5) Wait for the Chromium window ---
elapsed=0
CHROMIUM_WINDOW_ID=""
log "Looking for the Chromium window..."
while [ -z "$CHROMIUM_WINDOW_ID" ] && [ "$elapsed" -lt "$TIMEOUT" ]; do
    sleep "$SLEEP_INTERVAL"
    elapsed=$((elapsed + SLEEP_INTERVAL))
    CHROMIUM_WINDOW_ID=$(xdotool search --onlyvisible --class "chromium" 2>/dev/null | head -n 1)
    log "Searching for Chromium window... ($elapsed seconds)"
done

if [ -z "$CHROMIUM_WINDOW_ID" ]; then
    log "Error: No Chromium window found! Stopping script."
    exit 1
fi

# --- 6) Activate the window and check focus ---
log "Chromium window found: $CHROMIUM_WINDOW_ID. Activating window..."
xdotool windowactivate --sync "$CHROMIUM_WINDOW_ID"
sleep 1
ACTIVE_WIN=$(xdotool getactivewindow)
log "Current active window: $ACTIVE_WIN"
if [ "$ACTIVE_WIN" != "$CHROMIUM_WINDOW_ID" ]; then
    log "Warning: The active window ($ACTIVE_WIN) does not match the expected Chromium window ($CHROMIUM_WINDOW_ID)."
fi

# --- 7) Introduce a wait to allow the page to load completely ---
log "Waiting $KEY_SEND_DELAY seconds for the page to fully load..."
sleep "$KEY_SEND_DELAY"

# --- 8) Send Ctrl+Alt+P shortcut (activate fullscreen mode) ---
log "Sending Ctrl+Alt+P shortcut..."
xdotool key --clearmodifiers --delay 100 ctrl+alt+p
if [ $? -ne 0 ]; then
    log "Error: Could not send the keyboard shortcut."
else
    log "Shortcut successfully sent!"
fi

# --- 9) Wait 5 seconds before performing mouse actions ---
log "Waiting $CLICK_DELAY seconds before performing mouse actions..."
sleep "$CLICK_DELAY"

# --- 10) Simulate a mouse move to display the Canva menu bar ---
log "Simulating mouse movement to display the Canva menu bar..."
xdotool mousemove 1820 1050
sleep 1

# --- 11) Perform the first mouse click (open menu) ---
log "Clicking on the menu at (1820,1050)..."
xdotool click 1
sleep 1

# --- 12) Perform the second mouse click (activate autoplay) ---
log "Moving the mouse to the autoplay button at (1559,872) and clicking..."
xdotool mousemove 1559 872
sleep 1
xdotool click 1

log "Autoplay activated via mouse click."
sleep 1

# --- 13) Additional click to close the menu ---
log "Clicking on an empty area (0,0) to close the menu..."
xdotool mousemove 0 0
sleep 1
xdotool click 1
log "Menu has been closed."

# Optional: Wait a bit to observe the result
sleep 2

log "Script finished."