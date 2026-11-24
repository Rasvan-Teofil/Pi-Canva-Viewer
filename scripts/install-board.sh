#!/usr/bin/env bash
# Pi-Screen · Stufe 1: Board (Bibelvers, ICF-Logo, Uhr) + HDMI-CEC-Zeitplan
# Als normaler Desktop-User ausführen (nicht als root), sudo wird bei Bedarf genutzt:
#   curl -fsSL https://raw.githubusercontent.com/Rasvan-Teofil/Pi-Canva-Viewer/main/scripts/install-board.sh | bash
# Wiederholbar: aktualisiert Repo, Autostart und Zeitplan, Configs bleiben erhalten.
set -Eeuo pipefail

REPO_URL="${PI_SCREEN_REPO:-https://github.com/Rasvan-Teofil/Pi-Canva-Viewer.git}"
BRANCH="${PI_SCREEN_BRANCH:-main}"
REPO_DIR="$HOME/pi-screen"
CONF_DIR="$HOME/.config/pi-screen"
AUTOSTART_DIR="$HOME/.config/autostart"
START_CMD="$REPO_DIR/scripts/start-board.sh"

log()  { printf '\033[1;32m[pi-screen]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[pi-screen]\033[0m %s\n' "$*" >&2; }

if [[ "$EUID" -eq 0 ]]; then
  echo "Bitte als Desktop-User ausführen (ohne sudo davor). sudo wird intern genutzt." >&2
  exit 1
fi

# 1. Pakete (nur fehlende)
PKGS=(git curl python3 chromium unclutter x11-xserver-utils cec-utils v4l-utils cron)
missing=()
for p in "${PKGS[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done
if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
  [[ " ${missing[*]} " == *" chromium "* ]] || missing+=(chromium)
