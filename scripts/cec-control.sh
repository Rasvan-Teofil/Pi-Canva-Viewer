#!/usr/bin/env bash
# Minimal, local HDMI-CEC control for the Samsung display connected to the Pi.
# Usage: cec-control.sh on|off|active|status

set -Eeuo pipefail

CONFIG_FILE="${PI_SCREEN_CONFIG:-/etc/pi-screen/config.env}"
if [[ -r "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

ACTION="${1:-status}"
ADDRESS="${CEC_ADDRESS:-0}"

if ! command -v cec-client >/dev/null 2>&1; then
  echo "cec-client is not installed. Install cec-utils first." >&2
  exit 127
fi

send_cec() {
  # -s: single command session, -d 1: concise diagnostic output
  printf '%s\n' "$1" | cec-client -s -d 1
}

case "$ACTION" in
  on)
    send_cec "on ${ADDRESS}"
    send_cec "as"
    ;;
  off|standby)
    send_cec "standby ${ADDRESS}"
    ;;
  active|active-source)
    send_cec "as"
    ;;
  status)
    send_cec "pow ${ADDRESS}"
    ;;
  *)
    echo "Usage: $0 on|off|active|status" >&2
    exit 2
    ;;
esac
