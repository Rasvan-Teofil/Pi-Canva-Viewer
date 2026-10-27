#!/usr/bin/env bash
# Runs from the user's graphical autostart session and restarts Chromium on exit.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${KIOSK_PORT:-8080}"
URL="http://127.0.0.1:${PORT}/display"
PROFILE_DIR="${HOME}/.local/share/pi-screen/chromium-profile"

find_browser() {
    local candidate
    for candidate in chromium-browser chromium /snap/bin/chromium; do
        if [[ "$candidate" == /* ]]; then
            [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
        elif command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

mkdir -p "$PROFILE_DIR"

# The backend may still be starting when the desktop session comes up.
for _ in $(seq 1 30); do
    if curl --silent --fail --max-time 2 "http://127.0.0.1:${PORT}/api/state" >/dev/null; then
        break
    fi
    sleep 1
done

if command -v unclutter >/dev/null 2>&1; then
    unclutter -idle 1 -root >/dev/null 2>&1 &
fi

while true; do
    BROWSER="$(find_browser || true)"
    if [[ -z "$BROWSER" ]]; then
        logger -t pi-screen-kiosk "Chromium was not found; retrying in 30 seconds."
        sleep 30
        continue
    fi

    "$BROWSER" \
        --kiosk \
        --noerrdialogs \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --no-first-run \
        --ozone-platform=x11 \
        --autoplay-policy=no-user-gesture-required \
        --user-data-dir="$PROFILE_DIR" \
        "$URL"
    sleep 5
done
