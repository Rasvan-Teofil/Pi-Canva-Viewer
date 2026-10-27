#!/usr/bin/env bash
# One-time, repeatable installer for Ubuntu on Raspberry Pi.
# Run: sudo bash ./install.sh [--install-desktop] [--user USER] [--admin-pin PIN]

set -Eeuo pipefail

INSTALL_DESKTOP=0
TARGET_USER="${SUDO_USER:-}"
ADMIN_PIN=""

usage() {
    cat <<'EOF'
Usage: sudo bash ./install.sh [options]

Options:
  --install-desktop      Install Ubuntu Desktop Minimal when this is Ubuntu Server.
  --user USER            Desktop user that will run the kiosk (default: invoking sudo user).
  --admin-pin PIN        Set a numeric admin PIN (default: 1234).
  --help                 Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-desktop) INSTALL_DESKTOP=1 ;;
        --user)
            TARGET_USER="${2:?--user needs a value}"
            shift
            ;;
        --admin-pin)
            ADMIN_PIN="${2:?--admin-pin needs a value}"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ ${EUID} -ne 0 ]]; then
    echo "Run this installer with sudo: sudo bash ./install.sh" >&2
    exit 1
fi
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]] || ! id "$TARGET_USER" &>/dev/null; then
    echo "A non-root desktop user is required. Use --user USER." >&2
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"

if [[ ! -f "$PROJECT_DIR/app.py" || ! -f "$PROJECT_DIR/config/dashboard_data.json" ]]; then
    echo "This does not look like the Pi-Canva-Viewer repository: $PROJECT_DIR" >&2
    exit 1
fi

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        echo "Warning: this installer is tested for Ubuntu, found ${PRETTY_NAME:-unknown}." >&2
    fi
fi

has_display_manager() {
    [[ -d /etc/gdm3 || -d /etc/lightdm ]] || systemctl -q is-enabled display-manager.service 2>/dev/null
}

if ! has_display_manager && [[ $INSTALL_DESKTOP -ne 1 ]]; then
    cat >&2 <<'EOF'
No graphical desktop was detected. The kiosk needs one to run Chromium.
Run again with --install-desktop to install Ubuntu Desktop Minimal automatically.
EOF
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 ca-certificates curl cec-utils v4l-utils x11-xserver-utils

if [[ $INSTALL_DESKTOP -eq 1 ]] && ! has_display_manager; then
    apt-get install -y ubuntu-desktop-minimal gdm3
fi

if ! command -v chromium-browser >/dev/null 2>&1 && ! command -v chromium >/dev/null 2>&1 && [[ ! -x /snap/bin/chromium ]]; then
    # On current Ubuntu releases this package installs the supported Chromium snap.
    apt-get install -y chromium-browser || {
        apt-get install -y snapd
        snap install chromium
    }
fi

# Nice-to-have utilities only; the kiosk does not rely on coordinate-based clicks.
apt-get install -y unclutter xdotool || true

for group in video render; do
    if getent group "$group" >/dev/null; then
        usermod -aG "$group" "$TARGET_USER"
    fi
done

mkdir -p /etc/pi-screen
RUNTIME_ENV=/etc/pi-screen/runtime.env
if [[ -z "$ADMIN_PIN" && -f "$RUNTIME_ENV" ]]; then
    ADMIN_PIN="$(sed -n 's/^PI_SCREEN_ADMIN_PIN=//p' "$RUNTIME_ENV" | head -n 1)"
fi
if [[ -z "$ADMIN_PIN" ]]; then
    ADMIN_PIN="1234"
fi
if [[ ! "$ADMIN_PIN" =~ ^[0-9]{4,12}$ ]]; then
    echo "Admin PIN must contain 4 to 12 digits." >&2
    exit 2
fi

umask 077
cat >"${RUNTIME_ENV}.tmp" <<EOF
KIOSK_HOST=0.0.0.0
KIOSK_PORT=8080
PI_SCREEN_ADMIN_PIN=${ADMIN_PIN}
EOF
install -o root -g "$TARGET_GROUP" -m 0640 "${RUNTIME_ENV}.tmp" "$RUNTIME_ENV"
rm -f "${RUNTIME_ENV}.tmp"

install -d -o "$TARGET_USER" -g "$TARGET_GROUP" -m 0755 "$TARGET_HOME/.config/autostart"
sed "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
    "$PROJECT_DIR/systemd/pi-screen-kiosk.desktop.in" \
    >"$TARGET_HOME/.config/autostart/pi-screen-kiosk.desktop"
chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.config/autostart/pi-screen-kiosk.desktop"
chmod 0644 "$TARGET_HOME/.config/autostart/pi-screen-kiosk.desktop"
chmod 0755 "$PROJECT_DIR/scripts/kiosk_supervisor.sh"

sed \
    -e "s|__PI_SCREEN_USER__|$TARGET_USER|g" \
    -e "s|__PI_SCREEN_GROUP__|$TARGET_GROUP|g" \
    -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
    "$PROJECT_DIR/systemd/pi-screen-server.service.in" \
    >/etc/systemd/system/pi-screen-server.service

if [[ -d /etc/gdm3 ]]; then
    GDM_CONFIG=/etc/gdm3/custom.conf
    cp -n "$GDM_CONFIG" "${GDM_CONFIG}.pi-screen.bak" 2>/dev/null || true
    python3 - "$GDM_CONFIG" "$TARGET_USER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
user = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
start = next((i for i, line in enumerate(lines) if line.strip().lower() == "[daemon]"), None)
if start is None:
    lines += ["", "[daemon]"]
    start = len(lines) - 1
end = next((i for i in range(start + 1, len(lines)) if lines[i].strip().startswith("[")), len(lines))
section = [line for line in lines[start + 1:end] if not line.strip().startswith(("AutomaticLoginEnable=", "AutomaticLogin="))]
section += ["AutomaticLoginEnable=True", f"AutomaticLogin={user}"]
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("\n".join(lines[:start + 1] + section + lines[end:]).rstrip() + "\n", encoding="utf-8")
PY
elif [[ -d /etc/lightdm ]]; then
    install -d /etc/lightdm/lightdm.conf.d
    cat >/etc/lightdm/lightdm.conf.d/50-pi-screen-autologin.conf <<EOF
[Seat:*]
autologin-user=${TARGET_USER}
autologin-user-timeout=0
EOF
else
    echo "No supported display manager found (GDM or LightDM). Configure automatic login manually." >&2
fi

chown -R "$TARGET_USER:$TARGET_GROUP" "$PROJECT_DIR/config"
chown "$TARGET_USER:$TARGET_GROUP" "$PROJECT_DIR/canva_url.txt"
systemctl daemon-reload
# Avoid two browser/server stacks fighting for port 8080 when upgrading the
# original prototype in place.
for legacy_service in pi_kiosk_server.service start_canva.service; do
    systemctl disable --now "$legacy_service" 2>/dev/null || true
done
systemctl enable pi-screen-server.service
systemctl restart pi-screen-server.service
systemctl set-default graphical.target

cat <<EOF

Installation complete.

  Display:  http://127.0.0.1:8080/display
  Admin:    http://<PI-IP>:8080/admin
  Admin-PIN: ${ADMIN_PIN}

After the next reboot, Ubuntu logs in as ${TARGET_USER}, starts the kiosk
automatically, and keeps the server running via systemd. The default PIN is
1234; you can set another PIN with --admin-pin. It is stored in ${RUNTIME_ENV}.
EOF
