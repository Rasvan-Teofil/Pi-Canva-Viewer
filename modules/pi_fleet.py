import json
import urllib.error
import urllib.request
from typing import Any, Dict, List

from .config_manager import load_config


def fetch_fleet_status() -> List[Dict[str, Any]]:
    """Query status of all registered Raspberry Pis in the fleet (local + remote nodes)."""
    cfg = load_config()
    fleet = cfg.get("pi_fleet", [])
    results = []

    for node in fleet:
        if node.get("is_local"):
            results.append(
                {
                    **node,
                    "online": True,
                    "mode": cfg.get("display", {}).get("mode", "dashboard"),
                    "tv_power": cfg.get("tv_power", {}).get("simulated_state", "on"),
                    "last_action": cfg.get("tv_power", {}).get("last_action"),
                }
            )
            continue

        host = (node.get("host") or "").rstrip("/")
        if not host:
            results.append({**node, "online": False, "error": "Kein Host konfiguriert"})
            continue

        try:
            req = urllib.request.Request(f"{host}/api/state", method="GET")
            with urllib.request.urlopen(req, timeout=2.0) as resp:
                remote_state = json.loads(resp.read().decode("utf-8"))
                results.append(
                    {
                        **node,
                        "online": True,
                        "mode": remote_state.get("display", {}).get("mode", "unknown"),
                        "tv_power": remote_state.get("tv_power", {}).get("simulated_state", "unknown"),
                        "last_action": remote_state.get("tv_power", {}).get("last_action"),
                    }
                )
        except Exception as exc:
            results.append(
                {
                    **node,
                    "online": False,
                    "mode": "offline",
                    "tv_power": "unknown",
                    "error": str(exc),
                }
            )
    return results


def dispatch_to_node(node: Dict[str, Any], endpoint: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    """Send a REST POST command to a remote Raspberry Pi node."""
    host = (node.get("host") or "").rstrip("/")
    url = f"{host}{endpoint}"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=3.5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return {"node_id": node.get("id"), "name": node.get("name"), "ok": True, "response": data}
    except Exception as exc:
        return {"node_id": node.get("id"), "name": node.get("name"), "ok": False, "error": str(exc)}
