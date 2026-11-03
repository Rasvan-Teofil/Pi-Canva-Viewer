#!/usr/bin/env bash
# Startet Chromium mit dem Canva-Link (XDG-Autostart des Kiosk-Users).
# Konfiguration: /etc/pi-screen/config.env

set -u
CONF="/etc/pi-screen/config.env"
# shellcheck disable=SC1090
[[ -r "$CONF" ]] && . "$CONF"

PROFILE="$HOME/.local/share/pi-screen/chromium"
LOGIN_FLAG="$HOME/.pi-screen-login"
mkdir -p "$PROFILE"

BROWSER="$(command -v chromium-browser || command -v chromium || true)"
[[ -n "$BROWSER" ]] || { logger -t pi-screen "Chromium fehlt"; exit 1; }

xset s off -dpms s noblank 2>/dev/null || true
command -v unclutter >/dev/null && unclutter -idle 1 -root &

if [[ -z "${CANVA_URL:-}" ]]; then
    CANVA_URL="data:text/html,<h1 style='font-family:sans-serif'>Kein CANVA_URL in /etc/pi-screen/config.env</h1>"
fi

# Einmaliger Login: normales Fenster, kein Kiosk.
if [[ -f "$LOGIN_FLAG" ]]; then
    rm -f "$LOGIN_FLAG"
    exec "$BROWSER" --user-data-dir="$PROFILE" --no-first-run --start-maximized "https://www.canva.com/login"
fi

autoplay_clicks() {
    [[ -n "${CANVA_AUTOPLAY_CLICKS:-}" ]] || return 0
    sleep "${CANVA_LOAD_WAIT_SEC:-25}"
    local win
    win="$(xdotool search --onlyvisible --class chromium 2>/dev/null | head -n1)"
    [[ -n "$win" ]] && xdotool windowactivate --sync "$win"
    xdotool key --clearmodifiers ctrl+alt+p   # Canva Präsentationsmodus
    sleep 5
    local IFS=';' p
    for p in $CANVA_AUTOPLAY_CLICKS; do
        xdotool mousemove "${p%,*}" "${p#*,}" click 1
        sleep 1
    done
}

while true; do
    "$BROWSER" --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
        --no-first-run --autoplay-policy=no-user-gesture-required \
        --user-data-dir="$PROFILE" "$CANVA_URL" >/dev/null 2>&1 &
    BPID=$!
    autoplay_clicks &
    wait "$BPID"
    logger -t pi-screen "Chromium beendet, Neustart in 5 s"
    sleep 5
done
