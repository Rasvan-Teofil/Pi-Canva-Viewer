#!/usr/bin/env bash
# Startet das Pi-Screen-Board (Stufe 1) im Chromium-Kiosk mit Neustart-Schleife.
# Wird per Autostart des Desktop-Users aufgerufen; ein Lock verhindert Doppelstarts.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$HOME/.config/pi-screen/board.env"
PROFILE="$HOME/.local/share/pi-screen/board-profile"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/pi-screen-board.lock"
SERVER_LOG="$HOME/.local/share/pi-screen/board-server.log"

BOARD_PORT=8787
# shellcheck disable=SC1090
[[ -r "$CONFIG" ]] && source "$CONFIG"

log() { logger -t pi-screen-board -- "$*" 2>/dev/null || true; echo "pi-screen-board: $*" >&2; }

exec 9>"$LOCK"
if ! flock -n 9; then
  log "läuft bereits, Abbruch"
  exit 0
fi

export DISPLAY="${DISPLAY:-:0}"
mkdir -p "$PROFILE" "$(dirname "$SERVER_LOG")"

# Bildschirmschoner/Energiesparen aus (nur X11)
if [[ -z "${WAYLAND_DISPLAY:-}" ]] && command -v xset >/dev/null 2>&1; then
  xset s off -dpms s noblank >/dev/null 2>&1 || true
fi
if command -v unclutter >/dev/null 2>&1 && ! pgrep -u "$USER" -x unclutter >/dev/null; then
  unclutter -idle 1 -root >/dev/null 2>&1 9>&- &
fi

server_up() { curl -fsS -m 2 "http://127.0.0.1:${BOARD_PORT}/health" >/dev/null 2>&1; }

start_server() {
  server_up && return 0
  log "starte Board-Server auf 127.0.0.1:${BOARD_PORT}"
  python3 "$REPO_DIR/scripts/board-server.py" >>"$SERVER_LOG" 2>&1 9>&- &
  for _ in $(seq 1 20); do server_up && return 0; sleep 0.5; done
  return 1
}

BROWSER="$(command -v chromium || command -v chromium-browser || echo /usr/lib/chromium/chromium)"

while true; do
  if start_server; then
    URL="http://127.0.0.1:${BOARD_PORT}/"
  else
    log "Board-Server nicht erreichbar, nutze file://"
    URL="file://$REPO_DIR/board/index.html"
  fi
  # Profil-Prefs: Übersetzen aus, Absturz-Hinweis unterdrücken
  python3 - "$PROFILE/Default/Preferences" <<'PY' || log "Preferences konnten nicht gesetzt werden"
import json, os, sys
path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)
try:
    with open(path, encoding="utf-8") as f:
        prefs = json.load(f)
except (OSError, ValueError):
    prefs = {}
prefs.setdefault("translate", {})["enabled"] = False
prefs["translate_blocked_languages"] = ["en", "de"]
prefs.setdefault("intl", {})["accept_languages"] = "de-DE,de,en-US,en"
prof = prefs.setdefault("profile", {})
prof["exited_cleanly"] = True
prof["exit_type"] = "Normal"
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(prefs, f)
os.replace(tmp, path)
PY
  log "starte Chromium: $URL"
  "$BROWSER" --kiosk --noerrdialogs --disable-infobars --no-first-run \
    --disable-session-crashed-bubble --password-store=basic \
    --lang=de-DE --accept-lang=de-DE,de,en-US,en \
    --disable-features=Translate,TranslateUI --check-for-update-interval=31536000 \
    --user-data-dir="$PROFILE" "$URL" >/dev/null 2>&1 9>&-
  log "Chromium beendet (Code $?), Neustart in 3 s"
  sleep 3
done