fi
if ((${#missing[@]})); then
  log "Installiere: ${missing[*]}"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
else
  log "Pakete vorhanden"
fi
sudo systemctl enable --now cron >/dev/null 2>&1 || warn "cron konnte nicht aktiviert werden"

# 2. Repo klonen/aktualisieren
if [[ -d "$REPO_DIR/.git" ]]; then
  log "Aktualisiere $REPO_DIR"
  git -C "$REPO_DIR" fetch --quiet origin "$BRANCH"
  git -C "$REPO_DIR" checkout --quiet "$BRANCH"
  git -C "$REPO_DIR" reset --quiet --hard "origin/$BRANCH"
else
  log "Klone Repo nach $REPO_DIR"
  git clone --quiet --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi
chmod +x "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/scripts/*.py

# 3. Configs (nur anlegen, nie überschreiben)
mkdir -p "$CONF_DIR"
[[ -f "$CONF_DIR/board.env" ]]    || cp "$REPO_DIR/config/board.env.example" "$CONF_DIR/board.env"
[[ -f "$CONF_DIR/schedule.env" ]] || cp "$REPO_DIR/config/schedule.env.example" "$CONF_DIR/schedule.env"
# Alter Standard-Zeitplan (08:00–22:30 täglich) -> neuer Standard (Mo–Fr 07:30–20:17); eigene Zeiten bleiben
if grep -qx 'TV_ON=08:00' "$CONF_DIR/schedule.env" && grep -qx 'TV_OFF=22:30' "$CONF_DIR/schedule.env" \
   && grep -qx 'TV_DAYS=\*' "$CONF_DIR/schedule.env"; then
  cp "$REPO_DIR/config/schedule.env.example" "$CONF_DIR/schedule.env"
  log "Zeitplan auf neuen Standard gesetzt (Mo–Fr 07:30 an, 20:17 aus)"
fi
# Testbuttons gibt es nicht mehr
sed -i -e '/^SHOW_TEST_BUTTONS=/d' -e '/Testbuttons/d' "$CONF_DIR/board.env" 2>/dev/null || true
# Neue Keys aus dem Beispiel in bestehende board.env ergänzen (vorhandene Werte bleiben)
added=()
while IFS= read -r line; do
  [[ "$line" =~ ^([A-Z_]+)= ]] || continue
  key="${BASH_REMATCH[1]}"
  if ! grep -qE "^#?[[:space:]]*${key}=" "$CONF_DIR/board.env"; then
    printf '%s\n' "$line" >>"$CONF_DIR/board.env"
    added+=("$key")
  fi
done <"$REPO_DIR/config/board.env.example"
((${#added[@]})) && log "board.env ergänzt: ${added[*]}"

# 4. Alte Pi-Screen-Starts entfernen (normaler Desktop-Login bleibt)
if [[ -f /etc/lightdm/lightdm.conf.d/90-pi-screen.conf ]]; then
  log "Entferne alten LightDM-Override (canva-Autologin)"
  sudo rm -f /etc/lightdm/lightdm.conf.d/90-pi-screen.conf
fi
sudo rm -f /usr/share/xsessions/pi-screen-x11.desktop
rm -f "$AUTOSTART_DIR/pi-screen.desktop" "$AUTOSTART_DIR/pi-screen-x11.desktop"
pkill -u "$USER" -f '/opt/pi-screen/kiosk/start-kiosk.sh' 2>/dev/null || true

# 5. Autostart: XDG (LXDE-pi/openbox, labwc mit xdg-autostart) + labwc direkt
mkdir -p "$AUTOSTART_DIR"
cat >"$AUTOSTART_DIR/pi-screen-board.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Pi-Screen Board
Comment=Pi-Screen Stufe 1 (Bibelvers, ICF-Logo, Uhr)
Exec=$START_CMD
X-GNOME-Autostart-enabled=true
NoDisplay=true
DESKTOP
if [[ -d "$HOME/.config/labwc" ]] || pgrep -x labwc >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/labwc"
  touch "$HOME/.config/labwc/autostart"
  grep -qF "$START_CMD" "$HOME/.config/labwc/autostart" || echo "$START_CMD &" >>"$HOME/.config/labwc/autostart"
  log "labwc-Autostart ergänzt"
fi

# 6. HDMI-CEC: Rechte + Zeitplan
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx video; then
  log "Füge $USER zur Gruppe video hinzu (wirksam nach Neu-Login)"
  sudo usermod -aG video "$USER"
fi
for dev in /dev/cec0 /dev/cec1 /dev/vchiq; do
  [[ -e "$dev" ]] || continue
  if [[ -r "$dev" && -w "$dev" ]]; then
    log "CEC-Zugriff ok: $dev"
  else
    warn "Kein Zugriff auf $dev ($(stat -c '%U:%G %a' "$dev")) – nach Neu-Login erneut prüfen"
  fi
done
"$REPO_DIR/scripts/apply-schedule.sh"

# 7. Board sofort (neu) starten
pkill -u "$USER" -f "$START_CMD" 2>/dev/null || true
pkill -u "$USER" -f 'pi-screen/board-profile' 2>/dev/null || true
pkill -u "$USER" -f "$REPO_DIR/scripts/board-server.py" 2>/dev/null || true
sleep 1
if [[ -S /tmp/.X11-unix/X0 || -n "${WAYLAND_DISPLAY:-}" ]]; then
  log "Starte Board auf DISPLAY=:0"
  DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
    setsid nohup "$START_CMD" >/dev/null 2>&1 < /dev/null &
else
  warn "Kein laufender Desktop gefunden – Board startet beim nächsten Login"
fi

log "Fertig."
log "Board-Config:  $CONF_DIR/board.env  (CANVA_URL, CANVA_SLIDE_SECONDS, START_VIEW)"
log "Ansicht wechseln: Pfeiltaste links/rechts"
log "Zeitplan:      $CONF_DIR/schedule.env  -> danach $REPO_DIR/scripts/apply-schedule.sh"
log "TV per SSH:    $REPO_DIR/scripts/cec-control.sh on|off|status"
