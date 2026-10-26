#!/bin/bash
# ==============================================================================
# Raspberry Pi Canva Kiosk & ICF Church Dashboard Autostart Script
# ==============================================================================
# Supports two operating modes via KIOSK_MODE:
#   - "hub" (Default): Starts the local Python Kiosk & Control Server (app.py)
#     and launches http://localhost:8080/display in Chromium Kiosk mode.
#     Allows live switching between Canva Keynote, Church Tasks Dashboard,
#     Verse of the Week, and Auto-Rotation, plus HDMI-CEC TV power scheduling.
#   - "classic_canva": Original behavior — opens the URL from canva_url.txt
#     directly in Chromium and runs the xdotool Ctrl+Alt+P & autoplay click sequence.
# ==============================================================================

DEBUG=0
[ "$DEBUG" = "1" ] && set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL_FILE="${URL_FILE:-$SCRIPT_DIR/canva_url.txt}"
KIOSK_MODE="${KIOSK_MODE:-hub}"
KIOSK_PORT="${KIOSK_PORT:-8080}"
DISPLAY_NUM="${DISPLAY_NUM:-:0}"

TIMEOUT=20
SLEEP_INTERVAL=2
KEY_SEND_DELAY=25
CLICK_DELAY=5

log() {
    echo "[$(date +'%H:%M:%S')] $*"
}

# --- 1) Ensure local Python Kiosk & CEC Control Server is running ---
if ! pgrep -f "app.py" > /dev/null; then
    log "Starting ICF Church Screen & CEC Server (app.py on port $KIOSK_PORT)..."
    nohup python3 "$SCRIPT_DIR/app.py" --port "$KIOSK_PORT" > /tmp/pi_kiosk_server.log 2>&1 &
    sleep 2
fi

# --- 2) Wake TV via HDMI-CEC and set Pi as Active Source ---
if [ -x "$SCRIPT_DIR/scripts/tv_cec_power.sh" ]; then
    log "Waking TV via HDMI-CEC and setting Active Source..."
    "$SCRIPT_DIR/scripts/tv_cec_power.sh" on || true
fi

# --- 3) Determine Target URL ---
if [ "$KIOSK_MODE" = "classic_canva" ]; then
    if [ ! -f "$URL_FILE" ]; then
        echo "Error: URL file not found at $URL_FILE. Exiting."
        exit 1
    fi
    URL="$(tr -d '[:space:]' < "$URL_FILE")"
    if [ -z "$URL" ]; then
        echo "Error: The URL in $URL_FILE is empty. Exiting."
        exit 1
    fi
else
    URL="http://localhost:${KIOSK_PORT}/display"
fi

# --- 4) Terminate any existing Chromium instances ---
if pgrep -x "chromium" > /dev/null || pgrep -x "chromium-browser" > /dev/null; then
    log "Chromium is already running. Terminating old instance..."
    pkill -x chromium 2>/dev/null || true
    pkill -x chromium-browser 2>/dev/null || true
    sleep 2
fi

# --- 5) Wait for the X server & disable screen blanking ---
log "Waiting for the X server on $DISPLAY_NUM..."
export DISPLAY="$DISPLAY_NUM"
sleep 5

xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

if command -v unclutter >/dev/null 2>&1; then
    unclutter -idle 1 -root &
    log "Mouse cursor hidden via unclutter."
fi

# --- 6) Start Chromium in kiosk mode ---
CHROMIUM_BIN="chromium-browser"
command -v chromium-browser >/dev/null 2>&1 || CHROMIUM_BIN="chromium"

log "Starting $CHROMIUM_BIN in kiosk mode with URL: $URL (Mode: $KIOSK_MODE)"
"$CHROMIUM_BIN" --kiosk --noerrdialogs --disable-infobars --autoplay-policy=no-user-gesture-required \
    --ozone-platform=x11 "$URL" > /dev/null 2>&1 &
sleep 2

# --- 7) Optional classic xdotool Canva sequence when in classic_canva mode ---
if [ "$KIOSK_MODE" = "classic_canva" ] && command -v xdotool >/dev/null 2>&1; then
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

    log "Chromium window found: $CHROMIUM_WINDOW_ID. Activating window..."
    xdotool windowactivate --sync "$CHROMIUM_WINDOW_ID"
    sleep 1

    log "Waiting $KEY_SEND_DELAY seconds for the Canva page to fully load..."
    sleep "$KEY_SEND_DELAY"

    log "Sending Ctrl+Alt+P shortcut..."
    xdotool key --clearmodifiers --delay 100 ctrl+alt+p

    log "Waiting $CLICK_DELAY seconds before performing mouse actions..."
    sleep "$CLICK_DELAY"

    log "Simulating mouse movement and clicks for Canva autoplay..."
    xdotool mousemove 1820 1050 && sleep 1 && xdotool click 1 && sleep 1
    xdotool mousemove 1559 872 && sleep 1 && xdotool click 1 && sleep 1
    xdotool mousemove 0 0 && sleep 1 && xdotool click 1
    log "Canva Autoplay activated and menu closed."
fi

log "Kiosk startup script finished."
