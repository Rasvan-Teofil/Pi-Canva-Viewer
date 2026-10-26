#!/bin/bash
# Standalone CLI helper script for HDMI-CEC TV Power Management on Raspberry Pi
# Usage: ./scripts/tv_cec_power.sh [on|standby|active|status] [cec_address]
# Recommended Cron / Systemd Timer companion or manual test tool.

ACTION="${1:-status}"
CEC_ADDR="${2:-0}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [TV-CEC] $*"
}

case "$ACTION" in
    on|wake)
        log "Turning TV ON (CEC address $CEC_ADDR) and setting Pi as Active Source..."
        if command -v cec-client >/dev/null 2>&1; then
            printf "on %s\nas\n" "$CEC_ADDR" | cec-client -s -d 1
        elif command -v cec-ctl >/dev/null 2>&1; then
            cec-ctl --to "$CEC_ADDR" --image-view-on
            cec-ctl --active-source phys-addr=1.0.0.0
        fi
        command -v vcgencmd >/dev/null 2>&1 && vcgencmd display_power 1
        command -v xset >/dev/null 2>&1 && DISPLAY=:0 xset dpms force on 2>/dev/null || true
        log "TV Wakeup command completed."
        ;;
    standby|off)
        log "Putting TV into STANDBY (CEC address $CEC_ADDR)..."
        if command -v cec-client >/dev/null 2>&1; then
            printf "standby %s\n" "$CEC_ADDR" | cec-client -s -d 1
        elif command -v cec-ctl >/dev/null 2>&1; then
            cec-ctl --to "$CEC_ADDR" --standby
        fi
        command -v vcgencmd >/dev/null 2>&1 && vcgencmd display_power 0
        command -v xset >/dev/null 2>&1 && DISPLAY=:0 xset dpms force off 2>/dev/null || true
        log "TV Standby command completed."
        ;;
    active|as|active-source)
        log "Forcing HDMI Active Source via CEC..."
        if command -v cec-client >/dev/null 2>&1; then
            echo "as" | cec-client -s -d 1
        elif command -v cec-ctl >/dev/null 2>&1; then
            cec-ctl --active-source phys-addr=1.0.0.0
        fi
        ;;
    status|pow)
        log "Querying TV power status via HDMI-CEC..."
        if command -v cec-client >/dev/null 2>&1; then
            printf "pow %s\n" "$CEC_ADDR" | cec-client -s -d 1
        else
            log "cec-client not installed. Install via: sudo apt-get install -y cec-utils"
        fi
        ;;
    *)
        echo "Usage: $0 {on|standby|active|status} [cec_address]"
        exit 1
        ;;
esac
