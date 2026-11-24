#!/usr/bin/env bash
# Schreibt den HDMI-CEC-Zeitplan aus ~/.config/pi-screen/schedule.env
# idempotent in die crontab des aktuellen Users.
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEDULE="${PI_SCREEN_SCHEDULE:-$HOME/.config/pi-screen/schedule.env}"
BEGIN="# >>> pi-screen cec schedule >>>"
END="# <<< pi-screen cec schedule <<<"

TV_ON="" TV_OFF="" TV_DAYS="*"
if [[ -r "$SCHEDULE" ]]; then
  # shellcheck disable=SC1090
  source "$SCHEDULE"
fi

cron_line() { # HH:MM action
  local t="$1" action="$2"
  [[ -z "$t" ]] && return 0
  if [[ ! "$t" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
    echo "Ungültige Uhrzeit: $t (erwartet HH:MM)" >&2; exit 1
  fi
  printf '%d %d * * %s %s/scripts/cec-control.sh %s >/dev/null 2>&1\n' \
    "$((10#${BASH_REMATCH[2]}))" "$((10#${BASH_REMATCH[1]}))" "${TV_DAYS:-*}" "$REPO_DIR" "$action"
}

lines="$(cron_line "$TV_ON" on)" || exit 1
off_line="$(cron_line "$TV_OFF" off)" || exit 1
[[ -n "$off_line" ]] && lines="${lines:+$lines
}$off_line"
block="$BEGIN${lines:+
$lines}
$END"

current="$(crontab -l 2>/dev/null || true)"
cleaned="$(awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' <<<"$current")"
printf '%s\n%s\n' "$cleaned" "$block" | sed '/^$/N;/^\n$/D' | crontab -

echo "CEC-Zeitplan aktiv (crontab -l):"
crontab -l | awk -v b="$BEGIN" -v e="$END" '$0==b{p=1} p; $0==e{p=0}'
