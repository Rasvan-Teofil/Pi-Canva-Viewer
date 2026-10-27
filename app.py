#!/usr/bin/env python3
"""
ICF Church Screen & Raspberry Pi Canva Kiosk Server
Zero-dependency Python 3 HTTP + REST server for managing:
1. Fullscreen Canva Keynote / Presentation Kiosk
2. ICF Church & Volunteer Tasks Dashboard (with optional Notion sync or live Notion Embed)
3. Any Published Notion Database / View (Notion Site /ebd/ Embed)
4. Verse of the Week (Vers der Woche) Fullscreen View
5. Automatic Playlist / Rotation Mode
6. Multi-Pi Fleet Control & HDMI-CEC TV Power Scheduling (Night Off / Auto Wake)
"""

import argparse
import datetime
import hmac
import json
import mimetypes
import os
import shutil
import subprocess
import uuid
from functools import wraps
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict
from urllib.parse import urlparse

from modules.config_manager import (
    config_write_lock,
    load_config,
    public_config,
    save_config,
    to_canva_embed_url,
    to_notion_embed_url,
)
from modules.notion_sync import sync_tasks_from_notion
from modules.pi_fleet import fetch_fleet_status
from modules.tv_power import NightPowerScheduler, apply_schedule_update, execute_tv_power

BASE_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = BASE_DIR / "templates"
STATIC_DIR = BASE_DIR / "static"

VALID_MODES = ("canva", "dashboard", "notion", "verse", "rotation")


def serialize_config_writes(method: Any) -> Any:
    """Keep a whole REST mutation atomic, not just the final file write."""

    @wraps(method)
    def wrapped(self: Any, *args: Any, **kwargs: Any) -> Any:
        with config_write_lock():
            return method(self, *args, **kwargs)

    return wrapped


def valid_web_url(value: Any, *, canva_only: bool = False) -> str | None:
    """Accept only plain HTTP(S) URLs; fleet hosts must never contain credentials."""
    raw = str(value or "").strip()
    try:
        parsed = urlparse(raw)
        port = parsed.port  # Accessing it validates an out-of-range port.
    except ValueError:
        return None
    if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.password:
        return None
    if canva_only:
        hostname = parsed.hostname.lower()
        if hostname != "canva.com" and not hostname.endswith(".canva.com"):
            return None
    if port is not None and not 1 <= port <= 65535:
        return None
    return raw


def trigger_xdotool_canva_autoplay() -> Dict[str, Any]:
    """Run the classic xdotool sequence from start_canva.sh to activate Canva fullscreen autoplay."""
    if not shutil.which("xdotool"):
        return {"ok": False, "error": "xdotool nicht installiert (nur auf Raspberry Pi Desktop verfügbar)."}
    script = """
    export DISPLAY=:0
    WIN_ID=$(xdotool search --onlyvisible --class "chromium" 2>/dev/null | head -n 1)
    if [ -n "$WIN_ID" ]; then
        xdotool windowactivate --sync "$WIN_ID"
        sleep 0.5
        xdotool key --clearmodifiers --delay 100 ctrl+alt+p
        sleep 2
        xdotool mousemove 1820 1050 && sleep 0.5 && xdotool click 1
        sleep 0.8
        xdotool mousemove 1559 872 && sleep 0.5 && xdotool click 1
        sleep 0.5
        xdotool mousemove 0 0 && xdotool click 1
    fi
    """
    subprocess.Popen(["/bin/bash", "-c", script])
    return {"ok": True, "message": "xdotool Canva-Autoplay Sequenz gestartet."}


