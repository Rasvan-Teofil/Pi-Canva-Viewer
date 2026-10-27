import datetime
import shutil
import subprocess
import threading
import time
from typing import Any, Dict, Tuple

from .config_manager import config_write_lock, load_config, save_config


def _run_cmd(cmd: list[str], stdin_text: str | None = None, timeout: int = 8) -> Tuple[int, str]:
    try:
        proc = subprocess.run(
            cmd,
            input=stdin_text,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
        out = ((proc.stdout or "") + "\n" + (proc.stderr or "")).strip()
        return proc.returncode, out
    except Exception as exc:
        return 1, str(exc)


def _parse_time(value: Any, field_name: str) -> datetime.time:
    if not isinstance(value, str):
        raise ValueError(f"{field_name} muss im Format HH:MM angegeben werden.")
    try:
        return datetime.datetime.strptime(value.strip(), "%H:%M").time()
    except ValueError as exc:
        raise ValueError(f"{field_name} muss im Format HH:MM angegeben werden.") from exc


def apply_schedule_update(tv_cfg: Dict[str, Any], payload: Dict[str, Any]) -> Dict[str, Any]:
    """Validate and apply schedule settings to a TV config in place."""
    sched = tv_cfg.setdefault("schedule", {})

    if "enabled" in payload:
        if not isinstance(payload["enabled"], bool):
            raise ValueError("enabled muss true oder false sein.")
        sched["enabled"] = payload["enabled"]
    if "off_time" in payload:
        _parse_time(payload["off_time"], "off_time")
        sched["off_time"] = payload["off_time"].strip()
    if "on_time" in payload:
        _parse_time(payload["on_time"], "on_time")
        sched["on_time"] = payload["on_time"].strip()
    if "active_days" in payload:
        raw_days = payload["active_days"]
        if not isinstance(raw_days, list) or not raw_days:
            raise ValueError("active_days muss mindestens einen Wochentag enthalten.")
        try:
            days = sorted({int(day) for day in raw_days})
        except (TypeError, ValueError) as exc:
            raise ValueError("active_days enthält ungültige Wochentage.") from exc
        if any(day < 0 or day > 6 for day in days):
            raise ValueError("active_days darf nur Werte von 0 (Montag) bis 6 (Sonntag) enthalten.")
        sched["active_days"] = days
    if "cec_address" in payload:
        address = str(payload["cec_address"]).strip()
        if not address or len(address) > 16:
            raise ValueError("Ungültige CEC-Adresse.")
        tv_cfg["cec_address"] = address

    _parse_time(sched.get("off_time", "22:30"), "off_time")
    _parse_time(sched.get("on_time", "08:00"), "on_time")
    return tv_cfg


def scheduled_power_state(now: datetime.datetime, schedule: Dict[str, Any]) -> str | None:
    """Return the desired CEC state or None when scheduling is disabled.

    ``active_days`` describes the days on which a screen starts its display
    window. It correctly covers windows that run past midnight.
    """
    if not schedule.get("enabled", True):
        return None

    on_time = _parse_time(schedule.get("on_time", "08:00"), "on_time")
    off_time = _parse_time(schedule.get("off_time", "22:30"), "off_time")
    if on_time == off_time:
        raise ValueError("on_time und off_time dürfen nicht identisch sein.")

    raw_days = schedule.get("active_days", list(range(7)))
    try:
        active_days = {int(day) for day in raw_days}
    except (TypeError, ValueError) as exc:
        raise ValueError("active_days enthält ungültige Wochentage.") from exc
    if not active_days or any(day < 0 or day > 6 for day in active_days):
        raise ValueError("active_days muss Wochentage von 0 bis 6 enthalten.")

    current_time = now.time().replace(second=0, microsecond=0)
    today = now.weekday()
    yesterday = (today - 1) % 7

    if on_time < off_time:
        is_on = today in active_days and on_time <= current_time < off_time
    else:
        is_on = (today in active_days and current_time >= on_time) or (
            yesterday in active_days and current_time < off_time
        )
    return "on" if is_on else "standby"


def execute_tv_power(action: str, cec_address: str = "0") -> Dict[str, Any]:
    """
    Execute an HDMI-CEC or display power command on the Raspberry Pi.
    Supported actions: 'on', 'standby' (or 'off'), 'active-source' (or 'as'), 'status'
    """
    norm_action = action.lower().strip()
    if norm_action == "off":
        norm_action = "standby"
    elif norm_action == "as":
        norm_action = "active-source"

    methods_tried = []
    success = False
    details = ""

    has_cec_client = shutil.which("cec-client") is not None
    has_cec_ctl = shutil.which("cec-ctl") is not None
    has_vcgencmd = shutil.which("vcgencmd") is not None
    has_xset = shutil.which("xset") is not None

    if norm_action == "on":
        if has_cec_client:
            rc, out = _run_cmd(["cec-client", "-s", "-d", "1"], stdin_text=f"on {cec_address}\nas\n")
            methods_tried.append("cec-client (on + active-source)")
            if rc == 0:
                success = True
                details = out
        elif has_cec_ctl:
            rc, out = _run_cmd(["cec-ctl", "--to", cec_address, "--image-view-on"])
            methods_tried.append("cec-ctl (--image-view-on)")
            if rc == 0:
                success = True
                details = out
                source_rc, source_out = _run_cmd(["cec-ctl", "--active-source", "phys-addr=1.0.0.0"])
                methods_tried.append("cec-ctl (--active-source)")
                details = (details + " | " + source_out).strip(" |")

        if has_vcgencmd:
            rc, out = _run_cmd(["vcgencmd", "display_power", "1"])
            methods_tried.append("vcgencmd display_power 1")
            if rc == 0:
                success = True
                details = (details + " | " + out).strip(" |")

        if has_xset:
            _run_cmd(["xset", "-display", ":0", "dpms", "force", "on"])
            methods_tried.append("xset dpms force on")

    elif norm_action == "standby":
        if has_cec_client:
            rc, out = _run_cmd(["cec-client", "-s", "-d", "1"], stdin_text=f"standby {cec_address}\n")
            methods_tried.append("cec-client (standby)")
            if rc == 0:
                success = True
                details = out
        elif has_cec_ctl:
            rc, out = _run_cmd(["cec-ctl", "--to", cec_address, "--standby"])
            methods_tried.append("cec-ctl (--standby)")
            if rc == 0:
                success = True
                details = out

        if has_vcgencmd:
            rc, out = _run_cmd(["vcgencmd", "display_power", "0"])
            methods_tried.append("vcgencmd display_power 0")
            if rc == 0:
                success = True
                details = (details + " | " + out).strip(" |")

        if has_xset:
            _run_cmd(["xset", "-display", ":0", "dpms", "force", "off"])
            methods_tried.append("xset dpms force off")

    elif norm_action == "active-source":
        if has_cec_client:
            rc, out = _run_cmd(["cec-client", "-s", "-d", "1"], stdin_text="as\n")
            methods_tried.append("cec-client (active-source)")
            if rc == 0:
                success = True
                details = out
        elif has_cec_ctl:
            rc, out = _run_cmd(["cec-ctl", "--active-source", "phys-addr=1.0.0.0"])
            methods_tried.append("cec-ctl (--active-source)")
            if rc == 0:
                success = True
                details = out

    elif norm_action == "status":
        cfg = load_config()
        tv_cfg = cfg.get("tv_power", {})
        # A status command that cannot identify an actual power state must not
        # recycle a potentially stale cached value as if it were verified.
        state = "unknown"
        if has_cec_client:
            rc, out = _run_cmd(["cec-client", "-s", "-d", "1"], stdin_text=f"pow {cec_address}\n")
            methods_tried.append("cec-client (pow)")
            success = rc == 0
            if "power status: on" in out.lower():
                state = "on"
            elif "standby" in out.lower():
                state = "standby"
            details = out
        elif has_cec_ctl:
            rc, out = _run_cmd(["cec-ctl", "--to", cec_address, "--give-device-power-status"])
            methods_tried.append("cec-ctl (--give-device-power-status)")
            success = rc == 0
            lower_out = out.lower()
            if "on" in lower_out and "standby" not in lower_out:
                state = "on"
            elif "standby" in lower_out:
                state = "standby"
            details = out
        else:
            details = "Kein HDMI-CEC-Tool gefunden. Der TV-Status kann nicht bestätigt werden."

        tv_cfg["last_power_state"] = state
        tv_cfg["simulated_state"] = state  # Compatibility with the existing display UI.
        tv_cfg["last_status_check"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        save_config(cfg)
        return {
            "ok": success,
            "action": "status",
            "power_state": state,
            "cec_available": has_cec_client or has_cec_ctl,
            "methods_tried": methods_tried,
            "last_action": tv_cfg.get("last_action"),
            "last_action_time": tv_cfg.get("last_action_time"),
            "schedule": tv_cfg.get("schedule", {}),
            "details": details,
            "error": None if success else "CEC-Status konnte nicht abgefragt werden.",
        }
    else:
        return {"ok": False, "error": f"Unknown TV power action: {action}"}

    now_iso = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cfg = load_config()
    tv_cfg = cfg.setdefault("tv_power", {})
    if success and norm_action in ("on", "active-source"):
        tv_cfg["simulated_state"] = "on"
        tv_cfg["last_power_state"] = "on"
    elif success and norm_action == "standby":
        tv_cfg["simulated_state"] = "standby"
        tv_cfg["last_power_state"] = "standby"
    tv_cfg["last_action"] = norm_action if success else f"{norm_action} fehlgeschlagen"
    tv_cfg["last_action_time"] = now_iso
    save_config(cfg)

    return {
        "ok": success,
        "action": norm_action,
        "power_state": tv_cfg.get("last_power_state", "unknown"),
        "hardware_executed": success,
        "cec_available": has_cec_client or has_cec_ctl,
        "methods_tried": methods_tried,
        "timestamp": now_iso,
        "details": details,
        "error": None if success else "TV-Befehl wurde nicht über HDMI-CEC ausgeführt.",
    }


class NightPowerScheduler(threading.Thread):
    """Background daemon that automatically switches the TV into standby at night and wakes it up in the morning."""

    def __init__(self, check_interval_sec: int = 30) -> None:
        super().__init__(daemon=True, name="NightPowerScheduler")
        self.check_interval_sec = check_interval_sec
        self._last_failure_state = ""
        self._last_failure_at: datetime.datetime | None = None

    def run(self) -> None:
        while True:
            try:
                self._check_schedule()
            except Exception:
                pass
            time.sleep(self.check_interval_sec)

    def _check_schedule(self) -> None:
        with config_write_lock():
            self._check_schedule_locked()

    def _check_schedule_locked(self) -> None:
        now = datetime.datetime.now()
        cfg = load_config()
        tv_cfg = cfg.get("tv_power", {})
        sched = tv_cfg.get("schedule", {})
        desired_state = scheduled_power_state(now, sched)
        if desired_state is None:
            return

        # Reconcile on boot as well as at a transition. This means a Pi that
        # restarts during its opening hours wakes the TV again automatically.
        if tv_cfg.get("last_schedule_state") == desired_state:
            return

        if (
            self._last_failure_state == desired_state
            and self._last_failure_at is not None
            and (now - self._last_failure_at).total_seconds() < 300
        ):
            return

        cec_addr = str(tv_cfg.get("cec_address", "0"))
        result = execute_tv_power(desired_state, cec_address=cec_addr)
        if not result.get("ok"):
            self._last_failure_state = desired_state
            self._last_failure_at = now
            return

        self._last_failure_state = ""
        self._last_failure_at = None

        latest_cfg = load_config()
        latest_tv_cfg = latest_cfg.setdefault("tv_power", {})
        latest_tv_cfg["last_schedule_state"] = desired_state
        latest_tv_cfg["last_schedule_reconcile"] = now.strftime("%Y-%m-%d %H:%M:%S")
        save_config(latest_cfg)
