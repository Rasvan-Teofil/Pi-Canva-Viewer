#!/usr/bin/env bash
# Desktop autostart entry point for the dedicated Pi-Screen user.

set -Eeuo pipefail

INSTALL_DIR="/opt/pi-screen"
CONFIG_FILE="/etc/pi-screen/config.env"
RUNTIME_DIR="${HOME}/.local/share/pi-screen"
PROFILE_DIR="${RUNTIME_DIR}/chromium-profile"
LOGIN_WINDOW_FLAG="${HOME}/.pi-screen-login"
DISPLAY="${DISPLAY:-:0}"
export DISPLAY
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"

log() {
  logger -t pi-screen-kiosk "$*" 2>/dev/null || true
  printf '[pi-screen] %s\n' "$*"
}

[[ -r "$CONFIG_FILE" ]] || { log "Missing $CONFIG_FILE"; exit 1; }
# config.env is installed root-owned and group-readable only by the kiosk user.
# shellcheck disable=SC1090
. "$CONFIG_FILE"

find_browser() {
  local candidate
  for candidate in chromium-browser chromium; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

wait_for_x11() {
  local attempt
  for attempt in $(seq 1 30); do
    if xset q >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wake_tv() {
  [[ "${CEC_WAKE_ON_BOOT:-true}" == "true" ]] || return 0
  [[ -x "$INSTALL_DIR/scripts/cec-control.sh" ]] || return 0
  "$INSTALL_DIR/scripts/cec-control.sh" on >/dev/null 2>&1 || \
    log "HDMI-CEC wake/source command was not accepted"
}

write_dashboard_config() {
  local destination="$RUNTIME_DIR/dashboard-config.js"
  [[ -d "$(dirname "$destination")" ]] || return 0

  CONFIG_FILE="$CONFIG_FILE" DASHBOARD_CONFIG_DESTINATION="$destination" python3 - <<'PY'
import json
import os
import pathlib
import shlex
import tempfile

source = pathlib.Path(os.environ["CONFIG_FILE"])
destination = pathlib.Path(os.environ["DASHBOARD_CONFIG_DESTINATION"])
values = {}
for raw_line in source.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, raw_value = line.split("=", 1)
    try:
        parsed = shlex.split(raw_value, comments=False, posix=True)
    except ValueError:
        continue
    values[key] = parsed[0] if parsed else ""

config = {
    "churchName": values.get("DASHBOARD_CHURCH_NAME", "ICF Heilbronn"),
    "logoText": "ICF",
    "timezone": "Europe/Berlin",
    "backgroundImage": values.get("DASHBOARD_BACKGROUND_URL", ""),
    "weather": {
        "location": values.get("DASHBOARD_WEATHER_LOCATION", "Heilbronn"),
        "latitude": values.get("DASHBOARD_WEATHER_LAT", "49.1427"),
        "longitude": values.get("DASHBOARD_WEATHER_LON", "9.2109"),
        "refreshMinutes": 30,
    },
    "verse": {
        "label": "Vers des Tages",
        "text": values.get("DASHBOARD_VERSE_TEXT", ""),
        "reference": values.get("DASHBOARD_VERSE_REFERENCE", ""),
    },
    "calendar": {
        "title": "Demnächst in der Church",
        "embedUrl": values.get("DASHBOARD_CALENDAR_URL", ""),
    },
}
logo_url = values.get("DASHBOARD_LOGO_URL", "")
if logo_url:
    config["logoUrl"] = logo_url
serialized = json.dumps(config, ensure_ascii=False)
data = f'''const piScreenBaseConfig = window.PI_SCREEN_CONFIG || {{}};
const piScreenRuntimeConfig = {serialized};
window.PI_SCREEN_CONFIG = {{
  ...piScreenBaseConfig,
  ...piScreenRuntimeConfig,
  weather: {{...(piScreenBaseConfig.weather || {{}}), ...piScreenRuntimeConfig.weather}},
  verse: {{...(piScreenBaseConfig.verse || {{}}), ...piScreenRuntimeConfig.verse}},
  calendar: {{...(piScreenBaseConfig.calendar || {{}}), ...piScreenRuntimeConfig.calendar}},
}};
'''
fd, temp_name = tempfile.mkstemp(prefix=".dashboard-config.", dir=str(destination.parent))
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    handle.write(data)
os.replace(temp_name, destination)
PY
}

start_canva_presentation() {
  [[ "${MODE:-canva}" == "canva" || "${MODE:-canva}" == "public" ]] || return 0
  command -v xdotool >/dev/null 2>&1 || return 0

  # An empty value is an intentional opt-out for installations where Canva's
  # controls differ from the calibrated display coordinates.
  local autoplay_clicks="${CANVA_AUTOPLAY_CLICKS-1820,1050;1559,872;0,0}"
  [[ -n "$autoplay_clicks" ]] || { log "Canva click automation is disabled"; return 0; }

  local window_id=""
  local elapsed=0
  while [[ -z "$window_id" && "$elapsed" -lt 30 ]]; do
    window_id="$(xdotool search --onlyvisible --class 'chromium' 2>/dev/null | head -n 1 || true)"
    [[ -n "$window_id" ]] || { sleep 1; elapsed=$((elapsed + 1)); }
  done
  [[ -n "$window_id" ]] || { log "Chromium window not found for Canva presentation mode"; return 0; }

  sleep "${CANVA_LOAD_WAIT_SEC:-25}"
  xdotool windowactivate --sync "$window_id" 2>/dev/null || return 0
  xdotool key --clearmodifiers --delay 100 "${CANVA_PRESENT_SHORTCUT:-ctrl+alt+p}" 2>/dev/null || return 0
  sleep 2
  local click_pair x y
  IFS=';' read -r -a click_pairs <<< "$autoplay_clicks"
  for click_pair in "${click_pairs[@]}"; do
    IFS=',' read -r x y <<< "$click_pair"
    [[ "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]] || continue
    xdotool mousemove "$x" "$y" click 1 2>/dev/null || return 0
    sleep 1
  done
  xdotool mousemove 0 0 2>/dev/null || true
  log "Canva presentation/autoplay click sequence sent"
}

wait_for_x11 || { log "X11 display was not ready"; exit 1; }
xset s off || true
xset -dpms || true
xset s noblank || true
mkdir -p "$RUNTIME_DIR" "$PROFILE_DIR"
unclutter -idle 1 -root >/dev/null 2>&1 &
wake_tv
write_dashboard_config

case "${MODE:-canva}" in
  canva|public)
    TARGET_URL="${CANVA_URL:?CANVA_URL is missing from $CONFIG_FILE}"
    ;;
  dashboard)
    TARGET_URL="file://$INSTALL_DIR/dashboard/index.html"
    ;;
  *)
    log "Unsupported MODE '${MODE:-}' in $CONFIG_FILE"
    exit 2
    ;;
esac

BROWSER="$(find_browser)" || { log "Chromium is not installed"; exit 1; }
while true; do
  launch_url="$TARGET_URL"
  browser_args=(
    --no-first-run
    --noerrdialogs
    --disable-infobars
    --disable-session-crashed-bubble
    --allow-file-access-from-files
    --autoplay-policy=no-user-gesture-required
    "--user-data-dir=$PROFILE_DIR"
  )
  run_presentation_automation=1

  if [[ -e "$LOGIN_WINDOW_FLAG" && ( "${MODE:-canva}" == "canva" || "${MODE:-canva}" == "public" ) ]]; then
    # The marker is deliberately consumed before Chromium opens: when the
    # normal browser window is closed, the loop returns to the kiosk.
    rm -f "$LOGIN_WINDOW_FLAG"
    browser_args+=(--start-maximized)
    run_presentation_automation=0
    launch_url="https://www.canva.com/login"
    log "Opening normal Chromium once for the Canva login"
  else
    browser_args+=(--kiosk)
    log "Opening $TARGET_URL (mode: ${MODE:-canva})"
  fi

  "$BROWSER" "${browser_args[@]}" "$launch_url" &
  browser_pid=$!
  if [[ "$run_presentation_automation" -eq 1 ]]; then
    start_canva_presentation &
  fi
  wait "$browser_pid" || true
  sleep 5
done