def apply_notion_view_update(cfg: Dict[str, Any], body: Dict[str, Any]) -> Dict[str, Any]:
    """Update notion_view config and presets in-place and return the updated notion_view dict."""
    nv = cfg.setdefault("notion_view", {})
    nv.setdefault("subdomain", "icfhn")
    nv.setdefault("presets", [])

    action = body.get("action", "update")
    subdomain = str(body.get("subdomain") or nv.get("subdomain") or "icfhn").strip() or "icfhn"
    nv["subdomain"] = subdomain

    if action == "delete_preset":
        pid = body.get("id")
        nv["presets"] = [p for p in nv.get("presets", []) if p.get("id") != pid]
        return nv

    if action == "activate_preset":
        pid = body.get("id")
        for p in nv.get("presets", []):
            if p.get("id") == pid:
                nv["title"] = p.get("title") or nv.get("title") or "Notion Datenbank"
                nv["url"] = p.get("url") or ""
                nv["embed_url"] = to_notion_embed_url(nv["url"], subdomain)
                break
        if body.get("switch_mode"):
            cfg.setdefault("display", {})["mode"] = "notion"
        return nv

    # Regular update or save_preset
    if "title" in body:
        nv["title"] = str(body["title"]).strip() or "Notion Datenbank"
    if "url" in body:
        raw_url = str(body["url"]).strip()
        if raw_url:
            nv["url"] = raw_url
            nv["embed_url"] = to_notion_embed_url(raw_url, subdomain)
    if "show_in_dashboard" in body:
        nv["show_in_dashboard"] = bool(body["show_in_dashboard"])
    if "fullscreen_without_header" in body:
        nv["fullscreen_without_header"] = bool(body["fullscreen_without_header"])
    if "auto_refresh_min" in body:
        nv["auto_refresh_min"] = max(0, int(body.get("auto_refresh_min") or 0))
    if body.get("switch_mode"):
        cfg.setdefault("display", {})["mode"] = "notion"

    if action == "save_preset":
        preset_url = (body.get("url") or nv.get("url") or "").strip()
        preset_title = (body.get("title") or nv.get("title") or "Notion Ansicht").strip()
        if preset_url:
            embed_url = to_notion_embed_url(preset_url, subdomain)
            presets = nv.setdefault("presets", [])
            presets.append(
                {
                    "id": f"preset-{uuid.uuid4().hex[:6]}",
                    "title": preset_title,
                    "url": preset_url,
                    "embed_url": embed_url,
                }
            )

    return nv


