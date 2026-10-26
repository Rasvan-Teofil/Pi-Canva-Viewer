import datetime
import shutil
import subprocess
import threading
import time
from typing import Any, Dict, Tuple

from .config_manager import load_config, save_config


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
        if has_cec_client:
            rc, out = _run_cmd(["cec-client", "-s", "-d", "1"], stdin_text=f"pow {cec_address}\n")
            methods_tried.append("cec-client (pow)")
            if "power status: on" in out.lower():
                tv_cfg["simulated_state"] = "on"
            elif "standby" in out.lower():
                tv_cfg["simulated_state"] = "standby"
            details = out
        return {
            "ok": True,
            "action": "status",
            "power_state": tv_cfg.get("simulated_state", "on"),
            "cec_available": has_cec_client or has_cec_ctl,
            "methods_tried": methods_tried,
            "last_action": tv_cfg.get("last_action"),
            "last_action_time": tv_cfg.get("last_action_time"),
            "schedule": tv_cfg.get("schedule", {}),
            "details": details or "Simulated/cached state (CEC binary not detected on host)",
        }
    else:
        return {"ok": False, "error": f"Unknown TV power action: {action}"}

    now_iso = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cfg = load_config()
    tv_cfg = cfg.setdefault("tv_power", {})
    if norm_action in ("on", "active-source"):
        tv_cfg["simulated_state"] = "on"
    elif norm_action == "standby":
        tv_cfg["simulated_state"] = "standby"
    tv_cfg["last_action"] = norm_action
    tv_cfg["last_action_time"] = now_iso
    save_config(cfg)

    return {
        "ok": True,
        "action": norm_action,
        "power_state": tv_cfg.get("simulated_state", "on"),
        "hardware_executed": success,
        "cec_available": has_cec_client or has_cec_ctl,
        "methods_tried": methods_tried or ["simulation (no cec-client found)"],
        "timestamp": now_iso,
        "details": details or "State updated (CEC simulated on non-Pi host)",
    }


class NightPowerScheduler(threading.Thread):
    """Background daemon that automatically switches the TV into standby at night and wakes it up in the morning."""

    def __init__(self, check_interval_sec: int = 30) -> None:
        super().__init__(daemon=True, name="NightPowerScheduler")
        self.check_interval_sec = check_interval_sec
        self._last_triggered_minute = ""

    def run(self) -> None:
        while True:
            try:
                self._check_schedule()
            except Exception:
                pass
            time.sleep(self.check_interval_sec)

    def _check_schedule(self) -> None:
        now = datetime.datetime.now()
        current_hm = now.strftime("%H:%M")
        minute_key = now.strftime("%Y-%m-%d %H:%M")
        if minute_key == self._last_triggered_minute:
            return

        cfg = load_config()
        tv_cfg = cfg.get("tv_power", {})
        sched = tv_cfg.get("schedule", {})
        if not sched.get("enabled", True):
            return

        active_days = sched.get("active_days", [0, 1, 2, 3, 4, 5, 6])
        off_time = sched.get("off_time", "22:30")
        on_time = sched.get("on_time", "08:00")
        cec_addr = str(tv_cfg.get("cec_address", "0"))

        if current_hm == off_time:
            self._last_triggered_minute = minute_key
            execute_tv_power("standby", cec_address=cec_addr)
        elif current_hm == on_time and now.weekday() in active_days:
            self._last_triggered_minute = minute_key
            execute_tv_power("on", cec_address=cec_addr)
