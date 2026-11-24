#!/usr/bin/env bash
# HDMI-CEC-Steuerung für den Fernseher am Pi. Läuft ohne root
# (User braucht Zugriff auf /dev/cec* bzw. /dev/vchiq, i. d. R. Gruppe "video").
# Usage: cec-control.sh on|off|active|status

set -Eeuo pipefail

for cfg in "${PI_SCREEN_BOARD_CONFIG:-$HOME/.config/pi-screen/board.env}" /etc/pi-screen/config.env; do
  if [[ -r "$cfg" ]]; then
    # shellcheck disable=SC1090
    source "$cfg"
    break
  fi
done

ACTION="${1:-status}"
ADDRESS="${CEC_ADDRESS:-0}"
DEVICE="${CEC_DEVICE:-/dev/cec0}"

log() { logger -t pi-screen-cec -- "$*" 2>/dev/null || true; echo "$*"; }

# 1. Weg: cec-client (libcec, cec-utils)
via_cec_client() {
  command -v cec-client >/dev/null 2>&1 || return 1
  local out
  out="$(printf '%s\n' "$1" | timeout 15 cec-client -s -d 1 2>&1)" || { echo "$out"; return 1; }
  echo "$out"
  ! grep -qiE 'could not open|autodetect FAILED|no device|ERROR' <<<"$out"
}

# 2. Weg: cec-ctl (v4l-utils, Linux-CEC /dev/cec0) – Fallback
via_cec_ctl() {
  command -v cec-ctl >/dev/null 2>&1 || return 1
  [[ -e "$DEVICE" ]] || return 1
  cec-ctl -d "$DEVICE" --playback >/dev/null 2>&1 || true
  case "$1" in
    on)
      cec-ctl -d "$DEVICE" --to "$ADDRESS" --image-view-on
      local phys
      phys="$(cec-ctl -d "$DEVICE" 2>/dev/null | awk '/Physical Address/ {print $NF; exit}')"
      [[ -n "$phys" && "$phys" != "f.f.f.f" ]] && cec-ctl -d "$DEVICE" --to 15 --active-source "phys-addr=$phys" || true
      ;;
    off)    cec-ctl -d "$DEVICE" --to "$ADDRESS" --standby ;;
    active)
      local phys
      phys="$(cec-ctl -d "$DEVICE" 2>/dev/null | awk '/Physical Address/ {print $NF; exit}')"
      cec-ctl -d "$DEVICE" --to 15 --active-source "phys-addr=${phys:-1.0.0.0}"
      ;;
    status) cec-ctl -d "$DEVICE" --to "$ADDRESS" --give-device-power-status ;;
  esac
}

run() {
  local action="$1"; shift
  local cmd
  for cmd in "$@"; do
    via_cec_client "$cmd" || { log "cec-client fehlgeschlagen ($cmd), versuche cec-ctl"; via_cec_ctl "$action" && return 0; log "CEC $action fehlgeschlagen"; return 1; }
  done
}

case "$ACTION" in
  on)                 log "TV an";    run on "on ${ADDRESS}" "as" ;;
  off|standby)        log "TV aus";   run off "standby ${ADDRESS}" ;;
  active|active-source) run active "as" ;;
  status)             run status "pow ${ADDRESS}" ;;
  *) echo "Usage: $0 on|off|active|status" >&2; exit 2 ;;
esac