class KioskRequestHandler(BaseHTTPRequestHandler):
    server_version = "PiCanvaChurchKiosk/2.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        # Quiet logging for frequent polling
        if self.path.startswith("/api/state"):
            return
        super().log_message(fmt, *args)

    def _send_json(self, data: Dict[str, Any], status: int = 200) -> None:
        raw = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def _require_admin(self) -> bool:
        """Protect every control API from devices merely connected to the LAN."""
        expected = os.environ.get("PI_SCREEN_ADMIN_TOKEN", "").strip()
        if not expected:
            self._send_json(
                {
                    "ok": False,
                    "error": "Der Server hat keinen PI_SCREEN_ADMIN_TOKEN. Bitte ./install.sh ausführen.",
                },
                status=503,
            )
            return False

        supplied = self.headers.get("X-API-Token", "").strip()
        if not hmac.compare_digest(supplied, expected):
            self._send_json({"ok": False, "error": "Nicht autorisiert."}, status=401)
            return False
        return True

    def _send_file(self, file_path: Path, content_type: str | None = None) -> None:
        if not file_path.exists() or not file_path.is_file():
            self.send_error(404, "File not found")
            return
        raw = file_path.read_bytes()
        ctype = content_type or mimetypes.guess_type(str(file_path))[0] or "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(raw)

    def _read_json_body(self) -> Dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return {}
        raw = self.rfile.read(length).decode("utf-8")
        return json.loads(raw) if raw else {}

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Allow", "GET, POST, OPTIONS")
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path in ("/display", "/kiosk"):
            self._send_file(TEMPLATES_DIR / "display.html", "text/html; charset=utf-8")
            return

        if path in ("/", "/admin", "/control"):
            self._send_file(TEMPLATES_DIR / "admin.html", "text/html; charset=utf-8")
            return

        if path.startswith("/static/"):
            rel = path[len("/static/") :]
            target = (STATIC_DIR / rel).resolve()
            try:
                target.relative_to(STATIC_DIR.resolve())
            except ValueError:
                self.send_error(403, "Forbidden")
                return
            else:
                self._send_file(target)
                return

        if path == "/api/state":
            cfg = load_config()
            now = datetime.datetime.now()
            self._send_json(
                {
                    **public_config(cfg),
                    "server_time": {
                        "iso": now.isoformat(),
                        "time_hm": now.strftime("%H:%M"),
                        "time_hms": now.strftime("%H:%M:%S"),
                        "date_de": now.strftime("%d.%m.%Y"),
                        "weekday_de": [
                            "Montag",
                            "Dienstag",
                            "Mittwoch",
                            "Donnerstag",
                            "Freitag",
                            "Samstag",
                            "Sonntag",
                        ][now.weekday()],
                    },
                }
            )
            return

        if path == "/api/fleet/status":
            if not self._require_admin():
                return
            self._send_json({"ok": True, "nodes": fetch_fleet_status()})
            return

        self.send_error(404, "Endpoint not found")

    @serialize_config_writes
    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        try:
            body = self._read_json_body()
        except Exception as exc:
            self._send_json({"ok": False, "error": f"Ungültiges JSON: {exc}"}, status=400)
            return

        if not self._require_admin():
            return

        cfg = load_config()

        # 1. Switch Display Mode / Rotation Settings
        if path == "/api/display/mode":
            mode = body.get("mode")
            if mode in VALID_MODES:
                cfg.setdefault("display", {})["mode"] = mode
            if "durations_sec" in body:
                durations = body["durations_sec"]
                rot = cfg.setdefault("display", {}).setdefault("rotation", {}).setdefault("durations_sec", {})
                for k in ("canva", "dashboard", "notion", "verse"):
                    if k in durations and int(durations[k]) >= 5:
                        rot[k] = int(durations[k])
            if "enabled_modes" in body and isinstance(body["enabled_modes"], list):
                enabled_modes = body["enabled_modes"]
                allowed_modes = {"canva", "dashboard", "notion", "verse"}
                if not enabled_modes or any(mode not in allowed_modes for mode in enabled_modes):
                    self._send_json({"ok": False, "error": "Ungültige Ansichten für die Rotation."}, status=400)
                    return
                cfg["display"].setdefault("rotation", {})["enabled_modes"] = enabled_modes
            if "device_name" in body:
                cfg.setdefault("device", {})["name"] = str(body["device_name"]).strip()
            if "device_location" in body:
                cfg.setdefault("device", {})["location"] = str(body["device_location"]).strip()
            save_config(cfg)
            self._send_json({"ok": True, "display": cfg["display"], "device": cfg["device"]})
            return

        # 2. Force Reload Display
        if path == "/api/display/reload":
            disp = cfg.setdefault("display", {})
            disp["reload_token"] = int(disp.get("reload_token", 1)) + 1
            save_config(cfg)
            if shutil.which("xdotool"):
                subprocess.Popen(
                    ["/bin/bash", "-c", "DISPLAY=:0 xdotool key F5 2>/dev/null || true"]
                )
            self._send_json({"ok": True, "reload_token": disp["reload_token"]})
            return

        # 3. Update Canva Presentation URL
        if path == "/api/canva":
            url = (body.get("url") or "").strip()
            title = (body.get("title") or cfg.get("canva", {}).get("title") or "").strip()
            if not url:
                self._send_json({"ok": False, "error": "Canva URL darf nicht leer sein."}, status=400)
                return
            if not valid_web_url(url, canva_only=True):
                self._send_json({"ok": False, "error": "Bitte einen gültigen canva.com Design-Link angeben."}, status=400)
                return
            cfg["canva"] = {
                "url": url,
                "embed_url": to_canva_embed_url(url),
                "title": title,
                "use_xdotool_autoplay": bool(body.get("use_xdotool_autoplay", True)),
            }
            save_config(cfg)
            self._send_json({"ok": True, "canva": cfg["canva"]})
            return

        # 4. Trigger classic xdotool Canva Autoplay
        if path == "/api/kiosk/canva-autoplay":
            res = trigger_xdotool_canva_autoplay()
            self._send_json(res)
            return

        # 5. Update Verse of the Week
        if path == "/api/verse":
            verse = cfg.setdefault("verse_of_the_week", {})
            for field in ("title", "week_label", "text", "reference", "impulse", "accent_color"):
                if field in body:
                    verse[field] = str(body[field]).strip()
            save_config(cfg)
            self._send_json({"ok": True, "verse_of_the_week": verse})
            return

        # 6. Manage Church / Volunteer Tasks
        if path == "/api/tasks":
            action = body.get("action", "add")
            tasks = cfg.setdefault("tasks", [])

            if action == "add":
                new_task = {
                    "id": f"task-{uuid.uuid4().hex[:6]}",
                    "title": (body.get("title") or "Neue Aufgabe").strip(),
                    "category": (body.get("category") or "Allgemein").strip(),
                    "status": body.get("status", "todo"),
                    "priority": body.get("priority", "medium"),
                    "assignee": (body.get("assignee") or "Offen").strip(),
                    "due": (body.get("due") or "Diese Woche").strip(),
                }
                tasks.insert(0, new_task)
            elif action == "toggle":
                tid = body.get("id")
                cycle = {"todo": "in_progress", "in_progress": "done", "done": "todo"}
                for t in tasks:
                    if t.get("id") == tid:
                        t["status"] = body.get("status") or cycle.get(t.get("status", "todo"), "todo")
                        break
            elif action == "delete":
                tid = body.get("id")
                cfg["tasks"] = [t for t in tasks if t.get("id") != tid]
            elif action == "update":
                tid = body.get("id")
                for t in tasks:
                    if t.get("id") == tid:
                        for k in ("title", "category", "status", "priority", "assignee", "due"):
                            if k in body:
                                t[k] = body[k]
                        break

            save_config(cfg)
            self._send_json({"ok": True, "tasks": cfg["tasks"]})
            return

        # 7. Sync Tasks from Notion
        if path == "/api/notion/sync":
            api_token = body.get("api_token")
            database_id = body.get("database_id")
            if database_id:
                cfg.setdefault("notion", {})["database_id"] = str(database_id).strip()
                save_config(cfg)
            res = sync_tasks_from_notion(api_token=api_token, database_id=database_id)
            self._send_json(res)
            return

        # 7b. Configure Generic Published Notion Database / Embed View & Presets
        if path == "/api/notion/view":
            nv = apply_notion_view_update(cfg, body)
            save_config(cfg)
            self._send_json({"ok": True, "notion_view": nv, "display": cfg.get("display", {})})
            return

        # 8. Manage Events
        if path == "/api/events":
            action = body.get("action", "add")
            events = cfg.setdefault("events", [])
            if action == "add":
                events.append(
                    {
                        "id": f"evt-{uuid.uuid4().hex[:6]}",
                        "title": (body.get("title") or "Neues Event").strip(),
                        "date_label": (body.get("date_label") or "").strip(),
                        "subtitle": (body.get("subtitle") or "").strip(),
                        "badge": (body.get("badge") or "Event").strip(),
                    }
                )
            elif action == "delete":
                eid = body.get("id")
                cfg["events"] = [e for e in events if e.get("id") != eid]
            save_config(cfg)
            self._send_json({"ok": True, "events": cfg["events"]})
            return

        # 9. TV Power Control via HDMI-CEC
        if path == "/api/tv/power":
            action = body.get("action", "status")
            cec_addr = str(body.get("cec_address") or cfg.get("tv_power", {}).get("cec_address", "0"))
            res = execute_tv_power(action=action, cec_address=cec_addr)
            self._send_json(res)
            return

        # 10. TV Night Schedule Configuration
        if path == "/api/tv/schedule":
            tv_cfg = cfg.setdefault("tv_power", {})
            try:
                apply_schedule_update(tv_cfg, body)
            except ValueError as exc:
                self._send_json({"ok": False, "error": str(exc)}, status=400)
                return
            save_config(cfg)
            self._send_json({"ok": True, "tv_power": tv_cfg})
            return

        # 11. Multi-Pi Fleet Node Registry
        if path == "/api/fleet/nodes":
            action = body.get("action", "add")
            fleet = cfg.setdefault("pi_fleet", [])
            if action == "add":
                host = valid_web_url(body.get("host"))
                if not host:
                    self._send_json({"ok": False, "error": "Bitte eine gültige Pi-URL ohne Zugangsdaten angeben."}, status=400)
                    return
                fleet.append(
                    {
                        "id": f"pi-{uuid.uuid4().hex[:6]}",
                        "name": (body.get("name") or "Neuer Raspberry Pi").strip(),
                        "location": (body.get("location") or "Church Space").strip(),
                        "host": host.rstrip("/"),
                        "is_local": False,
                    }
                )
            elif action == "delete":
                nid = body.get("id")
                cfg["pi_fleet"] = [n for n in fleet if n.get("id") != nid or n.get("is_local")]
            save_config(cfg)
            self._send_json({"ok": True, "pi_fleet": cfg["pi_fleet"]})
            return

        # 12. Multi-Pi Fleet Command Dispatch (Single Pi or Broadcast to ALL Pis)
        if path == "/api/fleet/command":
            target = body.get("target", "pi-local")  # 'all' or specific node id
            cmd_type = body.get("command")  # 'mode' | 'tv_power' | 'reload' | 'notion_view'
            payload = body.get("payload", {})

            endpoint_map = {
                "mode": "/api/display/mode",
                "tv_power": "/api/tv/power",
                "reload": "/api/display/reload",
                "notion_view": "/api/notion/view",
                "schedule": "/api/tv/schedule",
            }
            endpoint = endpoint_map.get(cmd_type)
            if not endpoint:
                self._send_json({"ok": False, "error": f"Unbekannter Fleet-Befehl: {cmd_type}"}, status=400)
                return

            fleet = cfg.get("pi_fleet", [])
            results = []
            for node in fleet:
                if target not in ("all", node.get("id")):
                    continue
                if node.get("is_local"):
                    # Execute directly on this local instance
                    if cmd_type == "mode":
                        mode = payload.get("mode", "dashboard")
                        if mode in VALID_MODES:
                            cfg.setdefault("display", {})["mode"] = mode
                        save_config(cfg)
                        results.append({"node_id": node["id"], "name": node["name"], "ok": True, "mode": mode})
                    elif cmd_type == "tv_power":
                        res = execute_tv_power(payload.get("action", "on"))
                        results.append({"node_id": node["id"], "name": node["name"], "ok": True, "response": res})
                    elif cmd_type == "reload":
                        disp = cfg.setdefault("display", {})
                        disp["reload_token"] = int(disp.get("reload_token", 1)) + 1
                        save_config(cfg)
                        results.append({"node_id": node["id"], "name": node["name"], "ok": True})
                    elif cmd_type == "notion_view":
                        nv = apply_notion_view_update(cfg, payload)
                        save_config(cfg)
                        results.append({"node_id": node["id"], "name": node["name"], "ok": True, "notion_view": nv})
                    elif cmd_type == "schedule":
                        try:
                            apply_schedule_update(cfg.setdefault("tv_power", {}), payload)
                        except ValueError as exc:
                            results.append({"node_id": node["id"], "name": node["name"], "ok": False, "error": str(exc)})
                        else:
                            save_config(cfg)
                            results.append({"node_id": node["id"], "name": node["name"], "ok": True})
                else:
                    results.append(
                        {
                            "node_id": node.get("id"),
                            "name": node.get("name"),
                            "ok": False,
                            "error": "Sichere Fernsteuerung ist noch nicht konfiguriert.",
                        }
                    )

            self._send_json({"ok": True, "target": target, "results": results})
            return

        self.send_error(404, "API endpoint not found")


def main() -> None:
    parser = argparse.ArgumentParser(description="ICF Church Screen & Pi Canva Kiosk Server")
    parser.add_argument("--host", default=os.environ.get("KIOSK_HOST", "0.0.0.0"), help="Bind host (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=int(os.environ.get("KIOSK_PORT", "8080")), help="Port (default: 8080)")
    args = parser.parse_args()

    # Start background HDMI-CEC Night Schedule worker
    scheduler = NightPowerScheduler(check_interval_sec=30)
    scheduler.start()

    server = ThreadingHTTPServer((args.host, args.port), KioskRequestHandler)
    print(f"============================================================")
    print(f" ICF Church Screen & Pi-Canva-Viewer Server gestartet!")
    print(f" -> TV Fullscreen Display:  http://localhost:{args.port}/display")
    print(f" -> Pi Control & Admin UI:  http://localhost:{args.port}/admin")
    print(f"============================================================")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer wird beendet...")
        server.server_close()


if __name__ == "__main__":
    main()
