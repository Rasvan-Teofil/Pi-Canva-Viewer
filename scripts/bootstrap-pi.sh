#!/usr/bin/env bash
# Pi-Screen V1 bootstrap for a fresh Raspberry Pi OS Desktop installation.
# Intended to be run as root, including through curl | sudo bash.

set -Eeuo pipefail

REPOSITORY_URL="${PI_SCREEN_REPOSITORY_URL:-https://github.com/Rasvan-Teofil/Pi-Canva-Viewer.git}"
INSTALL_DIR="/opt/pi-screen"
CONFIG_DIR="/etc/pi-screen"
CONFIG_FILE="${CONFIG_DIR}/config.env"
KIOSK_USER="canva"
BRANCH="main"
CANVA_URL=""
MODE=""
ADMIN_PIN=""
NO_UPGRADE=0
REBOOT_AFTER_INSTALL=0

usage() {
  cat <<'EOF'
Usage: sudo bash bootstrap-pi.sh [options]

Options:
  --canva-url URL       Canva URL to open in the kiosk (required on a fresh Pi)
  --user USER           Kiosk account name (default: canva)
  --admin-pin PIN       Reserved V2 PIN; 4 digits (default: 1234)
  --mode MODE           canva, public, or dashboard (default: existing value or canva)
  --branch BRANCH       Repository branch to install (default: main)
  --no-upgrade          Install missing packages without a full OS upgrade
  --reboot              Reboot automatically when the setup succeeds
  --help                Show this help text

V1 configuration is stored outside the repository in /etc/pi-screen/config.env.
EOF
}

die() {
  echo "pi-screen bootstrap: $*" >&2
  exit 1
}

log() {
  echo "[pi-screen] $*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --canva-url)
      CANVA_URL="${2:?--canva-url needs a value}"
      shift
      ;;
    --user)
      KIOSK_USER="${2:?--user needs a value}"
      shift
      ;;
    --admin-pin)
      ADMIN_PIN="${2:?--admin-pin needs a value}"
      shift
      ;;
    --mode)
      MODE="${2:?--mode needs a value}"
      shift
      ;;
    --branch)
      BRANCH="${2:?--branch needs a value}"
      shift
      ;;
    --no-upgrade)
      NO_UPGRADE=1
      ;;
    --reboot)
      REBOOT_AFTER_INSTALL=1
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

