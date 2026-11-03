#!/usr/bin/env bash
# Pi-Screen Bootstrap: frisches Raspberry Pi OS (Desktop, Bookworm) -> Standalone-Kiosk.
#
# One-Liner auf dem frischen Pi:
#   curl -fsSL https://raw.githubusercontent.com/Rasvan-Teofil/Pi-Canva-Viewer/feat/requirements-v2/scripts/bootstrap-pi.sh \
#     | sudo bash -s -- --canva-url "https://www.canva.com/design/.../view"
#
# Wiederholbar (idempotent). Danach: Reboot -> Canva-User loggt automatisch ein -> Kiosk startet.

set -Eeuo pipefail

REPO_URL="https://github.com/Rasvan-Teofil/Pi-Canva-Viewer.git"
BRANCH="feat/requirements-v2"
INSTALL_DIR="/opt/pi-screen"
CONF_DIR="/etc/pi-screen"
KIOSK_USER="canva"
CANVA_URL=""
ADMIN_PIN=""
MODE="canva"          # canva | public  (dashboard folgt in V1-Code)
UPGRADE=1
REBOOT=0

usage() {
    cat <<'USAGE'
Usage: sudo bash bootstrap-pi.sh [Optionen]

  --canva-url URL     Canva-Link (Präsentation/View-Link)
  --user NAME         Kiosk-User (Default: canva)
  --admin-pin PIN     4-stelliger PIN (erst V2 aktiv; Default: zufällig)
  --mode MODE         canva | public (Default: canva)
  --branch NAME       Git-Branch (Default: feat/requirements-v2)
  --no-upgrade        apt full-upgrade überspringen
  --reboot            Am Ende automatisch neu starten
  --help              Hilfe
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --canva-url) CANVA_URL="${2:?}"; shift ;;
        --user)      KIOSK_USER="${2:?}"; shift ;;
        --admin-pin) ADMIN_PIN="${2:?}"; shift ;;
        --mode)      MODE="${2:?}"; shift ;;
        --branch)    BRANCH="${2:?}"; shift ;;
        --no-upgrade) UPGRADE=0 ;;
        --reboot)    REBOOT=1 ;;
        --help)      usage; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mFehler: %s\033[0m\n' "$*" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || die "Bitte mit sudo ausführen."
[[ "$MODE" =~ ^(canva|public)$ ]] || die "--mode muss canva oder public sein."
[[ "$KIOSK_USER" =~ ^[a-z][a-z0-9_-]{1,31}$ ]] || die "Ungültiger Username: $KIOSK_USER"

. /etc/os-release 2>/dev/null || true
if [[ "${ID:-}" != "debian" && "${ID:-}" != "raspbian" ]]; then
    echo "Warnung: getestet für Raspberry Pi OS (Bookworm), gefunden: ${PRETTY_NAME:-unbekannt}" >&2
fi
if ! dpkg -s lightdm >/dev/null 2>&1; then
    die "Kein Desktop (LightDM) gefunden. Bitte 'Raspberry Pi OS with desktop' flashen."
fi

# --- 1) OS-Setup -----------------------------------------------------------
log "1/7 System aktualisieren & Pakete installieren"
export DEBIAN_FRONTEND=noninteractive
apt-get update
[[ $UPGRADE -eq 1 ]] && apt-get -y full-upgrade
apt-get install -y git curl ca-certificates python3 xdotool unclutter cec-utils x11-xserver-utils
apt-get install -y chromium-browser 2>/dev/null || apt-get install -y chromium

# --- 2) Sauberer Neustart: Altlasten entfernen -----------------------------
log "2/7 Alte Services & Prozesse entfernen"
for svc in start_canva.service pi_kiosk_server.service pi-screen-server.service; do
    systemctl disable --now "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/$svc"
done
systemctl daemon-reload
pkill -f start_canva.sh 2>/dev/null || true
pkill -f kiosk_supervisor.sh 2>/dev/null || true
rm -f /home/*/.config/autostart/pi-screen-kiosk.desktop

# --- 3) Canva-User anlegen -------------------------------------------------
log "3/7 Kiosk-User '$KIOSK_USER' anlegen"
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "Pi Screen Kiosk" "$KIOSK_USER"
fi
passwd -l "$KIOSK_USER" >/dev/null           # kein Passwort-Login, nur Autologin
for g in video render audio input; do
    getent group "$g" >/dev/null && usermod -aG "$g" "$KIOSK_USER"
done
KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"

# --- 4) Repo klonen / aktualisieren ----------------------------------------
log "4/7 Repo nach $INSTALL_DIR ($BRANCH)"
if [[ -d "$INSTALL_DIR/.git" ]]; then
    git -C "$INSTALL_DIR" fetch --depth 1 origin "$BRANCH"
    git -C "$INSTALL_DIR" checkout -B "$BRANCH" FETCH_HEAD
    git -C "$INSTALL_DIR" reset --hard FETCH_HEAD
else
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi
chown -R root:root "$INSTALL_DIR"
chmod 0755 "$INSTALL_DIR/kiosk/start-kiosk.sh"

# --- 5) Konfiguration ------------------------------------------------------
log "5/7 Konfiguration in $CONF_DIR"
install -d -m 0755 "$CONF_DIR"
CONF="$CONF_DIR/config.env"
if [[ -f "$CONF" ]]; then
    [[ -z "$CANVA_URL" ]] && CANVA_URL="$(sed -n 's/^CANVA_URL=//p' "$CONF" | tr -d '"')"
    [[ -z "$ADMIN_PIN" ]] && ADMIN_PIN="$(sed -n 's/^ADMIN_PIN=//p' "$CONF" | tr -d '"')"
fi
[[ -z "$ADMIN_PIN" ]] && ADMIN_PIN="$(shuf -i 1000-9999 -n 1)"
[[ "$ADMIN_PIN" =~ ^[0-9]{4}$ ]] || die "Admin-PIN: genau 4 Ziffern."
if [[ -z "$CANVA_URL" ]]; then
    echo "Hinweis: kein --canva-url gesetzt. Später in $CONF eintragen." >&2
fi
cat > "$CONF" <<CFG
# Pi-Screen Konfiguration – nach Änderung: sudo systemctl restart lightdm
MODE="${MODE}"
CANVA_URL="${CANVA_URL}"
# V1: Dashboard öffentlich, kein PIN. V2: PIN per Tastatur beim Start des Dashboard-Fensters.
ADMIN_PIN="${ADMIN_PIN}"
# Emulierte Klicks für Canva-Autoplay (x,y;x,y;...). Leer = aus.
CANVA_AUTOPLAY_CLICKS="1820,1050;1559,872;0,0"
CANVA_LOAD_WAIT_SEC=25
CFG
chown root:"$KIOSK_USER" "$CONF"
chmod 0640 "$CONF"

# --- 6) Desktop: X11 + Autologin ------------------------------------------
log "6/7 X11 & Autologin für '$KIOSK_USER'"
# X11 statt Wayland: nötig für xdotool (emulierte Klicks)
command -v raspi-config >/dev/null && raspi-config nonint do_wayland W1 || true
systemctl set-default graphical.target
install -d /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-pi-screen.conf <<LDM
[Seat:*]
autologin-user=${KIOSK_USER}
autologin-user-timeout=0
xserver-command=X -s 0 -dpms
LDM

# --- 7) Autostart ----------------------------------------------------------
log "7/7 Autostart einrichten"
install -d -o "$KIOSK_USER" -g "$KIOSK_USER" -m 0755 "$KIOSK_HOME/.config" "$KIOSK_HOME/.config/autostart"
cat > "$KIOSK_HOME/.config/autostart/pi-screen.desktop" <<DSK
[Desktop Entry]
Type=Application
Name=Pi Screen Kiosk
Exec=${INSTALL_DIR}/kiosk/start-kiosk.sh
X-GNOME-Autostart-enabled=true
DSK
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config/autostart/pi-screen.desktop"

cat <<DONE

Fertig.
  User:       ${KIOSK_USER} (Autologin, kein Passwort)
  Modus:      ${MODE}
  Canva-URL:  ${CANVA_URL:-<nicht gesetzt>}
  Config:     ${CONF}
  Admin-PIN:  ${ADMIN_PIN} (vorbereitet, aktiv ab V2)

Nächste Schritte:
  1. sudo reboot
  2. Einmalig im Kiosk-Fenster bei Canva einloggen (Session bleibt gespeichert).
     Login-Modus mit normalem Fenster: sudo -u ${KIOSK_USER} touch ${KIOSK_HOME}/.pi-screen-login && sudo systemctl restart lightdm
DONE

if [[ $REBOOT -eq 1 ]]; then reboot; fi