[[ ${EUID} -eq 0 ]] || die "run this script with sudo"
[[ "$KIOSK_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "--user must be a valid Linux user name"
[[ "$BRANCH" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || die "--branch contains unsupported characters"
if [[ -n "$MODE" && "$MODE" != "canva" && "$MODE" != "public" && "$MODE" != "dashboard" ]]; then
  die "--mode must be canva, public, or dashboard"
fi
if [[ -n "$ADMIN_PIN" && ! "$ADMIN_PIN" =~ ^[0-9]{4}$ ]]; then
  die "--admin-pin must contain exactly four digits"
fi
if [[ -n "$CANVA_URL" && ! "$CANVA_URL" =~ ^https:// ]]; then
  die "--canva-url must start with https://"
fi

export DEBIAN_FRONTEND=noninteractive

install_packages() {
  log "Updating Raspberry Pi OS packages"
  apt-get update
  if [[ "$NO_UPGRADE" -eq 0 ]]; then
    apt-get -y full-upgrade
  fi

  apt-get install -y \
    ca-certificates \
    cec-utils \
    curl \
    dbus-x11 \
    git \
    lightdm \
    openbox \
    python3 \
    unclutter \
    xserver-xorg \
    x11-xserver-utils \
    xdotool

  if apt-cache show chromium-browser >/dev/null 2>&1; then
    apt-get install -y chromium-browser
  elif apt-cache show chromium >/dev/null 2>&1; then
    apt-get install -y chromium
  else
    die "No Chromium package is available through apt on this image"
  fi
}

stop_legacy_installations() {
  log "Removing known legacy Pi-Screen services and autostarts"
  local service
  for service in \
    pi-screen.service \
    pi-screen-kiosk.service \
    pi-screen-server.service \
    pi_kiosk_server.service \
    start_canva.service; do
    systemctl disable --now "$service" 2>/dev/null || true
    rm -f "/etc/systemd/system/$service"
  done
  systemctl daemon-reload

  # These names only belong to previous Pi-Screen experiments; do not remove
  # arbitrary user autostart files.
  find /home -maxdepth 4 -type f \( \
    -name 'pi-screen.desktop' -o \
    -name 'pi-screen-kiosk.desktop' -o \
    -name 'start-canva.desktop' \
  \) -path '*/.config/autostart/*' -delete 2>/dev/null || true

  # Only target process names that belonged to the discontinued prototypes.
  # The patterns include the script filename boundary so unrelated programs are
  # not caught during a repeat installation.
  pkill -f '/start_canva\.sh($| )' 2>/dev/null || true
  pkill -f '/kiosk_supervisor\.sh($| )' 2>/dev/null || true
}

install_repository() {
  log "Installing branch '$BRANCH' into $INSTALL_DIR"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    git -C "$INSTALL_DIR" fetch --prune origin "$BRANCH"
    git -C "$INSTALL_DIR" checkout --force -B "$BRANCH" FETCH_HEAD
    git -C "$INSTALL_DIR" reset --hard FETCH_HEAD
    git -C "$INSTALL_DIR" clean -ffd
  elif [[ -e "$INSTALL_DIR" ]]; then
    die "$INSTALL_DIR exists but is not a Git checkout; move it aside before installing"
  else
    git clone --branch "$BRANCH" --single-branch "$REPOSITORY_URL" "$INSTALL_DIR"
  fi
  [[ -f "$INSTALL_DIR/kiosk/start-kiosk.sh" ]] || die "The selected branch has no kiosk/start-kiosk.sh"
  [[ -f "$INSTALL_DIR/scripts/cec-control.sh" ]] || die "The selected branch has no scripts/cec-control.sh"
}

ensure_kiosk_user() {
  if ! id "$KIOSK_USER" >/dev/null 2>&1; then
    log "Creating dedicated kiosk user '$KIOSK_USER'"
    useradd --create-home --shell /bin/bash "$KIOSK_USER"
  fi

  # The session is entered only via LightDM autologin. A locked password keeps
  # SSH/su password authentication unavailable while satisfying the no-password
  # kiosk requirement.
  passwd --lock "$KIOSK_USER" >/dev/null 2>&1 || true
  for group in video render input; do
    if getent group "$group" >/dev/null; then
      usermod -aG "$group" "$KIOSK_USER"
    fi
  done
  KIOSK_GROUP="$(id -gn "$KIOSK_USER")"
}

write_config() {
  install -d -o root -g "$KIOSK_GROUP" -m 0750 "$CONFIG_DIR"

  CONFIG_PATH="$CONFIG_FILE" \
  CONFIG_TEMPLATE_PATH="$INSTALL_DIR/config/config.env.example" \
  CONFIG_CANVA_URL="$CANVA_URL" \
  CONFIG_MODE="$MODE" \
  CONFIG_ADMIN_PIN="$ADMIN_PIN" \
  python3 - <<'PY'
import os
import pathlib
import shlex
import tempfile

path = pathlib.Path(os.environ["CONFIG_PATH"])
template_path = pathlib.Path(os.environ["CONFIG_TEMPLATE_PATH"])

def read_env_file(candidate: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not candidate.exists():
        return values
    for line in candidate.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, raw_value = line.split("=", 1)
        try:
            parts = shlex.split(raw_value, comments=False, posix=True)
        except ValueError:
            continue
        values[key] = parts[0] if parts else ""
    return values

if not template_path.exists():
    raise SystemExit(f"Missing configuration template: {template_path}")

values = read_env_file(template_path)
values.update(read_env_file(path))
canva_url = os.environ["CONFIG_CANVA_URL"] or values.get("CANVA_URL", "")
mode = os.environ["CONFIG_MODE"] or values.get("MODE", "canva")
admin_pin = os.environ["CONFIG_ADMIN_PIN"] or values.get("ADMIN_PIN", "1234")

if not canva_url:
    raise SystemExit("A Canva URL is required on the first installation; pass --canva-url")
if mode not in {"canva", "public", "dashboard"}:
    raise SystemExit("MODE must be canva, public, or dashboard")
if len(admin_pin) != 4 or not admin_pin.isdigit():
    raise SystemExit("ADMIN_PIN must contain four digits")

values.update({"CANVA_URL": canva_url, "MODE": mode, "ADMIN_PIN": admin_pin})

lines = [
    "# Managed by scripts/bootstrap-pi.sh. Values remain on repeat installs.",
    "# Edit this file and restart lightdm to switch the active content.",
]
lines += [f"{key}={shlex.quote(value)}" for key, value in values.items()]
data = "\n".join(lines) + "\n"
fd, temp_name = tempfile.mkstemp(prefix=".config.env.", dir=str(path.parent))
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    handle.write(data)
    handle.flush()
    os.fsync(handle.fileno())
os.chmod(temp_name, 0o640)
os.replace(temp_name, path)
PY
  chown root:"$KIOSK_GROUP" "$CONFIG_FILE"
}

configure_x11_autologin() {
  # Raspberry Pi OS Desktop may default to Wayland. The calibrated Canva
  # controls use xdotool, so install and select our explicit X11 session
  # instead of depending on whichever desktop session happens to be default.
  install -d -m 0755 /usr/share/xsessions
  install -m 0644 \
    "$INSTALL_DIR/kiosk/pi-screen-x11.desktop" \
    /usr/share/xsessions/pi-screen-x11.desktop

  install -d -m 0755 /etc/lightdm/lightdm.conf.d
  {
    echo "[Seat:*]"
    echo "autologin-user=$KIOSK_USER"
    echo "autologin-user-timeout=0"
    echo "user-session=pi-screen-x11"
    echo "autologin-session=pi-screen-x11"
  } >/etc/lightdm/lightdm.conf.d/90-pi-screen.conf

  install -d -o "$KIOSK_USER" -g "$KIOSK_GROUP" -m 0755 "/home/$KIOSK_USER/.config/autostart"
  install -o "$KIOSK_USER" -g "$KIOSK_GROUP" -m 0644 \
    "$INSTALL_DIR/kiosk/pi-screen.desktop" \
    "/home/$KIOSK_USER/.config/autostart/pi-screen.desktop"
  chmod 0755 "$INSTALL_DIR/kiosk/start-kiosk.sh"
  chmod 0755 "$INSTALL_DIR/scripts/cec-control.sh"
  if [[ -d "$INSTALL_DIR/dashboard" ]]; then
    install -d -o "$KIOSK_USER" -g "$KIOSK_GROUP" -m 0755 "/home/$KIOSK_USER/.local/share/pi-screen"
    ln -sfn "/home/$KIOSK_USER/.local/share/pi-screen/dashboard-config.js" \
      "$INSTALL_DIR/dashboard/runtime-config.js"
  fi
  systemctl set-default graphical.target
  systemctl enable lightdm
}

install_packages
stop_legacy_installations
install_repository
ensure_kiosk_user
write_config
configure_x11_autologin

log "V1 kiosk installation complete. Current mode: $(sed -n 's/^MODE=//p' "$CONFIG_FILE" | head -n 1)"
log "Canva login window: sudo -u $KIOSK_USER touch /home/$KIOSK_USER/.pi-screen-login && sudo systemctl restart lightdm"
log "Change URL or mode: sudoedit $CONFIG_FILE && sudo systemctl restart lightdm"

if [[ "$REBOOT_AFTER_INSTALL" -eq 1 ]]; then
  log "Rebooting now"
  systemctl reboot
else
  # Applying LightDM now makes a first-time installation self-contained and
  # also replaces a previously running kiosk after an update.
  log "Restarting LightDM so the kiosk starts immediately"
  systemctl restart lightdm
fi
